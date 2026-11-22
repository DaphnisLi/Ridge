import AppKit
import EventKit
import SwiftUI

/// 嵌入「下一场会议」小组件预览页的配置区（含岛预览）。
struct MeetingWidgetConfigSection: View {
    @ObservedObject private var settings = MeetingSettings.shared
    @ObservedObject private var calendar = MeetingCalendarService.shared
    @State private var leadText: String = ""
    @State private var tipDismissText: String = ""
    @State private var customName: String = ""
    @State private var customLink: String = ""
    @State private var customError: String?
    @State private var isRequestingAuth = false
    @State private var previewUrgency: MeetingLeadUrgency = .relaxed
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case leadMinutes
        case tipDismissMinutes
        case customName
        case customLink
    }

    private let leadPresets = [5, 10, 15]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 未授权置顶；已授权整卡不展示。
                    authCard
                    islandPreviewCard
                    leadMinutesCard
                    tipDismissCard
                    supportedPlatformsCard
                    customAppsCard
                }
                .padding(.horizontal, SettingsChrome.Spacing.pageHorizontal)
                .padding(.top, 16)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)

            SettingsRestoreDefaultsFooter {
                resignFields()
                settings.restoreDefaults()
                leadText = "\(settings.leadMinutes)"
                tipDismissText = "\(settings.tipDismissMinutes)"
                AppLog.info("Meeting", "用户恢复默认设置")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SettingsChrome.pageBackground)
        .onAppear {
            leadText = "\(settings.leadMinutes)"
            tipDismissText = "\(settings.tipDismissMinutes)"
            calendar.start()
            calendar.refreshUpcoming(reason: "widgetPreviewConfig")
            AppLog.debug("Meeting", "会议配置区已显示（预览页）")
        }
        .onChange(of: settings.leadMinutes) { _, value in
            let next = "\(value)"
            if focusedField != .leadMinutes, leadText != next {
                leadText = next
            }
        }
        .onChange(of: settings.tipDismissMinutes) { _, value in
            let next = "\(value)"
            if focusedField != .tipDismissMinutes, tipDismissText != next {
                tipDismissText = next
            }
        }
        .onChange(of: focusedField) { old, new in
            if old == .leadMinutes, new != .leadMinutes {
                commitLeadMinutes()
            }
            if old == .tipDismissMinutes, new != .tipDismissMinutes {
                commitTipDismissMinutes()
            }
        }
    }

    private func resignFields() {
        focusedField = nil
    }

    // MARK: - 岛预览（绿 / 琥珀 / 红三态）

    private var islandPreviewCard: some View {
        SettingsIslandStage(
            options: MeetingLeadUrgency.allCases.map { urgency in
                SettingsIslandStageOption(
                    id: urgency.rawValue,
                    title: urgency.stageTitle,
                    badge: urgency.stageBadge,
                    symbol: "circle.fill",
                    tint: urgency.settingsTint,
                    maxIslandWidth: SettingsIslandPreviewWidth.tip,
                    hugsContent: WidgetSamplePreview.tipPreviewHugsContent,
                    bottomRadius: 18,
                    outlineStyle: .panel,
                    minStageHeight: SettingsIslandPreviewWidth.tipStageMinHeight,
                    compactShell: true
                )
            },
            selection: Binding(
                get: { previewUrgency.rawValue },
                set: { previewUrgency = MeetingLeadUrgency(rawValue: $0) ?? .relaxed }
            )
        ) { option in
            let urgency = MeetingLeadUrgency(rawValue: option.id) ?? .relaxed
            // 预览壳无 IslandChrome：舞台补左右/底，与真岛 notchWing 令牌一致。
            MeetingIslandCardView.previewSample(urgency: urgency, compact: true)
                .padding(.horizontal, IslandChrome.contentHorizontal)
                .padding(.bottom, IslandChrome.compactTipBottom)
                .frame(minHeight: SettingsIslandPreviewWidth.tipDetailMinHeight)
                .id(urgency.rawValue)
        }
    }

    // MARK: - 日历授权（仅未授权时置顶展示）

    private var authCard: some View {
        SettingsPermissionCard(
            status: calendarPermissionStatus,
            symbol: "calendar",
            tint: SettingsChrome.secondary,
            title: L10n.Meeting.calendarAccess,
            subtitle: calendarPermissionSubtitle,
            requestTitle: L10n.Meeting.calendarAllow,
            requestSymbol: "key.fill",
            action: calendarPermissionAction
        )
    }

    private var calendarPermissionStatus: SettingsPermissionCard.Status {
        switch calendar.authStatus {
        case .authorized:
            return .authorized
        case .notDetermined:
            return isRequestingAuth ? .busy : .request
        case .denied, .restricted:
            return .openSettings
        }
    }

    private var calendarPermissionSubtitle: String {
        switch calendar.authStatus {
        case .denied, .restricted:
            return L10n.Meeting.calendarDeniedDesc
        default:
            return L10n.Meeting.calendarDesc
        }
    }

    private var calendarPermissionAction: (() -> Void)? {
        switch calendar.authStatus {
        case .authorized:
            return nil
        case .notDetermined:
            return {
                guard !isRequestingAuth else { return }
                resignFields()
                isRequestingAuth = true
                AppLog.info("Meeting", "设置页点击请求日历权限")
                Task {
                    _ = await calendar.requestAccess()
                    isRequestingAuth = false
                }
            }
        case .denied, .restricted:
            return {
                resignFields()
                calendar.openSystemPrivacySettings()
                AppLog.info("Meeting", "设置页打开系统日历隐私")
            }
        }
    }

    // MARK: - 提前提醒

    private var leadMinutesCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.Meeting.leadTitle)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(SettingsChrome.onSurface)
                        Text(L10n.Meeting.leadSubtitle(settings.leadMinutes))
                            .font(.system(size: 12))
                            .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    }
                    Spacer(minLength: 8)
                    Text(L10n.Meeting.leadBadge(settings.leadMinutes))
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(SettingsChrome.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(SettingsChrome.primary.opacity(0.10))
                        )
                }

                HStack(spacing: 4) {
                    ForEach(leadPresets, id: \.self) { minutes in
                        let selected = settings.leadMinutes == minutes
                        Button {
                            resignFields()
                            applyLeadMinutes(minutes)
                        } label: {
                            Text(minutes == 10 ? L10n.Meeting.minutesRecommended(minutes) : L10n.Meeting.minutes(minutes))
                                .font(.system(size: 12, weight: selected ? .semibold : .medium))
                                .foregroundStyle(selected ? SettingsChrome.onSurface : SettingsChrome.onSurfaceVariant)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(selected ? Color.white : Color.clear)
                                        .shadow(color: selected ? .black.opacity(0.06) : .clear, radius: 2, y: 1)
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    Rectangle()
                        .fill(SettingsChrome.outlineVariant.opacity(0.60))
                        .frame(width: 1, height: 18)
                        .padding(.horizontal, 4)

                    HStack(spacing: 4) {
                        TextField("", text: $leadText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 44)
                            .multilineTextAlignment(.center)
                            .font(.system(size: 12).monospacedDigit())
                            .focused($focusedField, equals: .leadMinutes)
                            .onSubmit {
                                commitLeadMinutes()
                                focusedField = nil
                            }
                            .onChange(of: leadText) { _, newValue in
                                let filtered = newValue.filter(\.isNumber)
                                if filtered != newValue { leadText = filtered }
                            }
                        Text(L10n.Common.minuteUnit)
                            .font(.system(size: 11))
                            .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    }
                    .padding(.leading, 2)
                }
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(SettingsChrome.surfaceContainerLow)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(SettingsChrome.cardStroke, lineWidth: SettingsChrome.cardStrokeWidth)
                        )
                )
            }
            .padding(16)
        }
    }

    private func applyLeadMinutes(_ minutes: Int) {
        leadText = "\(minutes)"
        commitLeadMinutes()
    }

    private func commitLeadMinutes() {
        let parsed = Int(leadText) ?? settings.leadMinutes
        let clamped = min(
            max(parsed, MeetingSettings.leadMinutesRange.lowerBound),
            MeetingSettings.leadMinutesRange.upperBound
        )
        if settings.leadMinutes != clamped {
            settings.leadMinutes = clamped
            AppLog.info("Meeting", "提前倒计时已更新", ["minutes": clamped])
        }
        leadText = "\(clamped)"
    }

    // MARK: - 开始后保留提示

    private var tipDismissCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.Meeting.tipDismissTitle)
                            .font(SettingsChrome.Font.rowTitle)
                            .foregroundStyle(SettingsChrome.onSurface)
                        Text(
                            L10n.Meeting.tipDismissSubtitle(
                                settings.tipDismissMode,
                                minutes: settings.tipDismissMinutes
                            )
                        )
                        .font(SettingsChrome.Font.body)
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    }
                    Spacer(minLength: 8)
                    Text(
                        L10n.Meeting.tipDismissBadge(
                            settings.tipDismissMode,
                            minutes: settings.tipDismissMinutes
                        )
                    )
                    .font(SettingsChrome.Font.footnote)
                    .foregroundStyle(SettingsChrome.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(SettingsChrome.primary.opacity(0.10))
                    )
                }

                HStack(spacing: 4) {
                    tipDismissPresetButton(
                        title: L10n.Meeting.tipDismissAtStart,
                        selected: settings.tipDismissMode == .atStart
                    ) {
                        resignFields()
                        settings.tipDismissMode = .atStart
                    }

                    tipDismissPresetButton(
                        title: L10n.Meeting.minutesRecommended(5),
                        selected: settings.tipDismissMode == .afterMinutes
                            && settings.tipDismissMinutes == 5
                    ) {
                        resignFields()
                        tipDismissText = "5"
                        settings.tipDismissMinutes = 5
                        settings.tipDismissMode = .afterMinutes
                    }

                    tipDismissPresetButton(
                        title: L10n.Meeting.tipDismissUntilEnd,
                        selected: settings.tipDismissMode == .untilEnd
                    ) {
                        resignFields()
                        settings.tipDismissMode = .untilEnd
                    }

                    Rectangle()
                        .fill(SettingsChrome.outlineVariant.opacity(0.60))
                        .frame(width: 1, height: 18)
                        .padding(.horizontal, 4)

                    HStack(spacing: 4) {
                        TextField("", text: $tipDismissText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 44)
                            .multilineTextAlignment(.center)
                            .font(.system(size: 12).monospacedDigit())
                            .focused($focusedField, equals: .tipDismissMinutes)
                            .onSubmit {
                                commitTipDismissMinutes()
                                focusedField = nil
                            }
                            .onChange(of: tipDismissText) { _, newValue in
                                let filtered = newValue.filter(\.isNumber)
                                if filtered != newValue { tipDismissText = filtered }
                            }
                        Text(L10n.Common.minuteUnit)
                            .font(.system(size: 11))
                            .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    }
                    .padding(.leading, 2)
                }
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(SettingsChrome.surfaceContainerLow)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(SettingsChrome.cardStroke, lineWidth: SettingsChrome.cardStrokeWidth)
                        )
                )
            }
            .padding(SettingsChrome.Spacing.cardPadding)
        }
    }

    private func tipDismissPresetButton(
        title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(selected ? SettingsChrome.Font.chipSelected : SettingsChrome.Font.chip)
                .foregroundStyle(selected ? SettingsChrome.onSurface : SettingsChrome.onSurfaceVariant)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selected ? Color.white : Color.clear)
                        .shadow(color: selected ? .black.opacity(0.06) : .clear, radius: 2, y: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func commitTipDismissMinutes() {
        let parsed = Int(tipDismissText) ?? settings.tipDismissMinutes
        let clamped = min(
            max(parsed, MeetingSettings.tipDismissMinutesRange.lowerBound),
            MeetingSettings.tipDismissMinutesRange.upperBound
        )
        settings.tipDismissMinutes = clamped
        settings.tipDismissMode = .afterMinutes
        tipDismissText = "\(clamped)"
        AppLog.info("Meeting", "开始后保留分钟已更新", [
            "minutes": clamped,
            "mode": settings.tipDismissMode.rawValue
        ])
    }

    // MARK: - 支持的平台

    private var supportedPlatformsCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.Meeting.platformsTitle)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(SettingsChrome.onSurface)
                        Text(L10n.Meeting.platformsSubtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(SettingsChrome.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Text(L10n.Meeting.platformsAllSupported)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(SettingsChrome.secondary)
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8)
                    ],
                    spacing: 8
                ) {
                    ForEach(MeetingPlatform.supportedForJoin) { platform in
                        platformInfoRow(platform)
                    }
                }
            }
            .padding(16)
        }
    }

    private func platformInfoRow(_ platform: MeetingPlatform) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(platform.accentColor)
                Image(systemName: platform.settingsSymbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 20, height: 20)

            Text(platform.shortDisplayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(SettingsChrome.onSurface)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(SettingsChrome.surfaceContainerLow.opacity(0.70))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(SettingsChrome.cardStroke.opacity(0.85), lineWidth: SettingsChrome.cardStrokeWidth)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(platform.shortDisplayName)
    }

    // MARK: - 自定义会议

    private var customAppsCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.Meeting.customTitle)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(SettingsChrome.onSurface)
                    Text(L10n.Meeting.customSubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    // 名称 / 链接共用同一套 placeholder 灰；链接文案避免 https://，否则 AppKit 会当成超链接标蓝变黑。
                    TextField(
                        "",
                        text: $customName,
                        prompt: Text(L10n.Meeting.customNamePlaceholder)
                            .foregroundStyle(SettingsChrome.placeholder)
                    )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .focused($focusedField, equals: .customName)
                        .onSubmit { focusedField = .customLink }
                        .frame(maxWidth: 180)

                    TextField(
                        "",
                        text: $customLink,
                        prompt: Text(L10n.Meeting.customLinkPlaceholder)
                            .foregroundStyle(SettingsChrome.placeholder)
                    )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .focused($focusedField, equals: .customLink)
                        .onSubmit {
                            resignFields()
                            commitCustomApp()
                        }

                    Button {
                        resignFields()
                        commitCustomApp()
                    } label: {
                        Label(L10n.Common.add, systemImage: "plus")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(SettingsChrome.primary)
                    .disabled(
                        customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || customLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }

                if let customError {
                    Text(customError)
                        .font(.system(size: 11))
                        .foregroundStyle(SettingsChrome.error)
                }

                if !settings.customApps.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(settings.customApps) { app in
                            HStack(spacing: 10) {
                                Image(systemName: "link")
                                    .font(.system(size: 12))
                                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                                Text(app.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(SettingsChrome.onSurface)
                                    .lineLimit(1)
                                Text(app.domain)
                                    .font(.system(size: 11).monospaced())
                                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Button {
                                    resignFields()
                                    settings.removeCustomApp(id: app.id)
                                    customError = nil
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 12))
                                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                                }
                                .buttonStyle(.plain)
                                .help(L10n.Common.delete)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(SettingsChrome.surfaceContainerLow.opacity(0.70))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(SettingsChrome.cardStroke.opacity(0.85), lineWidth: SettingsChrome.cardStrokeWidth)
                                    )
                            )
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func commitCustomApp() {
        if let error = settings.addCustomApp(name: customName, sampleLink: customLink) {
            customError = error
            AppLog.warn("Meeting", "添加自定义会议失败", ["reason": error])
            return
        }
        customError = nil
        customName = ""
        customLink = ""
    }
}

