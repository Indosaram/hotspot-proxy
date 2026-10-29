import Foundation
import Network

/// SOCKS5 UDP ASSOCIATE relay, listening on a UDP socket with the same port number as TCP.
/// One destination NWConnection per client flow; flows idle for 60s are reaped (low power).
final class UdpRelay {
    private let queue: DispatchQueue
    private var listener: NWListener?
    private var flows: [ObjectIdentifier: Flow] = [:]
    var onBytes: ((Int) -> Void)?

    init(queue: DispatchQueue) { self.queue = queue }

    func start(port: UInt16) {
        stop()
        let p = NWParameters.udp
        p.allowLocalEndpointReuse = true
        guard let l = try? NWListener(using: p, on: NWEndpoint.Port(rawValue: port)!) else { return }
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
        l.start(queue: queue)
        listener = l
    }

    func stop() {
        listener?.cancel(); listener = nil
        flows.values.forEach { $0.close() }
        flows.removeAll()
    }

    private func accept(_ c: NWConnection) {
        let f = Flow(inbound: c, queue: queue)
        let id = ObjectIdentifier(f)
        flows[id] = f
        f.onBytes = { [weak self] n in self?.onBytes?(n) }
        f.onClose = { [weak self] in self?.flows[id] = nil }
        f.start()
    }

    final class Flow {
        let inbound: NWConnection
        let queue: DispatchQueue
        var outs: [String: NWConnection] = [:]
        var lastActive = Date()
        var timer: DispatchSourceTimer?
        var closed = false
        var onBytes: ((Int) -> Void)?
        var onClose: (() -> Void)?

        init(inbound: NWConnection, queue: DispatchQueue) { self.inbound = inbound; self.queue = queue }

        func start() {
            inbound.stateUpdateHandler = { [weak self] s in
                if case .failed = s { self?.close() }
            }
            inbound.start(queue: queue)
            receive()
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now() + 30, repeating: 30, leeway: .seconds(10))
            t.setEventHandler { [weak self] in
                guard let self else { return }
                if Date().timeIntervalSince(self.lastActive) > 60 { self.close() }
            }
            t.resume()
            timer = t
        }

        private func receive() {
            inbound.receiveMessage { [weak self] data, _, _, err in
                guard let self, !self.closed else { return }
                if let data { self.handle(data) }
                if err == nil { self.receive() } else { self.close() }
            }
        }

        /// RSV(2) FRAG(1) ATYP(1) ADDR PORT(2) DATA
        private func handle(_ d: Data) {
            let b = [UInt8](d)
            guard b.count > 4, b[2] == 0 else { return }
            var i = 4
            let host: NWEndpoint.Host
            switch b[3] {
            case 1:
                guard b.count >= i + 6 else { return }
                host = Nat64.host(b[i..<i + 4].map(String.init).joined(separator: ".")); i += 4
            case 4:
                guard b.count >= i + 18 else { return }
                host = .ipv6(IPv6Address(Data(b[i..<i + 16]))!); i += 16
            case 3:
                let n = Int(b[i]); guard b.count >= i + 1 + n + 2 else { return }
                host = NWEndpoint.Host(String(decoding: b[(i + 1)..<(i + 1 + n)], as: UTF8.self)); i += 1 + n
            default: return
            }
            let port = (UInt16(b[i]) << 8) | UInt16(b[i + 1]); i += 2
            let header = Data(b[0..<i])
            let payload = Data(b[i...])
            lastActive = Date()
            onBytes?(payload.count)
            let key = header.base64EncodedString()
            if let c = outs[key] { c.send(content: payload, completion: .idempotent); return }
            guard let p = NWEndpoint.Port(rawValue: port) else { return }
            let c = NWConnection(host: host, port: p, using: .udp)
            outs[key] = c
            c.stateUpdateHandler = { [weak self] s in
                if case .failed = s { self?.outs[key]?.cancel(); self?.outs[key] = nil }
            }
            c.start(queue: queue)
            c.send(content: payload, completion: .idempotent)
            pump(c, header: header)
        }

        private func pump(_ c: NWConnection, header: Data) {
            c.receiveMessage { [weak self] data, _, _, err in
                guard let self, !self.closed else { return }
                if let data, !data.isEmpty {
                    self.lastActive = Date()
                    self.onBytes?(data.count)
                    self.inbound.send(content: header + data, completion: .idempotent)
                }
                if err == nil { self.pump(c, header: header) }
            }
        }

        func close() {
            if closed { return }
            closed = true
            timer?.cancel()
            outs.values.forEach { $0.cancel() }
            outs.removeAll()
            inbound.cancel()
            onClose?()
        }
    }
}
