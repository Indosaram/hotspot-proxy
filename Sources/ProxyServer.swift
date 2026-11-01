import Foundation
import Network

/// All listener/session state is confined to queue. Socket I/O is asynchronous and backpressured.
final class ProxyServer {
    let queue = DispatchQueue(label: "proxy", qos: .userInitiated)
    private var listeners: [NWListener] = []
    private var readyHosts: Set<String> = []
    private var generation: UUID?
    private var live: [ObjectIdentifier: Session] = [:]
    private var bytes: UInt64 = 0
    var onStats: ((Int, UInt64) -> Void)?
    var onState: ((UUID, String?) -> Void)?

    /// Bind only the selected hotspot address, never a wildcard LAN listener.
    func start(port: UInt16, hosts: [String], generation: UUID) {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopOnQueue()
            self.generation = generation
            do {
                guard !hosts.isEmpty, port > 0, let endpointPort = NWEndpoint.Port(rawValue: port) else { throw ProxyError.invalidPort }
                for host in Set(hosts) {
                    let params = Tcp.params()
                    params.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(host), port: endpointPort)
                    let listener = try NWListener(using: params)
                    self.listeners.append(listener)
                    listener.newConnectionHandler = { [weak self] c in
                        guard let self, self.generation == generation else { c.cancel(); return }
                        self.accept(c)
                    }
                    listener.stateUpdateHandler = { [weak self] state in
                        guard let self, self.generation == generation else { return }
                        switch state {
                        case .ready:
                            self.readyHosts.insert(host)
                            if self.readyHosts.count == Set(hosts).count { self.onState?(generation, nil) }
                        case .failed(let error), .waiting(let error):
                            self.stopOnQueue()
                            self.onState?(generation, "Listener error: \(error)")
                        default: break
                        }
                    }
                    listener.start(queue: self.queue)
                }
            } catch {
                self.stopOnQueue()
                self.onState?(generation, "Failed to start: \(error)")
            }
        }
    }

    func stop() { queue.async { [weak self] in self?.stopOnQueue() } }

    private func stopOnQueue() {
        generation = nil
        for listener in listeners {
            listener.stateUpdateHandler = nil
            listener.newConnectionHandler = nil
            listener.cancel()
        }
        listeners.removeAll()
        readyHosts.removeAll()
        let sessions = Array(live.values)
        live.removeAll()
        sessions.forEach { $0.close() }
        report()
    }

    private func accept(_ c: NWConnection) {
        guard live.count < ProxyProtocol.maxSessions else { c.cancel(); return }
        let session = Session(client: c, queue: queue)
        let id = ObjectIdentifier(session)
        live[id] = session
        session.onBytes = { [weak self] n in self?.bytes &+= UInt64(n) }
        session.onClose = { [weak self] in self?.live[id] = nil }
        session.start()
    }

    private func report() { onStats?(live.count, bytes) }
    func pollStats() { queue.async { [weak self] in self?.report() } }
    private enum ProxyError: Error { case invalidPort }
}

enum Tcp {
    /// SOCKS carries address bytes, not an IPv6 zone identifier. The bound listener
    /// supplies interface scope; compare the peer bytes within that scope.
    static func sameHost(_ lhs: NWEndpoint.Host, _ rhs: NWEndpoint.Host) -> Bool {
        switch (lhs, rhs) {
        case (.ipv4(let a), .ipv4(let b)): return a.rawValue == b.rawValue
        case (.ipv6(let a), .ipv6(let b)): return a.rawValue == b.rawValue
        default: return lhs == rhs
        }
    }
    static func params() -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.connectionTimeout = 10
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 60
        return NWParameters(tls: nil, tcp: tcp)
    }
    static let chunk = 128 * 1024
}

final class Session {
    let client: NWConnection
    private var upstream: NWConnection?
    private var udp: UdpRelay?
    let queue: DispatchQueue
    private var buf = Data()
    private var closed = false
    private var inputEnded = false
    private var finished = 0
    private var handshakeTimer: DispatchSourceTimer?
    private let handshakeTimeout: TimeInterval
    var onBytes: ((Int) -> Void)?
    var onClose: (() -> Void)?

