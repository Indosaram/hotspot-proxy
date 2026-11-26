#if os(iOS)
import Foundation
import ActivityKit

struct ProxyActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var status: ProxySnapshot.Status
        var endpoint: String?
        var connections: Int
        var bytes: UInt64
    }

    var startedAt: Date
}
#endif
