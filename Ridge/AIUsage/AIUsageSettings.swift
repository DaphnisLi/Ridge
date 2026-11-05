import Combine
import Foundation

/// AI 额度监测设置：感知总开关 + 三阶阈值。
@MainActor
final class AIUsageSettings: ObservableObject {
    static let shared = AIUsageSettings()

    enum Defaults {
        static let sensingEnabled = true
        static let abundantThreshold = 60
        static let warningThreshold = 30
        static let criticalThreshold = 10
        static let refreshMinutes = 10
    }

    private enum Key {
        static let sensing = "aiUsage.sensingEnabled"
        static let abundant = "aiUsage.abundantThreshold"
        static let warning = "aiUsage.warningThreshold"
        static let critical = "aiUsage.criticalThreshold"
        static let refresh = "aiUsage.refreshMinutes"
        static let lastAlertStage = "aiUsage.lastAlertStage"
        static let lastAlertProvider = "aiUsage.lastAlertProvider"
    }

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
            clearAlertMemory()
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
            clearAlertMemory()
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
            clearAlertMemory()
        }
    }

    @Published var refreshMinutes: Int {
        didSet {
            let clamped = min(max(refreshMinutes, 5), 60)
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
        normalizeHierarchy()
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

    /// 展示分档：截流 / 警戒 / 充裕（含高于充裕线的健康态，仍显示绿色充裕，勿标「未知」）。
    func stage(forRemaining remaining: Double) -> AIUsageStage {
        if remaining <= Double(criticalThreshold) { return .critical }
        if remaining <= Double(warningThreshold) { return .warning }
        return .abundant
    }

    /// 是否已跌破充裕触发线（≤ 充裕阈值）——仅此时充裕档才上岛提示。
    func isWithinAbundantTipBand(_ remaining: Double) -> Bool {
        remaining <= Double(abundantThreshold)
    }

    /// 层级：充裕 > 警戒 > 截流。
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

    // MARK: - 提醒去重

    func lastAlertedStage() -> (AIUsageProviderID, AIUsageStage)? {
        let defaults = UserDefaults.standard
        guard let providerRaw = defaults.string(forKey: Key.lastAlertProvider),
              let provider = AIUsageProviderID(rawValue: providerRaw),
              let stageRaw = defaults.string(forKey: Key.lastAlertStage),
              let stage = AIUsageStage(rawValue: stageRaw)
        else { return nil }
        return (provider, stage)
    }

    func rememberAlert(provider: AIUsageProviderID, stage: AIUsageStage) {
        UserDefaults.standard.set(provider.rawValue, forKey: Key.lastAlertProvider)
        UserDefaults.standard.set(stage.rawValue, forKey: Key.lastAlertStage)
    }

    func clearAlertMemory() {
        UserDefaults.standard.removeObject(forKey: Key.lastAlertProvider)
        UserDefaults.standard.removeObject(forKey: Key.lastAlertStage)
    }
}
