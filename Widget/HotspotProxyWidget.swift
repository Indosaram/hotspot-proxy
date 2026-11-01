import SwiftUI
import WidgetKit

struct StatusEntry: TimelineEntry {
    let date: Date
    let snapshot: ProxySnapshot
}

struct StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        let s = context.isPreview ? ProxySnapshot.placeholder : SharedStore.load()
        completion(StatusEntry(date: .now, snapshot: s.fresh(at: .now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        let now = Date()
        let snapshot = SharedStore.load()
        var entries = [StatusEntry(date: now, snapshot: snapshot.fresh(at: now))]
        if [.running, .starting, .noHotspot].contains(snapshot.status), snapshot.expiresAt > now {
            entries.append(StatusEntry(date: snapshot.expiresAt, snapshot: snapshot.fresh(at: snapshot.expiresAt)))
        }
        // The pre-scheduled expiry entry remains useful even if iOS delays the next reload.
        completion(Timeline(entries: entries, policy: .after(max(now.addingTimeInterval(60), snapshot.expiresAt))))
    }
}

struct HotspotStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedStore.widgetKind, provider: StatusProvider()) { entry in
            EntryView(entry: entry)
        }
        .configurationDisplayName("Proxy Status")
        .description("Shows Hotspot Proxy status and the address to connect to.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .systemSmall])
    }
}

private struct EntryView: View {
    let entry: StatusEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        StatusWidgetView(snapshot: entry.snapshot, family: family)
            .widgetURL(DeepLink.open.url)
            .containerBackground(for: .widget) {
                if family == .systemSmall { Color("WidgetBackground") } else { Color.clear }
            }
    }
}

@main
struct HotspotProxyWidgets: WidgetBundle {
    var body: some Widget {
        HotspotStatusWidget()
    }
}

private extension ProxySnapshot {
    static var noHotspotSample: ProxySnapshot {
        var s = ProxySnapshot.placeholder
        s.status = .noHotspot; s.hotspotIP = nil; s.connections = 0; s.bytes = 0
        return s
    }
    static var stoppedSample: ProxySnapshot {
        var s = noHotspotSample
        s.status = .stopped
        return s
    }
}

#Preview("Rectangular", as: .accessoryRectangular) {
    HotspotStatusWidget()
} timeline: {
    StatusEntry(date: .now, snapshot: .placeholder)
    StatusEntry(date: .now, snapshot: .noHotspotSample)
    StatusEntry(date: .now, snapshot: .stoppedSample)
}

#Preview("Circular", as: .accessoryCircular) {
    HotspotStatusWidget()
} timeline: {
    StatusEntry(date: .now, snapshot: .placeholder)
    StatusEntry(date: .now, snapshot: .stoppedSample)
}

#Preview("Inline", as: .accessoryInline) {
    HotspotStatusWidget()
} timeline: {
    StatusEntry(date: .now, snapshot: .placeholder)
}

#Preview("Small", as: .systemSmall) {
    HotspotStatusWidget()
} timeline: {
    StatusEntry(date: .now, snapshot: .placeholder)
    StatusEntry(date: .now, snapshot: .noHotspotSample)
}
