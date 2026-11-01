import SwiftUI

/// 会议岛卡：设置页预览与岛上真机共用同一套布局（设计稿样张）。
struct MeetingIslandCardView: View {
    let title: String
    let platformBadge: String?
    let statusText: String
    let timeRangeText: String?
    let showJoin: Bool
    let showAuth: Bool
    var onJoin: (() -> Void)?
    var onRequestAuth: (() -> Void)?

    private let statusGreen = Color(red: 0.20, green: 0.83, blue: 0.60)
    private let pulseGreen = Color(red: 0.157, green: 0.784, blue: 0.251)

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
                    Text(title)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let platformBadge, !platformBadge.isEmpty {
                        Text(platformBadge)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.7))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.white.opacity(0.10))
                            )
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(pulseGreen)
                        .frame(width: 6, height: 6)
                    Text(statusText)
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(statusGreen)
                        .lineLimit(1)
                    if let timeRangeText, !timeRangeText.isEmpty {
                        Text("· \(timeRangeText)")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.white.opacity(0.4))
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 8)

            if showAuth {
                Button(action: { onRequestAuth?() }) {
                    Text(L10n.Common.authorize)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.white))
                }
                .buttonStyle(.plain)
            } else if showJoin {
                Button(action: { onJoin?() }) {
                    Text(L10n.Meeting.joinMeeting)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.white))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.Meeting.joinA11y)
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// 设置页样张。
    static func previewSample(leadMinutes: Int) -> MeetingIslandCardView {
        MeetingIslandCardView(
            title: L10n.Meeting.previewSampleTitle,
            platformBadge: L10n.Meeting.platformZoom,
            statusText: L10n.Meeting.previewMinutesAhead(max(leadMinutes, 1)),
            timeRangeText: "14:00 - 15:30",
            showJoin: true,
            showAuth: false
        )
    }
}
