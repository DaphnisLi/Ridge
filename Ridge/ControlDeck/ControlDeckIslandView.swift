import SwiftUI

/// 岛上控制台页：当前以「专业双轨混音台」为功能组件。
struct ControlDeckIslandView: View {
    var body: some View {
        SoundMixerDeckView()
            .accessibilityLabel(L10n.ControlDeck.title)
    }
}