    init(client: NWConnection, queue: DispatchQueue, handshakeTimeout: TimeInterval = ProxyProtocol.handshakeTimeout) {
        self.client = client; self.queue = queue; self.handshakeTimeout = handshakeTimeout
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + handshakeTimeout)
        timer.setEventHandler { [weak self] in self?.close() }
        timer.resume(); handshakeTimer = timer
        client.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.close() }
            if case .cancelled = state { self?.close() }
        }
        client.start(queue: queue)
        need(1) { [weak self] in
            guard let self else { return }
            if self.buf.first == 5 { self.socksGreeting() } else { self.readHttpHeader() }
        }
    }

    private func endHandshake() { handshakeTimer?.cancel(); handshakeTimer = nil }

    private func need(_ n: Int, _ then: @escaping () -> Void) {
        guard !closed else { return }
        if buf.count >= n { then(); return }
        guard !inputEnded else { close(); return }
        client.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, error in
            guard let self, !self.closed else { return }
            if let data { self.buf.append(data) }
            self.inputEnded = done
            if error != nil { self.close(); return }
            self.need(n, then)
        }
    }

    private func take(_ n: Int) -> Data {
        let data = Data(buf.prefix(n)); buf.removeFirst(n); return data
    }

    private func send(_ data: Data, then: @escaping () -> Void) {
        client.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self, !self.closed else { return }
            if error != nil { self.close() } else { then() }
        })
    }

    private func failSocks(_ code: UInt8) {
        send(Data([5, code, 0, 1, 0, 0, 0, 0, 0, 0])) { [weak self] in self?.close() }
    }

    private func socksGreeting() {
        need(2) { [weak self] in
            guard let self else { return }
            let count = Int(self.buf[self.buf.startIndex + 1])
            self.need(2 + count) { [weak self] in
                guard let self else { return }
                guard ProxyProtocol.acceptsNoAuthentication(self.take(2 + count)) else {
                    self.send(Data([5, 255])) { [weak self] in self?.close() }
                    return
                }
                self.send(Data([5, 0])) { [weak self] in self?.socksRequest() }
            }
        }
    }

    private func socksRequest() {
        need(5) { [weak self] in
            guard let self else { return }
            let b = Array(self.buf.prefix(5))
            guard b[0] == 5, b[2] == 0, b[1] == 1 || b[1] == 3 else { self.failSocks(7); return }
            let count: Int
            switch b[3] {
            case 1: count = 10
            case 4: count = 22
            case 3: count = 7 + Int(b[4])
            default: self.failSocks(8); return
            }
            self.need(count) { [weak self] in
                guard let self else { return }
                let request = self.take(count)
                guard let (address, _) = ProxyProtocol.address(Data(request.dropFirst(3))) else { self.failSocks(8); return }
                if b[1] == 3 { self.udpAssociate(address); return }
                self.connect(host: address.host, port: address.port) { [weak self] ok in
                    guard let self else { return }
                    guard ok else { self.failSocks(5); return }
                    self.send(Data([5, 0, 0, 1, 0, 0, 0, 0, 0, 0])) { [weak self] in self?.pipe() }
                }
            }
        }
    }

    private func udpAssociate(_ requested: ProxyProtocol.Address) {
        guard case .hostPort(let peer, _ ) = client.endpoint,
              case .hostPort(let local, _)? = client.currentPath?.localEndpoint,
              requested.type != 3,
              requested.isUnspecified || Tcp.sameHost(NWEndpoint.Host(requested.host), peer) else { failSocks(8); return }
        let relay = UdpRelay(queue: queue, local: local, peer: peer, clientPort: requested.port)
        udp = relay
        relay.onBytes = { [weak self] n in self?.onBytes?(n) }
        relay.onFailure = { [weak self] in self?.close() }
        relay.start { [weak self] reply in
            guard let self, !self.closed else { return }
            guard let reply else { self.failSocks(1); return }
            self.send(reply) { [weak self] in
                self?.endHandshake()
                self?.holdOpen()
            }
        }
    }

    private func holdOpen() {
        guard !inputEnded else { close(); return }
        client.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] _, _, done, error in
            guard let self, !self.closed else { return }
            if done || error != nil { self.close() } else { self.holdOpen() }
        }
    }

    private func readHttpHeader() {
        if let range = buf.range(of: Data("\r\n\r\n".utf8)) {
            guard buf.distance(from: buf.startIndex, to: range.upperBound) <= 64 * 1024,
                  let head = String(data: buf[buf.startIndex..<range.lowerBound], encoding: .utf8) else { close(); return }
            buf.removeSubrange(buf.startIndex..<range.upperBound)
            handleHttp(head)
        } else if buf.count >= 64 * 1024 { close() }
        else { need(buf.count + 1) { [weak self] in self?.readHttpHeader() } }
    }

    private func httpError(_ status: String) {
        send(Data("HTTP/1.1 \(status)\r\nConnection: close\r\nContent-Length: 0\r\n\r\n".utf8)) { [weak self] in self?.close() }
    }

    private func handleHttp(_ head: String) {
        var lines = head.components(separatedBy: "\r\n")
        let parts = lines[0].split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, !parts[0].isEmpty, ["HTTP/1.0", "HTTP/1.1"].contains(parts[2]),
              let target = ProxyProtocol.httpTarget(parts[1], connect: parts[0] == "CONNECT") else { httpError("400 Bad Request"); return }
        if parts[0] == "CONNECT" {
            connect(host: target.host, port: target.port) { [weak self] ok in
                guard let self else { return }
                if ok { self.send(Data("HTTP/1.1 200 Connection Established\r\n\r\n".utf8)) { [weak self] in self?.pipe() } }
                else { self.httpError("502 Bad Gateway") }
            }
            return
        }
        lines[0] = "\(parts[0]) \(target.path) \(parts[2])"
        lines = lines.filter {
            let name = $0.split(separator: ":", maxSplits: 1).first?.lowercased() ?? ""
            return !["proxy-connection", "connection", "keep-alive", "proxy-authorization"].contains(name)
        }
        lines.append("Connection: close")
        let header = Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
        connect(host: target.host, port: target.port) { [weak self] ok in
            guard let self else { return }
            guard ok else { self.httpError("502 Bad Gateway"); return }
            self.upstream?.send(content: header, completion: .contentProcessed { [weak self] error in
                if error != nil { self?.close() } else { self?.pipe() }
            })
        }
    }

    private func connect(host: String, port: UInt16, _ done: @escaping (Bool) -> Void) {
        guard port > 0, let p = NWEndpoint.Port(rawValue: port) else { done(false); return }
        let up = NWConnection(host: NWEndpoint.Host(host), port: p, using: Tcp.params())
        upstream = up
        var callback: ((Bool) -> Void)? = done
        up.stateUpdateHandler = { [weak self] state in
            guard let self, !self.closed else { return }
            switch state {
            case .ready:
                let completion = callback; callback = nil; completion?(true)
            case .failed, .waiting:
                if let completion = callback { callback = nil; completion(false) } else { self.close() }
            case .cancelled: self.close()
            default: break
            }
        }
        up.start(queue: queue)
    }

    private func pipe() {
        guard !closed, let up = upstream else { close(); return }
        endHandshake()
        // Preserve EOF received with the initial request instead of reading a completed stream again.
        let data = buf.isEmpty ? nil : buf
        buf = Data()
        if let data { onBytes?(data.count) }
        if data == nil && !inputEnded {
            relay(from: client, to: up)
        } else {
            up.send(content: data, contentContext: inputEnded ? .finalMessage : .defaultMessage, isComplete: inputEnded,
                    completion: .contentProcessed { [weak self] error in
                guard let self, !self.closed else { return }
                if error != nil { self.close(); return }
                if self.inputEnded { self.finishDirection() } else { self.relay(from: self.client, to: up) }
            })
        }
        relay(from: up, to: client)
    }

    private func finishDirection() { finished += 1; if finished == 2 { close() } }

    private func relay(from: NWConnection, to: NWConnection) {
        from.receive(minimumIncompleteLength: 1, maximumLength: Tcp.chunk) { [weak self] data, _, done, error in
            guard let self, !self.closed else { return }
            if error != nil { self.close(); return }
            let payload = (data?.isEmpty == false) ? data : nil
            if let payload { self.onBytes?(payload.count) }
            if payload == nil && !done { self.relay(from: from, to: to); return }
            to.send(content: payload, contentContext: done ? .finalMessage : .defaultMessage, isComplete: done,
                    completion: .contentProcessed { [weak self] error in
                guard let self, !self.closed else { return }
                if error != nil { self.close(); return }
                if done { self.finishDirection() } else { self.relay(from: from, to: to) }
            })
        }
    }

    func close() {
        guard !closed else { return }
        closed = true
        endHandshake()
        udp?.stop(); udp = nil
        client.stateUpdateHandler = nil
        upstream?.stateUpdateHandler = nil
        client.cancel(); upstream?.cancel(); upstream = nil
        let completion = onClose; onClose = nil; completion?()
    }
}
