import Foundation
import WidgetKit

@MainActor
final class NaiKangAppModel: ObservableObject {
    @Published var snapshot = NaiKangSharedStore.load()
    @Published var statusMessage = "请登录 ChatGPT 后读取额度"
    @Published var isRefreshingNetwork = false
    @Published var liveActivityEnabled = false

    private let defaults = UserDefaults.standard

    init() {
        liveActivityEnabled = LiveActivityManager.shared.isRunning
    }

    func applyBrowserUsage(text: String) -> BrowserUsageResult {
        let result = BrowserUsageParser.parse(text)
        guard result.primaryRemaining != nil || result.secondaryRemaining != nil else {
            statusMessage = "未识别到额度，请确认已打开 ChatGPT 的 Usage 页面"
            return result
        }

        let now = Date().timeIntervalSince1970
        let primary = result.primaryRemaining ?? snapshot.primaryRemaining
        let secondary = result.secondaryRemaining ?? snapshot.secondaryRemaining
        let burnRate = calculatedBurnRate(for: primary, at: now)

        snapshot.petName = "奶康"
        snapshot.available = true
        snapshot.primaryRemaining = primary
        snapshot.secondaryRemaining = secondary
        snapshot.burnRate = burnRate
        snapshot.updatedAt = now
        publishSnapshot()

        let primaryText = result.primaryRemaining.map { "5 小时剩余 \($0)%" } ?? "5 小时未识别"
        let secondaryText = result.secondaryRemaining.map { "7 天剩余 \($0)%" } ?? "7 天未识别"
        statusMessage = "已读取 · \(primaryText) · \(secondaryText)"
        return result
    }

    func refreshNetworkInfo() async {
        guard !isRefreshingNetwork else { return }
        isRefreshingNetwork = true
        defer { isRefreshingNetwork = false }

        guard let url = URL(string: "https://ipwho.is/?lang=zh-CN&fields=ip,success,country,region,city") else { return }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            let info = try JSONDecoder().decode(IPWhoResponse.self, from: data)
            guard info.success != false, let address = info.ip else { return }
            snapshot.publicIP = address
            snapshot.ipLocation = [info.country, info.region, info.city]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .reduce(into: [String]()) { parts, item in
                    if !parts.contains(item) { parts.append(item) }
                }
                .joined(separator: " · ")
            snapshot.localIP = "本机浏览器"
            snapshot.downloadBps = 0
            snapshot.uploadBps = 0
            snapshot.updatedAt = Date().timeIntervalSince1970
            publishSnapshot()
        } catch {
            if snapshot.publicIP == "等待同步" {
                snapshot.publicIP = "获取失败"
                snapshot.ipLocation = "获取失败"
                publishSnapshot()
            }
        }
    }

    func toggleLiveActivity() async {
        if LiveActivityManager.shared.isRunning {
            await LiveActivityManager.shared.stop()
        } else {
            await LiveActivityManager.shared.start(with: snapshot)
        }
        liveActivityEnabled = LiveActivityManager.shared.isRunning
    }

    private func calculatedBurnRate(for remaining: Int, at timestamp: TimeInterval) -> Double {
        let oldRemaining = defaults.object(forKey: "lastBrowserQuotaRemaining") as? Int
        let oldTimestamp = defaults.double(forKey: "lastBrowserQuotaTimestamp")
        defaults.set(remaining, forKey: "lastBrowserQuotaRemaining")
        defaults.set(timestamp, forKey: "lastBrowserQuotaTimestamp")

        guard let oldRemaining, oldTimestamp > 0, oldRemaining >= remaining else {
            return snapshot.burnRate
        }
        let hours = (timestamp - oldTimestamp) / 3_600
        guard hours >= 0.03 else { return snapshot.burnRate }
        return max(0, Double(oldRemaining - remaining) / hours)
    }

    private func publishSnapshot() {
        NaiKangSharedStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        Task { await LiveActivityManager.shared.update(with: snapshot) }
    }
}

struct BrowserUsageResult: Equatable {
    var primaryRemaining: Int?
    var secondaryRemaining: Int?
}

enum BrowserUsageParser {
    private enum PercentageKind { case remaining, used, unknown }
    private static let primaryLabels = ["5 小时限额", "5小时限额", "5 小时", "5小时", "5 hour", "5-hour", "5h"]
    private static let secondaryLabels = ["每周限额", "每周", "7 天限额", "7天限额", "7 天", "7天", "weekly", "week limit", "7 day", "7-day"]

    static func parse(_ text: String) -> BrowserUsageResult {
        let normalized = text.replacingOccurrences(of: "\u{00a0}", with: " ")
        return BrowserUsageResult(
            primaryRemaining: remainingPercentage(in: normalized, labels: primaryLabels),
            secondaryRemaining: remainingPercentage(in: normalized, labels: secondaryLabels)
        )
    }

    private static func remainingPercentage(in text: String, labels: [String]) -> Int? {
        let lowercased = text.lowercased()
        for label in labels {
            guard let labelRange = lowercased.range(of: label.lowercased()) else { continue }
            let maximumEnd = lowercased.index(labelRange.upperBound, offsetBy: 220, limitedBy: lowercased.endIndex) ?? lowercased.endIndex
            let followingRange = labelRange.upperBound..<maximumEnd
            let nextSectionStart = (primaryLabels + secondaryLabels)
                .compactMap { boundary in
                    lowercased.range(of: boundary.lowercased(), range: followingRange)?.lowerBound
                }
                .min() ?? maximumEnd
            let context = String(lowercased[labelRange.upperBound..<nextSectionStart])
            if let value = percentage(in: context, kind: .remaining) { return value }
            if let value = percentage(in: context, kind: .used) { return 100 - value }
            if let value = percentage(in: context, kind: .unknown) { return value }
        }
        return nil
    }

    private static func percentage(in text: String, kind: PercentageKind) -> Int? {
        let patterns: [String]
        switch kind {
        case .remaining:
            patterns = [
                #"(?:剩余|remaining|left)[^0-9]{0,20}([0-9]{1,3}(?:\.[0-9]+)?)\s*%"#,
                #"([0-9]{1,3}(?:\.[0-9]+)?)\s*%[^\n]{0,20}(?:剩余|remaining|left)"#
            ]
        case .used:
            patterns = [
                #"(?:已使用|使用量|used)[^0-9]{0,20}([0-9]{1,3}(?:\.[0-9]+)?)\s*%"#,
                #"([0-9]{1,3}(?:\.[0-9]+)?)\s*%[^\n]{0,20}(?:已使用|used)"#
            ]
        case .unknown:
            patterns = [#"([0-9]{1,3}(?:\.[0-9]+)?)\s*%"#]
        }

        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let valueRange = Range(match.range(at: 1), in: text),
                  let value = Double(text[valueRange]) else { continue }
            return min(100, max(0, Int(value.rounded())))
        }
        return nil
    }
}

private struct IPWhoResponse: Decodable {
    var ip: String?
    var success: Bool?
    var country: String?
    var region: String?
    var city: String?
}
