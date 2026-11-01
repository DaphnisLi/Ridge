import AppKit
import EventKit
import SwiftUI

/// 嵌入「下一场会议」小组件预览页的配置区（含岛预览）。
struct MeetingWidgetConfigSection: View {
    @ObservedObject private var settings = MeetingSettings.shared
    @ObservedObject private var calendar = MeetingCalendarService.shared
    @State private var leadText: String = ""
    @State private var customName: String = ""
    @State private var customLink: String = ""
    @State private var customError: String?
    @State private var isRequestingAuth = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case leadMinutes
        case customName
        case customLink
    }

    private let leadPresets = [5, 10, 15]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            islandPreviewCard
            authCard
            leadMinutesCard
            supportedPlatformsCard
            customAppsCard

            HStack {
                Spacer(minLength: 0)
                Button("恢复默认设置") {
                    resignFields()
                    settings.restoreDefaults()
                    leadText = "\(settings.leadMinutes)"
                    AppLog.info("Meeting", "用户恢复默认设置")
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(SettingsChrome.onSurfaceVariant)
            }
            .padding(.top, 4)
        }
        .onAppear {
            leadText = "\(settings.leadMinutes)"
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
        .onChange(of: focusedField) { old, new in
            if old == .leadMinutes, new != .leadMinutes {
                commitLeadMinutes()
            }
        }
    }

    private func resignFields() {
        focusedField = nil
    }

    // MARK: - 岛预览

    private var islandPreviewCard: some View {
        SettingsCard {
            VStack(spacing: 0) {
                // 设计稿样张：始终展示「有会议」状态，不用真日历空态。
                MeetingIslandPreviewCapsule(leadMinutes: settings.leadMinutes)
                .padding(.horizontal, 20)
                .padding(.vertical, 22)
            }
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [
                        SettingsChrome.surfaceContainerLow,
                        SettingsChrome.surfaceContainer.opacity(0.50)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    // MARK: - 日历授权

    private var authCard: some View {
        SettingsCard {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(SettingsChrome.secondary.opacity(0.15))
                    Image(systemName: "calendar")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SettingsChrome.secondary)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text("系统日历访问权限")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(SettingsChrome.onSurface)
                    Text(authDescription)
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                authAction
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private var authAction: some View {
        switch calendar.authStatus {
        case .authorized:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(SettingsChrome.secondary)
                Text("已授权")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SettingsChrome.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(SettingsChrome.secondary.opacity(0.12))
            )
        case .notDetermined:
            Button {
                guard !isRequestingAuth else { return }
                resignFields()
                isRequestingAuth = true
                AppLog.info("Meeting", "设置页点击请求日历权限")
                Task {
                    _ = await calendar.requestAccess()
                    isRequestingAuth = false
                }
            } label: {
                if isRequestingAuth {
                    Text("请求中…")
                        .font(.system(size: 12, weight: .medium))
                } else {
                    Label("允许访问系统日历", systemImage: "key.fill")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(SettingsChrome.primary)
            .disabled(isRequestingAuth)
        case .denied, .restricted:
            Button("打开系统设置") {
                resignFields()
                calendar.openSystemPrivacySettings()
                AppLog.info("Meeting", "设置页打开系统日历隐私")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var authDescription: String {
        switch calendar.authStatus {
        case .authorized:
            return "用于读取本地日历、iCloud、Exchange 与同步会议日程"
        case .notDetermined:
            return "用于读取本地日历、iCloud、Exchange 与同步会议日程"
        case .denied, .restricted:
            return "日历权限未开启，请在系统设置中允许 Ridge 访问"
        }
    }

    // MARK: - 提前提醒

    private var leadMinutesCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("提前提醒时间")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(SettingsChrome.onSurface)
                        Text("会议开始前在灵动岛显示入会按钮")
                            .font(.system(size: 12))
                            .foregroundStyle(SettingsChrome.onSurfaceVariant)
                    }
                    Spacer(minLength: 8)
                    Text("提前 \(settings.leadMinutes) 分钟")
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
                            Text(minutes == 10 ? "\(minutes) 分钟 (推荐)" : "\(minutes) 分钟")
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
                        Text("分")
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

    // MARK: - 支持的平台

    private var supportedPlatformsCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("支持的会议平台")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(SettingsChrome.onSurface)
                        Text("自动从日程详情中识别入会链接，轻点即可调起客户端")
                            .font(.system(size: 12))
                            .foregroundStyle(SettingsChrome.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Text("全部已支持")
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
                    Text("自定义会议应用与链接")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(SettingsChrome.onSurface)
                    Text("添加会议名称与完整会议链接；将按域名识别后续日程，加入时打开日历中的链接。")
                        .font(.system(size: 12))
                        .foregroundStyle(SettingsChrome.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    // 名称 / 链接共用同一套 placeholder 灰；链接文案避免 https://，否则 AppKit 会当成超链接标蓝变黑。
                    TextField(
                        "",
                        text: $customName,
                        prompt: Text("会议名称（例如：Jitsi Meet）")
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
                        prompt: Text("完整会议链接（例如：meet.jit.si/…）")
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
                        Label("添加", systemImage: "plus")
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
                                .help("删除")
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

// MARK: - 岛胶囊预览（设计稿样张：有会议 + 入会）

private struct MeetingIslandPreviewCapsule: View {
    /// 与「提前提醒」联动的样张倒计时。
    let leadMinutes: Int

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.10))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                Image(systemName: "video.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("周度产研协同同步会")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("Zoom")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.white.opacity(0.10))
                        )
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(red: 0.157, green: 0.784, blue: 0.251))
                        .frame(width: 6, height: 6)
                    Text("\(max(leadMinutes, 1)) 分钟后开始")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(Color(red: 0.20, green: 0.83, blue: 0.60))
                    Text("· 14:00 - 15:30")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
            }

            Spacer(minLength: 8)

            Text("进入会议")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.white))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: 540)
        .background(
            MeetingIslandPreviewShape(bottomRadius: 26)
                .fill(Color.black.opacity(0.92))
                .overlay(
                    MeetingIslandPreviewShape(bottomRadius: 26)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
        )
        .clipShape(MeetingIslandPreviewShape(bottomRadius: 26))
    }
}

/// 设置页预览岛：顶部直角贴齐（仿刘海），仅底部圆角。
private struct MeetingIslandPreviewShape: Shape, InsettableShape {
    var bottomRadius: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let radius = max(0, min(bottomRadius, r.height / 2, r.width / 2) - insetAmount)
        var path = Path()
        path.move(to: CGPoint(x: r.minX, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        path.addArc(
            center: CGPoint(x: r.maxX - radius, y: r.maxY - radius),
            radius: radius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: r.minX + radius, y: r.maxY))
        path.addArc(
            center: CGPoint(x: r.minX + radius, y: r.maxY - radius),
            radius: radius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> MeetingIslandPreviewShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

// MARK: - Platform UI helpers

private extension MeetingPlatform {
    var shortDisplayName: String {
        switch self {
        case .teams: return "MS Teams"
        case .googleMeet: return "Google Meet"
        case .tencentMeeting: return "腾讯会议"
        case .lark: return "飞书会议"
        case .dingTalk: return "钉钉会议"
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
