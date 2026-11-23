import AppKit
import Combine
import Foundation
import SwiftUI

/// 灵动岛通用瞬时通知：不进小组件库，不可左右滑动。
/// 默认约 3 秒后自动撤回；指针在岛上时不收，离开后再收。
/// 注意：`refresh` 不得再调 `requestDisplay`，否则会与 `applyPage` 形成重入栈溢出。
@MainActor
final class IslandNoticeWidget: IslandWidget {
    private static let defaultDisplayNanoseconds = IslandNoticeAutoDismissPolicy.standardNanoseconds
    private static let hoverPollNanoseconds = IslandNoticeAutoDismissPolicy.pollNanoseconds

    static let manifest = WidgetManifest(
        id: SystemWidgetID.islandNotice,
        displayName: L10n.IslandNotice.widgetName,
        summary: L10n.IslandNotice.widgetSummary,
        source: .builtin,
        kind: .systemTransient,
        supportsPinning: false,
        defaultGridSize: .twoByOne
    )

    private let context: WidgetContext
    private let noticeCenter = IslandNoticeCenter.shared

    var priority: Int = 0
    private(set) var wantsDisplay = false
    private(set) var requestedAt = Date.distantPast
    var title: String { "" }

    private var observers: Set<AnyCancellable> = []
    private var dismissTasks: [String: Task<Void, Never>] = [:]
    private var presenting: IslandNoticePayload?
    /// 设置会话挡住 tip 展开时轮询，关闭后再 expand。
    private var settingsUnblockTask: Task<Void, Never>?

    init(context: WidgetContext) {
        self.context = context
        noticeCenter.$slots
            .receive(on: RunLoop.main)
            .sink { [weak self] slots in
                self?.handleSlots(slots)
            }
            .store(in: &observers)
        handleSlots(noticeCenter.slots)
        context.log("瞬时通知小组件已创建")
    }

    func makeView() -> AnyView {
        // 直接观察中枢：替换提示时不必再 requestDisplay 才能换皮。
        AnyView(IslandNoticeCardView())
    }

    func onAppear() {
        context.log("瞬时通知 onAppear", fields: [
            "hasNotice": presenting != nil,
            "source": presenting?.sourceTag ?? "",
            "dual": noticeCenter.slots.isDual
        ])
    }

    func onDisappear() {
        context.log("瞬时通知 onDisappear")
    }

    /// 仅同步文案；展示争夺只由 `IslandNoticeCenter` 驱动。
    func refresh() {
        presenting = noticeCenter.current
        if noticeCenter.slots.isEmpty, wantsDisplay {
            hide()
        }
    }

    private func handleSlots(_ slots: IslandNoticeSlots) {
        // 清掉已离槽的自动收起任务。
        for id in dismissTasks.keys where !slots.contains(id: id) {
            dismissTasks[id]?.cancel()
            dismissTasks[id] = nil
        }

        // 仅专注满岛：走收起待命翼，不上通知页。
        guard slots.hasNoticePayload else {
            presenting = nil
            if wantsDisplay {
                hide()
            }
            return
        }

        let lead = slots.current!
        presenting = lead
        showThenExpand(payload: lead)

        for payload in [slots.primary, slots.secondary].compactMap({ $0 }) {
            if let nanos = payload.autoDismissNanoseconds {
                if dismissTasks[payload.id] == nil {
                    scheduleAutoDismiss(
                        for: payload.id,
                        nanoseconds: nanos,
                        holdWhileHovering: payload.holdsWhileHovering,
                        expandsDuringSettingsSession: payload.expandsDuringSettingsSession
                    )
                }
            } else {
                AppLog.debug("IslandNotice", "通知保持展示，直至用户操作", [
                    "id": payload.id,
                    "source": payload.sourceTag,
                    "lane": payload.displayLane.rawValue
                ])
            }
        }
    }

    /// 到达时长后撤回；可选：悬停时延后（剪贴板短提示不延后）。
    /// 仅「设置页挡住且未展开」的 tip 延后计时；瞬时 tip 设置中仍展开，按 3s 正常收。
    private func scheduleAutoDismiss(
        for noticeID: String,
        nanoseconds: UInt64,
        holdWhileHovering: Bool,
        expandsDuringSettingsSession: Bool
    ) {
        dismissTasks[noticeID]?.cancel()
        dismissTasks[noticeID] = Task { @MainActor [weak self] in
            guard let self else { return }
            // 会议等被设置挡住、尚未上岛：不计时。瞬时 tip 已上岛则立刻开计时。
            while !Task.isCancelled,
                  IslandNoticeAutoDismissPolicy.shouldWaitForSettingsUnblock(
                    expandsDuringSettingsSession: expandsDuringSettingsSession,
                    settingsBlocksExpand: IslandController.shared?.blocksProgrammaticNoticeExpand == true
                  )
            {
                AppLog.debug("IslandNotice", "设置页挡住展开，延后自动收起计时", ["id": noticeID])
                try? await Task.sleep(nanoseconds: Self.hoverPollNanoseconds)
            }
            guard !Task.isCancelled else { return }
            guard self.noticeCenter.slots.contains(id: noticeID) else { return }

            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            guard self.noticeCenter.slots.contains(id: noticeID) else { return }

            while !Task.isCancelled,
                  IslandNoticeAutoDismissPolicy.shouldWaitForHoverEnd(
                    holdWhileHovering: holdWhileHovering,
                    isHovering: IslandController.shared?.isHoveringIsland == true
                  )
            {
                AppLog.debug("IslandNotice", "指针在岛上，延后自动收起", ["id": noticeID])
                try? await Task.sleep(nanoseconds: Self.hoverPollNanoseconds)
            }
            guard !Task.isCancelled else { return }
            guard self.noticeCenter.slots.contains(id: noticeID) else { return }

            self.finishDismiss(
                noticeID: noticeID,
                reason: "auto",
                displayedNanoseconds: nanoseconds
            )
        }
    }

