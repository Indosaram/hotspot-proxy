#if canImport(Network)
import XCTest
import Network
@testable import ProxyCore

/// Apple Network.framework integration tests. All destinations are local loopback fixtures.
final class NetworkTests: XCTestCase {
    private final class Fixture {
        let queue = DispatchQueue(label: "proxy.tests")
        let listener: NWListener
        var sessions: [Session] = []
        init(host: String = "127.0.0.1", timeout: TimeInterval = 15) throws {
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(host), port: .any)
            listener = try NWListener(using: params)
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { connection.cancel(); return }
                let session = Session(client: connection, queue: self.queue, handshakeTimeout: timeout)
                self.sessions.append(session)
                session.start()
            }
        }
        func stop() {
            queue.sync {
                listener.cancel()
                sessions.forEach { $0.close() }
                sessions.removeAll()
            }
        }
    }

    private func start(_ fixture: Fixture, host: String = "127.0.0.1") async throws -> NWConnection {
        let ready = expectation(description: "listener ready")
        var failure: NWError?
        fixture.listener.stateUpdateHandler = { state in
            if case .ready = state { ready.fulfill() }
            if case .failed(let error) = state { failure = error; ready.fulfill() }
        }
        fixture.listener.start(queue: fixture.queue)
        await fulfillment(of: [ready], timeout: 3)
        if let failure { throw failure }
        let port = try XCTUnwrap(fixture.listener.port)
        let client = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
        let connected = expectation(description: "client ready")
        client.stateUpdateHandler = { state in
            if case .ready = state { connected.fulfill() }
            if case .failed(let error) = state { failure = error; connected.fulfill() }
        }
        client.start(queue: fixture.queue)
        await fulfillment(of: [connected], timeout: 3)
        client.stateUpdateHandler = nil
        if let failure { throw failure }
        return client
    }

    private func exchange(_ client: NWConnection, bytes: Data, count: Int) async throws -> Data {
        let received = expectation(description: "response")
        var result = Data()
        client.send(content: bytes, completion: .contentProcessed { _ in })
        client.receive(minimumIncompleteLength: count, maximumLength: 65536) { data, _, _, _ in
            result = data ?? Data(); received.fulfill()
        }
        await fulfillment(of: [received], timeout: 3)
        return result
    }

    func testUnsupportedAuthIsRejectedBeforeRequest() async throws {
        let fixture = try Fixture(); defer { fixture.stop() }
        let client = try await start(fixture); defer { client.cancel() }
        let response = try await exchange(client, bytes: Data([5, 1, 2]), count: 2)
        XCTAssertEqual(response, Data([5, 255]))
    }
    func testOutOfRangeHTTPPortReturns400AndServerSurvives() async throws {
        let fixture = try Fixture(); defer { fixture.stop() }
        let client = try await start(fixture); defer { client.cancel() }
        let response = try await exchange(client, bytes: Data("GET http://127.0.0.1:65536/ HTTP/1.1\r\nHost: localhost\r\n\r\n".utf8), count: 12)
        XCTAssertTrue(String(decoding: response, as: UTF8.self).hasPrefix("HTTP/1.1 400"))
    }
    func testIncompleteHandshakeIsClosedByDeadline() async throws {
        let fixture = try Fixture(timeout: 0.1); defer { fixture.stop() }
        let client = try await start(fixture); defer { client.cancel() }
        let ended = expectation(description: "handshake deadline closes stream")
        client.send(content: Data([5]), completion: .contentProcessed { _ in })
        client.receive(minimumIncompleteLength: 1, maximumLength: 16) { _, _, done, error in
            XCTAssertTrue(done || error != nil); ended.fulfill()
        }
        await fulfillment(of: [ended], timeout: 3)
    }
    func testIPv6AssociationReturnsNonzeroIPv6Endpoint() async throws {
        let fixture = try Fixture(host: "::1"); defer { fixture.stop() }
        let client = try await start(fixture, host: "::1"); defer { client.cancel() }
        let greeting = try await exchange(client, bytes: Data([5, 1, 0]), count: 2)
        XCTAssertEqual(greeting, Data([5, 0]))
        let request = Data([5, 3, 0, 4]) + Data(repeating: 0, count: 18)
        let response = try await exchange(client, bytes: request, count: 22)
        XCTAssertEqual(Array(response.prefix(4)), [5, 0, 0, 4])
        let address = try XCTUnwrap(ProxyProtocol.address(Data(response.dropFirst(3)))?.0)
        XCTAssertEqual(address.bytes, Data(repeating: 0, count: 15) + Data([1]))
        XCTAssertGreaterThan(address.port, 0)
    }
    func testAssociationRejectsAnotherClientAddress() async throws {
        let fixture = try Fixture(); defer { fixture.stop() }
        let client = try await start(fixture); defer { client.cancel() }
        _ = try await exchange(client, bytes: Data([5, 1, 0]), count: 2)
        let response = try await exchange(client, bytes: Data([5, 3, 0, 1, 192, 0, 2, 1, 0, 0]), count: 10)
        XCTAssertNotEqual(response[response.startIndex + 1], 0)
    }
    func testUDPRelayEchoAndControlClosure() async throws {
        let fixture = try Fixture(); defer { fixture.stop() }
        let control = try await start(fixture); defer { control.cancel() }
        _ = try await exchange(control, bytes: Data([5, 1, 0]), count: 2)
        let reply = try await exchange(control, bytes: Data([5, 3, 0, 1, 0, 0, 0, 0, 0, 0]), count: 10)
        let relay = try XCTUnwrap(ProxyProtocol.address(Data(reply.dropFirst(3)))?.0)
        XCTAssertGreaterThan(relay.port, 0)

        let params = NWParameters.udp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let echo = try NWListener(using: params)
        defer { echo.cancel() }
        let echoReady = expectation(description: "loopback UDP echo ready")
        var echoConnections: [NWConnection] = []
        echo.newConnectionHandler = { connection in
            echoConnections.append(connection)
            connection.start(queue: fixture.queue)
            func respond() {
                connection.receiveMessage { data, _, _, error in
                    guard error == nil else { return }
                    connection.send(content: data, completion: .contentProcessed { error in
                        if error == nil { respond() }
                    })
                }
            }
            respond()
        }
        echo.stateUpdateHandler = { if case .ready = $0 { echoReady.fulfill() } }
        echo.start(queue: fixture.queue)
        await fulfillment(of: [echoReady], timeout: 3)
        defer { fixture.queue.sync { echoConnections.forEach { $0.cancel() } } }
        let destinationPort = try XCTUnwrap(echo.port?.rawValue)
        let packet = Data([0, 0, 0, 1, 127, 0, 0, 1, UInt8(destinationPort >> 8), UInt8(destinationPort & 255)]) + Data("echo".utf8)
        let udp = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: relay.port)!, using: .udp)
        defer { udp.cancel() }
        udp.start(queue: fixture.queue)
        let echoed = expectation(description: "associated UDP round trip")
        udp.receiveMessage { data, _, _, _ in XCTAssertEqual(data, packet); echoed.fulfill() }
        udp.send(content: packet, completion: .contentProcessed { _ in })
        await fulfillment(of: [echoed], timeout: 3)

        let closed = expectation(description: "TCP control session closed")
        fixture.queue.sync { fixture.sessions[0].onClose = { closed.fulfill() } }
        control.cancel()
        await fulfillment(of: [closed], timeout: 3)
        let unexpected = expectation(description: "no UDP reply after association closes")
        unexpected.isInverted = true
        udp.receiveMessage { data, _, _, _ in if data != nil { unexpected.fulfill() } }
        udp.send(content: packet, completion: .contentProcessed { _ in })
        await fulfillment(of: [unexpected], timeout: 0.3)
    }

}
#endif
