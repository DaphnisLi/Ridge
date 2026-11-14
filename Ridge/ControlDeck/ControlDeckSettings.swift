import Combine
import Foundation

/// 控制台：最多一个，与小组件库分离；放功能性磁贴（音量、货架、项目释放等），不承载会议等内容型页。
@MainActor
final class ControlDeckSettings: ObservableObject {
    static let shared = ControlDeckSettings()

    /// 控制台页 id 前缀；每个已开启模块各占一页：`system.controlDeck.volume` 等。
    static let pageIDPrefix: WidgetID = "system.controlDeck"
    /// 兼容旧单一页 id。
    static let pageID: WidgetID = pageIDPrefix

    /// 已落地、可上岛的模块 id。
    static let liveModuleIDs: Set<String> = ["shelf", "volume", "projects", "battery"]

    enum Pane: String, CaseIterable, Identifiable {
        case shelf
        case volume
        case projects
        case battery

        var id: String { rawValue }

        var title: String {
            switch self {
            case .shelf: return L10n.ControlDeck.moduleShelf
            case .volume: return L10n.ControlDeck.moduleVolume
            case .projects: return L10n.ControlDeck.moduleProjects
            case .battery: return L10n.ControlDeck.moduleBattery
            }
        }

        var pageID: WidgetID { "\(ControlDeckSettings.pageIDPrefix).\(rawValue)" }

        static func from(pageID: WidgetID) -> Pane? {
            guard pageID.hasPrefix(ControlDeckSettings.pageIDPrefix + ".") else {
                if pageID == ControlDeckSettings.pageIDPrefix { return nil }
                return nil
            }
            let suffix = String(pageID.dropFirst(ControlDeckSettings.pageIDPrefix.count + 1))
            return Pane(rawValue: suffix)
        }
    }

    static func isControlDeckPageID(_ id: WidgetID) -> Bool {
        id == pageIDPrefix || id.hasPrefix(pageIDPrefix + ".")
    }

    static func pageID(for pane: Pane) -> WidgetID { pane.pageID }

    private enum Key {
        static let enabled = "controlDeck.enabled.v1"
        static let modules = "controlDeck.modules.v1"
        static let migratedFromCombo = "controlDeck.migratedFromCombo.v1"
        static let activePane = "controlDeck.activePane.v1"
        /// 磁贴默认全关（升 v 号会再强制关一次；v1 曾只写标记未关模块）。
        static let modulesDefaultOffMigrated = "controlDeck.modulesDefaultOff.v2"
    }

