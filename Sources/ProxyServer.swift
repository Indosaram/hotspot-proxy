import Foundation
import Network
import os

/// Proxy serving HTTP (incl. CONNECT) and SOCKS5 on the same port.
final class ProxyServer {
    let queue = DispatchQueue(label: "proxy", qos: .userInitiated)
    private var listener: NWListener?
    private var live: [ObjectIdentifier: Session] = [:]
    var onStats: ((Int, UInt64) -> Void)?
    var onState: ((String?) -> Void)?
    private let bytes = OSAllocatedUnfairLock(initialState: UInt64(0))
    private lazy var udp = UdpRelay(queue: queue)
    /// Each session gets a serial queue targeting this concurrent queue, so connections run in parallel across cores.
    private let work = DispatchQueue(label: "proxy.sessions", qos: .userInitiated, attributes: .concurrent)

    func start(port: UInt16) {
        stop()
        do {
            let params = Tcp.params()
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            l.newConnectionHandler = { [weak self] c in self?.accept(c) }
            l.stateUpdateHandler = { [weak self] s in
                switch s {
                case .ready: self?.onState?(nil)
                case .failed(let e): self?.onState?("Listener error: \(e)")
                default: break
                }
            }
            l.start(queue: queue)
            listener = l
            queue.async { [self] in
                udp.onBytes = { [weak self] n in self?.bytes.withLock { $0 &+= UInt64(n) } }
                udp.start(port: port)
            }
        } catch {
            onState?("Failed to start: \(error)")
        }
    }

    func stop() {
        listener?.cancel(); listener = nil
        queue.async { [weak self] in
            self?.udp.stop()
            self?.live.values.forEach { s in s.queue.async { s.close() } }
            self?.live.removeAll()
            self?.report()
        }
    }

    private func accept(_ c: NWConnection) {
        let s = Session(client: c, queue: DispatchQueue(label: "proxy.s", target: work))
        let id = ObjectIdentifier(s)
        live[id] = s
        s.onBytes = { [weak self] n in self?.bytes.withLock { $0 &+= UInt64(n) } }
        s.onClose = { [weak self] in self?.queue.async { self?.live[id] = nil } }
        s.queue.async { s.start() }
    }

    /// Called only while the UI is visible (never wakes the main thread in background).
    private func report() {
        let n = live.count, b = bytes.withLock { $0 }
        onStats?(n, b)
    }
    func pollStats() { queue.async { [weak self] in self?.report() } }
}

enum Tcp {
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

/// On IPv6-only cellular (NAT64/DNS64), Network.framework cannot reach IPv4 literals directly.
/// getaddrinfo synthesizes the NAT64 IPv6 address for an IPv4 literal; elsewhere it returns IPv4 and we keep the host as-is.
enum Nat64 {
    static func host(_ s: String) -> NWEndpoint.Host {
        guard IPv4Address(s) != nil else { return NWEndpoint.Host(s) }
        var hints = addrinfo()
        hints.ai_flags = AI_DEFAULT
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(s, nil, &hints, &res) == 0 else { return NWEndpoint.Host(s) }
        defer { freeaddrinfo(res) }
        var p = res
        while let ai = p {
            if ai.pointee.ai_family == AF_INET6, let sa = ai.pointee.ai_addr {
                let a6 = sa.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee.sin6_addr }
                if let v6 = IPv6Address(withUnsafeBytes(of: a6) { Data($0) }) { return .ipv6(v6) }
            }
            p = ai.pointee.ai_next
        }
        return NWEndpoint.Host(s)
    }
}

final class Session {
    let client: NWConnection
    var upstream: NWConnection?
    let queue: DispatchQueue
    var buf = Data()
    var closed = false
    private var finished = 0   // directions that hit EOF; session closes at 2
    var onBytes: ((Int) -> Void)?
    var onClose: (() -> Void)?

    init(client: NWConnection, queue: DispatchQueue) { self.client = client; self.queue = queue }

