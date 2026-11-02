import Combine
import Foundation

/// 整岛文件拖入会话：拖入接近 / 命中时为 true，松手或离开后恢复。
@MainActor
final class ShelfDropSession: ObservableObject {
    static let shared = ShelfDropSession()

    @Published private(set) var isActive = false

    private init() {}

    func setActive(_ active: Bool, reason: String) {
        guard isActive != active else { return }
        isActive = active
        AppLog.info("Shelf", active ? "进入整岛暂存拖入态" : "退出整岛暂存拖入态", [
            "reason": reason
        ])
    }
}
