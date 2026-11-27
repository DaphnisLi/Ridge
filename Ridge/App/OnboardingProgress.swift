import Foundation

/// 首次引导进度：支持权限申请中途重开 App 后从断点续跑。
struct OnboardingProgress: Codable, Equatable {
    enum Step: String, Codable {
        case island
        case pickWidgets
        case permissions
        case loginItem
    }

    var step: Step
    /// 推荐页勾选的小组件。
    var selectedWidgetIDs: [WidgetID]
    /// 历史字段：曾用于强制悬停展开；现不挡继续，保留以兼容旧进度 JSON。
    var islandTried: Bool
    /// 待申请权限队列（`WidgetPermissionGate.Need.rawValue`）。
    var permissionQueue: [String]
    /// 刚跳去系统设置、等待用户重开后的那一项。
    var awaitingRelaunchFor: String?
    var enableLoginAtLogin: Bool

    static let storageKey = "onboarding.progress.v2"

    /// 首次引导推荐勾选：库内常用 tip + 会议/媒体；新 tip 默认一并推荐。
    static var recommendedWidgetIDs: [WidgetID] {
        [
            "builtin.copiedNotice",
            "builtin.meeting",
            "builtin.moveReminder",
            "builtin.colorPick",
            "builtin.ocrSelect",
            "builtin.peripheralTip",
            "builtin.macBatteryTip",
            "builtin.networkLinkTip",
            "builtin.systemFocusTip",
            "builtin.downloadComplete",
            "builtin.media",
        ]
    }

    /// 无对应库小组件、但引导仍要申请的权限（击键洞察 → 输入监控）。
    static var baselinePermissionNeeds: [WidgetPermissionGate.Need] {
        [.inputMonitoring]
    }

    static func fresh() -> OnboardingProgress {
        OnboardingProgress(
            step: .island,
            selectedWidgetIDs: recommendedWidgetIDs,
            islandTried: false,
            permissionQueue: [],
            awaitingRelaunchFor: nil,
            enableLoginAtLogin: true
        )
    }

    static func load() -> OnboardingProgress? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(OnboardingProgress.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    mutating func rebuildPermissionQueue() {
        var seen = Set<String>()
        var ordered: [String] = []
        for id in selectedWidgetIDs {
            for need in WidgetPermissionGate.needs(forWidgetID: id) where seen.insert(need.rawValue).inserted {
                ordered.append(need.rawValue)
            }
        }
        for need in Self.baselinePermissionNeeds where seen.insert(need.rawValue).inserted {
            ordered.append(need.rawValue)
        }
        permissionQueue = ordered
        awaitingRelaunchFor = nil
    }

    /// 勾选能力 + 固定基线权限，去重后的完整清单（权限页展示用）。
    func allPermissionNeeds() -> [WidgetPermissionGate.Need] {
        var seen = Set<String>()
        var ordered: [WidgetPermissionGate.Need] = []
        for id in selectedWidgetIDs {
            for need in WidgetPermissionGate.needs(forWidgetID: id) where seen.insert(need.rawValue).inserted {
                ordered.append(need)
            }
        }
        for need in Self.baselinePermissionNeeds where seen.insert(need.rawValue).inserted {
            ordered.append(need)
        }
        return ordered
    }

    /// 对照当前 TCC，去掉已满足项；若仍在等重开的项已满足则清除 awaiting。
    @MainActor
    mutating func reconcilePermissionsWithSystem() {
        permissionQueue = permissionQueue.filter { raw in
            guard let need = WidgetPermissionGate.Need(rawValue: raw) else { return false }
            return !WidgetPermissionGate.isSatisfied(need)
        }
        if let waiting = awaitingRelaunchFor,
           let need = WidgetPermissionGate.Need(rawValue: waiting),
           WidgetPermissionGate.isSatisfied(need)
        {
            awaitingRelaunchFor = nil
        }
        if let waiting = awaitingRelaunchFor, !permissionQueue.contains(waiting) {
            awaitingRelaunchFor = nil
        }
    }

    /// 所选推荐小组件 + 基线权限是否全部已满足（进自启页的唯一门槛）。
    @MainActor
    func allSelectedPermissionsSatisfied() -> Bool {
        unsatisfiedPermissionNeeds().isEmpty
    }

    /// 当前仍未满足的权限（日志 / 续跑诊断）。
    @MainActor
    func unsatisfiedPermissionNeeds() -> [WidgetPermissionGate.Need] {
        allPermissionNeeds().filter { !WidgetPermissionGate.isSatisfied($0) }
    }

    /// 队列空了但权限未齐时，按所选小组件重建剩余项，避免误跳步。
    @MainActor
    mutating func ensurePermissionQueueReflectsGaps() {
        reconcilePermissionsWithSystem()
        guard !allSelectedPermissionsSatisfied() else {
            permissionQueue = []
            awaitingRelaunchFor = nil
            return
        }
        if permissionQueue.isEmpty {
            rebuildPermissionQueue()
            reconcilePermissionsWithSystem()
        }
    }
}
