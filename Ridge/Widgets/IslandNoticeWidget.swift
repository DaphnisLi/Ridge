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
    private var dismissTask: Task<Void, Never>?
    private var presenting: IslandNoticePayload?

    init(context: WidgetContext) {
        self.context = context
        noticeCenter.$current
            .receive(on: RunLoop.main)
            .sink { [weak self] payload in
                self?.handlePayload(payload)
            }
            .store(in: &observers)
        if let existing = noticeCenter.current {
            handlePayload(existing)
        }
        context.log("瞬时通知小组件已创建")
    }

    func makeView() -> AnyView {
        // 直接观察中枢：替换提示时不必再 requestDisplay 才能换皮。
        AnyView(IslandNoticeCardView())
    }

    func onAppear() {
        context.log("瞬时通知 onAppear", fields: [
            "hasNotice": presenting != nil,
            "source": presenting?.sourceTag ?? ""
        ])
    }

    func onDisappear() {
        context.log("瞬时通知 onDisappear")
    }

    /// 仅同步文案；展示争夺只由 `IslandNoticeCenter` 驱动。
    func refresh() {
        presenting = noticeCenter.current
        if presenting == nil, wantsDisplay {
            hide()
        }
    }

    private func handlePayload(_ payload: IslandNoticePayload?) {
        guard let payload else {
            dismissTask?.cancel()
            dismissTask = nil
            presenting = nil
            if wantsDisplay {
                hide()
            }
            return
        }

        presenting = payload
        // 必须先切到通知页再 expand，否则会先闪出货架/控制台等当前页，看起来不像三种额度胶囊。
        showThenExpand(payload: payload)

        // RAM 高压需用户处理（释放 / 忽略），不自动收起。
        if let nanos = payload.autoDismissNanoseconds {
            scheduleAutoDismiss(
                for: payload.id,
                nanoseconds: nanos,
                holdWhileHovering: payload.holdsWhileHovering
            )
        } else {
            dismissTask?.cancel()
            dismissTask = nil
            AppLog.debug("IslandNotice", "通知保持展示，直至用户操作", [
                "id": payload.id,
                "source": payload.sourceTag
            ])
        }
    }

    /// 到达时长后撤回；可选：悬停时延后（剪贴板短提示不延后）。
    private func scheduleAutoDismiss(
        for noticeID: String,
        nanoseconds: UInt64,
        holdWhileHovering: Bool
    ) {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled, let self else { return }
            guard self.presenting?.id == noticeID else { return }

            if holdWhileHovering {
                while !Task.isCancelled, IslandController.shared?.isHoveringIsland == true {
                    AppLog.debug("IslandNotice", "指针在岛上，延后自动收起", ["id": noticeID])
                    try? await Task.sleep(nanoseconds: Self.hoverPollNanoseconds)
                }
                guard !Task.isCancelled else { return }
                guard self.presenting?.id == noticeID else { return }
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
        // 定时器触发时若已被新提示替换，绝不能 hide/collapse 把新条收掉。
        guard noticeCenter.current?.id == noticeID || noticeCenter.current == nil else {
            if presenting?.id == noticeID {
                presenting = noticeCenter.current
            }
            AppLog.warn("IslandNotice", "收起跳过：已被新通知替换", [
                "old": noticeID,
                "current": noticeCenter.current?.id ?? ""
            ])
            return
        }
        if case .processEnded(let notice) = presenting, notice.id == noticeID {
            ProjectReleaseSession.shared.dismissWatchEnded()
        } else {
            noticeCenter.dismiss(id: noticeID)
        }
        hide()
        AppLog.warn("IslandNotice", "瞬时通知已收起", [
            "id": noticeID,
            "reason": reason,
            "ms": Int(displayedNanoseconds / 1_000_000)
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
        dismissTask?.cancel()
        dismissTask = nil
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

    var body: some View {
        switch noticeCenter.current {
        case .processEnded(let notice):
            ProcessEndedNoticeCard(notice: notice)
        case .ramPressure(let notice):
            RAMPressureNoticeCard(notice: notice)
        case .peripheralLowBattery(let notice):
            PeripheralBatteryNoticeCard(notice: notice, style: .low)
        case .peripheralFullCharge(let notice):
            PeripheralBatteryNoticeCard(notice: notice, style: .full)
        case .peripheralConnected(let notice):
            PeripheralBatteryNoticeCard(notice: notice, style: .connect)
        case .clipboardCaptureHint(let id, let text, let symbol):
            if id.hasPrefix("copy.") {
                ClipboardCopiedIslandView(detail: text)
            } else {
                ClipboardCaptureHintNoticeCard(text: text, symbol: symbol)
            }
        case .colorPickTip:
            ColorPickTipIslandView()
        case .ocrSelectTip:
            OCRSelectTipIslandView()
        case .aiUsageAlert(_, let providerName, let remainingPercent, let stage, let resetsAt):
            // 根视图禁止再加外圈 padding：壳层 `IslandChrome` + notchWing 已管边距。
            AIUsageIslandCardView(
                providerName: providerName,
                remainingPercent: remainingPercent,
                stage: stage,
                resetsAt: resetsAt,
                errorMessage: nil
            )
        case .moveReminder(let notice):
            MoveReminderNoticeCard(notice: notice)
        case .meetingLead:
            MeetingLeadNoticeCard()
        case .none:
            ProcessEndedNoticeCard(notice: nil)
        }
    }
}

/// 会前提示卡：矮胶囊；入会后由会话撤提示。
private struct MeetingLeadNoticeCard: View {
    @ObservedObject private var lead = MeetingLeadSession.shared

    var body: some View {
        if let snap = lead.snapshot {
            MeetingIslandCardView(
                title: snap.title,
                secondsToStart: snap.secondsToStart,
                showJoin: snap.showJoin,
                showAuth: snap.showAuth,
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
    var previewNotchWidth: CGFloat = 110

    @Environment(\.islandNotchWidth) private var envNotchWidth
    @Environment(\.islandNotchHeight) private var envNotchHeight

    private let accentRed = Color(.sRGB, red: 0.86, green: 0.22, blue: 0.24, opacity: 1)
    private let accentGreen = Color(.sRGB, red: 0.18, green: 0.62, blue: 0.34, opacity: 1)
    private let accentBlue = Color(.sRGB, red: 0.20, green: 0.48, blue: 0.96, opacity: 1)

    private var notchWidth: CGFloat {
        compact ? previewNotchWidth : max(envNotchWidth, 110)
    }

    private var barHeight: CGFloat {
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

    private var statusTint: Color {
        switch style {
        case .low: return accentRed
        case .full: return accentGreen
        case .connect: return accentBlue
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
        HStack(spacing: 0) {
            leftCluster
                .frame(width: wingWidth + notchWidth * 0.35, alignment: .leading)
            Spacer(minLength: 0)
            statusPill
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(width: totalWidth, height: barHeight)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { openBatteryLive(reason: "\(style)NoticeTap") }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(displayName)，\(statusText)")
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
        HStack(spacing: 5) {
            Image(systemName: statusSymbol)
                .font(.system(size: compact ? 9 : 10, weight: .semibold))
            Text(statusText)
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 4 : 5)
        .background(
            Capsule(style: .continuous)
                .fill(statusTint)
                .shadow(color: statusTint.opacity(0.45), radius: 6, y: 0)
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

/// RAM 高压瞬时通知（`system.islandNotice` / `.ramPressure`）。
private struct RAMPressureNoticeCard: View {
    let notice: ResourceRAMPressureNotice

    private let accentRed = Color(red: 1.0, green: 0.42, blue: 0.38)

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(accentRed.opacity(0.28))
                        .frame(width: 28, height: 28)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accentRed)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(L10n.ResourceMonitor.noticeTitle(notice.ramUsedBytes))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(String(format: "%.0f%%", notice.ramPercent))
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.75))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.white.opacity(0.16)))
                    }
                    Text(
                        L10n.ResourceMonitor.noticeSubtitle(
                            notice.topAppName,
                            notice.topAppMemoryBytes
                        )
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(3)

            HStack(spacing: 8) {
                Button {
                    AppLog.info("IslandNotice", "RAM 通知：免打扰 30 分钟")
                    ResourceMonitorSession.shared.muteAlerts30m()
                    IslandNoticeCenter.shared.dismiss(id: notice.id)
                } label: {
                    Text(L10n.ResourceMonitor.muteAlert)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.88))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button {
                    AppLog.info("IslandNotice", "RAM 通知：一键释放")
                    ResourceMonitorSession.shared.purgeMemory()
                    IslandNoticeCenter.shared.dismiss(id: notice.id)
                } label: {
                    Text(L10n.ResourceMonitor.purgeShort)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white))
                }
                .buttonStyle(.plain)
            }
            .fixedSize()
            .layoutPriority(2)
        }
        .frame(minWidth: 380)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.ResourceMonitor.noticeTitle(notice.ramUsedBytes))
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
