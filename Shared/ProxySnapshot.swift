import Foundation

/// Proxy state shared between app and widget through the App Group.
/// The app save()s and reloads WidgetCenter on change; the widget only load()s.
struct ProxySnapshot: Codable, Equatable {
    enum Status: String, Codable {
        case starting
        case stale        // last running observation has expired; not a live health assertion
        case running      // listener ready, hotspot on
        case noHotspot    // proxy on but no hotspot (bridge) interface
        case stopped      // stopped by the user
        case error        // listener failed
    }

    var status: Status
    var hotspotIP: String?
    var port: Int
    var connections: Int
    var bytes: UInt64
    var errorMessage: String?
    var updatedAt: Date

    /// "IP:port" to enter on other devices; nil without a hotspot.
    var endpoint: String? { hotspotIP.map { "\($0.contains(":") ? "[\($0)]" : $0):\(port)" } }

    static let freshness: TimeInterval = 120
    var expiresAt: Date { updatedAt.addingTimeInterval(Self.freshness) }
    func fresh(at now: Date) -> ProxySnapshot {
        guard [.running, .starting, .noHotspot].contains(status), now >= expiresAt else { return self }
        var copy = self
        copy.status = .stale
        copy.connections = 0
        return copy
    }

    // Gallery previews may share a long-lived extension process. Never reuse its launch timestamp.
    static var placeholder: ProxySnapshot { preview(at: .now) }
    static func preview(at now: Date) -> ProxySnapshot {
        ProxySnapshot(status: .running, hotspotIP: "172.20.10.1", port: 8080,
                      connections: 3, bytes: 48_300_000, errorMessage: nil, updatedAt: now)
    }
    static let empty = ProxySnapshot(status: .stopped, hotspotIP: nil, port: 8080,
                                     connections: 0, bytes: 0, errorMessage: nil, updatedAt: .distantPast)
}

enum SharedStore {
    static let appGroup = "group.com.indoyoon.hotspotproxy"
    static let widgetKind = "HotspotProxyStatus"
    private static let key = "snapshot.v1"

    static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    static func load() -> ProxySnapshot {
        guard let data = defaults.data(forKey: key),
              let s = try? JSONDecoder().decode(ProxySnapshot.self, from: data) else { return .empty }
        return s
    }

    static func save(_ s: ProxySnapshot) {
        guard let data = try? JSONEncoder().encode(s) else { return }
        defaults.set(data, forKey: key)
    }
}

/// Deep links that open or control the app from widgets and Shortcuts. hotspotproxy://open | hotspotproxy://start | hotspotproxy://stop | hotspotproxy://copy
enum DeepLink: String {
    case open, start, stop, toggle, copy
    var url: URL { URL(string: "hotspotproxy://\(rawValue)")! }
    init?(url: URL) {
        guard url.scheme == "hotspotproxy", let v = DeepLink(rawValue: url.host ?? "open") else { return nil }
        self = v
    }
}
