import Combine
import Foundation
import SwiftUI

/// 灵动岛通用瞬时通知：不进小组件库，不可左右滑动。
/// 默认约 3 秒后自动撤回；指针在岛上时不收，离开后再收。
/// 注意：`refresh` 不得再调 `requestDisplay`，否则会与 `applyPage` 形成重入栈溢出。
@MainActor
final class IslandNoticeWidget: IslandWidget {
    private static let displayNanoseconds: UInt64 = 3_000_000_000
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
        AnyView(IslandNoticeCardView(payload: presenting))
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

        // 同一条已在展示：勿再 requestDisplay（防 applyPage→refresh 重入栈溢出）。
        if presenting?.id == payload.id, wantsDisplay {
            return
        }

        presenting = payload
        show()
        IslandController.shared?.expand(reason: "islandNotice")
        AppLog.info("IslandNotice", "瞬时通知已上岛", [
            "id": payload.id,
            "source": payload.sourceTag
        ])

        // RAM 高压需用户处理（释放 / 忽略），不自动收起。
        if case .ramPressure = payload {
            dismissTask?.cancel()
            dismissTask = nil
            AppLog.debug("IslandNotice", "RAM 高压通知保持展示，直至用户操作")
        } else {
            scheduleAutoDismiss(for: payload.id)
        }
    }

    /// 满 3s 后若仍悬停在岛上则等待离开，再撤回（不含 RAM 高压）。
    private func scheduleAutoDismiss(for noticeID: String) {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.displayNanoseconds)
            guard !Task.isCancelled, let self else { return }
            guard self.presenting?.id == noticeID else { return }

            while !Task.isCancelled, IslandController.shared?.isHoveringIsland == true {
                AppLog.debug("IslandNotice", "指针在岛上，延后自动收起", ["id": noticeID])
                try? await Task.sleep(nanoseconds: Self.hoverPollNanoseconds)
            }
            guard !Task.isCancelled else { return }
            guard self.presenting?.id == noticeID else { return }

            self.finishDismiss(noticeID: noticeID, reason: "auto")
        }
    }

    private func finishDismiss(noticeID: String, reason: String) {
        if case .processEnded(let notice) = presenting, notice.id == noticeID {
            ProjectReleaseSession.shared.dismissWatchEnded()
        } else {
            noticeCenter.dismiss(id: noticeID)
        }
        hide()
        AppLog.info("IslandNotice", "瞬时通知已收起", [
            "id": noticeID,
            "reason": reason,
            "ms": Int(Self.displayNanoseconds / 1_000_000)
        ])
    }

    private func show() {
        if wantsDisplay { return }
        wantsDisplay = true
        requestedAt = Date()
        // 与会议一致：延后 request，避开 Runtime applyPage / ensureInstance 同步栈。
        Task { @MainActor [weak self] in
            guard let self, self.wantsDisplay else { return }
            self.context.requestDisplay()
            AppLog.debug("IslandNotice", "已提交 requestDisplay")
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
        if !hovering {
            IslandController.shared?.collapse(reason: "islandNoticeEnd")
            AppLog.info("IslandNotice", "通知结束且未悬停，已收起灵动岛")
        } else {
            AppLog.debug("IslandNotice", "通知结束但指针仍在岛上，保持展开")
        }
    }
}

// MARK: - View

private struct IslandNoticeCardView: View {
    let payload: IslandNoticePayload?

    var body: some View {
        switch payload {
        case .processEnded(let notice):
            ProcessEndedNoticeCard(notice: notice)
        case .ramPressure(let notice):
            RAMPressureNoticeCard(notice: notice)
        case .peripheralLowBattery(let notice):
            PeripheralBatteryNoticeCard(notice: notice, style: .low)
        case .peripheralFullCharge(let notice):
            PeripheralBatteryNoticeCard(notice: notice, style: .full)
        case .none:
            ProcessEndedNoticeCard(notice: nil)
        }
    }
}

/// 外设低电 / 满电信息条（约 3s 自动收；低电可「稍后提醒」30 分钟）。
private struct PeripheralBatteryNoticeCard: View {
    enum Style {
        case low
        case full
    }

    let notice: BatteryPeripheralNotice
    let style: Style

    private let accentRed = Color(red: 0.729, green: 0.102, blue: 0.102)
    private let accentGreen = Color(red: 0.447, green: 0.996, blue: 0.533)

    private var accent: Color {
        style == .low ? accentRed : accentGreen
    }

    private var badge: String {
        switch style {
        case .low: return L10n.Battery.tipLowBadge(notice.percent)
        case .full: return L10n.Battery.tipFullBadge
        }
    }

    var body: some View {
        Group {
            if style == .full {
                fullBody
            } else {
                lowBody
            }
        }
        .frame(minWidth: 320)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(notice.deviceName)，\(badge)")
    }

