import AppKit
import Combine
import Foundation
import SwiftUI

/// 灵动岛通用瞬时通知：不进小组件库，不可左右滑动。
/// 默认约 3 秒后自动撤回；指针在岛上时不收，离开后再收。
/// 注意：`refresh` 不得再调 `requestDisplay`，否则会与 `applyPage` 形成重入栈溢出。
@MainActor
final class IslandNoticeWidget: IslandWidget {
    private static let defaultDisplayNanoseconds: UInt64 = 3_000_000_000
    private static let hoverPollNanoseconds: UInt64 = 100_000_000

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
                        holdWhileHovering: payload.holdsWhileHovering
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
    private func scheduleAutoDismiss(
        for noticeID: String,
        nanoseconds: UInt64,
        holdWhileHovering: Bool
    ) {
        dismissTasks[noticeID]?.cancel()
        dismissTasks[noticeID] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled, let self else { return }
            guard self.noticeCenter.slots.contains(id: noticeID) else { return }

            if holdWhileHovering {
                while !Task.isCancelled, IslandController.shared?.isHoveringIsland == true {
                    AppLog.debug("IslandNotice", "指针在岛上，延后自动收起", ["id": noticeID])
                    try? await Task.sleep(nanoseconds: Self.hoverPollNanoseconds)
                }
                guard !Task.isCancelled else { return }
                guard self.noticeCenter.slots.contains(id: noticeID) else { return }
            }

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
        let payload = noticeCenter.slots.primary?.id == noticeID
            ? noticeCenter.slots.primary
            : noticeCenter.slots.secondary
        if case .processEnded(let notice) = payload, notice.id == noticeID {
            ProjectReleaseSession.shared.dismissWatchEnded()
        } else {
            noticeCenter.dismiss(id: noticeID)
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
            // 设置设计页真岛保持收起：切页+expand 会与 pointerOverSettings 互殴连震。
            if IslandController.shared?.blocksProgrammaticNoticeExpand == true {
                AppLog.warn("IslandNotice", "设置设计页中，通知仅入槽不展开", [
                    "id": payload.id,
                    "source": payload.sourceTag
                ])
                return
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

    private func hide() {
        wantsDisplay = false
        for (_, task) in dismissTasks {
            task.cancel()
        }
        dismissTasks.removeAll()
        context.withdrawDisplay()
        // 通知是程序主动 expand 的；指针不在岛上时悬停轮询不会 scheduleCollapse
        //（over 与 isPointerOverIsland 同为 false），必须显式收岛，否则会闪一下空态/其它页。
        let hovering = IslandController.shared?.isHoveringIsland == true
        // 通知结束后若岛上已无面板/已点进实况，即使仍悬停也收起，避免空岛挂着。
        let keepExpanded = hovering && WidgetRuntime.shared.allowsHoverExpand
        if !keepExpanded {
            IslandController.shared?.collapse(reason: "islandNoticeEnd")
            AppLog.info("IslandNotice", "通知结束已收起灵动岛", [
                "hovering": hovering,
                "allowHover": WidgetRuntime.shared.allowsHoverExpand
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
            ProcessEndedNoticeCard(notice: nil)
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
            ProcessEndedNoticeCard(notice: notice)
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

    private var wingWidth: CGFloat { compact ? 96 : 104 }

    private var totalWidth: CGFloat { wingWidth * 2 + notchWidth }

    private var displayName: String {
        Self.cleanedDeviceName(notice.deviceName)
    }

    private var statusText: String {
        switch style {
        case .low:
            return L10n.Battery.tipLowBadge(notice.percent ?? 0)
        case .full:
            return L10n.Battery.tipFullBadge(notice.percent ?? 100)
        case .connect:
            return L10n.PeripheralTip.connectBadge
        }
    }

    /// 满岛 tip 原色（红/绿/蓝）；半块 flush 另用 `flushTint`。
    private var statusTint: Color {
        switch style {
        case .low: return Color(.sRGB, red: 0.86, green: 0.22, blue: 0.24, opacity: 1)
        case .full: return Color(.sRGB, red: 0.18, green: 0.62, blue: 0.34, opacity: 1)
        case .connect: return Color(.sRGB, red: 0.20, green: 0.48, blue: 0.96, opacity: 1)
        }
    }

    /// 仅双槽半块色；禁止改 `statusTint` 迁就 flush 稿。
    private var flushTint: Color {
        switch style {
        case .low:
            let pct = notice.percent ?? 0
            return (pct <= 5 ? IslandFlushWingStyle.Severity.danger : .warning).accent
        case .full: return IslandFlushWingStyle.accentSuccess
        case .connect: return IslandFlushWingStyle.accentInfoSolid
        }
    }

    private var statusSymbol: String {
        switch style {
        case .low: return "battery.25"
        case .full: return "battery.100"
        case .connect: return "link"
        }
    }

    /// 设置预览样张。
    static func previewSample(style: Style, threshold: Int = 15, compact: Bool = true) -> some View {
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
        return PeripheralBatteryNoticeCard(notice: notice, style: style, compact: true)
            .padding(.horizontal, IslandChrome.contentHorizontal)
            .padding(.bottom, IslandChrome.compactTipBottom)
            .frame(minHeight: compact ? 34 : 40)
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
        .accessibilityLabel("\(displayName)，\(statusText)")
    }

    private var fullWingBody: some View {
        HStack(spacing: 0) {
            leftCluster
                .frame(width: wingWidth + notchWidth * 0.35, alignment: .leading)
            Spacer(minLength: 0)
            statusPill
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(width: totalWidth, height: barHeight)
        .clipped()
    }

    /// 仅双槽半块：外图标 | 电量% | 刘海侧电量条；满岛仍走 `fullWingBody` + `statusTint`。
    private func flushCapsule(side: IslandFlushWingStyle.Side) -> some View {
        let pct = notice.percent ?? (style == .full ? 100 : 0)
        let spacer = bareWingContent
            ? IslandFlushWingStyle.bareContentSpacerMin
            : CGFloat(4)
        let tint = flushTint
        let row = HStack(spacing: 0) {
            Image(systemName: notice.kind.systemSymbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(style == .connect ? Color.white.opacity(0.85) : tint)
            Spacer(minLength: spacer)
            Text("\(pct)%")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.92))
                .monospacedDigit()
                .lineLimit(1)
            Spacer(minLength: spacer)
            flushBatteryBar(percent: pct, tint: tint)
        }
        if bareWingContent {
            return AnyView(row.islandBareFlushWingContent())
        }
        return AnyView(IslandFlushWingCapsule(side: side) { row })
    }

    private func flushBatteryBar(percent: Int, tint: Color) -> some View {
        let fill = min(max(CGFloat(percent) / 100, 0.05), 1)
        return RoundedRectangle(cornerRadius: 2, style: .continuous)
            .strokeBorder(Color.white.opacity(0.50), lineWidth: 1)
            .frame(width: 14, height: 8)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(tint)
                    .padding(1.5)
                    .frame(width: max(14 * fill, 3), height: 8)
            }
    }

    private var leftCluster: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.14))
                Image(systemName: notice.kind.systemSymbol)
                    .font(.system(size: compact ? 10 : 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
            }
            .frame(width: compact ? 18 : 20, height: compact ? 18 : 20)
            .layoutPriority(1)

            Text(displayName)
                .font(.system(size: compact ? 11 : 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var statusPill: some View {
        let connectSoft = style == .connect
        return HStack(spacing: 5) {
            Image(systemName: statusSymbol)
                .font(.system(size: compact ? 9 : 10, weight: .semibold))
            Text(statusText)
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
        }
        // 「已连接」：蓝字 + 浅底描边（旧 tip）；低电/满电仍实心填充。
        .foregroundStyle(connectSoft ? statusTint : Color.white)
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 4 : 5)
        .background(
            Capsule(style: .continuous)
                .fill(connectSoft ? statusTint.opacity(0.14) : statusTint)
                .shadow(color: statusTint.opacity(connectSoft ? 0.45 : 0.45), radius: 6, y: 0)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(connectSoft ? statusTint.opacity(0.75) : Color.clear, lineWidth: 1)
        )
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

/// RAM 高压 tip（C 类半块，靠右）：idle `● 96% RAM`；悬停免打扰 + 释放。
/// 单独上岛只要右翼；与 B/专注并排时走右翼 flush。根视图禁止外圈 padding。
private struct RAMPressureNoticeCard: View {
    let notice: ResourceRAMPressureNotice
    var flushSide: IslandFlushWingStyle.Side? = nil
    var bareWingContent: Bool = false

    @State private var localHover = false

    private let accentRed = IslandFlushWingStyle.accentDanger
    private let muteWell = Color.white.opacity(0.14)

    /// 仅本 tip 的 SwiftUI hover；勿跟 `isHoveringIsland`（常驻展开会粘住不复原）。
    private var showsActions: Bool { localHover }

    var body: some View {
        Group {
            if flushSide != nil {
                // 与 B/专注并排：本翼半块（右侧）。
                halfWingBody
            } else {
                // 单独 C：只要右翼半块，左翼留空。
                IslandDualNotchWingRow {
                    Color.clear
                        .accessibilityHidden(true)
                } right: {
                    halfWingBody
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
            Circle()
                .fill(accentRed)
                .frame(width: 7, height: 7)
            Spacer(minLength: IslandFlushWingStyle.bareContentSpacerMin)
            Text(L10n.ResourceMonitor.tipPercent(notice.ramPercent))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
            Spacer(minLength: IslandFlushWingStyle.bareContentSpacerMin)
            Text(L10n.ResourceMonitor.ramTipLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.45))
                .lineLimit(1)
        }
    }

    private var hoverActionsRow: some View {
        HStack(spacing: 8) {
            muteButton
            purgeButton
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var muteButton: some View {
        Button {
            AppLog.info("IslandNotice", "RAM 通知：免打扰 30 分钟")
            ResourceMonitorSession.shared.muteAlerts30m()
            IslandNoticeCenter.shared.dismiss(id: notice.id)
        } label: {
            Image(systemName: "bell.slash")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(muteWell)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.ResourceMonitor.muteTip)
    }

    private var purgeButton: some View {
        Button {
            AppLog.info("IslandNotice", "RAM 通知：一键释放")
            ResourceMonitorSession.shared.purgeMemory()
            IslandNoticeCenter.shared.dismiss(id: notice.id)
        } label: {
            HStack(spacing: 4) {
                Text(L10n.ResourceMonitor.purgeTip)
                    .font(.system(size: 12, weight: .bold))
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule(style: .continuous).fill(Color.white))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.ResourceMonitor.purgeTip)
    }
}

/// 进程监视结束卡片（`IslandNoticePayload.processEnded`）。
private struct ProcessEndedNoticeCard: View {
    let notice: ProjectWatchEndedNotice?

    private let accentGreen = Color(red: 0.325, green: 0.882, blue: 0.435)
    private let accentGreenSoft = Color(red: 0.325, green: 0.882, blue: 0.435).opacity(0.18)
    private let accentRed = Color(red: 1.0, green: 0.42, blue: 0.38)
    private let accentRedSoft = Color(red: 1.0, green: 0.42, blue: 0.38).opacity(0.18)
    private let accentAmber = Color(red: 1.0, green: 0.72, blue: 0.28)
    private let accentAmberSoft = Color(red: 1.0, green: 0.72, blue: 0.28).opacity(0.18)
    private let accentMuted = Color.white.opacity(0.55)
    private let accentMutedSoft = Color.white.opacity(0.12)

    private var canOpenLog: Bool {
        guard let path = notice?.logPath, !path.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    private static let glyphSize: CGFloat = 28

    var body: some View {
        let outcome = notice?.outcome ?? .unknown
        HStack(alignment: .top, spacing: 10) {
            terminalGlyph(for: outcome)

            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .center, spacing: 8) {
                    titleText

                    if let tag = exitTagText(for: outcome) {
                        Text(tag)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(accent(for: outcome))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(tagBackground(for: outcome))
                            )
                            .fixedSize()
                    }
                }

                if let notice {
                    Text(subtitle(for: notice))
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.40))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if canOpenLog {
                viewLogButton
            }
        }
        .frame(minWidth: 360)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            notice.map(L10n.IslandNotice.accessibilityLabel)
                ?? L10n.IslandNotice.headline(for: outcome)
        )
    }

    private var viewLogButton: some View {
        Button {
            AppLog.info("IslandNotice", "点击查看日志", [
                "path": (notice?.logPath as NSString?)?.lastPathComponent ?? ""
            ])
            ProjectReleaseSession.shared.openEndedWatchLogs()
        } label: {
            HStack(spacing: 4) {
                Text(L10n.Projects.viewLog)
                    .font(.system(size: 10, weight: .semibold))
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Color(nsColor: NSColor(calibratedWhite: 0.18, alpha: 1)))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel(L10n.Projects.viewLog)
    }

    @ViewBuilder
    private var titleText: some View {
        if let notice {
            HStack(spacing: 0) {
                Text("\(notice.projectName) / ")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.45))
                Text(notice.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .lineLimit(1)
        } else {
            Text(L10n.IslandNotice.endedHeadline)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
    }

    private func terminalGlyph(for outcome: ProjectWatchOutcome) -> some View {
        let color = accent(for: outcome)
        let side = Self.glyphSize
        return RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color.white.opacity(0.10))
            .frame(width: side, height: side)
            .overlay(
                Text(">_")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
            )
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(0.35), lineWidth: 1)
                    )
                    .offset(x: 2, y: -2)
            }
            .frame(width: side, height: side, alignment: .top)
    }

    private func exitTagText(for outcome: ProjectWatchOutcome) -> String? {
        switch outcome {
        case .succeeded, .failed:
            return L10n.Projects.exitTag(outcome)
        case .signaled, .unknown:
            return nil
        }
    }

    private func subtitle(for notice: ProjectWatchEndedNotice) -> String {
        var parts: [String] = []
        if notice.durationSeconds > 0 {
            parts.append(L10n.Projects.durationText(notice.durationSeconds))
        }
        if notice.peakMemoryBytes > 0 {
            parts.append(L10n.Projects.memoryUsed(notice.peakMemoryBytes))
        }
        if parts.isEmpty {
            return L10n.Projects.outcomeText(notice.outcome)
        }
        return parts.joined(separator: " · ")
    }

    /// 成功绿 / 退出码失败红 / 信号终止橙 / 未知灰。
    private func accent(for outcome: ProjectWatchOutcome) -> Color {
        switch outcome {
        case .succeeded: return accentGreen
        case .failed: return accentRed
        case .signaled: return accentAmber
        case .unknown: return accentMuted
        }
    }

    private func tagBackground(for outcome: ProjectWatchOutcome) -> Color {
        switch outcome {
        case .succeeded: return accentGreenSoft
        case .failed: return accentRedSoft
        case .signaled: return accentAmberSoft
        case .unknown: return accentMutedSoft
        }
    }
}
