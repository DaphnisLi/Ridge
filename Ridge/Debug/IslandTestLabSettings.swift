#if DEBUG
import Combine
import Foundation

/// 岛测试台会话偏好：仅 DEBUG；Release 无此类型、无覆盖入口。
@MainActor
final class IslandTestLabSettings: ObservableObject {
    static let shared = IslandTestLabSettings()

    private enum Key {
        static let tipOverrideEnabled = "debug.islandTestLab.tipOverrideEnabled"
        static let tipSeconds = "debug.islandTestLab.tipSeconds"
    }

    /// 是否覆盖瞬时 tip 默认约 3s。
    @Published var tipOverrideEnabled: Bool {
        didSet {
            UserDefaults.standard.set(tipOverrideEnabled, forKey: Key.tipOverrideEnabled)
            AppLog.info("TestLab", "tip 时长覆盖开关", [
                "enabled": tipOverrideEnabled,
                "seconds": tipSeconds
            ])
        }
    }

    /// 覆盖秒数；钳制 0.5…30。
    @Published var tipSeconds: Double {
        didSet {
            let clamped = Self.clampTipSeconds(tipSeconds)
            if clamped != tipSeconds {
                tipSeconds = clamped
                return
            }
            UserDefaults.standard.set(tipSeconds, forKey: Key.tipSeconds)
            AppLog.debug("TestLab", "tip 时长覆盖已改", ["seconds": tipSeconds])
        }
    }

    /// 供 `IslandNoticePayload.autoDismissNanoseconds` 读取；未开覆盖则 nil。
    var tipDurationNanoseconds: UInt64? {
        Self.resolvedTipDurationNanoseconds()
    }

    private init() {
        tipOverrideEnabled = UserDefaults.standard.bool(forKey: Key.tipOverrideEnabled)
        let raw = UserDefaults.standard.object(forKey: Key.tipSeconds) as? Double ?? 3
        tipSeconds = Self.clampTipSeconds(raw)
    }

    nonisolated static func clampTipSeconds(_ value: Double) -> Double {
        min(max(value, 0.5), 30)
    }

    /// 非 MainActor：通知策略路径可直接读 UserDefaults，避免隔离冲突。
    /// XCTest 进程忽略覆盖，避免本机调试台把套件里的 3s 断言打成 0.5s。
    nonisolated static func resolvedTipDurationNanoseconds() -> UInt64? {
        if NSClassFromString("XCTestCase") != nil { return nil }
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Key.tipOverrideEnabled) else { return nil }
        let raw = defaults.object(forKey: Key.tipSeconds) as? Double ?? 3
        return UInt64(clampTipSeconds(raw) * 1_000_000_000)
    }

    func resetTipDuration() {
        tipOverrideEnabled = false
        tipSeconds = 3
        AppLog.info("TestLab", "tip 时长已恢复默认 3s")
    }
}
#endif