    private func finishDismiss(
        noticeID: String,
        reason: String,
        displayedNanoseconds: UInt64 = IslandNoticeWidget.defaultDisplayNanoseconds
    ) {
        guard noticeCenter.slots.contains(id: noticeID) else {
            AppLog.warn("IslandNotice", "收起跳过：槽内已无此通知", [
                "old": noticeID,
                "primary": noticeCenter.slots.primary?.id ?? "",
                "secondary": noticeCenter.slots.secondary?.id ?? ""
            ])
            return
        }
        // 一律按 tip id 撤槽。进程结束勿再经 `dismissWatchEnded()`：
        // 控制台 `lastWatchEnded` 若仍是旧 id（或测试台从未写入），会撤错条，岛上 tip 永不消。
        let payload: IslandNoticePayload? = {
            if noticeCenter.slots.primary?.id == noticeID { return noticeCenter.slots.primary }
            if noticeCenter.slots.secondary?.id == noticeID { return noticeCenter.slots.secondary }
            return nil
        }()
        noticeCenter.dismiss(id: noticeID)
        var syncedWatchEnded = false
        if case .processEnded(let notice)? = payload, notice.id == noticeID {
            ProjectReleaseSession.shared.clearWatchEndedIfMatching(id: noticeID)
            syncedWatchEnded = true
        }
        dismissTasks[noticeID]?.cancel()
        dismissTasks[noticeID] = nil
        // 双槽时只撤一条，另一条仍在则保持上岛。
        if noticeCenter.slots.isEmpty {
            hide()
        } else {
            presenting = noticeCenter.current
        }
        AppLog.warn("IslandNotice", "瞬时通知已收起", [
            "id": noticeID,
            "reason": reason,
            "ms": Int(displayedNanoseconds / 1_000_000),
            "processEndedSync": syncedWatchEnded,
            "remainPrimary": noticeCenter.slots.primary?.id ?? "",
            "remainSecondary": noticeCenter.slots.secondary?.id ?? ""
        ])
    }

    /// 先 requestDisplay 切到通知页，再 expand，避免先展开货架/控制台。
    private func showThenExpand(payload: IslandNoticePayload) {
        let alreadyShowing = wantsDisplay
        if !wantsDisplay {
            wantsDisplay = true
            requestedAt = Date()
        }
        Task { @MainActor [weak self] in
            guard let self, self.wantsDisplay else { return }
            // 仅小组件设计 sticky 挡无自动收 tip；其它设置页走正式程序 expand。
            // 约 3s 瞬时 tip（RAM 等）：设计 sticky 中也立刻 expand，与悬停无关。
            if IslandController.shared?.blocksProgrammaticNoticeExpand == true,
               !payload.expandsDuringSettingsSession
            {
                AppLog.warn("IslandNotice", "设计 sticky 中，通知仅入槽不展开，待离开设计页后再展示", [
                    "id": payload.id,
                    "source": payload.sourceTag
                ])
                self.context.requestDisplay()
                self.ensureExpandAfterSettingsUnblock()
                return
            }
            if IslandController.shared?.blocksProgrammaticNoticeExpand == true {
                AppLog.warn("IslandNotice", "设置会话中仍展开瞬时 tip", [
                    "id": payload.id,
                    "source": payload.sourceTag
                ])
            }
            // 与会议一致：延后一拍避开 applyPage 同步重入；但 expand 必须在切页之后。
            // 替换（尤其上一短条→「已复制」）依赖 expand 内 allowPanelShrink，否则尺寸卡死看不见。
            self.context.requestDisplay()
            IslandController.shared?.expand(
                reason: alreadyShowing ? "islandNoticeReplace" : "islandNotice"
            )
            AppLog.warn("IslandNotice", alreadyShowing ? "瞬时通知已替换" : "瞬时通知已上岛", [
                "id": payload.id,
                "source": payload.sourceTag,
                "replaced": alreadyShowing
            ])
        }
    }

