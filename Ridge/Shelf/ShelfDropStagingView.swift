import AppKit
import SwiftUI

/// 瞬时暂存区：左栏空态用方案一；整岛拖入（磁吸）时整岛暂存入舱（不再提供隔空传送舱）。
struct ShelfDropStagingView: View {
    var highlighted: Bool = false
    /// 整岛拖入态（磁吸吸附）。
    var fillsIsland: Bool = false
    /// 铺满左栏矩形（方案一静息）。
    var fillsContainer: Bool = false

    @State private var shelfZoneTargeted = false

    private let accent = Color(red: 0.23, green: 0.51, blue: 0.96)
    private let accentBright = Color(red: 0.039, green: 0.518, blue: 1.0)
    private let glassHover = Color(red: 0.055, green: 0.106, blue: 0.192)

    var body: some View {
        Group {
            if fillsIsland {
                magneticActiveBody
            } else {
                idleSchemeOneBody
            }
        }
        .animation(.easeOut(duration: 0.18), value: highlighted || fillsIsland)
        .animation(.easeOut(duration: 0.12), value: shelfZoneTargeted)
        .accessibilityElement(children: fillsIsland ? .contain : .combine)
        .accessibilityLabel(fillsIsland ? L10n.Shelf.dropActiveHint : L10n.Shelf.dropHint)
        .accessibilityHint(fillsIsland ? L10n.Shelf.dropActiveDetail : L10n.Shelf.dropHintDetail)
    }

    // MARK: - 方案一：左栏空态（垂直居中）

    private var idleSchemeOneBody: some View {
        VStack(spacing: 10) {
            idleIcon

            VStack(spacing: 4) {
                Text(L10n.Shelf.dropHint)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(L10n.Shelf.dropHintDetail)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.42))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: fillsContainer ? .infinity : nil, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.04), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            accent.opacity(0.32),
                            style: StrokeStyle(lineWidth: 1.2, dash: [6, 4])
                        )
                )
        )
    }

    private var idleIcon: some View {
        BobbingBadge(amplitude: 2.5, period: 2.0) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(nsColor: NSColor(calibratedWhite: 0.22, alpha: 0.85)),
                                Color(nsColor: NSColor(calibratedWhite: 0.12, alpha: 0.90))
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )

                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .frame(width: 44, height: 44)
        }
    }

    // MARK: - 磁吸整岛：仅暂存入舱

    private var magneticActiveBody: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(glassHover.opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(accent.opacity(0.40), lineWidth: 1.5)
                )
                .shadow(color: accentBright.opacity(0.22), radius: 28, y: 8)

            dropZone(
                title: L10n.Shelf.dropActiveHint,
                detail: L10n.Shelf.dropActiveDetail,
                symbol: "plus",
                tint: accent,
                targeted: shelfZoneTargeted,
                accessibilityLabel: L10n.Shelf.dropActiveHint
            )
            .onDrop(of: [.fileURL], isTargeted: $shelfZoneTargeted) { providers in
                AppLog.info("Shelf", "磁吸暂存区接收拖入", ["providers": providers.count])
                return ShelfClipboardDeckView.ingestDrop(providers: providers, into: ShelfStore.shared)
            }
            .padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: shelfZoneTargeted) { _, targeted in
            if targeted {
                IslandController.shared?.setShelfDropTargeted(true)
            }
        }
    }

    private func dropZone(
        title: String,
        detail: String,
        symbol: String,
        tint: Color,
        targeted: Bool,
        accessibilityLabel: String
    ) -> some View {
        VStack(spacing: 10) {
            BobbingBadge(amplitude: targeted ? 3.2 : 2.4, period: targeted ? 0.85 : 1.1) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(tint)
                        .shadow(color: tint.opacity(targeted ? 0.65 : 0.45), radius: targeted ? 14 : 10, y: 3)

                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)
            }

            VStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .tracking(0.2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(targeted ? 0.92 : 0.70))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(targeted ? 0.22 : 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(tint.opacity(targeted ? 0.95 : 0.55), lineWidth: targeted ? 2 : 1.4)
                )
                .shadow(color: tint.opacity(targeted ? 0.35 : 0.18), radius: targeted ? 16 : 10, y: 0)
        )
        .scaleEffect(targeted ? 1.02 : 1.0)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(detail)
    }
}

/// 整块徽章上下轻浮（蓝底 + 符号一起动）。
private struct BobbingBadge<Content: View>: View {
    var amplitude: CGFloat = 2.5
    var period: Double = 2.0
    @ViewBuilder var content: () -> Content

    @State private var bobbing = false

    var body: some View {
        content()
            .offset(y: bobbing ? amplitude : -amplitude)
            .onAppear {
                withAnimation(.easeInOut(duration: period).repeatForever(autoreverses: true)) {
                    bobbing = true
                }
            }
    }
}
