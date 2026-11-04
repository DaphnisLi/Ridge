import Combine
import Foundation

/// 岛内瞬时通知载荷。新场景在此加 case，由 `IslandNoticeWidget` 渲染；勿另起通知通道。
enum IslandNoticePayload: Identifiable, Hashable {
    /// 控制台监视的进程结束（与当前 `activeWatch` 一致；被替换的监视不投递）。
    case processEnded(ProjectWatchEndedNotice)
    /// 资源监控：RAM 过载告警。
    case ramPressure(ResourceRAMPressureNotice)
    /// 外设低电（约 3s 自动收；同设备同态由会话边沿去重）。
    case peripheralLowBattery(BatteryPeripheralNotice)
    /// 外设满电（约 3s 自动收）。
    case peripheralFullCharge(BatteryPeripheralNotice)
    /// 剪贴板相关提示（复制成功 / 权限 / 失败）。`symbol` 为 SF Symbol。
    case clipboardCaptureHint(id: String, text: String, symbol: String)
    /// 取色进行中的操作提示（左键 / Esc）；取完或取消后由业务侧 dismiss。
    case colorPickTip

    static let colorPickTipID = "shelf.capture.colorPickTip"

    var id: String {
        switch self {
        case .processEnded(let notice):
            return notice.id
        case .ramPressure(let notice):
            return notice.id
        case .peripheralLowBattery(let notice), .peripheralFullCharge(let notice):
            return notice.id
        case .clipboardCaptureHint(let id, _, _):
            return "shelf.capture.\(id)"
        case .colorPickTip:
            return Self.colorPickTipID
        }
    }

    var sourceTag: String {
        switch self {
        case .processEnded:
            return "projects.watch"
        case .ramPressure:
            return "resource.ram"
        case .peripheralLowBattery:
            return "battery.low"
        case .peripheralFullCharge:
            return "battery.full"
        case .clipboardCaptureHint, .colorPickTip:
            return "shelf.capture"
        }
    }

    /// 自动收起时长；`nil` 表示不自动收（如 RAM 高压、取色引导）。
    var autoDismissNanoseconds: UInt64? {
        switch self {
        case .ramPressure, .colorPickTip:
            return nil
        case .clipboardCaptureHint:
            return 500_000_000
        case .processEnded, .peripheralLowBattery, .peripheralFullCharge:
            return 3_000_000_000
        }
    }

    /// 指针停在岛上时是否延后自动收起。剪贴板短提示强制按时长关掉。
    var holdsWhileHovering: Bool {
        switch self {
        case .clipboardCaptureHint, .colorPickTip:
            return false
        case .ramPressure, .processEnded, .peripheralLowBattery, .peripheralFullCharge:
            return true
        }
    }

    /// 取色引导：顶距 0，左右翼贴刘海。
    var usesNotchWingChrome: Bool {
        switch self {
        case .colorPickTip:
            return true
        default:
            return false
        }
    }

    /// 「已复制」：顶距躲开摄像头，内容落在刘海正下方短条（勿塞进刘海盲区）。
    var usesShortBelowNotchChrome: Bool {
        switch self {
        case .clipboardCaptureHint(let id, _, _):
            return id.hasPrefix("copy.")
        default:
            return false
        }
    }
}

/// 瞬时通知中枢：任意模块 `present`，`system.islandNotice` 统一上岛。
/// 同时只展示一条；后到的替换当前条。自动收起 / 悬停逻辑在 `IslandNoticeWidget`。
@MainActor
final class IslandNoticeCenter: ObservableObject {
    static let shared = IslandNoticeCenter()

    @Published private(set) var current: IslandNoticePayload?

    private init() {}

    func present(_ payload: IslandNoticePayload) {
        current = payload
        AppLog.info("IslandNotice", "已投递瞬时通知", [
            "id": payload.id,
            "source": payload.sourceTag
        ])
    }

    /// - Parameter id: 非 nil 时仅当正展示该 id 才清除。
    func dismiss(id: String? = nil) {
        guard let current else { return }
        if let id, current.id != id { return }
        AppLog.debug("IslandNotice", "瞬时通知已清除", [
            "id": current.id,
            "source": current.sourceTag
        ])
        self.current = nil
    }
}
