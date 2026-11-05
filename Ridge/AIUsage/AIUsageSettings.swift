import Combine
import Foundation

/// AI 额度监测设置：感知总开关 + 三阶阈值。
@MainActor
final class AIUsageSettings: ObservableObject {
    static let shared = AIUsageSettings()

    enum Defaults {
        static let sensingEnabled = true
        static let abundantThreshold = 70
        static let warningThreshold = 30
        static let criticalThreshold = 10
        /// 写代码时额度掉得快，10 分钟太钝；默认 2 分钟轮询。
        static let refreshMinutes = 2
    }

    private enum Key {
        static let sensing = "aiUsage.sensingEnabled"
        static let abundant = "aiUsage.abundantThreshold"
        static let warning = "aiUsage.warningThreshold"
        static let critical = "aiUsage.criticalThreshold"
        static let refresh = "aiUsage.refreshMinutes.v2"
        static let lastAlertStage = "aiUsage.lastAlertStage"
        static let lastAlertProvider = "aiUsage.lastAlertProvider"
        static let lastAlertAccount = "aiUsage.lastAlertAccount"
        static let lastAlertCycle = "aiUsage.lastAlertCycle"
    }

    /// init 完成前不回调 Session，避免双向初始化。
    private var isReady = false

    /// 关闭后不上岛、不发阈值提醒（设置页仍可手动同步）。
    @Published var sensingEnabled: Bool {
        didSet { UserDefaults.standard.set(sensingEnabled, forKey: Key.sensing) }
    }

    /// 充裕态触发阈值：剩余 ≤ 该值且高于警戒线时弹充裕形态。
    @Published var abundantThreshold: Int {
        didSet {
            let clamped = min(max(abundantThreshold, 50), 80)
            if clamped != abundantThreshold {
                abundantThreshold = clamped
                return
            }
            UserDefaults.standard.set(abundantThreshold, forKey: Key.abundant)
            normalizeHierarchy()
            notifyThresholdsChanged(reason: "abundant")
        }
    }

    /// 警戒：剩余 ≤ 该值。
    @Published var warningThreshold: Int {
        didSet {
            let clamped = min(max(warningThreshold, 20), 45)
            if clamped != warningThreshold {
                warningThreshold = clamped
                return
            }
            UserDefaults.standard.set(warningThreshold, forKey: Key.warning)
            normalizeHierarchy()
            notifyThresholdsChanged(reason: "warning")
        }
    }

    /// 截流：剩余 ≤ 该值。
    @Published var criticalThreshold: Int {
        didSet {
            let clamped = min(max(criticalThreshold, 5), 15)
            if clamped != criticalThreshold {
                criticalThreshold = clamped
                return
            }
            UserDefaults.standard.set(criticalThreshold, forKey: Key.critical)
            normalizeHierarchy()
            notifyThresholdsChanged(reason: "critical")
        }
    }

    /// 后台轮询间隔（分钟）；1…30，默认 2。
    @Published var refreshMinutes: Int {
        didSet {
            let clamped = min(max(refreshMinutes, 1), 30)
            if clamped != refreshMinutes {
                refreshMinutes = clamped
                return
            }
            UserDefaults.standard.set(refreshMinutes, forKey: Key.refresh)
        }
    }

    private init() {
        let defaults = UserDefaults.standard
        sensingEnabled = defaults.object(forKey: Key.sensing) as? Bool ?? Defaults.sensingEnabled
        abundantThreshold = defaults.object(forKey: Key.abundant) as? Int ?? Defaults.abundantThreshold
        warningThreshold = defaults.object(forKey: Key.warning) as? Int ?? Defaults.warningThreshold
        criticalThreshold = defaults.object(forKey: Key.critical) as? Int ?? Defaults.criticalThreshold
        refreshMinutes = defaults.object(forKey: Key.refresh) as? Int ?? Defaults.refreshMinutes
        defaults.removeObject(forKey: "aiUsage.refreshMinutes")
        defaults.removeObject(forKey: "aiUsage.lastAlertFingerprint.v1")
        // 旧默认 60 → 新默认 70；用户已改成其它值则保留。
        let migrated70 = "aiUsage.abundantDefault70.v1"
        if defaults.object(forKey: migrated70) == nil {
            if defaults.object(forKey: Key.abundant) as? Int == 60 {
                abundantThreshold = Defaults.abundantThreshold
            }
            defaults.set(true, forKey: migrated70)
        }
        // 无账号/周期字段的旧记忆作废，避免换号后误判「同档已提示」。
        if defaults.object(forKey: Key.lastAlertAccount) == nil {
            defaults.removeObject(forKey: Key.lastAlertStage)
            defaults.removeObject(forKey: Key.lastAlertProvider)
        }
        normalizeHierarchy()
        isReady = true
    }

