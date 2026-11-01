import SwiftUI

struct MainView: View {
    @EnvironmentObject var m: ProxyModel
    @Environment(\.scenePhase) private var phase
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showSettings = ProcessInfo.processInfo.arguments.contains("-showSettings")

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Space.l) {
                    StatusHero(status: m.status, endpoint: m.endpoint, errorMessage: m.error,
                               onCopy: { m.copyEndpoint() }, onRetry: { m.start() })
                    PowerButton(running: m.requested || m.running) { m.toggle() }
                    stats
                    guideLink
                }
                .padding(.horizontal, Space.l)
                .padding(.bottom, Space.xxl)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Hotspot Proxy")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
            }
            .navigationDestination(for: Guide.self) { g in
                switch g {
                case .connect: ConnectGuideView()
                case .mac: MacSetupView()
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView().environmentObject(m)
            }
        }
        .onChange(of: phase, initial: true) { _, p in m.setVisible(p == .active) }
    }

    private var stats: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Space.s))
            : AnyLayout(HStackLayout(spacing: Space.s))
        return layout {
            StatTile(symbol: "point.3.connected.trianglepath.dotted", label: "Connections") {
                Text(verbatim: String(m.connections))
            }
            StatTile(symbol: "arrow.up.arrow.down", label: "Transferred") {
                Text(Format.bytes(m.bytes))
            }
            StatTile(symbol: "clock", label: "Uptime") {
                if let start = m.startedAt, m.running {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(Duration.seconds(max(0, ctx.date.timeIntervalSince(start))),
                             format: .time(pattern: .hourMinuteSecond))
                    }
                } else {
                    Text("–")
                }
            }
        }
        .animation(Motion.standard, value: m.connections)
    }

    private var guideLink: some View {
        VStack(spacing: 0) {
            NavigationLink(value: Guide.connect) {
                GuideRow(symbol: "laptopcomputer.and.iphone", title: "Connect Other Devices", subtitle: "iPhone · Mac · Android · Windows")
            }
            Divider().padding(.leading, 56)
            NavigationLink(value: Guide.mac) {
                GuideRow(symbol: "macbook", title: "Mac Auto-Connect (TUN)", subtitle: "Route all Mac traffic automatically on hotspot")
            }
        }
        .buttonStyle(.plain)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
    }
}

enum Guide: Hashable { case connect, mac }

private struct GuideRow: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: Space.m) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body).foregroundStyle(.primary)
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}
