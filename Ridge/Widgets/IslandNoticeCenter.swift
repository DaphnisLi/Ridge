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
    /// 外设接入（约 3s 自动收）。
    case peripheralConnected(BatteryPeripheralNotice)
    /// 剪贴板相关提示（复制成功 / 权限 / 失败）。`symbol` 为 SF Symbol。
    case clipboardCaptureHint(id: String, text: String, symbol: String)
    /// 取色进行中的操作提示（左键 / Esc）；取完或取消后由业务侧 dismiss。
    case colorPickTip
    /// OCR 框选进行中的操作提示（正在框选 / Esc）；结束或取消后由业务侧 dismiss。
    case ocrSelectTip
    /// AI 额度触达充裕 / 警戒 / 截流任一阈值（约 3s 瞬时胶囊；非常驻页）。
    case aiUsageAlert(
        id: String,
        providerName: String,
        remainingPercent: Int,
        stage: AIUsageStage,
        resetsAt: Date?
    )
    /// 久坐起身提醒（须点「稍后」/「今天不再」；不自动收）。
    case moveReminder(MoveReminderSession.Notice)
    /// 会前提示（提示类；入会或日程结束前挂着，不占内容分页）。
    case meetingLead(meetingID: String)

    static let colorPickTipID = "shelf.capture.colorPickTip"
    static let ocrSelectTipID = "shelf.capture.ocrSelectTip"

    var id: String {
        switch self {
        case .processEnded(let notice):
            return notice.id
        case .ramPressure(let notice):
            return notice.id
        case .peripheralLowBattery(let notice),
             .peripheralFullCharge(let notice),
             .peripheralConnected(let notice):
            return notice.id
        case .clipboardCaptureHint(let id, _, _):
            return "shelf.capture.\(id)"
        case .colorPickTip:
            return Self.colorPickTipID
        case .ocrSelectTip:
            return Self.ocrSelectTipID
        case .aiUsageAlert(let id, _, _, _, _):
            return id
        case .moveReminder(let notice):
            return notice.id
        case .meetingLead(let meetingID):
            return "meeting.lead.\(meetingID)"
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
        case .peripheralConnected:
            return "battery.connect"
        case .clipboardCaptureHint, .colorPickTip, .ocrSelectTip:
            return "shelf.capture"
        case .aiUsageAlert:
            return "aiUsage"
        case .moveReminder:
            return "moveReminder"
        case .meetingLead:
            return "meeting"
        }
    }

    /// 自动收起时长；`nil` 表示不自动收（如 RAM 高压、取色/OCR 引导、久坐起身）。
    var autoDismissNanoseconds: UInt64? {
        switch self {
        case .ramPressure, .colorPickTip, .ocrSelectTip, .moveReminder, .meetingLead:
            return nil
        case .clipboardCaptureHint(let id, _, _):
            // 「已复制」圆岛：入场约 0.9s + 定格 0.5s；其它剪贴板提示仍约 3s。
            if id.hasPrefix("copy.") {
                return IslandChrome.notchRightOrbAutoDismissNanoseconds
            }
            return 3_000_000_000
        case .processEnded,
             .peripheralLowBattery,
             .peripheralFullCharge,
             .peripheralConnected,
             .aiUsageAlert:
            return 3_000_000_000
        }
    }

    /// 指针停在岛上时是否延后自动收起。
    var holdsWhileHovering: Bool {
        switch self {
        case .colorPickTip, .ocrSelectTip:
            return false
        case .clipboardCaptureHint, .ramPressure, .processEnded, .peripheralLowBattery,
             .peripheralFullCharge, .peripheralConnected, .aiUsageAlert, .moveReminder, .meetingLead:
            return true
        }
    }

    /// 会议 / AI 额度 / 久坐 / 取色 / 框选 / 外设电量：顶距 0，左右翼贴刘海；外形上直角、下圆角。
    var usesNotchWingChrome: Bool {
        switch self {
        case .meetingLead, .aiUsageAlert, .moveReminder, .colorPickTip, .ocrSelectTip,
             .peripheralLowBattery, .peripheralFullCharge, .peripheralConnected:
            return true
        default:
            return false
        }
    }

    /// 矮胶囊短条顶距（遗留；「已复制」已改刘海右侧圆岛）。
    var usesShortBelowNotchChrome: Bool {
        false
    }

    /// 刘海右侧 Ø32 圆形微岛（「已复制」方案 02）。
    var usesNotchRightOrbChrome: Bool {
        switch self {
        case .clipboardCaptureHint(let id, _, _):
            return id.hasPrefix("copy.")
        default:
            return false
        }
    }

    /// 指针离开岛时仍保持展开（会议 / 久坐 / 取色引导；「已复制」也须挂满自动收起时长，否则 Cmd+C 后移开指针会在展开中途收岛）。
    var keepsExpandedWithoutHover: Bool {
        switch self {
        case .meetingLead, .moveReminder, .ramPressure, .colorPickTip, .ocrSelectTip:
            return true
        case .clipboardCaptureHint(let id, _, _):
            return id.hasPrefix("copy.")
        default:
            return false
        }
    }

    /// 抢占优先级：数值越大越不易被盖掉。会前提示最高，其它瞬时条不得盖住它。
    var preemptionRank: Int {
        switch self {
        case .meetingLead:
            return 100
        default:
            return 0
        }
    }
}