    /// 设置会话结束后，把仍在槽内的瞬时通知真正展开到岛上。
    private func ensureExpandAfterSettingsUnblock() {
        guard settingsUnblockTask == nil else { return }
        settingsUnblockTask = Task { @MainActor [weak self] in
            defer { self?.settingsUnblockTask = nil }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.hoverPollNanoseconds)
                guard let self else { return }
                if IslandController.shared?.blocksProgrammaticNoticeExpand == true {
                    continue
                }
                guard self.wantsDisplay, let lead = self.noticeCenter.current else { return }
                AppLog.warn("IslandNotice", "设置已关闭，补展开被挡住的瞬时通知", [
                    "id": lead.id,
                    "source": lead.sourceTag
                ])
                self.showThenExpand(payload: lead)
                return
            }
        }
    }

    private func hide() {
        wantsDisplay = false
        settingsUnblockTask?.cancel()
        settingsUnblockTask = nil
        for (_, task) in dismissTasks {
            task.cancel()
        }
        dismissTasks.removeAll()
        context.withdrawDisplay()
        // 通知是程序主动 expand 的；指针不在岛上时悬停轮询不会 scheduleCollapse
        //（over 与 isPointerOverIsland 同为 false），必须显式收岛，否则会闪一下空态/其它页。
        let hovering = IslandController.shared?.isHoveringIsland == true
        // allowsHoverExpand 在「仍是瞬时通知页 / current 未清」时也会 true；
        // 若照单保展开，免打扰后悬停会留下空双翼岛。仅通知真正撤干净且仍有面板/实况才保。
        let noticeGone = IslandNoticeEndCollapsePolicy.isNoticeFullyGone(
            current: IslandNoticeCenter.shared.current,
            isTransientNoticePage: WidgetRuntime.shared.isTransientNoticePage
        )
        let keepExpanded = IslandNoticeEndCollapsePolicy.shouldKeepExpandedAfterNoticeEnd(
            hovering: hovering,
            noticeFullyGone: noticeGone,
            allowsHoverExpand: WidgetRuntime.shared.allowsHoverExpand
        )
        if !keepExpanded {
            IslandController.shared?.collapse(reason: "islandNoticeEnd")
            AppLog.info("IslandNotice", "通知结束已收起灵动岛", [
                "hovering": hovering,
                "noticeGone": noticeGone,
                "allowHover": WidgetRuntime.shared.allowsHoverExpand,
                "transientPage": WidgetRuntime.shared.isTransientNoticePage
            ])
        } else {
            AppLog.debug("IslandNotice", "通知结束但面板仍在且悬停，保持展开")
        }
    }
}

// MARK: - View

private struct IslandNoticeCardView: View {
    @ObservedObject private var noticeCenter = IslandNoticeCenter.shared
    @ObservedObject private var focusTimer = FocusTimerSession.shared

    var body: some View {
        switch noticeCenter.slots.resolvedLayout {
        case .empty, .fullFocus, .fullMedia:
            // 仅专注 / 仅音乐：收起翼由 IslandBody 画，不上通知页内容。
            Color.clear.frame(width: 1, height: 1)
        case .fullNotice(let payload):
            noticeBody(payload, compact: false)
        case .dual(let left, let right):
            // 贴刘海：左翼 | 刘海空隙 | 右翼；高=刘海。已复制仍用 Ø32，勿再包黑框。
            let rightOrb = noticeCenter.slots.usesDualFlushWithRightOrb
            IslandDualNotchWingRow(rightIsOrb: rightOrb) {
                sideView(left, flushSide: .leading)
            } right: {
                sideView(right, flushSide: .trailing)
            }
        }
    }

    @ViewBuilder
    private func sideView(
        _ side: IslandNoticeLayoutSide,
        flushSide: IslandFlushWingStyle.Side
    ) -> some View {
        switch side {
        case .notice(let payload):
            // 真岛双槽：一律 bare（壳层黑底），对齐音乐左翼标准。
            noticeBody(payload, flushSide: flushSide, bareWingContent: true)
        case .focus:
            FocusTimerStandbyView(
                snapshot: focusTimer.snapshot,
                flushSide: flushSide,
                bareWingContent: true
            )
        case .media:
            if let snap = NowPlayingService.shared.snapshot {
                MediaCompactStandbyView(
                    title: snap.title,
                    artwork: snap.artwork,
                    elapsedText: MediaCompactStandbyView.formatElapsed(snap.elapsed),
                    isPlaying: snap.isPlaying,
                    flushSide: flushSide,
                    bareWingContent: true
                )
            }
        }
    }

