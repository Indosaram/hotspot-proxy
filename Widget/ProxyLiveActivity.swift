#if os(iOS)
import SwiftUI
import WidgetKit
import ActivityKit

private let proxyGreen = Color(red: 0.20, green: 0.85, blue: 0.55)
private let proxyAmber = Color(red: 1.00, green: 0.72, blue: 0.25)
private let proxyGrey = Color(white: 0.62)

private func tint(for status: ProxySnapshot.Status) -> Color {
    switch status {
    case .running: proxyGreen
    case .starting, .noHotspot, .stale: proxyAmber
    case .stopped, .error: proxyGrey
    }
}

struct ProxyLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ProxyActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: context.state.status.symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(tint(for: context.state.status))

                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.status.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Text(subtitle(for: context.state))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text(context.attributes.startedAt, style: .timer)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .activityBackgroundTint(Color.black.opacity(0.35))
            .activitySystemActionForegroundColor(tint(for: context.state.status))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.status.symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(tint(for: context.state.status))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.startedAt, style: .timer)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 1) {
                        Text(context.state.status.title)
                            .font(.system(size: 13, weight: .semibold))
                        Text(subtitle(for: context.state))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.status.symbol)
                    .foregroundStyle(tint(for: context.state.status))
            } compactTrailing: {
                Text("\(context.state.connections)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            } minimal: {
                Image(systemName: context.state.status.symbol)
                    .foregroundStyle(tint(for: context.state.status))
            }
        }
    }

    private func subtitle(for state: ProxyActivityAttributes.ContentState) -> String {
        if let endpoint = state.endpoint {
            return "\(endpoint) · \(state.connections) conn · \(Format.bytes(state.bytes))"
        }
        switch state.status {
        case .running: return "No address"
        case .starting: return "Starting proxy…"
        case .stale: return "Open app to check status"
        case .noHotspot: return "Turn on Personal Hotspot"
        case .stopped: return "Tap to open"
        case .error: return "Retry in the app"
        }
    }
}
#endif
