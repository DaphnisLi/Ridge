import AVFoundation
import AVKit
import AppKit
import SwiftUI

private enum OnboardingDemoVideoResource {
    static let subdirectory = "Onboarding"
    static let name = "onboarding-island-demo"
    static let ext = "mov"
    /// 源片 1284×776，框按此比例撑开，避免矮框 + Fill 裁切。
    static let pixelWidth: CGFloat = 1284
    static let pixelHeight: CGFloat = 776
    static var aspectRatio: CGFloat { pixelWidth / pixelHeight }
}

/// 引导第一页演示片：Bundle 内 `Onboarding/onboarding-island-demo.mov`，静音循环。
/// 不用 SwiftUI `VideoPlayer`（AVKit SwiftUI 在引导窗 layout 时会 fatal）。
struct OnboardingDemoVideoView: View {
    @StateObject private var model = OnboardingDemoVideoModel()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: SettingsChrome.Radius.bento, style: .continuous)
                .fill(Color.black.opacity(0.92))

            if let player = model.player {
                OnboardingAVPlayerView(player: player)
                    .clipShape(RoundedRectangle(cornerRadius: SettingsChrome.Radius.bento, style: .continuous))
                    .allowsHitTesting(false)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(SettingsChrome.onSurfaceVariant.opacity(0.55))
                    Text(L10n.Onboarding.videoPlaceholder)
                        .font(SettingsChrome.Font.caption)
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                }
            }
        }
        .aspectRatio(OnboardingDemoVideoResource.aspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: SettingsChrome.Radius.bento, style: .continuous)
                .strokeBorder(SettingsChrome.cardStroke, lineWidth: SettingsChrome.cardStrokeWidth)
        )
        .accessibilityLabel(L10n.Onboarding.stepIslandTitle)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }
}

private struct OnboardingAVPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        // Fit：完整画面；框已按片源比例，基本铺满无裁切。
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}

@MainActor
private final class OnboardingDemoVideoModel: ObservableObject {
    @Published private(set) var player: AVPlayer?

    private var looper: AVPlayerLooper?
    private var queuePlayer: AVQueuePlayer?

    func start() {
        guard player == nil else {
            queuePlayer?.play()
            return
        }
        guard let url = Bundle.main.url(
            forResource: OnboardingDemoVideoResource.name,
            withExtension: OnboardingDemoVideoResource.ext,
            subdirectory: OnboardingDemoVideoResource.subdirectory
        ) else {
            AppLog.warn("Onboarding", "演示视频缺失", [
                "subdir": OnboardingDemoVideoResource.subdirectory,
                "name": OnboardingDemoVideoResource.name,
                "ext": OnboardingDemoVideoResource.ext
            ])
            return
        }
        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer(playerItem: item)
        queue.isMuted = true
        looper = AVPlayerLooper(player: queue, templateItem: item)
        queuePlayer = queue
        player = queue
        queue.play()
        AppLog.warn("Onboarding", "演示视频开始播放", ["loop": true, "muted": true])
    }

    func stop() {
        queuePlayer?.pause()
        AppLog.debug("Onboarding", "演示视频已暂停")
    }
}
