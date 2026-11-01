import Foundation
import Network

/// One relay per TCP UDP ASSOCIATE. It is never reachable without a live control session.
/// All state, including stop(), is accessed on the owning Session's serial queue.
final class UdpRelay {
    private let queue: DispatchQueue
    private let local: NWEndpoint.Host
    private let peer: NWEndpoint.Host
    private var clientPort: UInt16
    private var listener: NWListener?
    private var inbound: NWConnection?
    private var outs: [Data: NWConnection] = [:]
    private var activity = DestinationActivity<Data>()
    private var timer: DispatchSourceTimer?
    private var completion: ((Data?) -> Void)?
    private var stopped = false
    private var pendingSends = 0
    var onBytes: ((Int) -> Void)?
    var onFailure: (() -> Void)?

    init(queue: DispatchQueue, local: NWEndpoint.Host, peer: NWEndpoint.Host, clientPort: UInt16) {
        self.queue = queue; self.local = local; self.peer = peer; self.clientPort = clientPort
    }

    func start(_ completion: @escaping (Data?) -> Void) {
        self.completion = completion
        do {
            let params = NWParameters.udp
            params.requiredLocalEndpoint = .hostPort(host: local, port: .any)
            let listener = try NWListener(using: params)
            self.listener = listener
            listener.newConnectionHandler = { [weak self] connection in
                guard let self, !self.stopped else { connection.cancel(); return }
                self.accept(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                guard let self, !self.stopped else { return }
                switch state {
                case .ready:
                    guard let port = listener.port?.rawValue else { self.failed(); return }
                    let response: Data?
                    switch self.local {
                    case .ipv4(let address): response = ProxyProtocol.boundReply(type: 1, bytes: address.rawValue, port: port)
                    case .ipv6(let address): response = ProxyProtocol.boundReply(type: 4, bytes: address.rawValue, port: port)
                    default: response = nil
                    }
                    guard let response else { self.failed(); return }
                    let callback = self.completion; self.completion = nil; callback?(response)
                case .failed, .waiting: self.failed()
                default: break
                }
            }
            listener.start(queue: queue)
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 15, repeating: 15, leeway: .seconds(2))
            timer.setEventHandler { [weak self] in self?.reap() }
            timer.resume(); self.timer = timer
        } catch { failed() }
    }

    private func failed() {
        let callback = completion
        completion = nil
        stop()
        if let callback { callback(nil) } else { onFailure?() }
    }

    private func accept(_ connection: NWConnection) {
        guard inbound == nil, case .hostPort(let host, let port) = connection.endpoint,
              Tcp.sameHost(host, peer), clientPort == 0 || clientPort == port.rawValue else { connection.cancel(); return }
        clientPort = port.rawValue // An unspecified port is pinned to the first datagram from the TCP peer.
        inbound = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection, self.inbound === connection else { return }
            switch state {
            case .failed, .cancelled:
                self.clearDestinations()
                self.inbound = nil
                connection.stateUpdateHandler = nil
                connection.cancel()
            default: break
            }
        }
        connection.start(queue: queue)
        receive(connection)
    }

    private func receive(_ connection: NWConnection) {
        connection.receiveMessage { [weak self, weak connection] data, _, _, error in
            guard let self, !self.stopped, let connection, self.inbound === connection else { return }
            if let data { self.handle(data) }
            if error == nil { self.receive(connection) }
            else { self.clearDestinations(); self.inbound = nil; connection.cancel() }
        }
    }

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private func handle(_ data: Data) {
        guard let (address, payload) = ProxyProtocol.udpPacket(data), pendingSends < 128 else { return }
        reap()
        let key = address.encoded
        let connection: NWConnection
        if let existing = outs[key] { connection = existing }
        else {
            guard activity.canInsert, let port = NWEndpoint.Port(rawValue: address.port) else { return }
            connection = NWConnection(host: NWEndpoint.Host(address.host), port: port, using: .udp)
            outs[key] = connection
            connection.stateUpdateHandler = { [weak self, weak connection] state in
                guard let self, let connection, self.outs[key] === connection else { return }
                if case .failed = state { self.remove(key) }
            }
            connection.start(queue: queue)
            pump(connection, key: key)
        }
        activity.touch(key, now: now)
        pendingSends += 1
        connection.send(content: payload, completion: .contentProcessed { [weak self, weak connection] error in
            guard let self else { return }
            self.pendingSends -= 1
            if error != nil, let connection, self.outs[key] === connection { self.remove(key) }
        })
        onBytes?(payload.count)
    }

    private func pump(_ connection: NWConnection, key: Data) {
        connection.receiveMessage { [weak self, weak connection] data, _, _, error in
            guard let self, !self.stopped, let connection, self.outs[key] === connection else { return }
            if error != nil { self.remove(key); return }
            guard let inbound = self.inbound else { self.remove(key); return }
            if let data {
                self.activity.touch(key, now: self.now)
                self.onBytes?(data.count)
                // One pending reply per destination: do not accumulate an unbounded send queue.
                inbound.send(content: Data([0, 0, 0]) + key + data, completion: .contentProcessed { [weak self, weak connection] error in
                    guard let self, !self.stopped, let connection, self.outs[key] === connection else { return }
                    if error != nil { self.remove(key) } else { self.pump(connection, key: key) }
                })
            } else { self.pump(connection, key: key) }
        }
    }

    private func reap() { activity.expired(now: now).forEach { remove($0) } }
    private func remove(_ key: Data) {
        let connection = outs.removeValue(forKey: key)
        activity.remove(key)
        connection?.stateUpdateHandler = nil
        connection?.cancel()
    }
    private func clearDestinations() { Array(outs.keys).forEach { remove($0) } }

    func stop() {
        guard !stopped else { return }
        stopped = true
        completion = nil
        timer?.cancel(); timer = nil
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel(); listener = nil
        inbound?.stateUpdateHandler = nil
        inbound?.cancel(); inbound = nil
        clearDestinations()
    }
}
