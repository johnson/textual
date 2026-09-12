import SwiftUI

#if os(macOS)
import AppKit
typealias VirtualFont = NSFont
#elseif os(iOS) || os(tvOS) || os(visionOS)
import UIKit
typealias VirtualFont = UIFont
#endif

extension StructuredText {
  /// Precomputed geometry for the windowed (virtualized) table render path.
  ///
  /// Column widths and row heights are measured directly from the parsed cell
  /// text with CoreText, so a very large table never has to lay out every cell
  /// to discover its geometry. The values mirror the padding applied by
  /// GitHubTableCellStyle (13pt horizontal, 6pt vertical, 0.25 line spacing).
  struct VirtualTableGeometry: Equatable {
    var columnWidths: [CGFloat]
    var rowHeights: [CGFloat]
    var rowOffsets: [CGFloat]
    var totalSize: CGSize
  }

  /// The platform font used to measure large-table geometry.
  ///
  /// Pass the font the preview actually renders with so column widths stay exact
  /// for custom families. A nil familyName means the system font; if the family
  /// cannot be resolved, measurement fails and the table falls back to the exact
  /// Grid path.
  public struct TableFont: Hashable, Sendable {
    /// The font family name, or nil for the system font.
    public var familyName: String?
    /// The point size to measure at.
    public var pointSize: CGFloat

    public init(familyName: String? = nil, pointSize: CGFloat) {
      self.familyName = familyName
      self.pointSize = pointSize
    }
  }
}

private struct TableMeasurementFontKey: EnvironmentKey {
  static let defaultValue: StructuredText.TableFont? = nil
}

extension EnvironmentValues {
  var tableMeasurementFont: StructuredText.TableFont? {
    get { self[TableMeasurementFontKey.self] }
    set { self[TableMeasurementFontKey.self] = newValue }
  }
}

private struct TableVirtualizationKey: EnvironmentKey {
  static let defaultValue = true
}

extension EnvironmentValues {
  /// Whether very large tables render through the windowed path.
  var tableVirtualizationEnabled: Bool {
    get { self[TableVirtualizationKey.self] }
    set { self[TableVirtualizationKey.self] = newValue }
  }
}

#if os(macOS) || os(iOS) || os(tvOS) || os(visionOS)
extension StructuredText {
  enum VirtualTableMeasurer {
    static let horizontalPadding: CGFloat = 13
    static let verticalPadding: CGFloat = 6
    static let lineSpacingRatio: CGFloat = 0.25

    /// Resolves the configured font, or nil when a named family cannot be loaded.
    static func resolveBaseFont(_ descriptor: TableFont?) -> VirtualFont? {
      guard let descriptor else {
        return VirtualFont.preferredFont(forTextStyle: .body)
      }
      if let family = descriptor.familyName, !family.isEmpty {
        #if os(macOS)
        return NSFont(name: family, size: descriptor.pointSize)
        #else
        return UIFont(name: family, size: descriptor.pointSize)
        #endif
      }
      return VirtualFont.systemFont(ofSize: descriptor.pointSize)
    }

