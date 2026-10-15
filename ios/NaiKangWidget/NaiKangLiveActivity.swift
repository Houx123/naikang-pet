import ActivityKit
import SwiftUI
import WidgetKit

struct NaiKangLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NaiKangActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Image("NaiKang").renderingMode(.original).resizable().scaledToFit()
                    .frame(width: 54, height: 54).clipShape(Circle()).unredacted()
                VStack(alignment: .leading, spacing: 4) {
                    Text("奶康 · 额度剩余 \(context.state.primaryRemaining)%").font(.headline)
                    ProgressView(value: Double(context.state.primaryRemaining), total: 100).tint(.orange)
                    Text("7 天 \(context.state.secondaryRemaining)% · \(context.state.ipLocation)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.vertical, 4)
            .activityBackgroundTint(Color(.secondarySystemBackground))
            .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image("NaiKang").renderingMode(.original).resizable().scaledToFit()
                        .frame(width: 44, height: 44).clipShape(Circle()).unredacted()
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.primaryRemaining)%").font(.title2.bold()).foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text("7 天 \(context.state.secondaryRemaining)%")
                        Spacer()
                        Text(context.state.ipLocation).lineLimit(1)
                    }.font(.caption)
                }
            } compactLeading: {
                Image("NaiKang").renderingMode(.original).resizable().scaledToFit()
                    .clipShape(Circle()).unredacted()
            } compactTrailing: {
                Text("\(context.state.primaryRemaining)%").font(.caption.bold()).foregroundStyle(.orange)
            } minimal: {
                Text("\(context.state.primaryRemaining)").font(.caption2.bold())
            }
            .widgetURL(URL(string: "naikang://status"))
            .keylineTint(.orange)
        }
    }
}