// MARK: - Platform UI helpers

private extension MeetingPlatform {
    var shortDisplayName: String {
        switch self {
        case .teams: return L10n.Meeting.platformTeamsShort
        case .googleMeet: return L10n.Meeting.platformGoogleMeet
        case .tencentMeeting: return L10n.Meeting.platformTencent
        case .lark: return L10n.Meeting.platformLark
        case .dingTalk: return L10n.Meeting.platformDingTalk
        default: return displayName
        }
    }

    var settingsSymbol: String {
        switch self {
        case .zoom: return "video.fill"
        case .googleMeet: return "phone.fill"
        case .teams: return "person.3.fill"
        case .webex: return "desktopcomputer"
        case .faceTime: return "video.badge.waveform.fill"
        case .tencentMeeting: return "video.fill"
        case .lark: return "paperplane.fill"
        case .dingTalk: return "bolt.fill"
        case .custom, .generic: return "link"
        }
    }

    var accentColor: Color {
        switch self {
        case .zoom: return Color(red: 0.176, green: 0.549, blue: 1.0)
        case .googleMeet: return Color(red: 0.0, green: 0.537, blue: 0.482)
        case .teams: return Color(red: 0.357, green: 0.373, blue: 0.780)
        case .webex: return Color(red: 0.0, green: 0.565, blue: 0.792)
        case .faceTime: return Color(red: 0.20, green: 0.78, blue: 0.35)
        case .tencentMeeting: return Color(red: 0.0, green: 0.322, blue: 0.851)
        case .lark: return Color(red: 0.0, green: 0.839, blue: 0.725)
        case .dingTalk: return Color(red: 0.0, green: 0.498, blue: 1.0)
        case .custom, .generic: return Color.secondary
        }
    }
}
