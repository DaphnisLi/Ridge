import AppKit
import SwiftUI

/// 首次启动引导：认识岛 → 推荐勾选 → 权限队列（可重开续跑）→ 开机自启。
@MainActor
final class OnboardingController: NSObject, NSWindowDelegate {
    static let shared = OnboardingController()

    private var windowController: NSWindowController?

    func presentIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: AppIdentity.onboardingCompletedKey) else { return }
        present()
    }

    func present() {
        if let existing = windowController?.window, existing.isVisible {
            applySizeAndCenter(existing)
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        var progress = OnboardingProgress.load() ?? .fresh()
        progress.reconcilePermissionsWithSystem()
        progress.save()
        AppLog.warn("Onboarding", "恢复引导进度", [
            "step": progress.step.rawValue,
            "selected": progress.selectedWidgetIDs.count,
            "permQueue": progress.permissionQueue.count,
            "awaiting": progress.awaitingRelaunchFor ?? ""
        ])

        let root = OnboardingFlowView(
            progress: progress,
            onFinished: { [weak self] in
                self?.close()
            }
        )
        let hosting = NSHostingController(rootView: root)
        let contentSize = Self.windowContentSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.Onboarding.windowTitle
        window.titlebarAppearsTransparent = true
        window.backgroundColor = SettingsChrome.nsPageBackground
        window.contentViewController = hosting
        window.delegate = self
        window.isReleasedWhenClosed = false
        // 禁止系统记住上次窗位，保证每次默认开在屏幕正中。
        window.isRestorable = false
        window.setFrameAutosaveName("")
        applySizeAndCenter(window)

        let wc = NSWindowController(window: window)
        windowController = wc
        NSApp.setActivationPolicy(.regular)
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        // SwiftUI 首帧后再钉一次，避免布局撑开后偏出屏幕中心。
        DispatchQueue.main.async { [weak self] in
            self?.applySizeAndCenter(window)
            AppLog.warn("Onboarding", "引导窗已居中", [
                "midX": Int(window.frame.midX),
                "midY": Int(window.frame.midY),
                "screenMidX": Int(Self.targetScreen()?.visibleFrame.midX ?? 0),
                "screenMidY": Int(Self.targetScreen()?.visibleFrame.midY ?? 0)
            ])
        }
        AppLog.warn("Onboarding", "引导窗已显示")
    }

    /// 与 SwiftUI 根 `.frame` 一致：推荐双列卡需更宽，避免会议 tip 样张挤扁。
    private static let windowContentSize = NSSize(width: 860, height: 700)

    /// 首次引导默认开在主屏（刘海所在屏）正中；无主屏时退回鼠标所在屏。
    private static func targetScreen() -> NSScreen? {
        NSScreen.main
            ?? NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.screens.first
    }

    private func applySizeAndCenter(_ window: NSWindow) {
        let contentSize = Self.windowContentSize
        window.setContentSize(contentSize)
        window.layoutIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        Self.center(window, contentSize: contentSize, on: Self.targetScreen())
    }

    private static func center(_ window: NSWindow, contentSize: NSSize, on screen: NSScreen?) {
        guard let screen else {
            window.center()
            return
        }
        let frameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - frameSize.width / 2,
            y: visible.midY - frameSize.height / 2
        )
        window.setFrame(NSRect(origin: origin, size: frameSize), display: true)
    }

    private func close() {
        windowController?.close()
        windowController = nil
        DispatchQueue.main.async {
            if MenuBarController.shared?.isSettingsPresented != true {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        // 中途关窗：保留进度，下次启动续跑；不标 completed。
        OnboardingIslandMediaDemo.shared.stop()
        windowController = nil
        AppLog.warn("Onboarding", "引导窗关闭，进度已保留")
        DispatchQueue.main.async {
            if MenuBarController.shared?.isSettingsPresented != true {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}

// MARK: - Flow

private struct OnboardingFlowView: View {
    @State private var progress: OnboardingProgress
    var onFinished: () -> Void

    @State private var isRequestingPermission = false

    init(progress: OnboardingProgress, onFinished: @escaping () -> Void) {
        _progress = State(initialValue: progress)
        self.onFinished = onFinished
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                switch progress.step {
                case .island:
                    OnboardingIslandStep(progress: $progress)
                case .pickWidgets:
                    OnboardingPickWidgetsStep(progress: $progress)
                case .permissions:
                    OnboardingPermissionsStep(
                        progress: $progress,
                        isRequesting: $isRequestingPermission
                    )
                case .loginItem:
                    OnboardingLoginStep(progress: $progress)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            footer
        }
        /// 双列推荐卡 + 会议 tip 样张需要更宽；高度略增给滚动区。
        .frame(width: 860, height: 700)
        .background(SettingsChrome.pageBackground)
        .preferredColorScheme(.light)
        .onAppear {
            progress.ensurePermissionQueueReflectsGaps()
            // 重开后仅当所选能力权限全部满足才进自启页；队列空但未齐会重建，禁止误跳。
            if progress.step == .permissions, progress.allSelectedPermissionsSatisfied() {
                applySelectedWidgets()
                progress.step = .loginItem
                AppLog.warn("Onboarding", "重开后续跑：权限已齐，进入自启页")
            } else if progress.step == .permissions {
                AppLog.warn("Onboarding", "重开后续跑：权限未齐，留在权限页", [
                    "left": progress.permissionQueue.count,
                    "awaiting": progress.awaitingRelaunchFor ?? ""
                ])
            }
            persist()
        }
    }

    private var stepIndex: Int {
        switch progress.step {
        case .island: return 0
        case .pickWidgets: return 1
        case .permissions: return 2
        case .loginItem: return 3
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button(L10n.Onboarding.skip) { skip() }
                .buttonStyle(.plain)
                .font(SettingsChrome.Font.label)
                .foregroundStyle(SettingsChrome.onSurfaceVariant)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: SettingsChrome.Radius.chip, style: .continuous)
                        .fill(Color.clear)
                )
                .contentShape(Rectangle())
                .disabled(isRequestingPermission)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(
                            index == stepIndex
                                ? SettingsChrome.primary
                                : SettingsChrome.surfaceContainerHighest
                        )
                        .frame(width: index == stepIndex ? 16 : 6, height: 6)
                }
                Text(stepLabel)
                    .font(SettingsChrome.Font.monoCaption)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    .padding(.leading, 4)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                if canGoBack {
                    Button(L10n.Onboarding.back) { goBack() }
                        .buttonStyle(.bordered)
                        .disabled(isRequestingPermission)
                }
                Button(action: primaryAction) {
                    HStack(spacing: 4) {
                        Text(primaryTitle)
                        if progress.step == .island || progress.step == .loginItem {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canPrimary || isRequestingPermission)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var stepLabel: String {
        switch progress.step {
        case .island: return "1 / 4"
        case .pickWidgets: return "2 / 4"
        case .permissions: return "3 / 4"
        case .loginItem: return "4 / 4"
        }
    }

    private var canGoBack: Bool {
        switch progress.step {
        case .island: return false
        case .pickWidgets, .permissions, .loginItem: return true
        }
    }

    private var canPrimary: Bool {
        // 第 1 步须先悬停展开假媒体岛，再允许继续。
        if progress.step == .island { return progress.islandTried }
        return true
    }

    private var primaryTitle: String {
        switch progress.step {
        case .loginItem: return L10n.Onboarding.done
        case .permissions where !progress.permissionQueue.isEmpty:
            return L10n.Onboarding.grantNextPermission
        case .permissions where progress.awaitingRelaunchFor != nil:
            return L10n.Onboarding.openSystemSettingsAgain
        default:
            return L10n.Onboarding.next
        }
    }

    private func persist() {
        progress.save()
    }

    private func skip() {
        OnboardingIslandMediaDemo.shared.stop()
        OnboardingProgress.clear()
        UserDefaults.standard.set(true, forKey: AppIdentity.onboardingCompletedKey)
        AppLog.warn("Onboarding", "引导已跳过")
        onFinished()
    }

    private func goBack() {
        switch progress.step {
        case .pickWidgets:
            progress.step = .island
        case .permissions:
            progress.step = .pickWidgets
            progress.awaitingRelaunchFor = nil
        case .loginItem:
            progress.step = .permissions
            progress.rebuildPermissionQueue()
            progress.reconcilePermissionsWithSystem()
        case .island:
            break
        }
        persist()
    }

    private func primaryAction() {
        switch progress.step {
        case .island:
            progress.step = .pickWidgets
            persist()
        case .pickWidgets:
            progress.rebuildPermissionQueue()
            progress.reconcilePermissionsWithSystem()
            if progress.permissionQueue.isEmpty {
                applySelectedWidgets()
                progress.step = .loginItem
            } else {
                progress.step = .permissions
            }
            persist()
        case .permissions:
            progress.ensurePermissionQueueReflectsGaps()
            if progress.allSelectedPermissionsSatisfied() {
                advanceFromPermissionsToLogin(reason: "allSatisfied")
            } else {
                Task { await requestNextPermission() }
            }
        case .loginItem:
            finish()
        }
    }

    private func advanceFromPermissionsToLogin(reason: String) {
        progress.permissionQueue = []
        progress.awaitingRelaunchFor = nil
        applySelectedWidgets()
        progress.step = .loginItem
        persist()
        AppLog.warn("Onboarding", "全部权限已满足，进入自启页", ["reason": reason])
    }

    private func requestNextPermission() async {
        progress.ensurePermissionQueueReflectsGaps()
        if progress.allSelectedPermissionsSatisfied() {
            advanceFromPermissionsToLogin(reason: "requestAllSatisfied")
            return
        }
        guard let raw = progress.permissionQueue.first,
              let need = WidgetPermissionGate.Need(rawValue: raw)
        else {
            // 未齐却无队列：重建后再试；仍无则留在本页，绝不跳步。
            progress.rebuildPermissionQueue()
            progress.reconcilePermissionsWithSystem()
            persist()
            AppLog.warn("Onboarding", "权限未齐且队列异常，停留权限页", [
                "left": progress.permissionQueue.count
            ])
            return
        }
        isRequestingPermission = true
        defer { isRequestingPermission = false }
        let outcome = await WidgetPermissionGate.ensureOne(need, reason: "onboarding")
        switch outcome {
        case .satisfied:
            progress.permissionQueue.removeAll { $0 == raw }
            progress.awaitingRelaunchFor = nil
            AppLog.warn("Onboarding", "权限已满足", ["need": raw, "left": progress.permissionQueue.count])
        case .stillNeeded:
            progress.awaitingRelaunchFor = nil
            AppLog.warn("Onboarding", "权限仍缺，可重试", ["need": raw])
        case .awaitingSystemSettingsRelaunch:
            progress.awaitingRelaunchFor = raw
            AppLog.warn("Onboarding", "权限需系统设置，等待重开后续跑", ["need": raw])
        }
        progress.ensurePermissionQueueReflectsGaps()
        persist()
        if progress.allSelectedPermissionsSatisfied() {
            advanceFromPermissionsToLogin(reason: "afterEnsure")
        } else {
            AppLog.warn("Onboarding", "权限未齐，停留权限页", [
                "need": raw,
                "outcome": "\(outcome)",
                "left": progress.permissionQueue.count,
                "awaiting": progress.awaitingRelaunchFor ?? ""
            ])
        }
    }

    private func applySelectedWidgets() {
        let selected = Set(progress.selectedWidgetIDs)
        for id in OnboardingProgress.recommendedWidgetIDs {
            WidgetSettings.shared.setEnabled(id, enabled: selected.contains(id))
        }
        AppLog.info("Onboarding", "已应用推荐小组件开关", ["on": selected.count])
    }

    private func finish() {
        OnboardingIslandMediaDemo.shared.stop()
        if progress.enableLoginAtLogin {
            _ = LoginItemService.shared.setEnabled(true)
        }
        applySelectedWidgets()
        OnboardingProgress.clear()
        UserDefaults.standard.set(true, forKey: AppIdentity.onboardingCompletedKey)
        AppLog.warn("Onboarding", "引导已完成", ["loginItem": progress.enableLoginAtLogin])
        onFinished()
        SettingsNavigator.shared.open(.widgets)
    }
}

// MARK: - Step 1：认识岛（只演示，不强制用户操作）

private struct OnboardingIslandStep: View {
    @Binding var progress: OnboardingProgress

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text(L10n.Onboarding.stepIslandEyebrow.uppercased())
                    .font(SettingsChrome.Font.footnote)
                    .tracking(1.2)
                    .foregroundStyle(SettingsChrome.primary)
                Text(L10n.Onboarding.stepIslandTitle)
                    .font(SettingsChrome.Font.metricEmphasis)
                    .foregroundStyle(SettingsChrome.onSurface)
                Text(L10n.Onboarding.stepIslandBody)
                    .font(SettingsChrome.Font.body)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
            .padding(.bottom, 18)

            OnboardingDemoVideoView()

            HStack(spacing: 8) {
                Image(systemName: progress.islandTried ? "checkmark.circle.fill" : "hand.point.up.left.fill")
                    .font(SettingsChrome.Font.iconTile)
                    .foregroundStyle(progress.islandTried ? SettingsChrome.secondary : SettingsChrome.primary)
                Text(progress.islandTried ? L10n.Onboarding.stepIslandTriedHint : L10n.Onboarding.stepIslandTryHint)
                    .font(SettingsChrome.Font.caption)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(
                SettingsChrome.surfaceContainerLow,
                in: RoundedRectangle(cornerRadius: SettingsChrome.Radius.card, style: .continuous)
            )
            .padding(.top, 14)

            Spacer(minLength: 0)
        }
        .onAppear {
            OnboardingIslandMediaDemo.shared.onUserExpanded = {
                guard !progress.islandTried else { return }
                progress.islandTried = true
                progress.save()
                AppLog.info("Onboarding", "已记录刘海悬停展开", ["islandTried": true])
            }
            OnboardingIslandMediaDemo.shared.start()
        }
        .onDisappear {
            OnboardingIslandMediaDemo.shared.stop()
        }
    }
}

// MARK: - Step 2：推荐勾选（岛预览走 WidgetSamplePreview，与库卡同壳）

private struct OnboardingPickWidgetsStep: View {
    @Binding var progress: OnboardingProgress

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text(L10n.Onboarding.stepPickEyebrow.uppercased())
                    .font(SettingsChrome.Font.footnote)
                    .tracking(1.2)
                    .foregroundStyle(SettingsChrome.primary)
                Text(L10n.Onboarding.stepPickTitle)
                    .font(SettingsChrome.Font.metricEmphasis)
                    .foregroundStyle(SettingsChrome.onSurface)
                Text(L10n.Onboarding.stepPickBody)
                    .font(SettingsChrome.Font.body)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
            .padding(.bottom, 18)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(OnboardingProgress.recommendedWidgetIDs, id: \.self) { id in
                        OnboardingRecommendCard(
                            widgetID: id,
                            isOn: Binding(
                                get: { progress.selectedWidgetIDs.contains(id) },
                                set: { on in
                                    if on {
                                        if !progress.selectedWidgetIDs.contains(id) {
                                            progress.selectedWidgetIDs.append(id)
                                        }
                                    } else {
                                        progress.selectedWidgetIDs.removeAll { $0 == id }
                                    }
                                    progress.save()
                                    AppLog.info("Onboarding", "推荐能力勾选变更", [
                                        "id": id,
                                        "on": on,
                                        "count": progress.selectedWidgetIDs.count
                                    ])
                                }
                            )
                        )
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }
}

private struct OnboardingRecommendCard: View {
    let widgetID: WidgetID
    @Binding var isOn: Bool

    private var title: String {
        WidgetRegistry.shared.manifest(for: widgetID)?.displayName
            ?? widgetID
    }

    @ObservedObject private var colorPickSettings = ColorPickSettings.shared
    @ObservedObject private var ocrSelectSettings = OCRSelectSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 与小组件库卡同壳：灰舞台 + WidgetSamplePreview（假数据黑岛），禁止自绘假岛。
            WidgetSamplePreview.island(for: widgetID, compact: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.horizontal, 10)
                .frame(height: WidgetLibraryCardLayout.islandStageHeight)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(SettingsChrome.surfaceContainerLow)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(SettingsChrome.outlineVariant.opacity(0.45), lineWidth: 1)
                        )
                )
                .clipped()
                .allowsHitTesting(false)

            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(SettingsChrome.Font.sectionTitle)
                        .foregroundStyle(SettingsChrome.onSurface)
                        .lineLimit(1)
                    recommendSummary
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
        .padding(SettingsChrome.Spacing.cardInner)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(SettingsChrome.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: SettingsChrome.Radius.bento, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SettingsChrome.Radius.bento, style: .continuous)
                .strokeBorder(SettingsChrome.cardStroke, lineWidth: SettingsChrome.cardStrokeWidth)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
        .opacity(isOn ? 1 : 0.72)
        .contentShape(RoundedRectangle(cornerRadius: SettingsChrome.Radius.bento, style: .continuous))
        .onTapGesture {
            isOn.toggle()
        }
    }

    @ViewBuilder
    private var recommendSummary: some View {
        switch widgetID {
        case "builtin.colorPick":
            CaptureHotKeySummaryLabel(
                kind: .colorPick,
                chord: colorPickSettings.hotKey.displayString
            )
        case "builtin.ocrSelect":
            CaptureHotKeySummaryLabel(
                kind: .ocrSelect,
                chord: ocrSelectSettings.hotKey.displayString
            )
        default:
            Text(WidgetRegistry.shared.manifest(for: widgetID)?.summary ?? "")
                .font(SettingsChrome.Font.caption)
                .foregroundStyle(SettingsChrome.onSurfaceVariant)
        }
    }
}

// MARK: - Step 3：权限

private struct OnboardingPermissionsStep: View {
    @Binding var progress: OnboardingProgress
    @Binding var isRequesting: Bool

    /// 按勾选能力展开的完整权限清单（含已满足项，便于右侧显示「已授权」）。
    private var displayNeeds: [WidgetPermissionGate.Need] {
        var seen = Set<String>()
        var ordered: [WidgetPermissionGate.Need] = []
        for id in progress.selectedWidgetIDs {
            for need in WidgetPermissionGate.needs(forWidgetID: id) where seen.insert(need.rawValue).inserted {
                ordered.append(need)
            }
        }
        return ordered
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(SettingsChrome.primary)
                        .frame(width: 6, height: 6)
                    Text(L10n.Onboarding.stepPermissionsEyebrow)
                        .font(SettingsChrome.Font.chip)
                        .foregroundStyle(SettingsChrome.primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(SettingsChrome.primary.opacity(0.12), in: Capsule())

                Text(L10n.Onboarding.stepPermissionsTitle)
                    .font(SettingsChrome.Font.metricEmphasis)
                    .foregroundStyle(SettingsChrome.onSurface)
                Text(L10n.Onboarding.stepPermissionsResumeBody)
                    .font(SettingsChrome.Font.body)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 480)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
            .padding(.bottom, 18)

            if displayNeeds.isEmpty {
                Label(L10n.Onboarding.permissionsAllDone, systemImage: "checkmark.circle.fill")
                    .font(SettingsChrome.Font.sectionTitle)
                    .foregroundStyle(SettingsChrome.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(SettingsChrome.Spacing.cardPadding)
                    .background(SettingsChrome.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: SettingsChrome.Radius.bento, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: SettingsChrome.Radius.bento, style: .continuous)
                            .strokeBorder(SettingsChrome.cardStroke, lineWidth: SettingsChrome.cardStrokeWidth)
                    )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(displayNeeds.enumerated()), id: \.element.rawValue) { index, need in
                        OnboardingPermissionRow(
                            need: need,
                            isSatisfied: WidgetPermissionGate.isSatisfied(need),
                            isCurrent: progress.permissionQueue.first == need.rawValue,
                            isAwaitingRelaunch: progress.awaitingRelaunchFor == need.rawValue
                        )
                        if index < displayNeeds.count - 1 {
                            Rectangle()
                                .fill(SettingsChrome.surfaceContainerHighest.opacity(0.6))
                                .frame(height: 1)
                        }
                    }
                }
                .background(SettingsChrome.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: SettingsChrome.Radius.bento, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: SettingsChrome.Radius.bento, style: .continuous)
                        .strokeBorder(SettingsChrome.cardStroke, lineWidth: SettingsChrome.cardStrokeWidth)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .font(SettingsChrome.Font.iconTile)
                    .foregroundStyle(SettingsChrome.primary)
                Text(
                    progress.awaitingRelaunchFor != nil
                        ? L10n.Onboarding.awaitingRelaunchHint
                        : L10n.Onboarding.stepPermissionsHint
                )
                .font(SettingsChrome.Font.caption)
                .foregroundStyle(SettingsChrome.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(SettingsChrome.surfaceContainerLow, in: RoundedRectangle(cornerRadius: SettingsChrome.Radius.card, style: .continuous))
            .padding(.top, 16)

            Spacer(minLength: 0)
        }
        .onAppear {
            progress.ensurePermissionQueueReflectsGaps()
            progress.reconcilePermissionsWithSystem()
            progress.save()
            AppLog.info("Onboarding", "进入权限页", [
                "needs": displayNeeds.map(\.rawValue).joined(separator: ","),
                "left": progress.permissionQueue.count,
                "awaiting": progress.awaitingRelaunchFor ?? ""
            ])
        }
    }
}

