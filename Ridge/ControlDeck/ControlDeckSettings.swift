import Combine
import Foundation

/// 控制台：最多一个，与小组件库分离；放功能性磁贴（电量、音量等），不承载会议等内容型页。
@MainActor
final class ControlDeckSettings: ObservableObject {
    static let shared = ControlDeckSettings()

    /// 分页 / 宿主用的稳定 id（不进小组件库）。
    static let pageID: WidgetID = "system.controlDeck"

    private enum Key {
        static let enabled = "controlDeck.enabled.v1"
        static let migratedFromCombo = "controlDeck.migratedFromCombo.v1"
    }

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Key.enabled)
            AppLog.info("ControlDeck", "控制台开关变更", ["enabled": isEnabled])
        }
    }

    /// 设置页展示的规划中功能模块（只读说明，尚未逐项开关）。
    var plannedModules: [ControlDeckPlannedModule] {
        [
            .init(
                id: "battery",
                title: L10n.ControlDeck.moduleBattery,
                summary: L10n.ControlDeck.moduleBatterySummary,
                symbol: "battery.100.bolt"
            ),
            .init(
                id: "volume",
                title: L10n.ControlDeck.moduleVolume,
                summary: L10n.ControlDeck.moduleVolumeSummary,
                symbol: "speaker.wave.2.fill"
            ),
            .init(
                id: "focus",
                title: L10n.ControlDeck.moduleFocus,
                summary: L10n.ControlDeck.moduleFocusSummary,
                symbol: "cup.and.saucer.fill"
            ),
            .init(
                id: "system",
                title: L10n.ControlDeck.moduleSystem,
                summary: L10n.ControlDeck.moduleSystemSummary,
                symbol: "cpu"
            )
        ]
    }

    private init() {
        let defaults = UserDefaults.standard
        var enabled = defaults.object(forKey: Key.enabled) as? Bool ?? false

        // 旧「组合页」曾启用过 → 迁成控制台开一次，避免用户丢入口。
        if !defaults.bool(forKey: Key.migratedFromCombo) {
            let hadCombo: Bool = {
                if let raw = defaults.array(forKey: "widget.comboPages.v1") as? [[String]], !raw.isEmpty {
                    return true
                }
                if let legacy = defaults.array(forKey: "widget.pageGroups.v1") as? [[String]],
                   legacy.contains(where: { $0.count > 1 }) {
                    return true
                }
                return false
            }()
            if hadCombo, defaults.object(forKey: Key.enabled) == nil {
                enabled = true
                AppLog.info("ControlDeck", "已从旧组合页迁移为控制台", ["enabled": true])
            }
            defaults.set(true, forKey: Key.migratedFromCombo)
            defaults.set(enabled, forKey: Key.enabled)
            // 清掉旧组合成员，避免残留调度。
            defaults.removeObject(forKey: "widget.comboPages.v1")
        }

        isEnabled = enabled
        AppLog.debug("ControlDeck", "已加载控制台设置", ["enabled": isEnabled])
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
    }
}

struct ControlDeckPlannedModule: Identifiable, Hashable {
    let id: String
    let title: String
    let summary: String
    let symbol: String
}
