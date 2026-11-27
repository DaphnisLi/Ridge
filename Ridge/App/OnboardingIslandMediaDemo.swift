import Foundation

/// 引导第 1 步：在真岛上注入假「正在播放」小岛；用户悬停刘海时走既有
/// `MediaCompactPresence.openExpandedPanel` 展开媒体大面板。
@MainActor
final class OnboardingIslandMediaDemo {
    static let shared = OnboardingIslandMediaDemo()

    private(set) var isActive = false
    /// 用户悬停展开后的可选回调（仅日志 / 演示，不挡「继续」）。
    var onUserExpanded: (() -> Void)?

    private var previousMediaEnabled: Bool?
    private var didNoteExpand = false

    private init() {}

    func start() {
        guard !isActive else { return }
        isActive = true
        didNoteExpand = false

        let mediaID = MediaNowPlayingWidget.manifest.id
        previousMediaEnabled = WidgetSettings.shared.isEnabled(mediaID)
        if previousMediaEnabled != true {
            // 媒体默认关；演示临时打开（无 TCC）。离开本步再按原状恢复。
            WidgetSettings.shared.setEnabled(mediaID, enabled: true)
        }

        NowPlayingService.shared.start()
        NowPlayingService.shared.setOnboardingDemoActive(true)
        AppLog.warn("Onboarding", "第1步：假媒体已上岛", [
            "prevMediaOn": previousMediaEnabled ?? false
        ])
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        onUserExpanded = nil
        didNoteExpand = false

        LiveIslandGate.shared.close(LiveIslandGate.mediaID, reason: "onboardingDemoEnd")
        NowPlayingService.shared.setOnboardingDemoActive(false)

        if let previousMediaEnabled, !previousMediaEnabled {
            WidgetSettings.shared.setEnabled(MediaNowPlayingWidget.manifest.id, enabled: false)
        }
        previousMediaEnabled = nil

        if IslandController.shared?.viewModel.isExpanded == true {
            IslandController.shared?.collapse(reason: "onboardingDemoEnd")
        }
        AppLog.warn("Onboarding", "第1步：假媒体演示已结束")
    }

    /// 悬停 / 点按播放小岛展开大面板时由 `MediaCompactPresence` 调用。
    func noteUserExpandedIsland(reason: String) {
        guard isActive, !didNoteExpand else { return }
        didNoteExpand = true
        AppLog.warn("Onboarding", "第1步：用户已悬停展开媒体岛", ["reason": reason])
        onUserExpanded?()
    }
}