private struct OnboardingPermissionRow: View {
    let need: WidgetPermissionGate.Need
    let isSatisfied: Bool
    let isCurrent: Bool
    let isAwaitingRelaunch: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(iconBackground)
                    .frame(width: 36, height: 36)
                Image(systemName: iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(iconForeground)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(WidgetPermissionGate.title(for: need))
                    .font(SettingsChrome.Font.sectionTitle)
                    .foregroundStyle(SettingsChrome.onSurface)
                    .lineLimit(1)
                Text(WidgetPermissionGate.subtitle(for: need))
                    .font(SettingsChrome.Font.caption)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            statusSlot
        }
        .padding(.horizontal, SettingsChrome.Spacing.cardPadding)
        .padding(.vertical, 14)
        .background(isCurrent && !isSatisfied ? SettingsChrome.surfaceContainerLow.opacity(0.7) : Color.clear)
    }

    @ViewBuilder
    private var statusSlot: some View {
        if isSatisfied {
            HStack(spacing: 4) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                Text(L10n.Common.authorized)
                    .font(SettingsChrome.Font.chip)
            }
            .foregroundStyle(SettingsChrome.onSecondaryContainer)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(SettingsChrome.secondaryContainer, in: Capsule())
        } else if isAwaitingRelaunch {
            Text(L10n.Onboarding.awaitingRelaunchBadge)
                .font(SettingsChrome.Font.chip)
                .foregroundStyle(SettingsChrome.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(SettingsChrome.primary.opacity(0.12), in: Capsule())
        } else if isCurrent {
            Circle()
                .strokeBorder(SettingsChrome.primary.opacity(0.35), lineWidth: 1.5)
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .fill(SettingsChrome.primary)
                        .frame(width: 4, height: 4)
                )
        } else {
            Color.clear.frame(width: 10, height: 10)
        }
    }

    private var iconName: String {
        switch need {
        case .calendar: return "calendar"
        case .screenCapture: return "rectangle.dashed.badge.record"
        case .bluetooth: return "antenna.radiowaves.left.and.right"
        case .inputMonitoring: return "keyboard"
        }
    }

    private var iconBackground: Color {
        switch need {
        case .calendar: return SettingsChrome.primaryContainer
        case .screenCapture: return SettingsChrome.primary.opacity(0.12)
        case .bluetooth: return SettingsChrome.surfaceContainer
        case .inputMonitoring: return SettingsChrome.surfaceContainerHighest
        }
    }

    private var iconForeground: Color {
        switch need {
        case .calendar: return .white
        case .screenCapture: return SettingsChrome.primary
        case .bluetooth, .inputMonitoring: return SettingsChrome.onSurfaceVariant
        }
    }
}