    @ViewBuilder
    private func noticeBody(
        _ payload: IslandNoticePayload,
        compact: Bool = false,
        flushSide: IslandFlushWingStyle.Side? = nil,
        bareWingContent: Bool = false
    ) -> some View {
        switch payload {
        case .processEnded(let notice):
            ProcessEndedNoticeCard(
                notice: notice,
                flushSide: flushSide,
                bareWingContent: bareWingContent
            )
        case .ramPressure(let notice):
            RAMPressureNoticeCard(
                notice: notice,
                flushSide: flushSide,
                bareWingContent: bareWingContent
            )
        case .peripheralLowBattery(let notice):
            PeripheralBatteryNoticeCard(
                notice: notice,
                style: .low,
                flushSide: flushSide,
                bareWingContent: bareWingContent
            )
        case .peripheralFullCharge(let notice):
            PeripheralBatteryNoticeCard(
                notice: notice,
                style: .full,
                flushSide: flushSide,
                bareWingContent: bareWingContent
            )
        case .peripheralConnected(let notice):
            PeripheralBatteryNoticeCard(
                notice: notice,
                style: .connect,
                flushSide: flushSide,
                bareWingContent: bareWingContent
            )
        case .macBatteryCharging(let notice),
             .macBatteryLow(let notice),
             .macBatteryFull(let notice),
             .macBatteryUnplugged(let notice):
            MacBatteryNoticeCard(
                notice: notice,
                flushSide: flushSide,
                bareWingContent: bareWingContent
            )
        case .clipboardCaptureHint(let id, let text, let symbol):
            if id.hasPrefix("copy.") {
                // 单独 / 双槽右侧一律现有 Ø32 圆岛；双槽时不要外包 Spacer 黑翼。
                ClipboardCopiedIslandView(detail: text, animationToken: id)
            } else {
                ClipboardCaptureHintNoticeCard(text: text, symbol: symbol)
            }
        case .colorPickTip:
            ColorPickTipIslandView()
        case .ocrSelectTip:
            OCRSelectTipIslandView()
        case .aiUsageAlert(_, let providerName, let remainingPercent, let stage, let resetsAt):
            AIUsageIslandCardView(
                providerName: providerName,
                remainingPercent: remainingPercent,
                stage: stage,
                resetsAt: resetsAt,
                errorMessage: nil,
                compact: compact,
                flushSide: flushSide,
                bareWingContent: bareWingContent
            )
        case .moveReminder(let notice):
            MoveReminderNoticeCard(
                notice: notice,
                compact: compact,
                flushSide: flushSide,
                bareWingContent: bareWingContent
            )
        case .meetingLead:
            MeetingLeadNoticeCard(flushSide: flushSide, bareWingContent: bareWingContent)
        }
    }
}

/// 会前提示卡：矮胶囊；入会后由会话撤提示。
private struct MeetingLeadNoticeCard: View {
    @ObservedObject private var lead = MeetingLeadSession.shared
    var flushSide: IslandFlushWingStyle.Side? = nil
    var bareWingContent: Bool = false

    var body: some View {
        if let snap = lead.snapshot {
            MeetingIslandCardView(
                title: snap.title,
                secondsToStart: snap.secondsToStart,
                showJoin: snap.showJoin,
                showAuth: snap.showAuth,
                flushSide: flushSide,
                bareWingContent: bareWingContent,
                onJoin: { MeetingLeadSession.shared.joinFromNotice() },
                onRequestAuth: { MeetingLeadSession.shared.requestAuthFromNotice() }
            )
        } else {
            Color.clear.frame(width: 1, height: 1)
        }
    }
}

private struct ClipboardCaptureHintNoticeCard: View {
    let text: String
    var symbol: String = "eyedropper"

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Text(text)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 420, alignment: .leading)
    }
}

/// 外设低电 / 满电 / 接入：左右翼贴刘海（同会议）；约 3s 自动收，可点进电量实况。
/// 壳层 `usesNotchWingChrome`；根视图禁止外圈 padding；名称旁不展示 detail / 0x 代码。
struct PeripheralBatteryNoticeCard: View {
    enum Style {
        case low
        case full
        case connect
    }

    let notice: BatteryPeripheralNotice
    let style: Style
    var compact: Bool = false
    var flushSide: IslandFlushWingStyle.Side? = nil
    /// 真岛双槽：只画内容，不套黑胶囊（壳层已铺 flush 黑底）。
    var bareWingContent: Bool = false
    var previewNotchWidth: CGFloat = 110

    @Environment(\.islandNotchWidth) private var envNotchWidth
    @Environment(\.islandNotchHeight) private var envNotchHeight

    private var notchWidth: CGFloat {
        compact ? previewNotchWidth : max(envNotchWidth, 110)
    }

    private var barHeight: CGFloat {
        if flushSide != nil { return IslandFlushWingStyle.height }
        if compact { return 30 }
        return max(envNotchHeight, 32)
    }

    /// 与 `IslandChrome.preparedPeripheralWingWidth` 对齐；设置样张略收。
    private var wingWidth: CGFloat {
        compact ? 70 : IslandChrome.preparedPeripheralWingWidth
    }

    private var totalWidth: CGFloat { wingWidth * 2 + notchWidth }

    private let deviceIconSide: CGFloat = 15
    private let leftClusterSpacing: CGFloat = IslandFlushWingStyle.iconLabelSpacing

    private var displayName: String {
        Self.cleanedDeviceName(notice.deviceName)
    }

    private var accessibilityStatus: String {
        switch style {
        case .low:
            return L10n.Battery.tipLowAccessibility(notice.percent ?? 0)
        case .full:
            return L10n.Battery.tipFullAccessibility(notice.percent ?? 100)
        case .connect:
            if let pct = notice.percent {
                return "\(L10n.PeripheralTip.connectBadge)，\(L10n.Battery.tipPercentBadge(pct))"
            }
            return L10n.PeripheralTip.connectBadge
        }
    }

