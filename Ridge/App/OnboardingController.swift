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

    private static let windowContentSize = NSSize(width: 760, height: 640)

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
            .padding(.top, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            footer
        }
        .frame(width: 760, height: 640)
        .background(SettingsChrome.pageBackground)
        .preferredColorScheme(.light)
        .onAppear {
            progress.reconcilePermissionsWithSystem()
            // 重开 App 后若队列已空（上一权限已在系统设置勾上），直接进自启页。
            if progress.step == .permissions, progress.permissionQueue.isEmpty {
                applySelectedWidgets()
                progress.step = .loginItem
                AppLog.info("Onboarding", "重开后续跑：权限已齐，进入自启页")
            }
            persist()
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button(L10n.Onboarding.skip) { skip() }
                .buttonStyle(.plain)
                .foregroundStyle(SettingsChrome.onSurfaceVariant)
                .font(SettingsChrome.Font.body)
                .disabled(isRequestingPermission)

            Spacer()

            Text(stepLabel)
                .font(SettingsChrome.Font.caption)
                .foregroundStyle(SettingsChrome.onSurfaceVariant)

            Spacer()

            if canGoBack {
                Button(L10n.Onboarding.back) { goBack() }
                    .buttonStyle(.bordered)
                    .disabled(isRequestingPermission)
            }

            Button(primaryTitle) { primaryAction() }
                .buttonStyle(.borderedProminent)
                .disabled(!canPrimary || isRequestingPermission)
        }
        .padding(20)
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

    private var canPrimary: Bool { true }

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
            if progress.permissionQueue.isEmpty {
                applySelectedWidgets()
                progress.step = .loginItem
                persist()
            } else {
                Task { await requestNextPermission() }
            }
        case .loginItem:
            finish()
        }
    }

    private func requestNextPermission() async {
        progress.reconcilePermissionsWithSystem()
        guard let raw = progress.permissionQueue.first,
              let need = WidgetPermissionGate.Need(rawValue: raw)
        else {
            applySelectedWidgets()
            progress.step = .loginItem
            persist()
            return
        }
        isRequestingPermission = true
        defer { isRequestingPermission = false }
        let outcome = await WidgetPermissionGate.ensureOne(need, reason: "onboarding")
        switch outcome {
        case .satisfied:
            progress.permissionQueue.removeAll { $0 == raw }
            progress.awaitingRelaunchFor = nil
            AppLog.info("Onboarding", "权限已满足", ["need": raw, "left": progress.permissionQueue.count])
        case .stillNeeded:
            progress.awaitingRelaunchFor = nil
            AppLog.warn("Onboarding", "权限仍缺，可重试", ["need": raw])
        case .awaitingSystemSettingsRelaunch:
            progress.awaitingRelaunchFor = raw
            AppLog.warn("Onboarding", "权限需系统设置，等待重开后续跑", ["need": raw])
        }
        persist()
        if progress.permissionQueue.isEmpty {
            applySelectedWidgets()
            progress.step = .loginItem
            persist()
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
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.Onboarding.stepIslandTitle)
                .font(SettingsChrome.Font.pageTitle)
                .foregroundStyle(SettingsChrome.onSurface)
            Text(L10n.Onboarding.stepIslandBody)
                .font(SettingsChrome.Font.body)
                .foregroundStyle(SettingsChrome.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)

            // 视频占位：稍后替换为真实演示片。
            ZStack {
                RoundedRectangle(cornerRadius: SettingsChrome.Radius.bento, style: .continuous)
                    .fill(SettingsChrome.surfaceContainer)
                VStack(spacing: 10) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(SettingsChrome.onSurfaceVariant.opacity(0.55))
                    Text(L10n.Onboarding.videoPlaceholder)
                        .font(SettingsChrome.Font.caption)
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .overlay(
                RoundedRectangle(cornerRadius: SettingsChrome.Radius.bento, style: .continuous)
                    .strokeBorder(SettingsChrome.cardStroke, lineWidth: SettingsChrome.cardStrokeWidth)
            )

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Step 2：推荐勾选

private struct OnboardingPickWidgetsStep: View {
    @Binding var progress: OnboardingProgress

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.Onboarding.stepPickTitle)
                .font(SettingsChrome.Font.pageTitle)
                .foregroundStyle(SettingsChrome.onSurface)
            Text(L10n.Onboarding.stepPickBody)
                .font(SettingsChrome.Font.body)
                .foregroundStyle(SettingsChrome.onSurfaceVariant)

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
                                }
                            )
                        )
                    }
                }
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
            WidgetSamplePreview.island(for: widgetID, compact: true)
                .frame(maxWidth: .infinity)
                .frame(height: 88)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(SettingsChrome.surfaceContainerLow)
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
        .padding(12)
        .background(SettingsChrome.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: SettingsChrome.Radius.bento, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SettingsChrome.Radius.bento, style: .continuous)
                .strokeBorder(SettingsChrome.cardStroke, lineWidth: SettingsChrome.cardStrokeWidth)
        )
        .opacity(isOn ? 1 : 0.72)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.Onboarding.stepPermissionsTitle)
                .font(SettingsChrome.Font.pageTitle)
                .foregroundStyle(SettingsChrome.onSurface)
            Text(L10n.Onboarding.stepPermissionsResumeBody)
                .font(SettingsChrome.Font.body)
                .foregroundStyle(SettingsChrome.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)

            if progress.permissionQueue.isEmpty {
                Label(L10n.Onboarding.permissionsAllDone, systemImage: "checkmark.circle.fill")
                    .font(SettingsChrome.Font.sectionTitle)
                    .foregroundStyle(SettingsChrome.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(progress.permissionQueue.enumerated()), id: \.element) { index, raw in
                        let need = WidgetPermissionGate.Need(rawValue: raw)
                        let isCurrent = index == 0
                        HStack(spacing: 12) {
                            Image(systemName: isCurrent ? "circle.inset.filled" : "circle")
                                .foregroundStyle(isCurrent ? SettingsChrome.primary : SettingsChrome.onSurfaceVariant)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(need.map(WidgetPermissionGate.title(for:)) ?? raw)
                                    .font(SettingsChrome.Font.rowTitle)
                                    .foregroundStyle(SettingsChrome.onSurface)
                                Text(need.map(WidgetPermissionGate.subtitle(for:)) ?? "")
                                    .font(SettingsChrome.Font.caption)
                                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                            }
                            Spacer(minLength: 0)
                            if progress.awaitingRelaunchFor == raw {
                                Text(L10n.Onboarding.awaitingRelaunchBadge)
                                    .font(SettingsChrome.Font.badgeTiny)
                                    .foregroundStyle(SettingsChrome.primary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(SettingsChrome.primary.opacity(0.12), in: Capsule())
                            }
                        }
                        .padding(.vertical, 12)
                        if index < progress.permissionQueue.count - 1 {
                            SettingsHairline()
                        }
                    }
                }
                .padding(.horizontal, SettingsChrome.Spacing.cardPadding)
                .background(SettingsChrome.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: SettingsChrome.Radius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: SettingsChrome.Radius.card, style: .continuous)
                        .strokeBorder(SettingsChrome.cardStroke, lineWidth: SettingsChrome.cardStrokeWidth)
                )
            }

            if progress.awaitingRelaunchFor != nil {
                Text(L10n.Onboarding.awaitingRelaunchHint)
                    .font(SettingsChrome.Font.caption)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
            }

            Spacer(minLength: 0)
        }
        .onAppear {
            progress.reconcilePermissionsWithSystem()
            progress.save()
        }
    }
}

// MARK: - Step 4：开机自启

private struct OnboardingLoginStep: View {
    @Binding var progress: OnboardingProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.Onboarding.stepLaunchTitle)
                .font(SettingsChrome.Font.pageTitle)
                .foregroundStyle(SettingsChrome.onSurface)
            Text(L10n.Onboarding.stepLaunchBody)
                .font(SettingsChrome.Font.body)
                .foregroundStyle(SettingsChrome.onSurfaceVariant)

            Toggle(isOn: Binding(
                get: { progress.enableLoginAtLogin },
                set: {
                    progress.enableLoginAtLogin = $0
                    progress.save()
                }
            )) {
                Text(L10n.General.launchAtLogin)
                    .font(SettingsChrome.Font.rowTitle)
            }
            .toggleStyle(.switch)
            .padding(16)
            .background(SettingsChrome.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: SettingsChrome.Radius.card, style: .continuous))

            Spacer(minLength: 0)
        }
    }
}
