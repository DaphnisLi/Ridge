import Combine
import Foundation

/// 左音乐/下载 · 右计时双翼：Controller 命中右翼时钉住 morph，避免只靠 SwiftUI onHover 贴边误收。
/// 解除钉住短延迟，避免往右贴边时命中框抖一下就把操作钮收掉。
@MainActor
final class FocusTrailingWingHover: ObservableObject {
    static let shared = FocusTrailingWingHover()

    @Published private(set) var isActive = false

    private var clearWork: DispatchWorkItem?
    /// 指针刚出右翼命中框时的去抖（秒）；进入立刻钉住。
    private let clearDelay: TimeInterval = 0.14

    private init() {}

    func setActive(_ active: Bool, reason: String) {
        if active {
            clearWork?.cancel()
            clearWork = nil
            guard !isActive else { return }
            isActive = true
            AppLog.warn("FocusTimer", "右计时翼悬停钉住", [
                "reason": reason
            ])
            return
        }
        guard isActive || clearWork != nil else { return }
        clearWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.clearWork = nil
            guard self.isActive else { return }
            self.isActive = false
            AppLog.warn("FocusTimer", "右计时翼悬停解除", [
                "reason": reason
            ])
        }
        clearWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + clearDelay, execute: work)
    }
}
