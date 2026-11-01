import Foundation

/// Parsing is independent of sockets so malformed input can be tested without network access.
enum ProxyProtocol {
    static let maxSessions = 128
    static let handshakeTimeout: TimeInterval = 15
    static let maxUDPDestinations = 64
    static let udpIdleTimeout: TimeInterval = 60

    struct Target: Equatable {
        let host: String
        let port: UInt16
        let path: String
    }

    static func httpTarget(_ text: String, connect: Bool = false) -> Target? {
        // Do not let Foundation repair whitespace, controls or invalid percent escapes.
        guard !text.isEmpty, text.utf8.allSatisfy({ $0 > 32 && $0 < 127 }),
              let c = URLComponents(string: connect ? "http://" + text : text),
              c.scheme?.lowercased() == "http", c.user == nil, c.password == nil,
              c.fragment == nil, let host = c.host, !host.isEmpty,
              let port = UInt16(exactly: c.port ?? (connect ? 443 : 80)), port > 0 else { return nil }
        if connect && (!c.percentEncodedPath.isEmpty || c.percentEncodedQuery != nil) { return nil }
        // Validate explicit ports too: an empty, overflowed or malformed port must not become the default.
        let authority = (connect ? text : String(text.dropFirst(7))).prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        let suffix: Substring
        if authority.hasPrefix("[") {
            guard let end = authority.firstIndex(of: "]") else { return nil }
            suffix = authority[authority.index(after: end)...]
        } else if let colon = authority.firstIndex(of: ":") {
            suffix = authority[colon...]
        } else { suffix = "" }
        if !suffix.isEmpty {
            guard suffix.first == ":", !suffix.dropFirst().isEmpty,
                  suffix.dropFirst().allSatisfy({ $0.isASCII && $0.isNumber }),
                  UInt16(suffix.dropFirst()) == port else { return nil }
        }
        let path = (c.percentEncodedPath.isEmpty ? "/" : c.percentEncodedPath)
            + (c.percentEncodedQuery.map { "?" + $0 } ?? "")
        // URLComponents may repair a stray %. Reject that instead of silently changing the target.
        let originalPath = String((connect ? "" : String(text.dropFirst(7))).drop(while: { $0 != "/" && $0 != "?" }))
        if !connect && !originalPath.isEmpty {
            let expected = originalPath.hasPrefix("?") ? "/" + originalPath : originalPath
            guard path == expected else { return nil }
        }
        let unbracketed = host.hasPrefix("[") && host.hasSuffix("]") ? String(host.dropFirst().dropLast()) : host
        return Target(host: unbracketed, port: port, path: path)
    }

    static func acceptsNoAuthentication(_ greeting: Data) -> Bool {
        let b = [UInt8](greeting)
        return b.count >= 3 && b[0] == 5 && Int(b[1]) == b.count - 2 && b.dropFirst(2).contains(0)
    }

    struct Address: Equatable {
        let type: UInt8
        let bytes: Data
        let host: String
        let port: UInt16
        var isUnspecified: Bool { (type == 1 || type == 4) && bytes.allSatisfy { $0 == 0 } }
        var encoded: Data {
            Data([type]) + (type == 3 ? Data([UInt8(bytes.count)]) : Data()) + bytes
                + Data([UInt8(port >> 8), UInt8(port & 255)])
        }
    }

    /// Address begins at ATYP. Returns bytes consumed, permitting a UDP payload after it.
    static func address(_ data: Data) -> (Address, Int)? {
        let b = [UInt8](data)
        guard let type = b.first else { return nil }
        let start: Int, count: Int
        switch type {
        case 1: start = 1; count = 4
        case 4: start = 1; count = 16
        case 3:
            guard b.count >= 2, b[1] > 0 else { return nil }
            start = 2; count = Int(b[1])
        default: return nil
        }
        guard b.count >= start + count + 2 else { return nil }
        let raw = Data(b[start..<start + count])
        let host: String
        switch type {
        case 1: host = raw.map(String.init).joined(separator: ".")
        case 4:
            let a = [UInt8](raw)
            host = stride(from: 0, to: 16, by: 2).map { String((UInt16(a[$0]) << 8) | UInt16(a[$0 + 1]), radix: 16) }.joined(separator: ":")
        default:
            guard let name = String(data: raw, encoding: .utf8),
                  name.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else { return nil }
            host = name
        }
        let port = (UInt16(b[start + count]) << 8) | UInt16(b[start + count + 1])
        return (Address(type: type, bytes: raw, host: host, port: port), start + count + 2)
    }

    static func udpPacket(_ data: Data) -> (Address, Data)? {
        let b = [UInt8](data)
        guard b.count >= 4, b[0] == 0, b[1] == 0, b[2] == 0,
              let (address, length) = address(Data(b.dropFirst(3))), address.port > 0 else { return nil }
        return (address, Data(b.dropFirst(3 + length)))
    }

    static func boundReply(type: UInt8, bytes: Data, port: UInt16) -> Data? {
        guard port > 0, (type == 1 && bytes.count == 4) || (type == 4 && bytes.count == 16) else { return nil }
        return Data([5, 0, 0]) + Address(type: type, bytes: bytes, host: "", port: port).encoded
    }
}

/// Monotonic timestamps are supplied by the caller; traffic to one destination cannot renew another.
struct DestinationActivity<Key: Hashable> {
    private(set) var lastUsed: [Key: TimeInterval] = [:]
    mutating func touch(_ key: Key, now: TimeInterval) { lastUsed[key] = now }
    mutating func remove(_ key: Key) { lastUsed[key] = nil }
    mutating func expired(now: TimeInterval) -> [Key] {
        let keys = lastUsed.filter { now - $0.value >= ProxyProtocol.udpIdleTimeout }.map(\.key)
        keys.forEach { lastUsed[$0] = nil }
        return keys
    }
    var canInsert: Bool { lastUsed.count < ProxyProtocol.maxUDPDestinations }
}