    func start() {
        client.stateUpdateHandler = { [weak self] s in
            if case .failed = s { self?.close() }
            if case .cancelled = s { self?.close() }
        }
        client.start(queue: queue)
        need(1) { [weak self] in
            guard let self else { return }
            if self.buf.first == 0x05 { self.socksGreeting() } else { self.readHttpHeader() }
        }
    }

    // MARK: buffered reading
    private func need(_ n: Int, _ then: @escaping () -> Void) {
        if buf.count >= n { then(); return }
        client.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, err in
            guard let self else { return }
            if let data, !data.isEmpty { self.buf.append(data) }
            if err != nil || (done && self.buf.count < n) { self.close(); return }
            self.need(n, then)
        }
    }

    private func take(_ n: Int) -> Data {
        let d = buf.prefix(n); buf.removeFirst(n); return Data(d)
    }

    // MARK: SOCKS5
    private func socksGreeting() {
        need(2) { [self] in
            let nm = Int(buf[buf.startIndex + 1])
            need(2 + nm) { [self] in
                _ = take(2 + nm)
                client.send(content: Data([5, 0]), completion: .contentProcessed { _ in })
                socksRequest()
            }
        }
    }

    private func socksRequest() {
        need(5) { [self] in
            let b = Array(buf.prefix(5))
            guard b[0] == 5, b[1] == 1 || b[1] == 3 else { reply(7); close(); return }
            let cmd = b[1]
            let atyp = b[3]
            let addrLen: Int
            switch atyp {
            case 1: addrLen = 4
            case 3: addrLen = 1 + Int(b[4])
            case 4: addrLen = 16
            default: reply(8); close(); return
            }
            need(4 + addrLen + 2) { [self] in
                let r = Array(take(4 + addrLen + 2))
                let a = Array(r[4..<(4 + addrLen)])
                let host: String
                switch atyp {
                case 1: host = a.map(String.init).joined(separator: ".")
                case 3: host = String(decoding: a[1...], as: UTF8.self)
                default: host = stride(from: 0, to: 16, by: 2).map { String(format: "%x", (UInt16(a[$0]) << 8) | UInt16(a[$0 + 1])) }.joined(separator: ":")
                }
                let port = (UInt16(r[4 + addrLen]) << 8) | UInt16(r[5 + addrLen])
                if cmd == 3 { udpAssociate(); return }
                connect(host: host, port: port) { [self] ok in
                    reply(ok ? 0 : 5)
                    if ok { pipe() } else { close() }
                }
            }
        }
    }

    /// UDP ASSOCIATE: reply with the UDP relay on the same IP/port and hold until the TCP control connection closes.
    private func udpAssociate() {
        var resp = Data([5, 0, 0, 1, 0, 0, 0, 0, 0, 0])
        if case .hostPort(let h, let p)? = client.currentPath?.localEndpoint, case .ipv4(let v4) = h {
            resp = Data([5, 0, 0, 1]) + v4.rawValue + Data([UInt8(p.rawValue >> 8), UInt8(p.rawValue & 0xff)])
        }
        client.send(content: resp, completion: .contentProcessed { _ in })
        holdOpen()
    }

    private func holdOpen() {
        client.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] _, _, done, err in
            if done || err != nil { self?.close() } else { self?.holdOpen() }
        }
    }

    private func reply(_ code: UInt8) {
        client.send(content: Data([5, code, 0, 1, 0, 0, 0, 0, 0, 0]), completion: .contentProcessed { _ in })
    }

    // MARK: HTTP
    private func readHttpHeader() {
        if let r = buf.range(of: Data("\r\n\r\n".utf8)) {
            let head = String(decoding: buf[buf.startIndex..<r.lowerBound], as: UTF8.self)
            buf.removeSubrange(buf.startIndex..<r.upperBound)
            handleHttp(head)
            return
        }
        if buf.count > 64 * 1024 { close(); return }
        need(buf.count + 1) { [weak self] in self?.readHttpHeader() }
    }

    private func handleHttp(_ head: String) {
        var lines = head.components(separatedBy: "\r\n")
        let parts = lines[0].split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count == 3 else { close(); return }
        let method = parts[0], target = parts[1], version = parts[2]

        if method.uppercased() == "CONNECT" {
            let (h, p) = splitHostPort(target, defaultPort: 443)
            connect(host: h, port: p) { [self] ok in
                if ok {
                    client.send(content: Data("HTTP/1.1 200 Connection Established\r\n\r\n".utf8), completion: .contentProcessed { _ in })
                    pipe()
                } else {
                    client.send(content: Data("HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n".utf8), completion: .contentProcessed { [weak self] _ in self?.close() })
                }
            }
            return
        }

        guard let url = URL(string: target), let host = url.host else {
            client.send(content: Data("HTTP/1.1 400 Bad Request\r\nX-Proxy: hotspot\r\nContent-Length: 0\r\n\r\n".utf8), completion: .contentProcessed { [weak self] _ in self?.close() })
            return
        }
        let port = UInt16(url.port ?? 80)
        var path = url.path.isEmpty ? "/" : url.path
        if let q = url.query { path += "?" + q }
        lines[0] = "\(method) \(path) \(version)"
        lines = lines.filter {
            let k = $0.lowercased()
            return !(k.hasPrefix("proxy-connection:") || k.hasPrefix("connection:") || k.hasPrefix("keep-alive:") || k.hasPrefix("proxy-authorization:"))
        }
        lines.append("Connection: close")
        let newHead = Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
        connect(host: host, port: port) { [self] ok in
            guard ok else {
                client.send(content: Data("HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n".utf8), completion: .contentProcessed { [weak self] _ in self?.close() })
                return
            }
            upstream?.send(content: newHead, completion: .contentProcessed { _ in })
            pipe()
        }
    }

    private func splitHostPort(_ s: String, defaultPort: UInt16) -> (String, UInt16) {
        if s.hasPrefix("["), let end = s.firstIndex(of: "]") {
            let h = String(s[s.index(after: s.startIndex)..<end])
            let rest = s[s.index(after: end)...]
            return (h, rest.hasPrefix(":") ? UInt16(rest.dropFirst()) ?? defaultPort : defaultPort)
        }
        if let i = s.lastIndex(of: ":"), let p = UInt16(s[s.index(after: i)...]) { return (String(s[..<i]), p) }
        return (s, defaultPort)
    }

    // MARK: upstream + relay
    private func connect(host: String, port: UInt16, _ done: @escaping (Bool) -> Void) {
        guard let p = NWEndpoint.Port(rawValue: port) else { done(false); return }
        let up = NWConnection(host: Nat64.host(host), port: p, using: Tcp.params())
        upstream = up
        var fired = false
        up.stateUpdateHandler = { [weak self] s in
            switch s {
            case .ready: if !fired { fired = true; done(true) }
            case .failed, .waiting:
                if !fired { fired = true; done(false) } else { self?.close() }
            case .cancelled: self?.close()
            default: break
            }
        }
        up.start(queue: queue)
    }

    private func pipe() {
        guard let up = upstream else { close(); return }
        if !buf.isEmpty { let d = buf; buf = Data(); up.send(content: d, completion: .contentProcessed { _ in }) }
        relay(from: client, to: up)
        relay(from: up, to: client)
    }

    /// On EOF in one direction, forward only a FIN (half-close) and keep relaying the other direction.
    private func relay(from: NWConnection, to: NWConnection) {
        from.receive(minimumIncompleteLength: 1, maximumLength: Tcp.chunk) { [weak self] data, _, done, err in
            guard let self, !self.closed else { return }
            if err != nil { self.close(); return }
            let payload = (data?.isEmpty == false) ? data : nil
            if let payload { self.onBytes?(payload.count) }
            if payload == nil && !done { self.relay(from: from, to: to); return }
            to.send(content: payload, contentContext: done ? .finalMessage : .defaultMessage, isComplete: done,
                    completion: .contentProcessed { [weak self] e in
                guard let self, !self.closed else { return }
                if e != nil { self.close(); return }
                if done {
                    self.finished += 1
                    if self.finished == 2 { self.close() }
                } else {
                    self.relay(from: from, to: to)
                }
            })
        }
    }

    func close() {
        if closed { return }
        closed = true
        client.cancel(); upstream?.cancel()
        onClose?()
    }
}
