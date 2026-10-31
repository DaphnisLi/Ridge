import AppKit
import Foundation

/// 触控板震感。系统 API 无连续强度，用档位 + 连击近似强弱。
enum IslandHapticIntensity: Int, CaseIterable, Identifiable, Hashable {
    case off = 0
    case light = 1
    case medium = 2
    case strong = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .off: return "关"
        case .light: return "轻"
        case .medium: return "中"
        case .strong: return "强"
        }
    }
}

enum IslandHaptics {
    @MainActor
    static func play(_ intensity: IslandHapticIntensity) {
        guard intensity != .off else { return }
        let performer = NSHapticFeedbackManager.defaultPerformer

        switch intensity {
        case .off:
            return
        case .light:
            performer.perform(.alignment, performanceTime: .now)
        case .medium:
            // generic 比 alignment 更明显
            performer.perform(.generic, performanceTime: .now)
        case .strong:
            // 双击 generic，体感明显更重
            performer.perform(.generic, performanceTime: .now)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.045) {
                NSHapticFeedbackManager.defaultPerformer.perform(
                    .levelChange,
                    performanceTime: .now
                )
            }
        }
    }
}
