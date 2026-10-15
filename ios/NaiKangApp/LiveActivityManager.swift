import ActivityKit
import Foundation

@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()
    private init() {}

    var isRunning: Bool { !Activity<NaiKangActivityAttributes>.activities.isEmpty }

    func start(with snapshot: NaiKangSnapshot) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, !isRunning else { return }
        let attributes = NaiKangActivityAttributes(petName: snapshot.petName)
        let state = NaiKangActivityAttributes.ContentState(snapshot: snapshot)
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(120))
        _ = try? Activity.request(attributes: attributes, content: content, pushType: nil)
    }

    func update(with snapshot: NaiKangSnapshot) async {
        let state = NaiKangActivityAttributes.ContentState(snapshot: snapshot)
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(120))
        for activity in Activity<NaiKangActivityAttributes>.activities {
            await activity.update(content)
        }
    }

    func stop() async {
        for activity in Activity<NaiKangActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
