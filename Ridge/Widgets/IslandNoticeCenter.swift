import Combine
import Foundation

/// 岛内瞬时通知载荷。新场景在此加 case，由 `IslandNoticeWidget` 渲染；勿另起通知通道。
enum IslandNoticePayload: Identifiable, Hashable {
    case processEnded(ProjectWatchEndedNotice)
    case ramPressure(ResourceRAMPressureNotice)
    case peripheralLowBattery(BatteryPeripheralNotice)
    case peripheralFullCharge(BatteryPeripheralNotice)
    case peripheralConnected(BatteryPeripheralNotice)
    case clipboardCaptureHint(id: String, text: String, symbol: String)
    case colorPickTip
    case ocrSelectTip
    case aiUsageAlert(
        id: String,
        providerName: String,
        remainingPercent: Int,
        stage: AIUsageStage,
        resetsAt: Date?
    )
    case moveReminder(MoveReminderSession.Notice)
    case meetingLead(meetingID: String)

    static let colorPickTipID = "shelf.capture.colorPickTip"
    static let ocrSelectTipID = "shelf.capture.ocrSelectTip"

    var id: String {
        switch self {
        case .processEnded(let notice): return notice.id
        case .ramPressure(let notice): return notice.id
        case .peripheralLowBattery(let notice),
             .peripheralFullCharge(let notice),
             .peripheralConnected(let notice):
            return notice.id
        case .clipboardCaptureHint(let id, _, _):
            return "shelf.capture.\(id)"
        case .colorPickTip: return Self.colorPickTipID
        case .ocrSelectTip: return Self.ocrSelectTipID
        case .aiUsageAlert(let id, _, _, _, _): return id
        case .moveReminder(let notice): return notice.id
        case .meetingLead(let meetingID): return "meeting.lead.\(meetingID)"
        }
    }

    var sourceTag: String {
        switch self {
        case .processEnded: return "projects.watch"
        case .ramPressure: return "resource.ram"
        case .peripheralLowBattery: return "battery.low"
        case .peripheralFullCharge: return "battery.full"
        case .peripheralConnected: return "battery.connect"
        case .clipboardCaptureHint, .colorPickTip, .ocrSelectTip: return "shelf.capture"
        case .aiUsageAlert: return "aiUsage"
        case .moveReminder: return "moveReminder"
        case .meetingLead: return "meeting"
        }
    }

    /// 非专注提示统一约 3s；会议 / 取色 / OCR 仍手动收。
    var autoDismissNanoseconds: UInt64? {
        switch self {
        case .colorPickTip, .ocrSelectTip, .meetingLead:
            return nil
        case .clipboardCaptureHint, .moveReminder, .ramPressure, .processEnded,
             .peripheralLowBattery, .peripheralFullCharge, .peripheralConnected,
             .aiUsageAlert:
            return 3_000_000_000
        }
    }

    var holdsWhileHovering: Bool {
        switch self {
        case .colorPickTip, .ocrSelectTip:
            return false
        case .clipboardCaptureHint, .ramPressure, .processEnded, .peripheralLowBattery,
             .peripheralFullCharge, .peripheralConnected, .aiUsageAlert, .moveReminder, .meetingLead:
            return true
        }
    }

    var usesNotchWingChrome: Bool {
        switch self {
        case .meetingLead, .aiUsageAlert, .moveReminder, .colorPickTip, .ocrSelectTip,
             .peripheralLowBattery, .peripheralFullCharge, .peripheralConnected:
            return true
        default:
            return false
        }
    }

    /// 单独上岛时走左右 flush（RAM 右半 / 进程结束双翼）；勿抬会议双翼宽。
    var usesDualFlushSoloChrome: Bool {
        switch self {
        case .ramPressure, .processEnded:
            return true
        default:
            return false
        }
    }

    /// 单独上岛时只要右翼半块（RAM）；进程结束要左右双翼。
    var usesDualFlushTrailingOnlyChrome: Bool {
        switch self {
        case .ramPressure:
            return true
        default:
            return false
        }
    }

    var usesShortBelowNotchChrome: Bool { false }

    var usesNotchRightOrbChrome: Bool {
        switch self {
        case .clipboardCaptureHint(let id, _, _):
            return id.hasPrefix("copy.")
        default:
            return false
        }
    }

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

    var preemptionRank: Int {
        switch self {
        case .meetingLead: return 100
        case .moveReminder: return 50
        default: return 0
        }
    }
}

/// 旧单槽「能否整岛替换」语义；双槽投递走 `IslandNoticeSlotPolicy`。
enum IslandNoticePreemption {
    static func shouldAccept(incoming: IslandNoticePayload, replacing current: IslandNoticePayload?) -> Bool {
        guard let current else { return true }
        if current.id == incoming.id { return true }
        if current.displayLane >= .primary, incoming.displayLane == .secondary {
            return false
        }
        if current.displayLane == .exclusive, incoming.displayLane != .exclusive {
            return false
        }
        let solo: IslandNoticeSlots
        switch current.displayLane {
        case .secondary:
            solo = IslandNoticeSlots(secondary: current)
        case .primary, .exclusive:
            solo = IslandNoticeSlots(primary: current)
        }
        return IslandNoticeSlotPolicy.applying(incoming: incoming, to: solo) != nil
    }
}

