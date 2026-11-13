import Combine
import Foundation

/// 整岛文件拖入会话：拖入接近 / 命中时为 true，松手或离开后恢复。
@MainActor
final class ShelfDropSession: ObservableObject {
    static let shared = ShelfDropSession()

    /// 投放完成 / 未入舱松手后禁止再进入的冷却（秒）。
    /// 挡住 isTargeted 滞后二次双舱，以及拖完未投放却回头再开。
    static let postDropSuppress: TimeInterval = 0.55

    @Published private(set) var isActive = false
    private var suppressReactivateUntil: Date = .distantPast
    /// 最近一次成功投放时间；松手处理用它区分「入舱完成」与「未投放取消」。
    private(set) var lastDropCompletedAt: Date = .distantPast

    private init() {}

    /// 是否仍在投放后冷却窗内（测试 / 诊断用）。
    var isReactivateSuppressed: Bool {
        Date() < suppressReactivateUntil
    }

    /// 是否刚完成投放（成功入舱 / 隔空），松手路径勿当取消强收。
    func dropCompletedRecently(within seconds: TimeInterval = 0.35, now: Date = Date()) -> Bool {
        now.timeIntervalSince(lastDropCompletedAt) < seconds
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
    func endAfterDrop(reason: String, markCompleted: Bool = false) {
        if markCompleted {
            lastDropCompletedAt = Date()
        }
        suppressReactivateUntil = Date().addingTimeInterval(Self.postDropSuppress)
        if isActive {
            isActive = false
            AppLog.warn("Shelf", "退出整岛暂存拖入态", [
                "reason": reason,
                "suppressMs": Int(Self.postDropSuppress * 1000),
                "completed": markCompleted
            ])
        } else {
            AppLog.warn("Shelf", "投放结束（冷却已开）", [
                "reason": reason,
                "suppressMs": Int(Self.postDropSuppress * 1000),
                "completed": markCompleted
            ])
        }
    }

#if DEBUG
    func resetForTests() {
        isActive = false
        suppressReactivateUntil = .distantPast
        lastDropCompletedAt = .distantPast
    }
#endif
}
