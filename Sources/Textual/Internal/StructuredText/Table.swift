import SwiftUI

// MARK: - Overview
//
// Table uses a two-pass layout system. The first pass renders cells which emit their bounds via
// preferences. The second pass collects all cell bounds, transforms them from anchor coordinates
// to geometry coordinates, and builds a `TableLayout` that the style uses to render overlays
// (such as grid lines) and backgrounds with precise cell positions.

extension StructuredText {
  struct Table: View {
    @Environment(\.tableStyle) private var tableStyle

    @State private var spacing = TableCell.Spacing()
    @State private var virtualGeometry: VirtualTableGeometry?

    private static let virtualizationThreshold = 64

    private let intent: PresentationIntent.IntentType?
    private let content: AttributedSubstring
    private let columns: [PresentationIntent.TableColumn]

    init(
      intent: PresentationIntent.IntentType?,
      content: AttributedSubstring,
      columns: [PresentationIntent.TableColumn]
    ) {
      self.intent = intent
      self.content = content
      self.columns = columns
    }

    var body: some View {
      let configuration = TableStyleConfiguration(
        label: .init(label),
        indentationLevel: indentationLevel
      )
      let resolvedStyle = tableStyle.resolve(configuration: configuration)
        .onPreferenceChange(TableCell.SpacingKey.self) { @MainActor in
          spacing = $0
        }

      AnyView(resolvedStyle)
    }

    @ViewBuilder
    private var label: some View {
      let rowRuns = content.blockRuns(parent: intent)

      if rowRuns.count > Self.virtualizationThreshold {
        if let geometry = virtualGeometry {
          virtualLabel(rowRuns: rowRuns, geometry: geometry)
        } else {
          Color.clear
            .frame(height: CGFloat(rowRuns.count) * 30)
            .onAppear(perform: measureVirtualGeometry)
        }
      } else {
        exactLabel(rowRuns: rowRuns)
      }
    }

    @ViewBuilder
    private func exactLabel(rowRuns: AttributedString.BlockRuns) -> some View {
      Grid(horizontalSpacing: spacing.horizontal, verticalSpacing: spacing.vertical) {
        ForEach(rowRuns.indices, id: \.self) { rowIndex in
          let rowRun = rowRuns[rowIndex]
          let rowContent = content[rowRun.range]
          let columnRuns = rowContent.blockRuns(parent: rowRun.intent)

          GridRow {
            ForEach(columnRuns.indices, id: \.self) { columnIndex in
              let cellRun = columnRuns[columnIndex]
              let cellContent = rowContent[cellRun.range]

              TableCell(cellContent, row: rowIndex, column: columnIndex)
                .gridColumnAlignment(alignment(for: columnIndex))
            }
          }
        }
      }
    }

    @ViewBuilder
    private func virtualLabel(rowRuns: AttributedString.BlockRuns, geometry: VirtualTableGeometry) -> some View {
      LazyVStack(alignment: .leading, spacing: spacing.vertical ?? 0) {
        ForEach(rowRuns.indices, id: \.self) { rowIndex in
          let rowRun = rowRuns[rowIndex]
          let rowContent = content[rowRun.range]
          let columnRuns = rowContent.blockRuns(parent: rowRun.intent)

          HStack(alignment: .top, spacing: spacing.horizontal ?? 0) {
            ForEach(columnRuns.indices, id: \.self) { columnIndex in
              let cellRun = columnRuns[columnIndex]
              let cellContent = rowContent[cellRun.range]
              let width = columnIndex < geometry.columnWidths.count
                ? geometry.columnWidths[columnIndex]
                : nil

              TableCell(cellContent, row: rowIndex, column: columnIndex)
                .frame(
                  width: width,
                  alignment: Alignment(horizontal: alignment(for: columnIndex), vertical: .top)
                )
            }
          }
          .frame(
            height: rowIndex < geometry.rowHeights.count ? geometry.rowHeights[rowIndex] : nil,
            alignment: .top
          )
        }
      }
      .frame(height: geometry.totalSize.height, alignment: .top)
    }

    private func measureVirtualGeometry() {
      guard virtualGeometry == nil else { return }
      #if os(macOS) || os(iOS) || os(tvOS) || os(visionOS)
      virtualGeometry = VirtualTableMeasurer.measure(
        content: content,
        intent: intent,
        columns: columns,
        spacing: spacing
      )
      #endif
    }

    private var indentationLevel: Int {
      content.runs.first?.presentationIntent?.indentationLevel ?? 0
    }

    private func alignment(for columnIndex: Int) -> HorizontalAlignment {
      guard columnIndex < columns.count else {
        return .leading
      }

      switch columns[columnIndex].alignment {
      case .left:
        return .leading
      case .center:
        return .center
      case .right:
        return .trailing
      @unknown default:
        return .leading
      }
    }
  }
}
