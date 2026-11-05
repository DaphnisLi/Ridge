import Foundation
import SwiftUI

/// AI 额度提供商。MVP 仅落地 Cursor。
enum AIUsageProviderID: String, CaseIterable, Identifiable, Codable {
    case cursor

    var id: String { rawValue }

    var displayName: String { L10n.AIUsage.providerCursor }
}

/// 三阶流体态（对照设计稿 60 / 30 / 10）。
enum AIUsageStage: String, Hashable {
    case abundant
    case warning
    case critical
    case unknown

    /// 岛上胶囊强调色（对照新稿：绿 / `#facc15` / error）。
    var accent: Color {
        switch self {
        case .abundant:
            return Color(red: 0.447, green: 0.996, blue: 0.522) // secondary-fixed
        case .warning:
            return Color(red: 0.980, green: 0.800, blue: 0.082) // #facc15
        case .critical:
            return Color(red: 0.729, green: 0.102, blue: 0.102)
        case .unknown:
            return Color.white.opacity(0.45)
        }
    }

    /// 设置阈值卡边框 / 点色。
    var settingsAccent: Color {
        switch self {
        case .abundant: return SettingsChrome.secondary
        case .warning: return Color(red: 0.980, green: 0.800, blue: 0.082)
        case .critical: return SettingsChrome.error
        case .unknown: return SettingsChrome.outline
        }
    }

    var label: String {
        switch self {
        case .abundant: return L10n.AIUsage.stageAbundant
        case .warning: return L10n.AIUsage.stageWarning
        case .critical: return L10n.AIUsage.stageCritical
        case .unknown: return L10n.AIUsage.stageUnknown
        }
    }

    /// 预览舞台宽度上限参考；真岛高度由内容 + IslandChrome 撑开（勿再假定 36pt 内容高）。
    var capsuleSize: CGSize {
        switch self {
        case .abundant: return CGSize(width: 360, height: 44)
        case .warning: return CGSize(width: 340, height: 44)
        case .critical: return CGSize(width: 320, height: 44)
        case .unknown: return CGSize(width: 300, height: 44)
        }
    }
}

/// 百分比额度窗口。
struct AIUsageWindow: Hashable, Identifiable {
    let id: String
    let title: String
    /// 已用百分比 0…100。
    let usedPercent: Double
    let resetsAt: Date?

    var remainingPercent: Double {
        min(max(100 - usedPercent, 0), 100)
    }
}

/// 按需消费（金额，不是百分比）。
struct AIUsageOnDemandSpend: Hashable {
    /// 已花美元。
    var spentUSD: Double
    /// 软限额美元；0 表示未设。
    var limitUSD: Double

    var remainingUSD: Double {
        max(limitUSD - spentUSD, 0)
    }

    var occupancyPercent: Double {
        guard limitUSD > 0 else { return 0 }
        return min(max(spentUSD / limitUSD * 100, 0), 100)
    }
}

struct AIUsageProviderSnapshot: Hashable, Identifiable {
    let id: AIUsageProviderID
    var planLabel: String?
    /// 设置页展示用（脱敏）。
    var accountHint: String?
    /// 提示去重用稳定账号键（通常为小写邮箱）；勿上屏、勿打完整日志。
    var accountID: String?
    var windows: [AIUsageWindow]
    var onDemand: AIUsageOnDemandSpend?
    var fetchedAt: Date
    var errorMessage: String?
    var isStale: Bool

    var primaryWindow: AIUsageWindow? { windows.first }

    var remainingPercent: Double? { primaryWindow?.remainingPercent }

    var resetsAt: Date? { primaryWindow?.resetsAt }

    /// 计费周期键：优先用周期结束时间戳；未知则 `unknown`。
    var cycleKey: String {
        guard let resetsAt else { return "unknown" }
        return String(Int(resetsAt.timeIntervalSince1970))
    }

    /// 账号 + 周期作用域（换号 / 新周期时提示记忆互不串）。
    var alertScope: AIUsageAlertScope {
        let id: String = {
            guard let accountID, !accountID.isEmpty else { return "unknown" }
            return accountID
        }()
        return AIUsageAlertScope(accountID: id, cycleKey: cycleKey)
    }
}

/// 额度提示去重作用域：同账号同周期才共用「已提示过」记忆。
struct AIUsageAlertScope: Hashable {
    var accountID: String
    var cycleKey: String

    /// 日志用短前缀，避免完整邮箱。
    var logSummary: String {
        let account = accountID == "unknown"
            ? "unknown"
            : String(accountID.prefix(3)) + "***"
        let cycle = cycleKey == "unknown"
            ? "unknown"
            : String(cycleKey.suffix(6))
        return "\(account)/\(cycle)"
    }
}

struct AIUsageSnapshot: Hashable {
    var providers: [AIUsageProviderSnapshot]
    var updatedAt: Date

    var cursor: AIUsageProviderSnapshot? {
        providers.first { $0.id == .cursor }
    }

    var sensedChannelCount: Int {
        providers.filter { $0.errorMessage == nil && $0.remainingPercent != nil }.count
    }
}
