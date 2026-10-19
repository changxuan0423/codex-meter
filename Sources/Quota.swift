import Foundation

struct QuotaWindow: Decodable {
    let usedPercent: Double
    let windowDurationMins: Int?
    let resetsAt: Double?

    var remaining: Int { Int((100 - usedPercent).rounded()) }
    var resetDate: Date? { resetsAt.map(Date.init(timeIntervalSince1970:)) }
    func isExpired(at now: Date = Date()) -> Bool {
        resetDate.map { $0 <= now } ?? false
    }
}

struct QuotaBucket: Decodable {
    let limitId: String?
    let primary: QuotaWindow?
    let secondary: QuotaWindow?
    let planType: String?
}

struct QuotaSnapshot: Decodable {
    let rateLimits: QuotaBucket?
    let rateLimitsByLimitId: [String: QuotaBucket]?

    // Prefer the explicit Codex bucket. Never substitute another model's quota.
    var codex: QuotaBucket? {
        if let buckets = rateLimitsByLimitId, !buckets.isEmpty {
            return buckets["codex"]
        }
        guard rateLimits?.limitId == nil || rateLimits?.limitId == "codex" else { return nil }
        return rateLimits
    }

    func window(minutes: Int) -> QuotaWindow? {
        [codex?.primary, codex?.secondary].compactMap { $0 }.first {
            $0.windowDurationMins == minutes && $0.usedPercent.isFinite &&
            (0...100).contains($0.usedPercent) &&
            ($0.resetsAt == nil || ($0.resetsAt!.isFinite && $0.resetsAt! > 0))
        }
    }

    var fiveHour: QuotaWindow? { window(minutes: 300) }
    var weekly: QuotaWindow? { window(minutes: 10080) }
}

enum MeterError: LocalizedError {
    case missingCLI, timedOut, serverStopped, protocolError, signIn, serverError
    var errorDescription: String? {
        switch self {
        case .missingCLI: return "未找到 Codex。请安装 Codex CLI 或桌面应用后重试。"
        case .timedOut: return "读取额度超时，请检查网络后刷新。"
        case .serverStopped: return "Codex 服务未能启动，请打开 Codex 确认登录后重试。"
        case .protocolError: return "无法识别 Codex 返回的数据，请更新 Codex 后重试。"
        case .signIn: return "请先在 Codex 登录 ChatGPT 账户，再刷新额度。"
        case .serverError: return "Codex 暂时无法读取额度，请稍后刷新。"
        }
    }
}

enum MeterFormat {
    static func resetTime(_ date: Date?) -> String {
        guard let date else { return "--:--" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    static func resetDescription(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "未提供重置时间" }
        guard date > now else { return "等待最新额度" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "'今天' HH:mm" : "M月d日 HH:mm"
        return formatter.string(from: date) + " 重置"
    }
}