    static func withTraits(_ font: VirtualFont, bold: Bool, italic: Bool) -> VirtualFont {
      guard bold || italic else { return font }
      #if os(macOS)
      var traits = font.fontDescriptor.symbolicTraits
      if bold { traits.insert(.bold) }
      if italic { traits.insert(.italic) }
      return NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits), size: font.pointSize) ?? font
      #else
      var traits = font.fontDescriptor.symbolicTraits
      if bold { traits.insert(.traitBold) }
      if italic { traits.insert(.traitItalic) }
      if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
        return UIFont(descriptor: descriptor, size: font.pointSize)
      }
      return font
      #endif
    }

    static func font(base: VirtualFont, bold: Bool, italic: Bool, code: Bool) -> VirtualFont {
      if code {
        return VirtualFont.monospacedSystemFont(
          ofSize: base.pointSize,
          weight: bold ? .semibold : .regular
        )
      }
      return withTraits(base, bold: bold, italic: italic)
    }

    static func attributedString(
      for slice: AttributedSubstring,
      header: Bool,
      base: VirtualFont
    ) -> NSAttributedString {
      let result = NSMutableAttributedString()
      for run in slice.runs {
        let intent = run.inlinePresentationIntent
        let code = intent?.contains(.code) ?? false
        let bold = header || (intent?.contains(.stronglyEmphasized) ?? false)
        let italic = intent?.contains(.emphasized) ?? false
        let font = font(base: base, bold: bold, italic: italic, code: code)
        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        if intent?.contains(.strikethrough) == true {
          attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        result.append(
          NSAttributedString(string: String(slice[run.range].characters), attributes: attributes)
        )
      }
      if result.length == 0 {
        result.append(NSAttributedString(string: "", attributes: [.font: base]))
      }
      let paragraph = NSMutableParagraphStyle()
      paragraph.lineSpacing = base.pointSize * lineSpacingRatio
      result.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: result.length))
      return result
    }

    static func measuredSize(_ string: NSAttributedString, width: CGFloat) -> CGSize {
      let rect = string.boundingRect(
        with: CGSize(width: width, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        context: nil
      )
      return CGSize(width: ceil(rect.width), height: ceil(rect.height))
    }

    static func measure(
      content: AttributedSubstring,
      intent: PresentationIntent.IntentType?,
      columns: [PresentationIntent.TableColumn],
      spacing: TableCell.Spacing,
      font fontDescriptor: TableFont?
    ) -> VirtualTableGeometry? {
      guard let base = resolveBaseFont(fontDescriptor) else { return nil }

      let rowRuns = content.blockRuns(parent: intent)
      guard !rowRuns.isEmpty else { return nil }

      var rows: [[NSAttributedString]] = []
      rows.reserveCapacity(rowRuns.count)
      var columnCount = columns.count
      for (index, rowRun) in rowRuns.enumerated() {
        let rowContent = content[rowRun.range]
        let columnRuns = rowContent.blockRuns(parent: rowRun.intent)
        columnCount = max(columnCount, columnRuns.count)
        rows.append(
          columnRuns.map { attributedString(for: rowContent[$0.range], header: index == 0, base: base) }
        )
      }
      guard columnCount > 0 else { return nil }

      var textWidths = [CGFloat](repeating: 0, count: columnCount)
      for row in rows {
        for (column, cell) in row.enumerated() where column < columnCount {
          let width = measuredSize(cell, width: .greatestFiniteMagnitude).width
          textWidths[column] = max(textWidths[column], width)
        }
      }
      let columnWidths = textWidths.map { $0 + 2 * horizontalPadding }

      var rowHeights = [CGFloat](repeating: 0, count: rows.count)
      for (index, row) in rows.enumerated() {
        var height: CGFloat = 0
        for (column, cell) in row.enumerated() where column < columnCount {
          let contentWidth = max(columnWidths[column] - 2 * horizontalPadding, 1)
          height = max(height, measuredSize(cell, width: contentWidth).height)
        }
        rowHeights[index] = height + 2 * verticalPadding
      }

      let verticalGap = spacing.vertical ?? 0
      let horizontalGap = spacing.horizontal ?? 0
      var offsets = [CGFloat](repeating: 0, count: rows.count)
      var y: CGFloat = 0
      for index in rows.indices {
        offsets[index] = y
        y += rowHeights[index] + verticalGap
      }
      let totalHeight = max(y - (rows.isEmpty ? 0 : verticalGap), 0)
      let totalWidth =
        columnWidths.reduce(0, +) + CGFloat(max(columnCount - 1, 0)) * horizontalGap

      return VirtualTableGeometry(
        columnWidths: columnWidths,
        rowHeights: rowHeights,
        rowOffsets: offsets,
        totalSize: CGSize(width: totalWidth, height: totalHeight)
      )
    }
  }
}
#endif