    /// 仅双槽半块色。
    private var flushTint: Color {
        switch style {
        case .low:
            let pct = notice.percent ?? 0
            return (pct <= 5 ? IslandFlushWingStyle.Severity.danger : .warning).accent
        case .full: return IslandFlushWingStyle.accentSuccess
        case .connect: return IslandFlushWingStyle.accentInfoSolid
        }
    }

    /// 设置 / 图鉴样张。`flushSide` 非 nil 时只出半岛自身半翼（带黑胶囊），不叠满岛边距。
    static func previewSample(
        style: Style,
        threshold: Int = 15,
        compact: Bool = true,
        flushSide: IslandFlushWingStyle.Side? = nil
    ) -> some View {
        let notice: BatteryPeripheralNotice
        switch style {
        case .low:
            notice = BatteryPeripheralNotice(
                id: "preview.low",
                deviceID: "preview.mouse",
                deviceName: L10n.Battery.tipSampleMouse,
                kind: .mouse,
                percent: 12,
                threshold: threshold,
                detail: L10n.Battery.lowNoticeDetail(12, threshold)
            )
        case .full:
            notice = BatteryPeripheralNotice(
                id: "preview.full",
                deviceID: "preview.keyboard",
                deviceName: L10n.Battery.tipSampleKeyboard,
                kind: .keyboard,
                percent: 100,
                threshold: 100,
                detail: L10n.Battery.fullNoticeDetail
            )
        case .connect:
            notice = BatteryPeripheralNotice(
                id: "preview.connect",
                deviceID: "preview.headphones",
                deviceName: L10n.PeripheralTip.tipSampleHeadphones,
                kind: .headphones,
                percent: 86,
                threshold: 0,
                detail: L10n.PeripheralTip.connectNoticeDetail
            )
        }
        let card = PeripheralBatteryNoticeCard(
            notice: notice,
            style: style,
            compact: true,
            flushSide: flushSide
        )
        if flushSide != nil {
            return AnyView(card)
        }
        return AnyView(
            card
                .padding(.horizontal, IslandChrome.contentHorizontal)
                .padding(.bottom, IslandChrome.compactTipBottom)
                .frame(minHeight: compact ? 34 : 40)
        )
    }

