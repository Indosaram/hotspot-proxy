import SwiftUI

extension Color {
    static let signalOn = Color("SignalOn")
    static let signalWarn = Color("SignalWarn")
    static let signalOff = Color("SignalOff")
    static let heroTint = Color("HeroTint")
}

extension ProxySnapshot.Status {
    var color: Color {
        switch self {
        case .starting, .stale: .signalWarn
        case .running: .signalOn
        case .noHotspot: .signalWarn
        case .stopped: .signalOff
        case .error: .red
        }
    }

    var symbol: String {
        switch self {
        case .starting: "hourglass"
        case .stale: "questionmark.circle"
        case .running: "personalhotspot"
        case .noHotspot: "personalhotspot.slash"
        case .stopped: "pause.circle"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    var title: String {
        switch self {
        case .starting: "Starting Proxy"
        case .stale: "Status Unavailable"
        case .running: "Proxy Running"
        case .noHotspot: "Hotspot Off"
        case .stopped: "Proxy Off"
        case .error: "Error"
        }
    }

    var shortTitle: String {
        switch self {
        case .starting: "Starting"
        case .stale: "Unverified"
        case .running: "Running"
        case .noHotspot: "Hotspot Off"
        case .stopped: "Off"
        case .error: "Error"
        }
    }
}

enum Format {
    static func bytes(_ b: UInt64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false
        return f.string(fromByteCount: Int64(clamping: b))
    }
}