/// 瞬时通知中枢：A/B/C 双槽 + 专注待命常驻旗标。
@MainActor
final class IslandNoticeCenter: ObservableObject {
    static let shared = IslandNoticeCenter()

    @Published private(set) var slots = IslandNoticeSlots()
    @Published private(set) var current: IslandNoticePayload?

    private var residentObservers: Set<AnyCancellable> = []

    private init() {
        FocusTimerSession.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncResidents() }
            .store(in: &residentObservers)
        NowPlayingService.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncResidents() }
            .store(in: &residentObservers)
        WidgetSettings.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncResidents() }
            .store(in: &residentObservers)
        syncResidents()
    }

    func present(_ payload: IslandNoticePayload) {
        guard let next = IslandNoticeSlotPolicy.applying(incoming: payload, to: slots) else {
            AppLog.info("IslandNotice", "瞬时通知被更高优先级挡住", [
                "blocked": payload.id,
                "blockedSource": payload.sourceTag,
                "blockedLane": payload.displayLane.rawValue,
                "primary": slots.primary?.id ?? "",
                "secondary": slots.secondary?.id ?? "",
                "focus": slots.focusResident
            ])
            return
        }
        commit(next, triggering: payload)
    }

    func dismiss(id: String? = nil) {
        let previous = slots
        let next = IslandNoticeSlotPolicy.dismissing(id: id, from: slots)
        guard next != previous else { return }
        AppLog.debug("IslandNotice", "瞬时通知已清除", [
            "id": id ?? "all",
            "primary": next.primary?.id ?? "",
            "secondary": next.secondary?.id ?? "",
            "queue": next.secondaryQueue.count,
            "focus": next.focusResident
        ])
        commit(next, triggering: nil)
    }

    private func syncResidents() {
        let focus = FocusTimerSession.shared.showsCompactStandby
        // 音乐是 B；专注亮时业务上不播小岛，mediaResident 仍跟 MediaCompactPresence。
        let media = MediaCompactPresence.isActive
        guard slots.focusResident != focus || slots.mediaResident != media else { return }
        var next = slots
        next.focusResident = focus
        next.mediaResident = media
        AppLog.info("IslandNotice", "B/C 常驻旗标", [
            "focus": focus,
            "media": media,
            "phase": FocusTimerSession.shared.phase.rawValue,
            "layout": String(describing: next.resolvedLayout)
        ])
        commit(next, triggering: nil)
    }

    private func commit(_ next: IslandNoticeSlots, triggering payload: IslandNoticePayload?) {
        prepareLayout(for: next, triggering: payload)
        slots = next
        current = next.current
        if let payload {
            AppLog.warn("IslandNotice", "已投递瞬时通知", [
                "id": payload.id,
                "source": payload.sourceTag,
                "lane": payload.displayLane.rawValue,
                "dual": next.isDual,
                "primary": next.primary?.id ?? "",
                "secondary": next.secondary?.id ?? "",
                "queue": next.secondaryQueue.count,
                "queued": next.secondaryQueue.map(\.id).joined(separator: ","),
                "focus": next.focusResident,
                "media": next.mediaResident,
                "layout": String(describing: next.resolvedLayout),
                "dualFlush": next.usesDualFlushChrome,
                "orbTip": next.anyUsesNotchRightOrbChrome,
                "wingTip": next.anyUsesNotchWingChrome,
                "rank": payload.preemptionRank
            ])
        }
    }

    private func prepareLayout(for next: IslandNoticeSlots, triggering payload: IslandNoticePayload?) {
        switch next.resolvedLayout {
        case .empty, .fullFocus, .fullMedia:
            // 仅专注 / 仅音乐：收起翼，不预备通知页尺寸。
            return
        case .dual:
            if next.usesDualFlushChrome {
                IslandController.shared?.prepareDualFlushNoticeLayout(
                    reason: "presentDualFlush:\(payload?.id ?? "resident")"
                )
            } else {
                IslandController.shared?.prepareMeetingWingNoticeLayout(
                    reason: "presentDual:\(payload?.id ?? "resident")"
                )
            }
        case .fullNotice(let p):
            if next.usesDualFlushChrome {
                IslandController.shared?.prepareDualFlushNoticeLayout(reason: "presentDualFlushSolo:\(p.id)")
            } else if next.anyUsesNotchRightOrbChrome {
                IslandController.shared?.prepareNotchRightOrbLayout(reason: "present:\(p.id)")
            } else if p.usesShortBelowNotchChrome {
                IslandController.shared?.prepareShortNoticeLayout(reason: "present:\(p.id)")
            } else if next.anyUsesNotchWingChrome {
                IslandController.shared?.prepareMeetingWingNoticeLayout(reason: "present:\(p.id)")
            }
        }
    }
}
