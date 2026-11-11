import Combine
import Foundation

/// 「已复制」提示偏好（库总开关外的细节选项）。
@MainActor
final class CopiedNoticeSettings: ObservableObject {
    static let shared = CopiedNoticeSettings()

    private enum Key {
        static let haptic = "copiedNotice.haptic.v1"
    }

    private let defaults = UserDefaults.standard

    /// 上岛「已复制」时是否给触控板轻震；默认开。
    @Published var hapticEnabled: Bool {
        didSet {
            guard hapticEnabled != oldValue else { return }
            defaults.set(hapticEnabled, forKey: Key.haptic)
            AppLog.info("CopiedNotice", "触感反馈开关已更新", ["enabled": hapticEnabled])
        }
    }

    private init() {
        if defaults.object(forKey: Key.haptic) == nil {
            hapticEnabled = true
        } else {
            hapticEnabled = defaults.bool(forKey: Key.haptic)
        }
    }

    func restoreDefaults() {
        hapticEnabled = true
        AppLog.info("CopiedNotice", "已恢复默认设置", ["haptic": true])
    }

    /// 投递「已复制」后调用；关开关或强度为关时不震。
    func fireHapticIfNeeded() {
        guard hapticEnabled else { return }
        // 轻微一振；与设计「轻微震动」一致，不跟灵动岛全局震感档位绑死。
        IslandHaptics.play(.light)
        AppLog.debug("CopiedNotice", "已触发复制提示触感")
    }
}
