import Combine
import Foundation

/// 货架模块偏好（复制上岛提示等）。
@MainActor
final class ShelfSettings: ObservableObject {
    static let shared = ShelfSettings()

    private enum Key {
        static let showCopiedNotice = "shelf.showCopiedNotice.v1"
    }

    /// 复制成功时是否上岛「已复制」提示；默认开启。
    @Published var showCopiedNotice: Bool {
        didSet {
            UserDefaults.standard.set(showCopiedNotice, forKey: Key.showCopiedNotice)
            AppLog.info("Shelf", "复制提示开关已更新", ["enabled": showCopiedNotice])
        }
    }

    private init() {
        showCopiedNotice = UserDefaults.standard.object(forKey: Key.showCopiedNotice) as? Bool ?? true
        AppLog.debug("Shelf", "已加载货架设置", ["showCopiedNotice": showCopiedNotice])
    }
}
