import Foundation
import ActivityKit

struct NaiKangSnapshot: Codable, Hashable {
    var petName: String
    var available: Bool
    var primaryRemaining: Int
    var secondaryRemaining: Int
    var primaryResetsAt: TimeInterval
    var burnRate: Double
    var publicIP: String
    var ipLocation: String
    var localIP: String
    var downloadBps: Double
    var uploadBps: Double
    var updatedAt: TimeInterval

    static let placeholder = NaiKangSnapshot(
        petName: "奶康", available: false, primaryRemaining: 0,
        secondaryRemaining: 0, primaryResetsAt: 0, burnRate: 0,
        publicIP: "等待同步", ipLocation: "等待同步", localIP: "等待同步",
        downloadBps: 0, uploadBps: 0, updatedAt: 0
    )

    static let preview = NaiKangSnapshot(
        petName: "奶康", available: true, primaryRemaining: 68,
        secondaryRemaining: 91, primaryResetsAt: Date().addingTimeInterval(7_200).timeIntervalSince1970,
        burnRate: 5.2, publicIP: "203.0.113.8", ipLocation: "中国 · 上海",
        localIP: "192.168.1.64", downloadBps: 1_540_000,
        uploadBps: 31_000, updatedAt: Date().timeIntervalSince1970
    )

    var updatedDate: Date { Date(timeIntervalSince1970: updatedAt) }
    var resetDate: Date? { primaryResetsAt > 0 ? Date(timeIntervalSince1970: primaryResetsAt) : nil }

    func speed(_ value: Double) -> String {
        if value < 1_024 { return String(format: "%.0f B/s", value) }
        if value < 1_048_576 { return String(format: "%.1f KB/s", value / 1_024) }
        return String(format: "%.2f MB/s", value / 1_048_576)
    }
}

enum NaiKangSharedStore {
    static let appGroup = "group.local.openai.naikang"
    private static let key = "latestSnapshot"

    static func load() -> NaiKangSnapshot {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(NaiKangSnapshot.self, from: data) else {
            return .placeholder
        }
        return snapshot
    }

    static func save(_ snapshot: NaiKangSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let defaults = UserDefaults(suiteName: appGroup)
        defaults?.set(data, forKey: key)
        defaults?.synchronize()
    }
}

struct NaiKangActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var primaryRemaining: Int
        var secondaryRemaining: Int
        var burnRate: Double
        var ipLocation: String
        var updatedAt: TimeInterval
    }

    var petName: String
}

extension NaiKangActivityAttributes.ContentState {
    init(snapshot: NaiKangSnapshot) {
        primaryRemaining = snapshot.primaryRemaining
        secondaryRemaining = snapshot.secondaryRemaining
        burnRate = snapshot.burnRate
        ipLocation = snapshot.ipLocation
        updatedAt = snapshot.updatedAt
    }
}
