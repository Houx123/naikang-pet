import SwiftUI
import WidgetKit

struct NaiKangEntry: TimelineEntry {
    let date: Date
    let snapshot: NaiKangSnapshot
}

struct NaiKangProvider: TimelineProvider {
    func placeholder(in context: Context) -> NaiKangEntry {
        NaiKangEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (NaiKangEntry) -> Void) {
        completion(NaiKangEntry(date: .now, snapshot: context.isPreview ? .preview : NaiKangSharedStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NaiKangEntry>) -> Void) {
        let entry = NaiKangEntry(date: .now, snapshot: NaiKangSharedStore.load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60))))
    }
}

struct NaiKangWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NaiKangEntry

    var body: some View {
        switch family {
        case .systemSmall: small
        case .accessoryRectangular: lockScreen
        default: medium
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image("NaiKang").renderingMode(.original).resizable().scaledToFit()
                    .frame(width: 46, height: 46).clipShape(Circle()).unredacted()
                Spacer()
                Text("\(entry.snapshot.primaryRemaining)%").font(.title2.bold())
            }
            Text("奶康 · 5 小时额度").font(.caption.bold())
            ProgressView(value: Double(entry.snapshot.primaryRemaining), total: 100)
                .tint(entry.snapshot.primaryRemaining > 20 ? .green : .red)
            Text(entry.snapshot.ipLocation).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private var medium: some View {
        HStack(spacing: 14) {
            Image("NaiKang").renderingMode(.original).resizable().scaledToFit().frame(width: 82, height: 82)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous)).unredacted()
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text("奶康").font(.headline); Spacer(); Text("5h \(entry.snapshot.primaryRemaining)%").bold() }
                ProgressView(value: Double(entry.snapshot.primaryRemaining), total: 100).tint(.orange)
                HStack { Text("7d \(entry.snapshot.secondaryRemaining)%"); Spacer(); Text(entry.snapshot.ipLocation).lineLimit(1) }
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Label(entry.snapshot.speed(entry.snapshot.downloadBps), systemImage: "arrow.down")
                    Label(entry.snapshot.speed(entry.snapshot.uploadBps), systemImage: "arrow.up")
                }
                .font(.caption2.monospacedDigit())
            }
        }
    }

    private var lockScreen: some View {
        HStack {
            Image("NaiKang").renderingMode(.original).resizable().scaledToFit()
                .frame(width: 34, height: 34).clipShape(Circle()).unredacted()
            VStack(alignment: .leading) {
                Text("奶康 · 剩余 \(entry.snapshot.primaryRemaining)%").font(.headline)
                Text(entry.snapshot.ipLocation).font(.caption).lineLimit(1)
            }
        }
    }
}

struct NaiKangHomeWidget: Widget {
    let kind = "NaiKangHomeWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NaiKangProvider()) { entry in
            NaiKangWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(URL(string: "naikang://status"))
        }
        .configurationDisplayName("奶康")
        .description("查看额度、IP 归属地和网络状态。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

