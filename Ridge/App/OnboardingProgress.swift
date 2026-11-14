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
    /// 是否已在第 1 步成功悬停展开过岛。
    var islandTried: Bool
    /// 待申请权限队列（`WidgetPermissionGate.Need.rawValue`）。
    var permissionQueue: [String]
    /// 刚跳去系统设置、等待用户重开后的那一项。
    var awaitingRelaunchFor: String?
    var enableLoginAtLogin: Bool

    static let storageKey = "onboarding.progress.v2"

    static var recommendedWidgetIDs: [WidgetID] {
        [
            "builtin.copiedNotice",
            "builtin.meeting",
            "builtin.media",
            "builtin.moveReminder",
            "builtin.colorPick",
            "builtin.ocrSelect",
            "builtin.peripheralTip"
        ]
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
        permissionQueue = ordered
        awaitingRelaunchFor = nil
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
}
