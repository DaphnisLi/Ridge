import SwiftUI

/// 岛展开区宿主：当前页内容 + 底部分页点。
/// 左右切换由 `IslandHitTestView` 的 AppKit 拖拽 / 触控板横滑处理。
struct WidgetHostView: View {
    @ObservedObject var runtime: WidgetRuntime
    @Environment(\.islandPalette) private var palette

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if runtime.isControlDeckPage {
                    ControlDeckIslandView()
                        .id(runtime.contentEpoch)
                } else if runtime.isShowingEmpty || !runtime.isComboPage {
                    // 空态 / 普通单组件页：铺满。
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.18), value: runtime.pageIndex)

            if !runtime.isShowingEmpty, runtime.pageIDs.count > 1 {
                HStack(spacing: 5) {
                    ForEach(Array(runtime.pageIDs.indices), id: \.self) { index in
                        Circle()
                            .fill(index == runtime.pageIndex
                                  ? palette.pageDotActive
                                  : palette.pageDotInactive)
                            .frame(width: 5, height: 5)
                    }
                }
                .padding(.bottom, 2)
                .accessibilityLabel(L10n.Widgets.pageDotsA11y)
            }
        }
        .contentShape(Rectangle())
    }
}

/// 4×2 固定板：按 placement 绝对定位；未放满也按一行四格顺序排。
private struct WidgetPageGridView: View {
    let placements: [WidgetGridPlacement]
    @ObservedObject var runtime: WidgetRuntime
    @Environment(\.islandPalette) private var palette

    var body: some View {
        GeometryReader { geo in
            let metrics = WidgetGridBoard.cellMetrics(forWidth: geo.size.width + WidgetGridBoard.contentHorizontalInset)
            let cellW = metrics.cellWidth
            let cellH = min(
                metrics.cellHeight,
                (geo.size.height - WidgetGridBoard.spacing) / CGFloat(WidgetGridBoard.rows)
            )
            let gridW = cellW * CGFloat(WidgetGridBoard.columns)
                + WidgetGridBoard.spacing * CGFloat(WidgetGridBoard.columns - 1)
            let gridH = cellH * CGFloat(WidgetGridBoard.rows)
                + WidgetGridBoard.spacing * CGFloat(WidgetGridBoard.rows - 1)
            let originX = (geo.size.width - gridW) / 2
            let originY = max((geo.size.height - gridH) / 2, 0)

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
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
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