/// 瞬时通知抢占策略（纯函数，便于单测）。
enum IslandNoticePreemption {
    /// 是否允许 `incoming` 替换当前条。同级可互相替换；低优先级不得盖高优先级。
    static func shouldAccept(incoming: IslandNoticePayload, replacing current: IslandNoticePayload?) -> Bool {
        guard let current else { return true }
        if current.id == incoming.id { return true }
        return incoming.preemptionRank >= current.preemptionRank
    }
}

/// 瞬时通知中枢：任意模块 `present`，`system.islandNotice` 统一上岛。
/// 同时只展示一条；后到的替换当前条（受抢占优先级约束）。自动收起 / 悬停逻辑在 `IslandNoticeWidget`。
@MainActor
final class IslandNoticeCenter: ObservableObject {
    static let shared = IslandNoticeCenter()

    @Published private(set) var current: IslandNoticePayload?

    private init() {}

    func present(_ payload: IslandNoticePayload) {
        // 勿先清空再设：会走 dismiss→收岛，「已复制」来不及看见。
        // 同内容再投由业务侧换唯一 id（如 copy.token）保证 @Published 触发。
        //
        // 会前提示优先级最高：其它瞬时条在会议仍展示时直接丢弃，不得盖下去。
        if !IslandNoticePreemption.shouldAccept(incoming: payload, replacing: current) {
            AppLog.info("IslandNotice", "瞬时通知被更高优先级挡住", [
                "blocked": payload.id,
                "blockedSource": payload.sourceTag,
                "current": current?.id ?? "",
                "currentSource": current?.sourceTag ?? "",
                "blockedRank": payload.preemptionRank,
                "currentRank": current?.preemptionRank ?? 0
            ])
            return
        }
        //
        // 短胶囊必须在改 current 之前预备尺寸：SwiftUI 会立刻 Preference，
        // 若仍卡在上一通知尺寸会被误缩守卫拒绝，提示整段被顶出可视区。
        if payload.usesNotchRightOrbChrome {
            IslandController.shared?.prepareNotchRightOrbLayout(reason: "present:\(payload.id)")
        } else if payload.usesShortBelowNotchChrome {
            IslandController.shared?.prepareShortNoticeLayout(reason: "present:\(payload.id)")
        } else if payload.usesNotchWingChrome {
            // 翼 tip 必须先抬到双翼宽度，否则右翼按钮落在 interactiveFrame 外，点击整窗穿透。
            IslandController.shared?.prepareMeetingWingNoticeLayout(reason: "present:\(payload.id)")
        }
        current = payload
        AppLog.warn("IslandNotice", "已投递瞬时通知", [
            "id": payload.id,
            "source": payload.sourceTag,
            "orbTip": payload.usesNotchRightOrbChrome,
            "shortTip": payload.usesShortBelowNotchChrome,
            "wingTip": payload.usesNotchWingChrome,
            "rank": payload.preemptionRank
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
