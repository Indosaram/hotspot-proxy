import SwiftUI
import UIKit

struct SignalRing: View {
    let status: ProxySnapshot.Status
    var size: CGFloat = 132
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private var animating: Bool { status == .running && !reduceMotion }

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .strokeBorder(status.color.opacity(ringOpacity(i)), lineWidth: 2)
                    .frame(width: size * ringScale(i), height: size * ringScale(i))
                    .scaleEffect(animating && pulse ? 1.05 : 0.94)
                    .opacity(animating && pulse ? 0.55 : 1)
                    .animation(animating ? .easeInOut(duration: 2.4).repeatForever().delay(Double(i) * 0.3) : .default,
                               value: pulse)
            }
            Circle()
                .fill(status.color.gradient)
                .frame(width: size * 0.42, height: size * 0.42)
                .shadow(color: status.color.opacity(0.35), radius: 12, y: 6)
            Image(systemName: status.symbol)
                .font(.system(size: size * 0.18, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: size, height: size)
        .animation(Motion.standard, value: status)
        .onAppear { pulse = true }
        .accessibilityHidden(true)
    }

    private func ringScale(_ i: Int) -> CGFloat { 0.6 + CGFloat(i) * 0.2 }
    private func ringOpacity(_ i: Int) -> Double {
        let base = status == .stopped ? 0.3 : 0.9
        return base - Double(i) * 0.25
    }
}

struct StatusHero: View {
    let status: ProxySnapshot.Status
    let endpoint: String?
    let errorMessage: String?
    var onCopy: () -> Bool
    var onRetry: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(spacing: Space.l) {
            SignalRing(status: status)
                .padding(.top, Space.s)
            VStack(spacing: Space.xs) {
                Label(status.title, systemImage: "circle.fill")
                    .labelStyle(StatusDotLabelStyle(color: status.color))
                    .font(.headline)
                content
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.xl)
        .padding(.horizontal, Space.l)
        .background {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay {
                    if status == .running {
                        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                            .fill(LinearGradient(colors: [Color.heroTint, Color.heroTint.opacity(0)],
                                                 startPoint: .top, endPoint: .bottom))
                            .transition(.opacity)
                    }
                }
        }
        .animation(Motion.standard, value: status)
        .sensoryFeedback(.impact(weight: .light), trigger: copied) { _, new in new }
    }

    @ViewBuilder private var content: some View {
        switch status {
        case .starting:
            Text("Waiting for the hotspot listener to become ready.").foregroundStyle(.secondary)
        case .stale:
            Text("Open the app to check the proxy.").foregroundStyle(.secondary)
        case .running:
            if let endpoint {
                Text(endpoint)
                    .font(.largeTitle.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .textSelection(.enabled)
                    .accessibilityLabel("Proxy address \(endpoint.replacingOccurrences(of: ":", with: " port "))")
                Text("Enter this as the proxy server on other devices")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button {
                    if onCopy() {
                        copied = true
                        Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy Address", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.subheadline.weight(.semibold))
                        .contentTransition(.symbolEffect(.replace))
                        .padding(.horizontal, Space.l)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .padding(.top, Space.s)
                .accessibilityLabel("Copy address")
            }
        case .noHotspot:
            Text("Turn On Personal Hotspot")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("Go to Settings › Personal Hotspot and enable ‘Allow Others to Join’. The proxy address appears here once it’s on.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .frame(minHeight: 44)
            .padding(.top, Space.s)
        case .stopped:
            Text("Proxy Is Off")
                .font(.title2.weight(.semibold))
            Text("Start it below and devices on your hotspot will reach the internet through this iPhone.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        case .error:
            Text("Couldn’t Start the Proxy")
                .font(.title2.weight(.semibold))
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            Button("Try Again", action: onRetry)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .frame(minHeight: 44)
                .padding(.top, Space.s)
        }
    }
}

struct StatusDotLabelStyle: LabelStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Space.s) {
            configuration.icon.font(.system(size: 8)).foregroundStyle(color)
            configuration.title
        }
    }
}

struct PowerButton: View {
    let running: Bool
    let action: () -> Void
    @State private var tick = 0

    var body: some View {
        Button {
            tick += 1
            action()
        } label: {
            Label(running ? "Stop Proxy" : "Start Proxy", systemImage: running ? "stop.fill" : "play.fill")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 56)
                .foregroundStyle(running ? Color.primary : Color.white)
                .background(Capsule().fill(running ? AnyShapeStyle(Color(.tertiarySystemFill)) : AnyShapeStyle(Color.accentColor.gradient)))
                .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
        .sensoryFeedback(running ? .success : .impact(weight: .light), trigger: tick)
        .accessibilityHint(running ? "Disconnects hotspot devices from the proxy" : "Lets hotspot devices use this iPhone as a proxy")
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.micro, value: configuration.isPressed)
    }
}

struct StatTile<Value: View>: View {
    let symbol: String
    let label: String
    @ViewBuilder let value: () -> Value

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)
            value()
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.m)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct CopyableRow: View {
    let title: String
    let value: String
    @State private var copied = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                Text(value)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            Spacer()
            Button {
                UIPasteboard.general.string = value
                copied = true
                Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Copy \(title)")
        }
        .sensoryFeedback(.impact(weight: .light), trigger: copied) { _, new in new }
    }
}

struct SetupStep: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.accentColor))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number). \(title). \(detail)")
    }
}