// MARK: - Step 4：开机自启

private struct OnboardingLoginStep: View {
    @Binding var progress: OnboardingProgress

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text(L10n.Onboarding.stepLaunchTitle)
                    .font(SettingsChrome.Font.metricEmphasis)
                    .foregroundStyle(SettingsChrome.onSurface)
                Text(L10n.Onboarding.stepLaunchBody)
                    .font(SettingsChrome.Font.body)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 540)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
            .padding(.bottom, 18)

            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(SettingsChrome.surfaceContainer)
                        .frame(width: 40, height: 40)
                    Image(systemName: "power")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(SettingsChrome.primary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.General.launchAtLogin)
                        .font(SettingsChrome.Font.sectionTitle)
                        .foregroundStyle(SettingsChrome.onSurface)
                        .lineLimit(1)
                    Text(L10n.Onboarding.stepLaunchToggleSubtitle)
                        .font(SettingsChrome.Font.caption)
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Toggle("", isOn: Binding(
                    get: { progress.enableLoginAtLogin },
                    set: {
                        progress.enableLoginAtLogin = $0
                        progress.save()
                        AppLog.info("Onboarding", "开机自启勾选变更", ["on": $0])
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
            .padding(SettingsChrome.Spacing.cardPadding)
            .background(SettingsChrome.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: SettingsChrome.Radius.bento, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SettingsChrome.Radius.bento, style: .continuous)
                    .strokeBorder(SettingsChrome.cardStroke, lineWidth: SettingsChrome.cardStrokeWidth)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)

            Spacer(minLength: 0)
        }
        .onAppear {
            AppLog.info("Onboarding", "进入自启页", ["loginItem": progress.enableLoginAtLogin])
        }
    }
}