    /// 满电：左发光图标（右下角闪电图标）+ 文案 + 右发光「100% 已充满」。
    private var fullBody: some View {
        HStack(alignment: .center, spacing: 12) {
            fullDeviceIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(notice.deviceName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(notice.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(3)

            fullChargePill
                .fixedSize()
                .layoutPriority(2)
        }
    }

    private var fullDeviceIcon: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(accentGreen.opacity(0.85), lineWidth: 1.2)
                    )
                Image(systemName: notice.kind.systemSymbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
            }
            .frame(width: 30, height: 30)
            .shadow(color: accentGreen.opacity(0.75), radius: 7, x: 0, y: 0)
            .shadow(color: accentGreen.opacity(0.40), radius: 14, x: 0, y: 0)

            ZStack {
                Circle()
                    .fill(accentGreen)
                    .frame(width: 12, height: 12)
                    .shadow(color: accentGreen.opacity(0.85), radius: 4, x: 0, y: 0)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.88))
            }
            .offset(x: 3, y: 3)
            .accessibilityHidden(true)
        }
        .frame(width: 30, height: 30)
    }

    private var fullChargePill: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 9, weight: .semibold))
            Text(L10n.Battery.tipFullBadge)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(accentGreen)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(accentGreen.opacity(0.14))
                .overlay(
                    Capsule().strokeBorder(accentGreen.opacity(0.75), lineWidth: 1)
                )
        )
        .shadow(color: accentGreen.opacity(0.70), radius: 7, x: 0, y: 0)
        .shadow(color: accentGreen.opacity(0.35), radius: 12, x: 0, y: 0)
    }

    /// 低电：左发光图标（右上角闪烁感叹号）+ 文案 + 右发光红胶囊（循环电量格 + 百分比）。
    private var lowBody: some View {
        HStack(alignment: .center, spacing: 10) {
            lowDeviceIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(notice.deviceName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(notice.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(3)

            lowChargePill
                .fixedSize()
                .layoutPriority(2)
        }
    }

    private var lowDeviceIcon: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(accentRed.opacity(0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(accentRed, lineWidth: 1.4)
                    )
                Image(systemName: notice.kind.systemSymbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accentRed)
            }
            .frame(width: 30, height: 30)
            .shadow(color: accentRed.opacity(0.95), radius: 8, x: 0, y: 0)
            .shadow(color: accentRed.opacity(0.65), radius: 16, x: 0, y: 0)
            .shadow(color: accentRed.opacity(0.35), radius: 22, x: 0, y: 0)

            // 感叹号一闪一闪。
            TimelineView(.animation(minimumInterval: 0.45, paused: false)) { context in
                let on = Int(context.date.timeIntervalSinceReferenceDate / 0.45) % 2 == 0
                ZStack {
                    Circle()
                        .fill(accentRed)
                        .frame(width: 12, height: 12)
                        .shadow(color: accentRed.opacity(on ? 1.0 : 0.35), radius: on ? 6 : 2, x: 0, y: 0)
                    Image(systemName: "exclamationmark")
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(.white)
                }
                .opacity(on ? 1.0 : 0.28)
                .scaleEffect(on ? 1.0 : 0.92)
            }
            .offset(x: 3, y: -3)
            .accessibilityHidden(true)
        }
        .frame(width: 30, height: 30)
    }

    private var lowChargePill: some View {
        HStack(spacing: 5) {
            CyclingBatteryBarsGlyph(tint: .white)
            Text(L10n.Battery.tipLowBadge(notice.percent))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(accentRed)
                .overlay(
                    Capsule().strokeBorder(accentRed.opacity(0.95), lineWidth: 1)
                )
        )
        .shadow(color: accentRed.opacity(0.75), radius: 7, x: 0, y: 0)
        .shadow(color: accentRed.opacity(0.40), radius: 12, x: 0, y: 0)
    }
}

/// 低电胶囊内循环电量格：1 → 2 → 3 → 1 …
private struct CyclingBatteryBarsGlyph: View {
    var tint: Color = .white
    private let period: TimeInterval = 0.42

    var body: some View {
        TimelineView(.animation(minimumInterval: period, paused: false)) { context in
            let lit = Int(context.date.timeIntervalSinceReferenceDate / period) % 3 + 1
            HStack(spacing: 1.2) {
                HStack(spacing: 1.4) {
                    ForEach(1...3, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 0.8, style: .continuous)
                            .fill(index <= lit ? tint : tint.opacity(0.22))
                            .frame(width: 2.4, height: 6.5)
                    }
                }
                .padding(.horizontal, 2.2)
                .padding(.vertical, 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .strokeBorder(tint.opacity(0.95), lineWidth: 1)
                )

                RoundedRectangle(cornerRadius: 0.6, style: .continuous)
                    .fill(tint.opacity(0.95))
                    .frame(width: 1.4, height: 3.2)
            }
            .accessibilityHidden(true)
        }
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
