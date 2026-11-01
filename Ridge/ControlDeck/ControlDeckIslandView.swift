import SwiftUI

/// 岛上控制台页：控制中心式功能磁贴（占位布局，后续接真实模块）。
struct ControlDeckIslandView: View {
    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 8
            let colW = (geo.size.width - gap * 2) / 3
            let rowH = (geo.size.height - gap) / 2

            VStack(spacing: gap) {
                HStack(spacing: gap) {
                    mediaPlaceholder
                        .frame(width: colW * 2 + gap, height: rowH)
                    weatherPlaceholder
                        .frame(width: colW, height: rowH)
                }
                HStack(spacing: gap) {
                    batteryPlaceholder
                        .frame(width: colW, height: rowH)
                    togglesPlaceholder
                        .frame(width: colW, height: rowH)
                    metersPlaceholder
                        .frame(width: colW, height: rowH)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("控制台")
    }

    private var mediaPlaceholder: some View {
        deckCard {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.pink.opacity(0.35))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundStyle(.white.opacity(0.9))
                    )
                VStack(alignment: .leading, spacing: 4) {
                    Text("正在播放")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("媒体控制即将接入")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Capsule()
                        .fill(Color.pink.opacity(0.55))
                        .frame(height: 3)
                        .frame(maxWidth: 72, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var weatherPlaceholder: some View {
        deckCard {
            VStack(alignment: .leading, spacing: 4) {
                Label("天气", systemImage: "cloud.sun.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.skyBlue)
                Text("--°")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("稍后接入")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var batteryPlaceholder: some View {
        deckCard {
            HStack(spacing: 10) {
                ring(symbol: "laptopcomputer", progress: 0.82, tint: .green)
                ring(symbol: "keyboard", progress: 0.28, tint: .red)
                ring(symbol: "magicmouse.fill", progress: 0.64, tint: .white.opacity(0.85))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var togglesPlaceholder: some View {
        deckCard {
            VStack(spacing: 6) {
                toggleRow(symbol: "cup.and.saucer.fill", title: "防休眠", tint: .yellow)
                toggleRow(symbol: "timer", title: "专注", tint: .red)
                toggleRow(symbol: "mic.slash.fill", title: "静音麦", tint: .secondary)
            }
        }
    }

    private var metersPlaceholder: some View {
        deckCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "cpu")
                        .foregroundStyle(Color.skyBlue)
                    Text("系统")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer(minLength: 0)
                    Text("--%")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Capsule()
                    .fill(Color.skyBlue.opacity(0.25))
                    .frame(height: 4)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Color.skyBlue)
                            .frame(width: 36, height: 4)
                    }
                Text("CPU / 内存读数即将接入")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func deckCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.10))
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func ring(symbol: String, progress: CGFloat, tint: Color) -> some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.12), lineWidth: 3)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.9))
        }
        .frame(width: 34, height: 34)
    }

    private func toggleRow(symbol: String, title: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }
}

private extension Color {
    static let skyBlue = Color(red: 0.25, green: 0.55, blue: 0.95)
}
