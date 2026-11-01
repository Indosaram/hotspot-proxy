import SwiftUI
import Darwin
import UIKit
import WidgetKit
import Network

@MainActor
final class ProxyModel: ObservableObject {
    @AppStorage("port") var port: Int = 8080
    @AppStorage("autoStart") var autoStart: Bool = true
    @Published var running = false
    @Published private(set) var requested = false
    @Published private(set) var starting = false
    @Published var connections = 0
    @Published var bytes: UInt64 = 0
    @Published var error: String?
    @Published var addresses: [(String, String)] = []
    @Published var startedAt: Date?

    private let server = ProxyServer()
    private let keepAlive = KeepAlive()
    private var timer: Timer?
    private var heartbeat: Timer?
    private var generation: UUID?
    private var boundHosts: [String] = []
    private let pathMonitor = NWPathMonitor()
    private var lastWidgetReload = Date.distantPast
    private var lastPublished: ProxySnapshot?
    /// -uiDemo / -uiDemoNoHotspot: screenshot QA mode, never starts the real server.
    let demo: Bool

    init() {
        let args = ProcessInfo.processInfo.arguments
        demo = args.contains("-uiDemo") || args.contains("-uiDemoNoHotspot")
        server.onStats = { [weak self] n, b in Task { @MainActor in if let self { self.connections = self.running ? n : 0; self.bytes = b } } }
        server.onState = { [weak self] generation, error in
            Task { @MainActor in
                guard let self, self.generation == generation else { return }
                if let error { self.fail(error); return }
                self.starting = false
                self.running = true
                self.startedAt = .now
                self.publishSnapshot(force: true)
            }
        }
        keepAlive.onFailure = { [weak self] in self?.fail("Background audio could not resume. Start the proxy again.") }
        pathMonitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor in self?.refreshNetwork() }
        }
        pathMonitor.start(queue: DispatchQueue(label: "proxy.path"))
        if args.contains("-uiDemoNoHotspot") {
            running = true; startedAt = .now.addingTimeInterval(-412)
            addresses = [("pdp_ip0", "10.44.1.7")]
        } else if args.contains("-uiDemo") {
            running = true; connections = 3; bytes = 48_300_000
            startedAt = .now.addingTimeInterval(-3725)
            addresses = [("bridge100", "172.20.10.1"), ("en0", "192.168.0.12"), ("pdp_ip0", "10.44.1.7")]
        } else {
            refreshAddresses()
            if autoStart { start() }
        }
        publishSnapshot()
    }

    private var hotspotHosts: [String] { addresses.filter { $0.0.hasPrefix("bridge") }.map { $0.1 }.sorted() }
    var hotspotIP: String? { hotspotHosts.first { !$0.contains(":") } ?? hotspotHosts.first }
    var endpoint: String? { snapshot.endpoint }

    var status: ProxySnapshot.Status {
        if error != nil { return .error }
        if !requested && !running { return .stopped }
        if hotspotIP == nil { return .noHotspot }
        if starting { return .starting }
        return .running
    }

    var snapshot: ProxySnapshot {
        ProxySnapshot(status: status, hotspotIP: hotspotIP, port: port, connections: connections,
                      bytes: bytes, errorMessage: error, updatedAt: .now)
    }

    func setVisible(_ visible: Bool) {
        timer?.invalidate(); timer = nil
        guard visible else { publishSnapshot(force: true); return }
        guard !demo else { return }
        refreshNetwork(); server.pollStats()
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshNetwork(); self?.server.pollStats(); self?.publishSnapshot() }
        }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func start() {
        guard !requested else { return }
        error = nil
        requested = true
        if demo {
            running = true; startedAt = .now
        } else {
            refreshNetwork()
            guard requested else { return }
            let t = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshNetwork()
                    self?.server.pollStats()
                    self?.publishSnapshot()
                }
            }
            t.tolerance = 5
            RunLoop.main.add(t, forMode: .common)
            heartbeat = t
        }
        publishSnapshot(force: true)
    }

    /// Address changes retire the entire previous generation before binding a new hotspot endpoint.
    private func refreshNetwork() {
        guard !demo else { return }
        refreshAddresses()
        guard requested else { return }
        let hosts = hotspotHosts
        guard hosts != boundHosts || (!hosts.isEmpty && generation == nil) else { return }
        generation = nil
        boundHosts = []
        server.stop()
        keepAlive.stop()
        running = false; starting = false; startedAt = nil
        guard !hosts.isEmpty else { publishSnapshot(force: true); return }
        guard let port = UInt16(exactly: port), port >= 1024 else { fail("Port must be between 1024 and 65535."); return }
        do { try keepAlive.start() } catch { fail("Could not start background audio: \(error)"); return }
        let id = UUID()
        generation = id
        boundHosts = hosts
        starting = true
        server.start(port: port, hosts: hosts, generation: id)
        publishSnapshot(force: true)
    }

    private func fail(_ message: String) {
        stop()
        error = message
        publishSnapshot(force: true)
    }

    func stop() {
        requested = false
        generation = nil
        boundHosts = []
        heartbeat?.invalidate(); heartbeat = nil
        if !demo { server.stop(); keepAlive.stop() }
        running = false; starting = false
        connections = 0
        startedAt = nil
        publishSnapshot(force: true)
    }

    func toggle() { requested || running ? stop() : start() }

    @discardableResult
    func setPort(_ value: Int) -> Bool {
        guard !requested && !running, (1024...65535).contains(value) else { return false }
        port = value
        publishSnapshot()
        return true
    }

    func copyEndpoint() -> Bool {
        guard let endpoint else { return false }
        UIPasteboard.general.string = endpoint
        return true
    }

    func handle(_ link: DeepLink) {
        switch link {
        case .open: break
        case .start: if !requested { start() }
        case .stop: stop()
        case .toggle: toggle()
        case .copy: _ = copyEndpoint()
        }
    }

    /// Status changes reload immediately; a bounded heartbeat renews the widget observation lease.
    func publishSnapshot(force: Bool = false) {
        let s = snapshot
        SharedStore.save(s)
        let changed = lastPublished.map { $0.status != s.status || $0.endpoint != s.endpoint || $0.port != s.port } ?? true
        if changed || force || (requested && Date().timeIntervalSince(lastWidgetReload) >= 60) {
            lastWidgetReload = .now
            WidgetCenter.shared.reloadTimelines(ofKind: SharedStore.widgetKind)
        }
        lastPublished = s
    }

    func refreshAddresses() {
        var out: [(String, String)] = []
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { addresses = []; return }
        defer { freeifaddrs(ifap) }
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let sa = p.pointee.ifa_addr else { continue }
            let name = String(cString: p.pointee.ifa_name)
            guard sa.pointee.sa_family == UInt8(AF_INET) || (name.hasPrefix("bridge") && sa.pointee.sa_family == UInt8(AF_INET6)) else { continue }
            guard name != "lo0", (p.pointee.ifa_flags & UInt32(IFF_UP)) != 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            out.append((name, String(cString: host)))
        }
        addresses = out.sorted { ($0.0.hasPrefix("bridge") ? 0 : 1) < ($1.0.hasPrefix("bridge") ? 0 : 1) }
    }
}