    /// 岛上是否展示控制台页（任一已落地模块开启即显示）。
    @Published private(set) var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Key.enabled)
            AppLog.info("ControlDeck", "控制台开关变更", ["enabled": isEnabled])
        }
    }

    /// 各规划模块开关。
    @Published private var moduleEnabled: [String: Bool] {
        didSet {
            UserDefaults.standard.set(moduleEnabled, forKey: Key.modules)
        }
    }

    /// 控制台内当前面板；多模块同时开启时用分段切换。
    @Published var activePane: Pane {
        didSet {
            UserDefaults.standard.set(activePane.rawValue, forKey: Key.activePane)
        }
    }

    /// 设置页展示的功能模块。
    var plannedModules: [ControlDeckPlannedModule] {
        [
            .init(
                id: "shelf",
                title: L10n.ControlDeck.moduleShelf,
                symbol: "tray.full.fill",
                isLive: true
            ),
            .init(
                id: "volume",
                title: L10n.ControlDeck.moduleVolume,
                symbol: "speaker.wave.2.fill",
                isLive: true
            ),
            .init(
                id: "projects",
                title: L10n.ControlDeck.moduleProjects,
                symbol: "hammer.fill",
                isLive: true
            ),
            .init(
                id: "battery",
                title: L10n.ControlDeck.moduleBattery,
                symbol: "battery.100.bolt",
                isLive: true
            ),
            .init(
                id: "focus",
                title: L10n.ControlDeck.moduleFocus,
                symbol: "cup.and.saucer.fill",
                isLive: false
            ),
            .init(
                id: "system",
                title: L10n.ControlDeck.moduleSystem,
                symbol: "cpu",
                isLive: false
            )
        ]
    }

    /// 当前已开启的已落地面板（有序）。
    var enabledPanes: [Pane] {
        Pane.allCases.filter { isModuleEnabled($0.rawValue) }
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
            defaults.removeObject(forKey: "widget.comboPages.v1")
        }

        var modules = defaults.dictionary(forKey: Key.modules) as? [String: Bool] ?? [:]
        // 未写过的磁贴默认关闭。
        for id in Self.liveModuleIDs where modules[id] == nil {
            modules[id] = false
        }
        // v2：强制全关并落盘（修复 v1 标记已写但模块仍全开）。
        if !defaults.bool(forKey: Key.modulesDefaultOffMigrated) {
            for id in Self.liveModuleIDs {
                modules[id] = false
            }
            defaults.set(modules, forKey: Key.modules)
            defaults.set(true, forKey: Key.modulesDefaultOffMigrated)
            AppLog.info("ControlDeck", "已迁移为控制台磁贴默认全关", [
                "version": Key.modulesDefaultOffMigrated
            ])
        }
        moduleEnabled = modules

        if let raw = defaults.string(forKey: Key.activePane),
           let pane = Pane(rawValue: raw),
           modules[pane.rawValue] == true
        {
            activePane = pane
        } else {
            activePane = .volume
        }

        isEnabled = Self.anyLiveModuleEnabled(modules)
        defaults.set(isEnabled, forKey: Key.enabled)
        AppLog.debug("ControlDeck", "已加载控制台设置", [
            "enabled": isEnabled,
            "modules": modules.filter(\.value).map(\.key).sorted().joined(separator: ","),
            "pane": activePane.rawValue
        ])
        // 勿在 init 同步 start：BatterySession.refreshLiveInvite 会再取 ControlDeckSettings.shared，
        // 触发 dispatch_once 重入 → 启动即 SIGTRAP。
        // 电量 / 项目等会话只在用户打开对应磁贴时 start，禁止启动即申请蓝牙等权限。
        Task { @MainActor in
            ShelfSettings.shared.migrateCopiedNoticeWidgetGateIfNeeded()
            ClipboardCopiedNoticeGate.syncClipboardMonitoring(reason: "controlDeckInit")
            AppLog.debug("ControlDeck", "启动后未拉起需权限的模块会话", [
                "copiedTip": ClipboardCopiedNoticeGate.isTipEnabled,
                "anyModule": isEnabled
            ])
        }
    }

    func isModuleEnabled(_ id: String) -> Bool {
        moduleEnabled[id] ?? false
    }

    func setModuleEnabled(_ id: String, _ enabled: Bool) {
        guard isModuleEnabled(id) != enabled else { return }
        moduleEnabled[id] = enabled
        AppLog.info("ControlDeck", "模块开关变更", ["id": id, "enabled": enabled])

        // 每次打开磁贴都校验并申请权限（音量→屏幕录制，电量→蓝牙）。
        if enabled {
            Task { @MainActor in
                await WidgetPermissionGate.ensureOnEnable(deckModule: id)
            }
        }

        if id == "shelf" {
            ClipboardCopiedNoticeGate.syncClipboardMonitoring(reason: "shelfModuleToggle")
        }
        if id == "volume" {
            if enabled {
                SoundSession.shared.start()
            }
        }
        if id == "projects" {
            if enabled {
                ProjectReleaseSession.shared.start()
            } else {
                ProjectReleaseSession.shared.stop()
            }
        }
        if id == "battery" {
            if enabled {
                BatterySession.shared.start()
                BatterySession.shared.refreshLiveInvite(reason: "moduleEnabled")
            } else {
                LiveIslandGate.shared.close(LiveIslandGate.batteryID, reason: "moduleDisabled")
                BatterySession.shared.stop()
            }
        }

        guard Self.liveModuleIDs.contains(id) else { return }

        let anyOn = Self.anyLiveModuleEnabled(moduleEnabled)
        setEnabled(anyOn)

        if enabled, let pane = Pane(rawValue: id) {
            // 实况（电量）：开启后先发邀请提示，点进才上岛；面板类仍直接切页。
            if WidgetLibraryFamily.family(for: pane.pageID) == .live {
                WidgetRuntime.shared.recompute(reason: "controlDeckLiveInvite")
                AppLog.info("ControlDeck", "实况模块已开，等待点进提示", ["pane": pane.rawValue])
            } else {
                activePane = pane
                WidgetRuntime.shared.focusControlDeck(pane: pane)
            }
        } else if !anyOn {
            WidgetRuntime.shared.recompute(reason: "controlDeckOff")
        } else {
            if activePane.rawValue == id, let fallback = enabledPanes.first {
                activePane = fallback
            }
            // 模块增减会改变页数，必须重算分页。
            WidgetRuntime.shared.recompute(reason: "controlDeckModules")
        }
    }

    /// 拖文件靠近刘海时切到货架面板。
    func focusShelfForDrop() {
        guard isModuleEnabled("shelf") else { return }
        if activePane != .shelf {
            activePane = .shelf
            AppLog.info("ControlDeck", "拖入文件，切到货架面板")
        }
        if !isEnabled {
            setEnabled(true)
        }
        WidgetRuntime.shared.focusControlDeck(pane: .shelf)
    }

    /// 岛滑动到某控制台页时回写当前面板。
    func syncActivePane(fromPageID pageID: WidgetID) {
        guard let pane = Pane.from(pageID: pageID), activePane != pane else { return }
        activePane = pane
        AppLog.debug("ControlDeck", "滑动同步控制台面板", ["pane": pane.rawValue])
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
    }

    private static func anyLiveModuleEnabled(_ modules: [String: Bool]) -> Bool {
        liveModuleIDs.contains { modules[$0] == true }
    }
}

struct ControlDeckPlannedModule: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let isLive: Bool
}
