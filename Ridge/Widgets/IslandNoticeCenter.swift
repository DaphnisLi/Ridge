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
    /// 实况邀请（遗留 case；电量/媒体已改为直接准入，不再投递）。
    case liveInvite(LiveIslandInvite)

    static let colorPickTipID = "shelf.capture.colorPickTip"
    static let ocrSelectTipID = "shelf.capture.ocrSelectTip"

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
        case .ocrSelectTip:
            return Self.ocrSelectTipID
        case .aiUsageAlert(let id, _, _, _, _):
            return id
        case .moveReminder(let notice):
            return notice.id
        case .meetingLead(let meetingID):
            return "meeting.lead.\(meetingID)"
        case .liveInvite(let invite):
            return invite.noticeID
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
        case .clipboardCaptureHint, .colorPickTip, .ocrSelectTip:
            return "shelf.capture"
        case .aiUsageAlert:
            return "aiUsage"
        case .moveReminder:
            return "moveReminder"
        case .meetingLead:
            return "meeting"
        case .liveInvite(let invite):
            return "live.\(invite.widgetID)"
        }
    }

    /// 自动收起时长；`nil` 表示不自动收（如 RAM 高压、取色/OCR 引导、久坐起身）。
    var autoDismissNanoseconds: UInt64? {
        switch self {
        case .ramPressure, .colorPickTip, .ocrSelectTip, .moveReminder, .meetingLead, .liveInvite:
            // 会议 / 实况邀请：挂到用户处理或状态结束；久坐同理。
            return nil
        case .clipboardCaptureHint:
            // 「已复制」短提示：约 2s，取色/OCR 成功后更容易看见。
            return 2_000_000_000
        case .processEnded, .peripheralLowBattery, .peripheralFullCharge, .aiUsageAlert:
            // 额度等瞬时条约 3s。
            return 3_000_000_000
        }
    }

    /// 指针停在岛上时是否延后自动收起。剪贴板短提示强制按时长关掉。
    var holdsWhileHovering: Bool {
        switch self {
        case .clipboardCaptureHint, .colorPickTip, .ocrSelectTip:
            return false
        case .ramPressure, .processEnded, .peripheralLowBattery, .peripheralFullCharge,
             .aiUsageAlert, .moveReminder, .meetingLead, .liveInvite:
            return true
        }
    }

    /// 会前提示：顶距 0，左右翼贴刘海；外形上直角、下圆角。
    var usesNotchWingChrome: Bool {
        switch self {
        case .meetingLead:
            return true
        default:
            return false
        }
    }

    /// 矮胶囊短条顶距（取色 / OCR / 已复制 / AI 额度）。
    /// 较高提示卡（RAM / 进程结束 / 实况邀请等）走普通通知顶距，岛壳仍是胶囊。
    var usesShortBelowNotchChrome: Bool {
        switch self {
        case .clipboardCaptureHint(let id, _, _):
            return id.hasPrefix("copy.")
        case .aiUsageAlert, .colorPickTip, .ocrSelectTip:
            return true
        default:
            return false
        }
    }

    /// 指针离开岛时仍保持展开（会议 / 久坐 / 实况邀请等须常驻到用户处理）。
    var keepsExpandedWithoutHover: Bool {
        switch self {
        case .meetingLead, .moveReminder, .liveInvite, .ramPressure, .colorPickTip, .ocrSelectTip:
            return true
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
        // 勿先清空再设：会走 dismiss→收岛，0.5s「已复制」来不及看见。
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
        if payload.usesShortBelowNotchChrome {
            IslandController.shared?.prepareShortNoticeLayout(reason: "present:\(payload.id)")
        } else if payload.usesNotchWingChrome {
            // 翼 tip 必须先抬到双翼宽度，否则右翼按钮落在 interactiveFrame 外，点击整窗穿透。
            IslandController.shared?.prepareMeetingWingNoticeLayout(reason: "present:\(payload.id)")
        }
        current = payload
        AppLog.warn("IslandNotice", "已投递瞬时通知", [
            "id": payload.id,
            "source": payload.sourceTag,
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