    var body: some View {
        Group {
            if let flushSide {
                flushCapsule(side: flushSide)
            } else {
                fullWingBody
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { openBatteryLive(reason: "\(style)NoticeTap") }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(displayName)，\(accessibilityStatus)")
    }

    private var fullWingBody: some View {
        // 左右翼必须各占满 wingWidth：右翼若只 fixedSize，子宽 < totalWidth，
        // 外层 .frame 会居中整条 → 左右外缘空一大截（用户「边距这么大」）。
        // 外缘只靠壳层 `notchWingTip` horizontal；卡根禁止再叠 padding。
        HStack(spacing: 0) {
            leftCluster
                .frame(width: wingWidth, alignment: .leading)
                .clipped()
            Color.clear
                .frame(width: notchWidth)
                .accessibilityHidden(true)
            rightCluster
                .frame(width: wingWidth, alignment: .trailing)
                .clipped()
        }
        .frame(width: totalWidth, height: barHeight)
        .clipped()
    }

    /// 半岛：左簇设备图标+电量%/「已连接」；右侧状态环与满岛同款（接入蓝弧 / 满电绿闪 / 低电红弧）。
    private func flushCapsule(side: IslandFlushWingStyle.Side) -> some View {
        let pct = notice.percent ?? (style == .full ? 100 : nil)
        let tint = flushTint
        let primaryLabel = pct.map(L10n.Battery.tipPercentBadge) ?? L10n.PeripheralTip.connectBadge
        let row = HStack(spacing: 0) {
            HStack(spacing: IslandFlushWingStyle.iconLabelSpacing) {
                // 半岛左侧设备图标一律白；色只留给右侧电量环。
                Image(systemName: notice.kind.systemSymbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.95))
                Text(primaryLabel)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: IslandFlushWingStyle.bareContentSpacerMin)
            PeripheralBatteryStatusGlyph(
                style: style,
                percent: pct,
                size: 16
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if bareWingContent {
            return AnyView(row.islandBareFlushWingContent())
        }
        return AnyView(IslandFlushWingCapsule(side: side) { row })
    }

    /// 左翼：设备图标 + 名称；展不开则横向轮播（同音乐歌名）。
    private var leftCluster: some View {
        // 翼内可用宽 = 翼宽 − 图标 − 间距（外缘 inset 只在壳层，勿再扣）。
        let titleBudget = max(0, wingWidth - deviceIconSide - leftClusterSpacing)
        return HStack(spacing: leftClusterSpacing) {
            Image(systemName: notice.kind.systemSymbol)
                .font(.system(size: compact ? 14 : 15, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.95))
                .frame(width: deviceIconSide, alignment: .center)
                .layoutPriority(1)

            IslandCompactTitleMarquee(
                text: displayName,
                animated: true,
                visibleWidth: titleBudget,
                fontSize: compact ? 12 : 13,
                fontWeight: .medium,
                logTag: "IslandNotice"
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 右翼：电量% + 状态环（接入蓝弧 / 满电绿闪 / 低电红弧；按实际电量画弧）。
    @ViewBuilder
    private var rightCluster: some View {
        HStack(spacing: 6) {
            if let pct = rightWingPercent {
                Text(L10n.Battery.tipPercentBadge(pct))
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundStyle(Color.white.opacity(0.90))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            PeripheralBatteryStatusGlyph(
                style: style,
                percent: rightWingPercent,
                size: 18
            )
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// 满电默认 100；低电用通知值；接入仅在读得到时显示。
    private var rightWingPercent: Int? {
        switch style {
        case .full:
            return notice.percent ?? 100
        case .low:
            return notice.percent
        case .connect:
            return notice.percent
        }
    }

    private func openBatteryLive(reason: String) {
        guard ControlDeckSettings.shared.isModuleEnabled("battery") else { return }
        AppLog.info("IslandNotice", "电量提示点进实况", [
            "reason": reason,
            "device": notice.deviceID,
            "style": "\(style)"
        ])
        IslandNoticeCenter.shared.dismiss(id: notice.id)
        LiveIslandGate.shared.open(LiveIslandGate.batteryID, reason: reason)
    }

    /// 去掉名称尾部 `0x…` / `(0x…)` 一类产品代码。
    static func cleanedDeviceName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(
            pattern: #"\s*\(?0[xX][0-9A-Fa-f]+\)?\s*$"#
        ) else { return trimmed }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        return regex.stringByReplacingMatches(in: trimmed, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// 外设 / 本机电池 tip 状态环（满岛右翼 / 半岛右侧共用）。
/// 满电：整环绿 + 闪电（固定）；接入/充电蓝弧 / 低电红弧：按实际电量画进度。
struct PeripheralBatteryStatusGlyph: View {
    let style: PeripheralBatteryNoticeCard.Style
    /// 接入 / 低电按此画弧；满电忽略。
    var percent: Int? = nil
    var size: CGFloat = 20

    /// 满电绿（HTML secondary-fixed-dim ≈ #53e16f）。
    private var fullAccent: Color {
        Color(.sRGB, red: 0.325, green: 0.882, blue: 0.435, opacity: 1)
    }
    /// 接入蓝（primary-container ≈ #0070eb）。
    private var connectAccent: Color {
        IslandFlushWingStyle.accentInfoSolid
    }
    /// 低电红（error ≈ #FF3B30 族）。
    private var lowAccent: Color {
        IslandFlushWingStyle.accentDanger
    }

    private var ringDiameter: CGFloat { size * 0.9 }
    private var ringLine: CGFloat { max(2, size * 0.125) }

    private var accent: Color {
        switch style {
        case .full: return fullAccent
        case .connect: return connectAccent
        case .low: return lowAccent
        }
    }

    private var trackColor: Color {
        switch style {
        case .full: return .clear
        case .connect: return Color.white.opacity(0.14)
        case .low: return Color.white.opacity(0.20)
        }
    }

    /// 0…1；满电恒 1；无读数时接入画空轨、低电至少可见一小段。
    private var progress: CGFloat {
        switch style {
        case .full:
            return 1
        case .connect:
            guard let percent else { return 0 }
            return min(max(CGFloat(percent) / 100, 0), 1)
        case .low:
            let raw = percent ?? 12
            return min(max(CGFloat(raw) / 100, 0.04), 1)
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(trackColor, lineWidth: ringLine)
                .frame(width: ringDiameter, height: ringDiameter)

            if style == .full {
                Circle()
                    .stroke(fullAccent, lineWidth: ringLine)
                    .frame(width: ringDiameter, height: ringDiameter)
                Image(systemName: "bolt.fill")
                    .font(.system(size: max(8, size * 0.5), weight: .bold))
                    .foregroundStyle(Color.white)
            } else if progress > 0 {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        accent,
                        style: StrokeStyle(lineWidth: ringLine, lineCap: .round)
                    )
                    .frame(width: ringDiameter, height: ringDiameter)
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// RAM 高压 tip：单独紧凑双翼贴刘海——左 `● 96% RAM`，右 App 名+内存（无图标）；悬停右翼切免打扰+管理。
/// 与 B/专注并排 = 右翼半块。程序 expand + 约 3s。禁止一键杀进程。根视图禁止外圈 padding。
struct RAMPressureNoticeCard: View {
    let notice: ResourceRAMPressureNotice
    var flushSide: IslandFlushWingStyle.Side? = nil
    var bareWingContent: Bool = false

    #if DEBUG
    /// 测试台样式图鉴假数据。`flushSide` 时只出半岛自身半翼。
    static func previewSample(
        compact: Bool = true,
        flushSide: IslandFlushWingStyle.Side? = nil
    ) -> some View {
        _ = compact
        let card = RAMPressureNoticeCard(
            notice: ResourceRAMPressureNotice(
                id: "preview.ram",
                ramUsedBytes: 28_000_000_000,
                ramPercent: 96,
                topAppName: "Xcode",
                topAppBundleID: "com.apple.dt.Xcode",
                topAppMemoryBytes: 4_200_000_000
            ),
            flushSide: flushSide,
            bareWingContent: flushSide != nil
        )
        if let flushSide {
            return AnyView(
                IslandFlushWingCapsule(side: flushSide, width: IslandChrome.dualFlushCompactWingWidth) {
                    card
                }
            )
        }
        return AnyView(card)
    }
    #endif

    @State private var localHover = false

    private let accentRed = IslandFlushWingStyle.accentDanger
    private let muteWell = Color.white.opacity(0.14)
    private let compactWing = IslandChrome.dualFlushCompactWingWidth

    /// 仅本 tip 的 SwiftUI hover；勿跟 `isHoveringIsland`（常驻展开会粘住不复原）。
    private var showsActions: Bool { localHover }

    private var topAppName: String {
        let raw = notice.topAppName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return L10n.ResourceMonitor.unknownApp }
        return raw
    }

    private var topAppMemoryLabel: String {
        L10n.ResourceMonitor.tipMemory(notice.topAppMemoryBytes)
    }

    var body: some View {
        Group {
            if flushSide != nil {
                // 与 B/专注并排：本翼半块（右侧）。
                halfWingBody
            } else {
                // 单独：紧凑左右双翼贴刘海。
                IslandDualNotchWingRow(wingWidth: compactWing) {
                    leftWingIdle
                } right: {
                    rightWingBody
                }
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            if localHover != hovering {
                localHover = hovering
                AppLog.debug("IslandNotice", "RAM tip 悬停", ["hover": hovering])
            }
        }
        .animation(.easeOut(duration: 0.18), value: showsActions)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            L10n.ResourceMonitor.noticeTitle(notice.ramUsedBytes)
        )
    }

    private var leftWingIdle: some View {
        idleRAMRow
            .islandBareFlushWingContent()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(showsActions ? 0.35 : 1)
    }

    /// 右翼：idle App 名 + 内存 ↔ 悬停免打扰 + 管理。
    private var rightWingBody: some View {
        ZStack {
            topAppRow
                .opacity(showsActions ? 0 : 1)
                .scaleEffect(showsActions ? 0.95 : 1)
                .allowsHitTesting(!showsActions)
            hoverActionsRow
                .opacity(showsActions ? 1 : 0)
                .scaleEffect(showsActions ? 1 : 0.95)
                .allowsHitTesting(showsActions)
        }
        .islandBareFlushWingContent()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 半块内容：idle 用量 ↔ 悬停双按钮。
    private var halfWingBody: some View {
        ZStack {
            idleRAMRow
                .opacity(showsActions ? 0 : 1)
                .scaleEffect(showsActions ? 0.95 : 1)
                .allowsHitTesting(!showsActions)
            hoverActionsRow
                .opacity(showsActions ? 1 : 0)
                .scaleEffect(showsActions ? 1 : 0.95)
                .allowsHitTesting(showsActions)
        }
        .islandBareFlushWingContent()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var idleRAMRow: some View {
        HStack(spacing: 0) {
            // 红点紧贴百分比；「RAM」仍靠右。
            HStack(spacing: 5) {
                Circle()
                    .fill(accentRed)
                    .frame(width: 7, height: 7)
                Text(L10n.ResourceMonitor.tipPercent(notice.ramPercent))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: IslandFlushWingStyle.bareContentSpacerMin)
            Text(L10n.ResourceMonitor.ramTipLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.45))
                .lineLimit(1)
        }
    }

    /// 右翼 idle：名称靠左、用量靠右；无 App 图标。
    private var topAppRow: some View {
        HStack(spacing: 0) {
            Text(topAppName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: IslandFlushWingStyle.bareContentSpacerMin)
            Text(topAppMemoryLabel)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.55))
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    private var hoverActionsRow: some View {
        HStack(spacing: 8) {
            muteButton
            manageButton
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    /// 浮层岛上 SwiftUI Button 易点不中；与会议半块一样用 onTapGesture。
    private var muteButton: some View {
        Image(systemName: "bell.slash")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(muteWell)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                AppLog.info("IslandNotice", "RAM 通知：免打扰 30 分钟", ["id": notice.id])
                ResourceMonitorSession.shared.muteAlerts30m()
                // muteAlerts30m 会撤 tip；此处再强制收岛，避免悬停保展开留下空翼。
                IslandController.shared?.collapse(reason: "ramMute")
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(L10n.ResourceMonitor.muteTip)
    }

    private var manageButton: some View {
        HStack(spacing: 4) {
            Text(L10n.ResourceMonitor.manageTip)
                .font(.system(size: 12, weight: .bold))
            Image(systemName: "list.bullet")
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule(style: .continuous).fill(Color.white))
        .contentShape(Capsule(style: .continuous))
        .onTapGesture {
            AppLog.info("IslandNotice", "RAM 通知：打开进程树设置页", ["id": notice.id])
            IslandNoticeCenter.shared.dismiss(id: notice.id)
            IslandController.shared?.collapse(reason: "ramManage")
            SettingsNavigator.shared.open(.resourceMonitor)
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(L10n.ResourceMonitor.manageTip)
    }
}

/// 进程监视结束 tip（C）：稿「Sequoia 双翼」——左 `>_`+短名+状态点，右 exit 徽标+耗时。
/// 单独上岛左右 flush；与 B/专注并排时只占右翼。根视图禁止外圈 padding。
struct ProcessEndedNoticeCard: View {
    let notice: ProjectWatchEndedNotice?
    var flushSide: IslandFlushWingStyle.Side? = nil
    var bareWingContent: Bool = false

    #if DEBUG
    /// 测试台样式图鉴假数据。`flushSide` 时只出半岛自身半翼。
    static func previewSample(
        outcome: ProjectWatchOutcome,
        compact: Bool = true,
        flushSide: IslandFlushWingStyle.Side? = nil
    ) -> some View {
        _ = compact
        let (message, codeHint): (String, String) = {
            switch outcome {
            case .succeeded: return (L10n.TestLab.processEndedSuccess, "ok")
            case .failed: return (L10n.TestLab.processEndedFailure, "fail")
            case .signaled: return (L10n.TestLab.processEndedFailure, "sig")
            case .unknown: return (L10n.TestLab.processEndedFailure, "unk")
            }
        }()
        let card = ProcessEndedNoticeCard(
            notice: ProjectWatchEndedNotice(
                id: "preview.process.\(codeHint)",
                projectName: "Ridge Lab",
                label: "dev server",
                message: message,
                endedAt: Date(),
                outcome: outcome,
                logPath: nil,
                peakMemoryBytes: 120_000_000,
                durationSeconds: 42
            ),
            flushSide: flushSide,
            bareWingContent: flushSide != nil
        )
        if let flushSide {
            return AnyView(
                IslandFlushWingCapsule(side: flushSide, width: IslandChrome.dualFlushCompactWingWidth) {
                    card
                }
            )
        }
        return AnyView(card)
    }
    #endif

    private var outcome: ProjectWatchOutcome {
        notice?.outcome ?? .unknown
    }

    private var canOpenLog: Bool {
        guard let path = notice?.logPath, !path.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    var body: some View {
        Group {
            if flushSide != nil {
                trailingWingBody
            } else if notice == nil {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityHidden(true)
            } else {
                IslandDualNotchWingRow(wingWidth: IslandChrome.dualFlushCompactWingWidth) {
                    leadingWingBody
                } right: {
                    trailingWingBody
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard canOpenLog else { return }
            AppLog.info("IslandNotice", "进程结束 tip 点击查看日志", [
                "path": (notice?.logPath as NSString?)?.lastPathComponent ?? ""
            ])
            ProjectReleaseSession.shared.openEndedWatchLogs()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            notice.map(L10n.IslandNotice.accessibilityLabel)
                ?? L10n.IslandNotice.headline(for: outcome)
        )
        .accessibilityHint(canOpenLog ? L10n.Projects.viewLog : "")
    }

    /// 左翼：`>_` 与进程名紧贴靠左，状态点靠右。
    private var leadingWingBody: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(">_")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent)
                Text(shortLabel)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 4)
            Circle()
                .fill(accent)
                .frame(width: 6, height: 6)
        }
        .islandBareFlushWingContent()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 右翼：exit 徽标与耗时紧挨，不再拉开。
    private var trailingWingBody: some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                exitBadge
                if let duration = tipDurationText {
                    Text(duration)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(durationColor)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            Spacer(minLength: 0)
        }
        .islandBareFlushWingContent()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var exitBadge: some View {
        Text(L10n.Projects.exitTag(outcome))
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(accent)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(tagBackground)
            )
            .fixedSize()
    }

    /// 翼宽紧：取 label 末段首词（`dev server` → `dev`）。
    private var shortLabel: String {
        let raw = (notice?.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            return notice?.projectName ?? "…"
        }
        let base = (raw as NSString).lastPathComponent
        if let space = base.firstIndex(of: " ") {
            return String(base[..<space])
        }
        return base
    }

    private var tipDurationText: String? {
        guard let notice, notice.durationSeconds > 0 else { return nil }
        return L10n.Projects.tipDuration(notice.durationSeconds)
    }

    private var accent: Color {
        switch outcome {
        case .succeeded: return IslandFlushWingStyle.accentSuccess
        case .failed: return IslandFlushWingStyle.accentDanger
        case .signaled: return IslandFlushWingStyle.accentWarning
        case .unknown: return Color.white.opacity(0.55)
        }
    }

    private var tagBackground: Color {
        switch outcome {
        case .succeeded: return Color(red: 0.02, green: 0.14, blue: 0.08)
        case .failed: return Color(red: 0.22, green: 0.04, blue: 0.05)
        case .signaled: return Color(red: 0.20, green: 0.12, blue: 0.02)
        case .unknown: return Color.white.opacity(0.10)
        }
    }

    private var durationColor: Color {
        switch outcome {
        case .failed: return Color(red: 1.0, green: 0.75, blue: 0.72)
        default: return Color.white.opacity(0.60)
        }
    }
}
