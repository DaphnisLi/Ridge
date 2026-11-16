import AVFoundation
import AVKit
import AppKit
import SwiftUI

private enum OnboardingDemoVideoResource {
    static let subdirectory = "Onboarding"
    static let name = "onboarding-island-demo"
    static let ext = "mov"
    /// 引导稿面 16:10；源片约 1284×776 接近此比，Fit 基本铺满。
    static let aspectRatio: CGFloat = 16.0 / 10.0
}

/// 引导第一页演示片：Bundle 内真片静音循环。
/// 不用 SwiftUI `VideoPlayer`（AVKit SwiftUI 在引导窗 layout 时会 fatal）。
struct OnboardingDemoVideoView: View {
    @StateObject private var model = OnboardingDemoVideoModel()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: SettingsChrome.Radius.bento, style: .continuous)
                .fill(Color.black)

            if let player = model.player {
                OnboardingAVPlayerView(player: player)
                    .clipShape(RoundedRectangle(cornerRadius: SettingsChrome.Radius.bento, style: .continuous))
                    .allowsHitTesting(false)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.45))
                    Text(L10n.Onboarding.videoPlaceholder)
                        .font(SettingsChrome.Font.caption)
                        .foregroundStyle(Color.white.opacity(0.55))
                }
            }
        }
        .aspectRatio(OnboardingDemoVideoResource.aspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: SettingsChrome.Radius.bento, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 18, y: 10)
        .overlay(
            RoundedRectangle(cornerRadius: SettingsChrome.Radius.bento, style: .continuous)
                .strokeBorder(Color.black.opacity(0.12), lineWidth: 1)
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
