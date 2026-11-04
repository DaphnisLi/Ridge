import CoreGraphics
import Foundation

/// 小组件在岛内网格中的占位尺寸（以 1×1 格为单位）。
struct WidgetGridSize: Hashable, Codable, Equatable {
    var columns: Int
    var rows: Int

    static let oneByOne = WidgetGridSize(columns: 1, rows: 1)
    static let twoByOne = WidgetGridSize(columns: 2, rows: 1)
    static let oneByTwo = WidgetGridSize(columns: 1, rows: 2)
    static let twoByTwo = WidgetGridSize(columns: 2, rows: 2)

    var cellCount: Int { max(columns, 0) * max(rows, 0) }

    var isValid: Bool {
        columns >= 1 && columns <= WidgetGridBoard.columns
            && rows >= 1 && rows <= WidgetGridBoard.rows
    }

    init(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
    }
}

/// 一页固定 4×2 = 8 格；位置按顺序自动占位，不可自由拖格。
enum WidgetGridBoard {
    static let columns = 4
    static let rows = 2
    static let cellCount = columns * rows
    static let spacing: CGFloat = 6
    static let contentHorizontalInset: CGFloat = 24
    static let chromeHeight: CGFloat = 56

    /// 组合页内容画布宽度（不含 IslandChrome）；由网格自己撑开岛宽。
    static let preferredContentWidth: CGFloat = 560

    /// 组合页内容画布尺寸（仅网格区，不含壳层 chrome / padding）。
    static var preferredContentSize: CGSize {
        let metrics = cellMetrics(forWidth: preferredContentWidth + contentHorizontalInset)
        let gridH = metrics.cellHeight * CGFloat(rows) + spacing * CGFloat(rows - 1)
        return CGSize(width: preferredContentWidth, height: gridH)
    }

    /// 根据岛展开宽估算面板高度（含标题 / 分页点区域）。
    static func expandedPanelHeight(forWidth width: CGFloat) -> CGFloat {
        let metrics = cellMetrics(forWidth: width)
        let gridH = metrics.cellHeight * CGFloat(rows) + spacing * CGFloat(rows - 1)
        return chromeHeight + gridH
    }

    static func cellMetrics(forWidth width: CGFloat) -> (cellWidth: CGFloat, cellHeight: CGFloat) {
        let inner = max(width - contentHorizontalInset, CGFloat(columns) * 24)
        let cellW = (inner - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        // 略扁，适配刘海下有限高度。
        let cellH = cellW * 0.78
        return (cellW, cellH)
    }
}

/// 打包后的占位：原点 + 尺寸。
struct WidgetGridPlacement: Hashable, Identifiable {
    let id: WidgetID
    let column: Int
    let row: Int
    let size: WidgetGridSize

    var frameInCells: (x: Int, y: Int, w: Int, h: Int) {
        (column, row, size.columns, size.rows)
    }
}

enum WidgetGridPacker {
    /// 按传入顺序做左→右、上→下首适打包。装不下返回 `nil`。
    static func pack(_ items: [(id: WidgetID, size: WidgetGridSize)]) -> [WidgetGridPlacement]? {
        var occupied = Array(
            repeating: Array(repeating: false, count: WidgetGridBoard.columns),
            count: WidgetGridBoard.rows
        )
        var result: [WidgetGridPlacement] = []

        for item in items {
            guard item.size.isValid else { return nil }
            guard let origin = firstFit(size: item.size, occupied: occupied) else {
                return nil
            }
            mark(size: item.size, at: origin, occupied: &occupied, value: true)
            result.append(
                WidgetGridPlacement(
                    id: item.id,
                    column: origin.col,
                    row: origin.row,
                    size: item.size
                )
            )
        }
        return result
    }

    /// 估算一组尺寸是否装得进 8 格板。
    static func canFit(_ sizes: [WidgetGridSize]) -> Bool {
        let items = sizes.enumerated().map { (id: "\($0.offset)", size: $0.element) }
        return pack(items) != nil
    }

    private static func firstFit(
        size: WidgetGridSize,
        occupied: [[Bool]]
    ) -> (col: Int, row: Int)? {
        for row in 0..<WidgetGridBoard.rows {
            for col in 0..<WidgetGridBoard.columns {
                if fits(size: size, at: (col, row), occupied: occupied) {
                    return (col, row)
                }
            }
        }
        return nil
    }

    private static func fits(
        size: WidgetGridSize,
        at origin: (col: Int, row: Int),
        occupied: [[Bool]]
    ) -> Bool {
        let maxCol = origin.col + size.columns
        let maxRow = origin.row + size.rows
        guard maxCol <= WidgetGridBoard.columns, maxRow <= WidgetGridBoard.rows else {
            return false
        }
        for r in origin.row..<maxRow {
            for c in origin.col..<maxCol {
                if occupied[r][c] { return false }
            }
        }
        return true
    }

    private static func mark(
        size: WidgetGridSize,
        at origin: (col: Int, row: Int),
        occupied: inout [[Bool]],
        value: Bool
    ) {
        for r in origin.row..<(origin.row + size.rows) {
            for c in origin.col..<(origin.col + size.columns) {
                occupied[r][c] = value
            }
        }
    }
}
