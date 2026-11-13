import Combine
import Foundation

/// 整岛文件拖入会话：拖入接近 / 命中时为 true，松手或离开后恢复。
@MainActor
final class ShelfDropSession: ObservableObject {
    static let shared = ShelfDropSession()

    /// 投放完成后禁止再进入的冷却（秒）。SwiftUI `isTargeted` 常滞后于松手，
    /// 若无冷却，`dropComplete` 退出后指针轮询会立刻再 `setActive(true)`，双舱闪第二次。
    static let postDropSuppress: TimeInterval = 0.55

    @Published private(set) var isActive = false
    private var suppressReactivateUntil: Date = .distantPast

    private init() {}

    /// 是否仍在投放后冷却窗内（测试 / 诊断用）。
    var isReactivateSuppressed: Bool {
        Date() < suppressReactivateUntil
    }

    func setActive(_ active: Bool, reason: String) {
        if active, Date() < suppressReactivateUntil {
            AppLog.warn("Shelf", "投放后冷却中，忽略再次进入双舱", [
                "reason": reason,
                "remainMs": Int(suppressReactivateUntil.timeIntervalSinceNow * 1000)
            ])
            return
        }
        guard isActive != active else { return }
        isActive = active
        // 落盘用 warn：info 不进 app.log，双舱闪第二次时否则无迹可查。
        AppLog.warn("Shelf", active ? "进入整岛暂存拖入态" : "退出整岛暂存拖入态", [
            "reason": reason
        ])
    }

    /// 投放完成：立刻退出，并开启冷却，挡住 isTargeted 滞后带来的二次进入。
    func endAfterDrop(reason: String) {
        suppressReactivateUntil = Date().addingTimeInterval(Self.postDropSuppress)
        if isActive {
            isActive = false
            AppLog.warn("Shelf", "退出整岛暂存拖入态", [
                "reason": reason,
                "suppressMs": Int(Self.postDropSuppress * 1000)
            ])
        } else {
            AppLog.warn("Shelf", "投放结束（冷却已开）", [
                "reason": reason,
                "suppressMs": Int(Self.postDropSuppress * 1000)
            ])
        }
    }

#if DEBUG
    func resetForTests() {
        isActive = false
        suppressReactivateUntil = .distantPast
    }
#endif
}
