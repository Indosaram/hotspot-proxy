import XCTest
#if SWIFT_PACKAGE
@testable import ProxyCore
#else
@testable import HotspotProxy
#endif

final class ProtocolTests: XCTestCase {
    func testRejectsInvalidPortsWithoutTrapping() {
        for port in ["0", "65536", "999999999999999999999999", "-1", "abc", ""] {
            XCTAssertNil(ProxyProtocol.httpTarget("http://example.com:\(port)/"), port)
            XCTAssertNil(ProxyProtocol.httpTarget("example.com:\(port)", connect: true), port)
        }
        XCTAssertEqual(ProxyProtocol.httpTarget("http://example.com:65535/")?.port, 65535)
        XCTAssertEqual(ProxyProtocol.httpTarget("example.com", connect: true)?.port, 443)
    }
    func testPreservesEncodedPathAndQueryAndTrailingSlash() {
        for path in ["/a%20b", "/dir/", "/a%2Fb/%3F", "/%0D%0A", "/?x=a%26b&y=%20", "/?", "/a//"] {
            XCTAssertEqual(ProxyProtocol.httpTarget("http://example.com" + path)?.path, path)
        }
        XCTAssertEqual(ProxyProtocol.httpTarget("http://example.com?x=1")?.path, "/?x=1")
        XCTAssertEqual(ProxyProtocol.httpTarget("http://example.com")?.path, "/")
    }
    func testRejectsMalformedAndUnsupportedHTTPRequests() {
        for target in ["http://example.com/a b", "http://example.com/\r\nX:yes", "https://example.com/", "file:///tmp/a", "http://u:p@example.com/", "http://example.com/#x", "http://example.com/%oops"] {
            XCTAssertNil(ProxyProtocol.httpTarget(target), target)
        }
        XCTAssertNil(ProxyProtocol.httpTarget("example.com:443/path", connect: true))
        XCTAssertEqual(ProxyProtocol.httpTarget("[::1]:443", connect: true)?.host, "::1")
    }
    func testMethodNegotiationRequiresOfferedNoAuth() {
        XCTAssertTrue(ProxyProtocol.acceptsNoAuthentication(Data([5, 1, 0])))
        XCTAssertTrue(ProxyProtocol.acceptsNoAuthentication(Data([5, 2, 2, 0])))
        for bytes: [UInt8] in [[5, 1, 2], [5, 0], [4, 1, 0], [5, 2, 0]] {
            XCTAssertFalse(ProxyProtocol.acceptsNoAuthentication(Data(bytes)))
        }
    }
    func testIPv6BoundReplyContainsActualAddressAndPort() {
        let ip = Data(repeating: 0, count: 15) + Data([1])
        let reply = ProxyProtocol.boundReply(type: 4, bytes: ip, port: 49153)
        XCTAssertEqual(reply, Data([5, 0, 0, 4]) + ip + Data([192, 1]))
        XCTAssertNil(ProxyProtocol.boundReply(type: 4, bytes: ip, port: 0))
        XCTAssertNil(ProxyProtocol.boundReply(type: 1, bytes: ip, port: 80))
    }
    func testUDPParsingRejectsFragmentsReservedBytesAndTruncation() {
        let header: [UInt8] = [0, 0, 0, 1, 127, 0, 0, 1, 0, 53]
        let parsed = ProxyProtocol.udpPacket(Data(header + [1, 2, 3]))
        XCTAssertEqual(parsed?.0.host, "127.0.0.1")
        XCTAssertEqual(parsed?.0.port, 53)
        XCTAssertEqual(parsed?.1, Data([1, 2, 3]))
        for n in 0..<header.count { XCTAssertNil(ProxyProtocol.udpPacket(Data(header.prefix(n)))) }
        for position in 0...2 {
            var invalid = header; invalid[position] = 1
            XCTAssertNil(ProxyProtocol.udpPacket(Data(invalid)))
        }
        XCTAssertNil(ProxyProtocol.udpPacket(Data([0, 0, 0, 3, 0, 0, 53])))
        XCTAssertNil(ProxyProtocol.udpPacket(Data([0, 0, 0, 1, 127, 0, 0, 1, 0, 0])))
    }
    func testUDPAddressFamiliesAndUnspecifiedAddress() {
        let ipv6 = Data([4]) + Data(repeating: 0, count: 16) + Data([0, 0])
        XCTAssertTrue(ProxyProtocol.address(ipv6)!.0.isUnspecified)
        let domain = Data([3, 11]) + Data("example.com".utf8) + Data([1, 187])
        let address = ProxyProtocol.address(domain)!.0
        XCTAssertEqual(address.host, "example.com")
        XCTAssertEqual(address.port, 443)
        XCTAssertEqual(address.encoded, domain)
    }
    func testActiveDestinationDoesNotKeepOldDestinationsAlive() {
        var activity = DestinationActivity<String>()
        activity.touch("old", now: 0)
        activity.touch("busy", now: 59)
        XCTAssertEqual(activity.expired(now: 60), ["old"])
        XCTAssertEqual(activity.lastUsed.count, 1)
        XCTAssertEqual(activity.expired(now: 119), ["busy"])
    }
    func testDestinationLimitCanRecoverAfterExpiry() {
        var activity = DestinationActivity<Int>()
        for n in 0..<ProxyProtocol.maxUDPDestinations { activity.touch(n, now: 0) }
        XCTAssertFalse(activity.canInsert)
        XCTAssertEqual(activity.expired(now: 60).count, ProxyProtocol.maxUDPDestinations)
        XCTAssertTrue(activity.canInsert)
    }
    func testSnapshotExpiresAndDoesNotLieAboutStoppedState() {
        var snapshot = ProxySnapshot.placeholder
        snapshot.updatedAt = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(snapshot.fresh(at: Date(timeIntervalSince1970: 219)).status, .running)
        XCTAssertEqual(snapshot.fresh(at: Date(timeIntervalSince1970: 220)).status, .stale)
        XCTAssertEqual(snapshot.fresh(at: Date(timeIntervalSince1970: 220)).connections, 0)
        for status: ProxySnapshot.Status in [.stopped, .error] {
            snapshot.status = status
            XCTAssertEqual(snapshot.fresh(at: Date(timeIntervalSince1970: 999)).status, status)
        }
    }
    func testGalleryPreviewRefreshesItsObservationTime() {
        let first = Date(timeIntervalSince1970: 100)
        let later = first.addingTimeInterval(3600)
        XCTAssertEqual(ProxySnapshot.preview(at: first).updatedAt, first)
        let preview = ProxySnapshot.preview(at: later)
        XCTAssertEqual(preview.updatedAt, later)
        XCTAssertEqual(preview.fresh(at: later).status, .running)
        XCTAssertEqual(preview.expiresAt, later.addingTimeInterval(120))
    }
    func testIPv6EndpointUsesBrackets() {
        var snapshot = ProxySnapshot.placeholder
        snapshot.hotspotIP = "fe80::1%bridge100"
        XCTAssertEqual(snapshot.endpoint, "[fe80::1%bridge100]:8080")
    }
    func testSnapshotRoundtripAndUnknownDeepLinks() throws {
        let snapshot = ProxySnapshot.empty
        XCTAssertEqual(try JSONDecoder().decode(ProxySnapshot.self, from: JSONEncoder().encode(snapshot)), snapshot)
        XCTAssertNil(DeepLink(url: URL(string: "https://start")!))
        XCTAssertNil(DeepLink(url: URL(string: "hotspotproxy://unknown")!))
    }
}
