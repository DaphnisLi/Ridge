import Combine
import Foundation

/// 岛内瞬时通知载荷。新场景在此加 case，由 `IslandNoticeWidget` 渲染；勿另起通知通道。
enum IslandNoticePayload: Identifiable, Hashable {
    case processEnded(ProjectWatchEndedNotice)
    case ramPressure(ResourceRAMPressureNotice)
    case peripheralLowBattery(BatteryPeripheralNotice)
    case peripheralFullCharge(BatteryPeripheralNotice)
    case peripheralConnected(BatteryPeripheralNotice)
    case macBatteryCharging(MacBatteryNotice)
    case macBatteryLow(MacBatteryNotice)
    case macBatteryFull(MacBatteryNotice)
    case macBatteryUnplugged(MacBatteryNotice)
    case networkWifiConnected(NetworkLinkNotice)
    case networkWiredConnected(NetworkLinkNotice)
    case networkVPNConnected(NetworkLinkNotice)
    case networkWifiDisconnected(NetworkLinkNotice)
    case networkVPNDisconnected(NetworkLinkNotice)
    case systemFocusOn(SystemFocusNotice)
    case systemFocusOff(SystemFocusNotice)
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
        case .macBatteryCharging(let notice),
             .macBatteryLow(let notice),
             .macBatteryFull(let notice),
             .macBatteryUnplugged(let notice):
            return notice.id
        case .networkWifiConnected(let notice),
             .networkWiredConnected(let notice),
             .networkVPNConnected(let notice),
             .networkWifiDisconnected(let notice),
             .networkVPNDisconnected(let notice):
            return notice.id
        case .systemFocusOn(let notice), .systemFocusOff(let notice):
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
        case .macBatteryCharging: return "macBattery.charging"
        case .macBatteryLow: return "macBattery.low"
        case .macBatteryFull: return "macBattery.full"
        case .macBatteryUnplugged: return "macBattery.unplugged"
        case .networkWifiConnected: return "network.wifiConnected"
        case .networkWiredConnected: return "network.wiredConnected"
        case .networkVPNConnected: return "network.vpnConnected"
        case .networkWifiDisconnected: return "network.wifiDisconnected"
        case .networkVPNDisconnected: return "network.vpnDisconnected"
        case .systemFocusOn: return "systemFocus.on"
        case .systemFocusOff: return "systemFocus.off"
        case .clipboardCaptureHint, .colorPickTip, .ocrSelectTip: return "shelf.capture"
        case .aiUsageAlert: return "aiUsage"
        case .moveReminder: return "moveReminder"
        case .meetingLead: return "meeting"
        }
    }

    /// 多数瞬时 tip 约 3s；「已复制」跟入场动效约 1.05s；会议 / 取色 / OCR 仍手动收。
    /// DEBUG 测试台可覆盖停留时长（`IslandTestLabSettings`）。
    var autoDismissNanoseconds: UInt64? {
        switch self {
        case .colorPickTip, .ocrSelectTip, .meetingLead:
            return nil
        case .clipboardCaptureHint(let id, _, _):
            // 「已复制」固定跟圆岛入场+定格，不受测试台 tip 时长覆盖（否则会闪没或拖太久）。
            if LockedInvariants.CopiedNotice.isCopiedTipID(id) {
                return IslandNoticeAutoDismissPolicy.copiedNoticeNanoseconds
            }
            #if DEBUG
            if let override = IslandTestLabSettings.resolvedTipDurationNanoseconds() {
                return override
            }
            #endif
            return IslandNoticeAutoDismissPolicy.standardNanoseconds
        case .moveReminder, .ramPressure, .processEnded,
             .peripheralLowBattery, .peripheralFullCharge, .peripheralConnected,
             .macBatteryCharging, .macBatteryLow, .macBatteryFull, .macBatteryUnplugged,
             .networkWifiConnected, .networkWiredConnected, .networkVPNConnected,
             .networkWifiDisconnected, .networkVPNDisconnected,
             .systemFocusOn, .systemFocusOff,
             .aiUsageAlert:
            #if DEBUG
            if let override = IslandTestLabSettings.resolvedTipDurationNanoseconds() {
                return override
            }
            #endif
            return IslandNoticeAutoDismissPolicy.standardNanoseconds
        }
    }

    var holdsWhileHovering: Bool {
        switch self {
        case .colorPickTip, .ocrSelectTip:
            return false
        case .clipboardCaptureHint(let id, _, _):
            // 「已复制」动效走完即收，悬停不续命。
            return LockedInvariants.CopiedNotice.isCopiedTipID(id)
                ? LockedInvariants.CopiedNotice.holdsWhileHovering
                : true
        case .ramPressure, .processEnded, .peripheralLowBattery,
             .peripheralFullCharge, .peripheralConnected,
             .macBatteryCharging, .macBatteryLow, .macBatteryFull, .macBatteryUnplugged,
             .networkWifiConnected, .networkWiredConnected, .networkVPNConnected,
             .networkWifiDisconnected, .networkVPNDisconnected,
             .systemFocusOn, .systemFocusOff,
             .aiUsageAlert, .moveReminder, .meetingLead:
            return true
        }
    }

    var usesNotchWingChrome: Bool {
        switch self {
        case .meetingLead, .aiUsageAlert, .moveReminder, .colorPickTip, .ocrSelectTip,
             .peripheralLowBattery, .peripheralFullCharge, .peripheralConnected,
             .macBatteryCharging, .macBatteryLow, .macBatteryFull, .macBatteryUnplugged,
             .networkWifiConnected, .networkWiredConnected, .networkVPNConnected,
             .networkWifiDisconnected, .networkVPNDisconnected,
             .systemFocusOn, .systemFocusOff:
            return true
        default:
            return false
        }
    }

    /// 外设满岛：翼宽比会议收窄，设备名滚动。
    var usesCompactPeripheralWing: Bool {
        switch self {
        case .peripheralLowBattery, .peripheralFullCharge, .peripheralConnected:
            return true
        default:
            return false
        }
    }

    /// 网络 tip：翼宽略收（`preparedNetworkLinkWingWidth`），名称可滚动。
    var usesNetworkLinkWing: Bool {
        switch self {
        case .networkWifiConnected, .networkWiredConnected, .networkVPNConnected,
             .networkWifiDisconnected, .networkVPNDisconnected:
            return true
        default:
            return false
        }
    }

    /// 单独上岛时走左右 flush（RAM / 进程结束双翼贴刘海）；勿抬会议双翼宽。
    var usesDualFlushSoloChrome: Bool {
        switch self {
        case .ramPressure, .processEnded:
            return true
        default:
            return false
        }
    }

    /// 单独上岛只要右翼半块；RAM 单独为左右双翼整岛，不走 trailing-only。
    var usesDualFlushTrailingOnlyChrome: Bool {
        false
    }

    var usesShortBelowNotchChrome: Bool { false }

    var usesNotchRightOrbChrome: Bool {
        switch self {
        case .clipboardCaptureHint(let id, _, _):
            return LockedInvariants.CopiedNotice.isCopiedTipID(id)
        default:
            return false
        }
    }

    /// 程序 expand 后保持展开，不依赖指针移入；约 3s 自动收的瞬时 tip 全部纳入。
    var keepsExpandedWithoutHover: Bool {
        switch self {
        case .meetingLead, .moveReminder, .ramPressure, .processEnded, .colorPickTip, .ocrSelectTip,
             .peripheralLowBattery, .peripheralFullCharge, .peripheralConnected,
             .macBatteryCharging, .macBatteryLow, .macBatteryFull, .macBatteryUnplugged,
             .networkWifiConnected, .networkWiredConnected, .networkVPNConnected,
             .networkWifiDisconnected, .networkVPNDisconnected,
             .systemFocusOn, .systemFocusOff,
             .aiUsageAlert:
            return true
        case .clipboardCaptureHint(let id, _, _):
            return LockedInvariants.CopiedNotice.isCopiedTipID(id)
        }
    }

    /// 有自动收起的瞬时 tip：设置设计页开着也要程序上岛（不靠悬停）；会议/取色等无自动收的仍挡。
    var expandsDuringSettingsSession: Bool {
        autoDismissNanoseconds != nil
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
        DownloadCompleteSession.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncResidents() }
            .store(in: &residentObservers)
        syncResidents()
    }

    /// 下载会话主动推一次常驻同步（与 objectWillChange 互补）。
    func refreshResidentsFromDownload() {
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
        // 音乐是 B；可与专注并排（左音乐右专注），mediaResident 跟播放态。
        let media = MediaCompactPresence.isActive
        // C 档下载：同档内高于计时；与计时并排占左、与 B 音乐并排占右；旗标跟会话。
        let download = DownloadCompactPresence.isActive
        guard slots.focusResident != focus
            || slots.mediaResident != media
            || slots.downloadResident != download
        else { return }
        var next = slots
        next.focusResident = focus
        next.mediaResident = media
        next.downloadResident = download
        AppLog.info("IslandNotice", "B/C 常驻旗标", [
            "focus": focus,
            "media": media,
            "download": download,
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
                "download": next.downloadResident,
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
        case .empty, .fullFocus, .fullMedia, .fullDownload:
            // 仅专注 / 仅音乐 / 仅下载：收起翼，不预备通知页尺寸。
            return
        case .dual:
            // 音乐+专注收起双翼走 compactSize；有 tip 的双槽才预备展开尺寸。
            guard next.hasNoticePayload else { return }
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
            } else if p.usesCompactPeripheralWing {
                IslandController.shared?.preparePeripheralWingNoticeLayout(reason: "present:\(p.id)")
            } else if p.usesNetworkLinkWing {
                IslandController.shared?.prepareNetworkLinkWingNoticeLayout(reason: "present:\(p.id)")
            } else if next.anyUsesNotchWingChrome {
                IslandController.shared?.prepareMeetingWingNoticeLayout(reason: "present:\(p.id)")
            }
        }
    }
}
