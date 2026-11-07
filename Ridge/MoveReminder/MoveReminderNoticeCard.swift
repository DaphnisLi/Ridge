import SwiftUI

/// 久坐起身提醒岛内卡片（根视图无外圈 padding，边距由壳层 / 预览舞台提供）。
struct MoveReminderNoticeCard: View {
    let notice: MoveReminderSession.Notice
    /// 设置样张：仍画出按钮，但不触发真实 snooze / mute。
    var isPreview: Bool = false

    private let amber = Color(red: 1.0, green: 0.584, blue: 0.0) // #ff9500
    private let amberSoft = Color(red: 1.0, green: 0.702, blue: 0.251) // #ffb340
    private let amberLabel = Color(red: 1.0, green: 0.910, blue: 0.839) // #ffe8d6
    private let subtitle = Color(red: 0.894, green: 0.722, blue: 0.588) // #e4b896
    private let ringTrack = Color(red: 0.259, green: 0.141, blue: 0.082) // #422415
    private let iconWell = Color(red: 0.169, green: 0.094, blue: 0.063) // #2b1810

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            progressGlyph
            textBlock
                .layoutPriority(3)
            actionButtons
                .fixedSize()
                .layoutPriority(2)
        }
        // 贴合内容宽：预览舞台才能在黑岛两侧留出灰底空隙
        .fixedSize(horizontal: true, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(L10n.MoveReminder.noticeTitle(notice.activeMinutes))，\(L10n.MoveReminder.noticeSubtitle(notice.restMinutes))"
        )
    }

    private var progressGlyph: some View {
        ZStack {
            Circle()
                .fill(iconWell)
                .frame(width: 36, height: 36)
                .overlay(
                    Circle()
                        .strokeBorder(amber.opacity(0.40), lineWidth: 1)
                )
            Circle()
                .stroke(ringTrack, lineWidth: 3.2)
                .frame(width: 36, height: 36)
            Circle()
                .trim(from: 0, to: 0.80)
                .stroke(amber, style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 36, height: 36)
            Image(systemName: "figure.stand")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(red: 1.0, green: 0.624, blue: 0.039)) // #ff9f0a
        }
        .frame(width: 36, height: 36)
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(L10n.MoveReminder.noticeTitle(notice.activeMinutes))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(L10n.MoveReminder.noticeBadge)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(amberSoft)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(amber.opacity(0.20))
                            .overlay(Capsule().strokeBorder(amber.opacity(0.35), lineWidth: 1))
                    )
            }
            Text(L10n.MoveReminder.noticeSubtitle(notice.restMinutes))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(subtitle.opacity(0.90))
                .lineLimit(1)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button {
                guard !isPreview else { return }
                AppLog.info("MoveReminder", "通知：稍后 10 分钟")
                MoveReminderSession.shared.snoozeTenMinutes()
            } label: {
                Text(L10n.MoveReminder.snoozeTen)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(amberLabel)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(amber.opacity(0.25))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(amber.opacity(0.30), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            .disabled(isPreview)

            Button {
                guard !isPreview else { return }
                AppLog.info("MoveReminder", "通知：今天不再提醒")
                MoveReminderSession.shared.muteForToday()
            } label: {
                Text(L10n.MoveReminder.muteToday)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isPreview)
        }
    }

    static func previewSample(
        activeMinutes: Int = 30,
        restMinutes: Int = 2
    ) -> some View {
        MoveReminderNoticeCard(
            notice: .init(
                id: "preview",
                activeMinutes: activeMinutes,
                restMinutes: restMinutes
            ),
            isPreview: true
        )
    }
}
