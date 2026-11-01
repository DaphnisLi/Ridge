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

        scheduleAutoDismiss(for: payload.id)
    }

    /// 满 3s 后若仍悬停在岛上则等待离开，再撤回。
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
        case .none:
            ProcessEndedNoticeCard(notice: nil)
        }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