    private func notifyThresholdsChanged(reason: String) {
        guard isReady else { return }
        // 去重清理由 Session 防抖后统一做，避免步进器每格都弹。
        AIUsageSession.shared.thresholdsDidChange(reason: reason)
    }

    func restoreDefaults() {
        sensingEnabled = Defaults.sensingEnabled
        abundantThreshold = Defaults.abundantThreshold
        warningThreshold = Defaults.warningThreshold
        criticalThreshold = Defaults.criticalThreshold
        refreshMinutes = Defaults.refreshMinutes
        clearAlertMemory()
        AppLog.info("AIUsage", "已恢复默认设置")
    }

    /// 与设置页「剩余 xx%」同一套四舍五入。
    func displayRemainingPercent(_ remaining: Double) -> Int {
        Int(remaining.rounded())
    }

    /// 设置页色条：高于充裕线仍显示充裕绿，勿标未知。
    func stage(forRemaining remaining: Double) -> AIUsageStage {
        let percent = displayRemainingPercent(remaining)
        if percent <= criticalThreshold { return .critical }
        if percent <= warningThreshold { return .warning }
        return .abundant
    }

    /// 瞬时提示分档：未触达充裕线返回 `nil`（不弹）；否则为充裕 / 警戒 / 截流之一。
    func tipStage(forRemaining remaining: Double) -> AIUsageStage? {
        let percent = displayRemainingPercent(remaining)
        if percent <= criticalThreshold { return .critical }
        if percent <= warningThreshold { return .warning }
        if percent <= abundantThreshold { return .abundant }
        return nil
    }

    var hierarchyValid: Bool {
        abundantThreshold > warningThreshold && warningThreshold > criticalThreshold
    }

    private func normalizeHierarchy() {
        if warningThreshold >= abundantThreshold {
            warningThreshold = max(abundantThreshold - 10, criticalThreshold + 1)
        }
        if criticalThreshold >= warningThreshold {
            criticalThreshold = max(warningThreshold - 10, 5)
        }
    }

    // MARK: - 提醒去重（同账号 + 同计费周期 + 档位）

    /// 仅当持久化记忆与当前作用域一致时返回档位；换号 / 新周期视为无记忆。
    func lastAlertedStage(for scope: AIUsageAlertScope) -> (AIUsageProviderID, AIUsageStage)? {
        let defaults = UserDefaults.standard
        guard let providerRaw = defaults.string(forKey: Key.lastAlertProvider),
              let provider = AIUsageProviderID(rawValue: providerRaw),
              let stageRaw = defaults.string(forKey: Key.lastAlertStage),
              let stage = AIUsageStage(rawValue: stageRaw),
              let account = defaults.string(forKey: Key.lastAlertAccount),
              let cycle = defaults.string(forKey: Key.lastAlertCycle),
              account == scope.accountID,
              cycle == scope.cycleKey
        else { return nil }
        return (provider, stage)
    }

    func rememberAlert(provider: AIUsageProviderID, stage: AIUsageStage, scope: AIUsageAlertScope) {
        let defaults = UserDefaults.standard
        defaults.set(provider.rawValue, forKey: Key.lastAlertProvider)
        defaults.set(stage.rawValue, forKey: Key.lastAlertStage)
        defaults.set(scope.accountID, forKey: Key.lastAlertAccount)
        defaults.set(scope.cycleKey, forKey: Key.lastAlertCycle)
        AppLog.debug("AIUsage", "已记录额度提示记忆", [
            "stage": stage.rawValue,
            "scope": scope.logSummary
        ])
    }

    func clearAlertMemory() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Key.lastAlertProvider)
        defaults.removeObject(forKey: Key.lastAlertStage)
        defaults.removeObject(forKey: Key.lastAlertAccount)
        defaults.removeObject(forKey: Key.lastAlertCycle)
        AppLog.debug("AIUsage", "已清空额度提示记忆")
    }
}
