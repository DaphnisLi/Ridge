import AppKit
import SwiftUI

/// 事后补填标题：待填 / 输入保存；快捷标签来自历史标题频次。
struct FocusTimerTitleBackfillCard: View {
    let record: FocusTimerRecord
    var badgeText: String
    var badgeTint: Color
    var barTint: Color
    /// 历史高频标题；空则不展示快捷行。
    var suggestedTitles: [String] = []
    var isEditing: Bool
    var draft: Binding<String>
    var onBeginEdit: () -> Void
    var onSave: (String) -> Void
    var onCancel: () -> Void

    @FocusState private var titleFieldFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                editingBody
            } else {
                pendingBody
            }
        }
        .onChange(of: isEditing) { _, editing in
            if editing {
                focusTitleFieldSoon()
            } else {
                titleFieldFocused = false
            }
        }
    }

    // MARK: - 待填

    private var pendingBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                badgeChip(badgeText, tint: badgeTint)
                HStack(spacing: 4) {
                    Image(systemName: "pencil")
                        .font(.system(size: 10, weight: .semibold))
                    Text(L10n.FocusTimer.fillTitleAction)
                        .font(SettingsChrome.Font.footnote)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(SettingsChrome.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(SettingsChrome.primary.opacity(0.08))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(
                                    SettingsChrome.primary.opacity(0.45),
                                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                                )
                        )
                )
                Spacer(minLength: 4)
                Text(FocusTimerFormatting.clock(record.totalMinutes * 60))
                    .font(SettingsChrome.Font.monoEmphasis)
                    .foregroundStyle(
                        record.endedEarly ? SettingsChrome.error : SettingsChrome.onSurface
                    )
            }

            HStack(spacing: 6) {
                Text(shortTimeRangeText)
                    .font(SettingsChrome.Font.footnote)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                Spacer(minLength: 4)
                HStack(spacing: 3) {
                    Image(systemName: record.endedEarly ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text(
                        record.endedEarly
                            ? L10n.FocusTimer.endedEarlyStatus
                            : L10n.FocusTimer.finishedOnTimeStatus
                    )
                    .font(SettingsChrome.Font.footnote)
                    .fontWeight(.medium)
                }
                .foregroundStyle(record.endedEarly ? SettingsChrome.error : SettingsChrome.secondary)
            }

            pendingProgressBar

            if record.overtimeMinutes > 0 {
                HStack(spacing: 6) {
                    Text(L10n.FocusTimer.overtimePlusMinutes(record.overtimeMinutes))
                        .font(SettingsChrome.Font.monoCaption)
                        .fontWeight(.bold)
                        .foregroundStyle(SettingsChrome.secondary)
                    Spacer(minLength: 4)
                    Text(L10n.FocusTimer.achievePercent(record.achievementPercent))
                        .font(SettingsChrome.Font.monoCaption)
                        .fontWeight(.bold)
                        .foregroundStyle(
                            record.endedEarly
                                ? SettingsChrome.error
                                : Color(red: 0.45, green: 0.27, blue: 0.0)
                        )
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(
                                    record.endedEarly
                                        ? SettingsChrome.error.opacity(0.12)
                                        : Color(red: 1.0, green: 0.90, blue: 0.70).opacity(0.85)
                                )
                        )
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SettingsChrome.surfaceContainerLow)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            SettingsChrome.primary.opacity(0.22),
                            style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                        )
                )
        )
        // 点整张待填卡即进入编辑并聚焦输入框，无需再点一次。
        .onTapGesture(perform: onBeginEdit)
    }

    private var pendingProgressBar: some View {
        let height: CGFloat = record.overtimeMinutes > 0 && !record.endedEarly ? 10 : 6
        return Group {
            if record.endedEarly {
                let planned = max(record.plannedMinutes, 1)
                let ratio = min(1, CGFloat(record.totalMinutes) / CGFloat(planned))
                GeometryReader { geo in
                    Capsule()
                        .fill(SettingsChrome.surfaceContainer)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(SettingsChrome.error)
                                .frame(width: max(4, geo.size.width * ratio))
                        }
                }
                .frame(height: height)
            } else if record.overtimeMinutes > 0 {
                let schedule = max(record.plannedMinutes + record.overtimeMinutes, 1)
                let base = CGFloat(record.plannedMinutes) / CGFloat(schedule)
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        Capsule()
                            .fill(SettingsChrome.primary)
                            .frame(width: max(8, geo.size.width * base - 1))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.96, green: 0.62, blue: 0.04),
                                        Color(red: 1.0, green: 0.80, blue: 0.35),
                                        SettingsChrome.secondary
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(8, geo.size.width * (1 - base) - 1))
                    }
                }
                .frame(height: height)
            } else {
                GeometryReader { geo in
                    Capsule()
                        .fill(SettingsChrome.surfaceContainer)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(SettingsChrome.secondary)
                                .frame(width: geo.size.width)
                        }
                }
                .frame(height: height)
            }
        }
    }

    // MARK: - 输入保存

    private var editingBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                badgeChip(badgeText, tint: badgeTint)
                Spacer(minLength: 4)
                Text(FocusTimerFormatting.clock(record.totalMinutes * 60))
                    .font(SettingsChrome.Font.monoEmphasis)
                    .foregroundStyle(SettingsChrome.onSurface)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField(L10n.FocusTimer.fillTitlePlaceholder, text: draft)
                        .textFieldStyle(.plain)
                        .font(SettingsChrome.Font.body)
                        .foregroundStyle(SettingsChrome.onSurface)
                        .focused($titleFieldFocused)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(SettingsChrome.cardBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(SettingsChrome.outline, lineWidth: 1)
                                )
                        )
                        .onSubmit { commitSave() }

                    Button(action: commitSave) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                            Text(L10n.FocusTimer.saveTitle)
                                .font(SettingsChrome.Font.label)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(SettingsChrome.primary)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(
                        draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? 0.45
                            : 1
                    )

                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(SettingsChrome.onSurfaceVariant)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle().fill(SettingsChrome.surfaceContainer)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(L10n.FocusTimer.escToClose)
                }

                if !suggestedTitles.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(suggestedTitles, id: \.self) { tag in
                            Button {
                                draft.wrappedValue = tag
                                titleFieldFocused = true
                                AppLog.debug("FocusTimer", "选用历史标题", ["len": tag.count])
                            } label: {
                                Text(tag)
                                    .font(SettingsChrome.Font.footnote)
                                    .fontWeight(.medium)
                                    .foregroundStyle(SettingsChrome.onSurface)
                                    .lineLimit(1)
                            }
                            .buttonStyle(FocusTimerQuickTagButtonStyle())
                        }
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(SettingsChrome.surfaceContainer.opacity(0.85))
            )
            // 点输入区空白处也聚焦输入框，避免还要再点一次。
            .onTapGesture {
                focusTitleFieldSoon()
            }

            HStack {
                Text(timeRangeText)
                    .font(SettingsChrome.Font.footnote)
                    .foregroundStyle(SettingsChrome.onSurfaceVariant)
                Spacer(minLength: 4)
            }

            HStack(spacing: 8) {
                Capsule()
                    .fill(barTint)
                    .frame(height: 8)
                Text(FocusTimerFormatting.compactDuration(record.totalMinutes))
                    .font(SettingsChrome.Font.monoCaption)
                    .foregroundStyle(SettingsChrome.outline)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SettingsChrome.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(SettingsChrome.primary.opacity(0.28), lineWidth: 1)
                )
        )
        .onAppear {
            focusTitleFieldSoon()
        }
        .onExitCommand(perform: onCancel)
    }

    /// 等编辑态视图挂上后再抢焦点，否则首帧 TextField 还没就绪。
    private func focusTitleFieldSoon() {
        DispatchQueue.main.async {
            titleFieldFocused = true
        }
    }

    private func commitSave() {
        let trimmed = draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSave(trimmed)
    }

    private var timeRangeText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm"
        return L10n.FocusTimer.timeRange(
            f.string(from: record.startedAt),
            f.string(from: record.endedAt)
        )
    }

    /// 看板二行：HH:mm - HH:mm（与具名行一致）。
    private var shortTimeRangeText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm"
        return "\(f.string(from: record.startedAt)) - \(f.string(from: record.endedAt))"
    }

    private func badgeChip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(SettingsChrome.Font.monoCaption)
            .fontWeight(.semibold)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(tint.opacity(0.14))
            )
    }
}

/// 历史标题胶囊：加深底色 + 按下缩放 / 加深。
private struct FocusTimerQuickTagButtonStyle: ButtonStyle {
    private let idle = Color(nsColor: NSColor(calibratedWhite: 0.78, alpha: 1))
    private let pressed = Color(nsColor: NSColor(calibratedWhite: 0.68, alpha: 1))

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(configuration.isPressed ? pressed : idle)
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
