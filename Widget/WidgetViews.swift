import SwiftUI
import WidgetKit

struct StatusWidgetView: View {
    let snapshot: ProxySnapshot
    let family: WidgetFamily

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: CircularView(s: snapshot)
            case .accessoryRectangular: RectangularView(s: snapshot)
            case .accessoryInline: InlineView(s: snapshot)
            default: SmallView(s: snapshot)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var t = "Hotspot Proxy, \(snapshot.status.title)"
        if let ip = snapshot.hotspotIP, snapshot.status == .running {
            t += ", address \(ip) port \(snapshot.port), \(snapshot.connections) connections"
        }
        return t
    }
}

extension ProxySnapshot {
    var guidance: String {
        switch status {
        case .starting: "Starting proxy…"
        case .stale: "Open app to check status"
        case .running: endpoint ?? "No address"
        case .noHotspot: "Turn on Personal Hotspot"
        case .stopped: "Tap to open"
        case .error: errorMessage ?? "Retry in the app"
        }
    }
    var statsLine: String { "\(connections) conn · \(Format.bytes(bytes))" }
}

private struct CircularView: View {
    let s: ProxySnapshot

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Circle()
                .strokeBorder(lineWidth: 3)
                .opacity(s.status == .running ? 1 : 0.25)
                .padding(2)
                .widgetAccentable()
            VStack(spacing: 0) {
                Image(systemName: s.status.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .widgetAccentable()
                Text(verbatim: s.status == .running ? String(s.connections) : s.status == .stopped ? "OFF" : "!")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .opacity(s.status == .stopped ? 0.6 : 1)
        }
    }
}

private struct RectangularView: View {
    let s: ProxySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(s.status.title, systemImage: s.status.symbol)
                .font(.headline)
                .widgetAccentable()
                .lineLimit(1)
            Text(s.guidance)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if s.status == .running {
                Text(s.statsLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InlineView: View {
    let s: ProxySnapshot

    var body: some View {
        ViewThatFits {
            Label(s.status == .running ? "Proxy \(s.endpoint ?? "")" : "Proxy \(s.status.shortTitle)",
                  systemImage: s.status.symbol)
            Label(s.status.shortTitle, systemImage: s.status.symbol)
        }
    }
}

private struct SmallView: View {
    let s: ProxySnapshot
    @Environment(\.widgetRenderingMode) private var mode

    private var tint: Color { mode == .fullColor ? s.status.color : .primary }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: s.status.symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(mode == .fullColor ? Color.white : Color.primary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(tint.gradient))
                    .widgetAccentable()
                Text(s.status.shortTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if s.status == .running, let ip = s.hotspotIP {
                Text(ip)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(verbatim: ":\(s.port)")
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } else {
                Text(s.guidance)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            if s.status == .running {
                Text(s.statsLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if s.updatedAt > .distantPast {
                Text(s.updatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
