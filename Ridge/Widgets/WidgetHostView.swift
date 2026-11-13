import SwiftUI

/// 岛展开区宿主：当前页内容。
/// 分页点改到岛左上 / 右上角（见 `IslandPageCornerDots`）；左右切换仍由 AppKit 拖拽 / 触控板横滑处理。
/// 尺寸由各页内容自行撑开，禁止在此铺 `maxWidth/maxHeight: .infinity`。
struct WidgetHostView: View {
    @ObservedObject var runtime: WidgetRuntime

    var body: some View {
        Group {
            if runtime.isControlDeckPage {
                ControlDeckIslandView()
                    .id(runtime.contentEpoch)
            } else if runtime.isShowingEmpty || !runtime.isComboPage {
                runtime.activeView()
                    .id(runtime.contentEpoch)
            } else {
                WidgetPageGridView(
                    placements: runtime.visiblePlacements,
                    runtime: runtime
                )
                .id(runtime.contentEpoch)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: runtime.pageIndex)
        .contentShape(Rectangle())
    }
}

/// 4×2 固定板：按 placement 绝对定位；未放满也按一行四格顺序排。
/// 画布宽高由网格自己给出，供岛壳测量。
private struct WidgetPageGridView: View {
    let placements: [WidgetGridPlacement]
    @ObservedObject var runtime: WidgetRuntime

    private var canvasSize: CGSize {
        WidgetGridBoard.preferredContentSize
    }

    var body: some View {
        let metrics = WidgetGridBoard.cellMetrics(
            forWidth: canvasSize.width + WidgetGridBoard.contentHorizontalInset
        )
        let cellW = metrics.cellWidth
        let cellH = metrics.cellHeight
        let gridW = cellW * CGFloat(WidgetGridBoard.columns)
            + WidgetGridBoard.spacing * CGFloat(WidgetGridBoard.columns - 1)
        let gridH = cellH * CGFloat(WidgetGridBoard.rows)
            + WidgetGridBoard.spacing * CGFloat(WidgetGridBoard.rows - 1)
        let originX = (canvasSize.width - gridW) / 2
        let originY = max((canvasSize.height - gridH) / 2, 0)

        ZStack(alignment: .topLeading) {
            ForEach(placements) { placement in
                let frame = cellFrame(
                    placement: placement,
                    cellW: cellW,
                    cellH: cellH,
                    originX: originX,
                    originY: originY
                )
                runtime.view(for: placement.id)
                    .padding(6)
                    .frame(width: frame.width, height: frame.height)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .position(x: frame.midX, y: frame.midY)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
    }

    private func cellFrame(
        placement: WidgetGridPlacement,
        cellW: CGFloat,
        cellH: CGFloat,
        originX: CGFloat,
        originY: CGFloat
    ) -> CGRect {
        let x = originX
            + CGFloat(placement.column) * (cellW + WidgetGridBoard.spacing)
        let y = originY
            + CGFloat(placement.row) * (cellH + WidgetGridBoard.spacing)
        let w = CGFloat(placement.size.columns) * cellW
            + CGFloat(placement.size.columns - 1) * WidgetGridBoard.spacing
        let h = CGFloat(placement.size.rows) * cellH
            + CGFloat(placement.size.rows - 1) * WidgetGridBoard.spacing
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

/// 岛左上 / 右上角分页点：左边 = 当前页之前的页数，右边 = 之后的页数。
struct IslandPageCornerDots: View {
    @ObservedObject var runtime: WidgetRuntime
    @Environment(\.islandPalette) private var palette

    private var leadingCount: Int {
        max(0, runtime.pageIndex)
    }

    private var trailingCount: Int {
        max(0, runtime.pageIDs.count - runtime.pageIndex - 1)
    }

    var body: some View {
        let total = runtime.pageIDs.count
        // 瞬时通知 / 媒体展开态不显示角点（媒体仍可左右滑翻页）。
        let hideDots = runtime.isTransientNoticePage
            || runtime.activeID == LiveIslandGate.mediaID
        if !runtime.isShowingEmpty, !hideDots, total > 1 {
            HStack(spacing: 0) {
                dots(count: leadingCount, side: "leading")
                Spacer(minLength: 0)
                dots(count: trailingCount, side: "trailing")
            }
            .padding(.horizontal, 14)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.Widgets.pageDotsA11y)
            .accessibilityValue(
                String(
                    format: L10n.Widgets.pageDotsCornerValueFormat,
                    leadingCount,
                    trailingCount,
                    runtime.pageIndex + 1,
                    total
                )
            )
        }
    }

    private func dots(count: Int, side: String) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(palette.pageDotInactive)
                    .frame(width: 5, height: 5)
                    .accessibilityHidden(true)
                    .id("\(side)-\(index)")
            }
        }
    }
}
