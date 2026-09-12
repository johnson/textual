import SwiftUI

extension StructuredText {
  /// A layout description for a rendered table.
  ///
  /// StructuredText computes a TableLayout from the measured sizes of each cell and provides
  /// it to StructuredText.TableStyle when rendering table backgrounds and overlays. Styles
  /// can use it to draw dividers or row backgrounds that align with the table grid.
  ///
  /// A windowed (virtualized) table only measures the cells it renders, so the layout describes
  /// the realized rows/columns only and indexes them from rowIndices/columnIndices.
  public struct TableLayout: Hashable {
    private struct Row: Hashable {
      var minY: CGFloat
      var height: CGFloat
    }

    private struct Column: Hashable {
      var minX: CGFloat
      var width: CGFloat
    }

    /// The bounding rectangle that contains the whole table.
    public let bounds: CGRect

    /// The measured row indices for this table.
    public var rowIndices: Range<Int> { rowBase..<(rowBase + rows.count) }

    /// The measured column indices for this table.
    public var columnIndices: Range<Int> { columnBase..<(columnBase + columns.count) }

    /// The number of rows in the table.
    public var numberOfRows: Int { rows.count }

    /// The number of columns in the table.
    public var numberOfColumns: Int { columns.count }

    private let rows: [Row]
    private let columns: [Column]
    private let rowBase: Int
    private let columnBase: Int

    init(_ cellBounds: [TableCell.Identifier: Anchor<CGRect>], geometry: GeometryProxy) {
      self.init(cellBounds.mapValues { geometry[$0] })
    }

    init(_ cellBounds: [TableCell.Identifier: CGRect] = [:]) {
      // Index measured rows/columns from the smallest realized index so the
      // backing arrays stay proportional to the rendered window, not to the
      // absolute row number (which can be in the thousands).
      let minRow = cellBounds.keys.map(\.row).min() ?? 0
      let maxRow = cellBounds.keys.map(\.row).max() ?? -1
      let minColumn = cellBounds.keys.map(\.column).min() ?? 0
      let maxColumn = cellBounds.keys.map(\.column).max() ?? -1

      let rowCount = maxRow >= minRow ? maxRow - minRow + 1 : 0
      let columnCount = maxColumn >= minColumn ? maxColumn - minColumn + 1 : 0

      var rows = Array(
        repeating: Row(minY: .greatestFiniteMagnitude, height: 0),
        count: rowCount
      )
      var columns = Array(
        repeating: Column(minX: .greatestFiniteMagnitude, width: 0),
        count: columnCount
      )

      for (identifier, bounds) in cellBounds {
        let row = identifier.row - minRow
        let column = identifier.column - minColumn
        guard row >= 0, row < rows.count, column >= 0, column < columns.count else {
          continue
        }

        rows[row].minY = min(rows[row].minY, bounds.minY)
        rows[row].height = max(rows[row].height, bounds.height)

        columns[column].minX = min(columns[column].minX, bounds.minX)
        columns[column].width = max(columns[column].width, bounds.width)
      }

      self.rowBase = minRow
      self.columnBase = minColumn
      self.rows = rows
      self.columns = columns
      self.bounds = cellBounds.values.reduce(CGRect.null, CGRectUnion)
    }

    /// Returns the bounds of the cell at the given row and column.
    public func cellBounds(row: Int, column: Int) -> CGRect {
      let row = row - rowBase
      let column = column - columnBase
      guard row >= 0, row < rows.count, column >= 0, column < columns.count else {
        return .null
      }

      let rowBox = rows[row]
      let columnBox = columns[column]
      guard rowBox.minY != .greatestFiniteMagnitude,
        columnBox.minX != .greatestFiniteMagnitude
      else {
        return .null
      }

      return CGRect(
        origin: .init(x: columnBox.minX, y: rowBox.minY),
        size: CGSize(width: columnBox.width, height: rowBox.height)
      )
    }

    /// Returns the bounds of the given row.
    public func rowBounds(_ row: Int) -> CGRect {
      columnIndices
        .map { cellBounds(row: row, column: $0) }
        .filter { !$0.isNull }
        .reduce(.null, CGRectUnion)
    }

    /// Returns the bounds of the given column.
    public func columnBounds(_ column: Int) -> CGRect {
      rowIndices
        .map { cellBounds(row: $0, column: column) }
        .filter { !$0.isNull }
        .reduce(.null, CGRectUnion)
    }

    /// Returns rectangles representing vertical dividers between columns.
    public func verticalDividers() -> [CGRect] {
      guard columns.count > 1 else { return [] }

      var dividers: [CGRect] = []

      for index in columns.indices.dropLast() {
        guard columns[index].minX != .greatestFiniteMagnitude,
          columns[index + 1].minX != .greatestFiniteMagnitude
        else {
          continue
        }

        let leftMaxX = columns[index].minX + columns[index].width
        let rightMinX = columns[index + 1].minX

        let width = rightMinX - leftMaxX
        guard width > 0 else { continue }

        dividers.append(
          CGRect(
            x: leftMaxX,
            y: bounds.minY,
            width: width,
            height: bounds.height
          )
        )
      }

      return dividers
    }

    /// Returns rectangles representing horizontal dividers between rows.
    public func horizontalDividers() -> [CGRect] {
      guard rows.count > 1 else { return [] }

      var dividers: [CGRect] = []

      for index in rows.indices.dropLast() {
        guard rows[index].minY != .greatestFiniteMagnitude,
          rows[index + 1].minY != .greatestFiniteMagnitude
        else {
          continue
        }

        let topMaxY = rows[index].minY + rows[index].height
        let bottomMinY = rows[index + 1].minY

        let height = bottomMinY - topMaxY
        guard height > 0 else { continue }

        dividers.append(
          CGRect(
            x: bounds.minX,
            y: topMaxY,
            width: bounds.width,
            height: height
          )
        )
      }

      return dividers
    }

    /// Returns rectangles for all dividers in the table.
    public func dividers() -> [CGRect] {
      horizontalDividers() + verticalDividers()
    }
  }
}
