import SwiftUI

/// A small eager grid for content tiles. Every tile in a multi-column grid
/// shares the tallest intrinsic height, including wrapped localized text.
/// Single-column presentations keep each tile's natural height so accessibility
/// sizes do not introduce empty space between short and long descriptions.
nonisolated struct EqualHeightTileLayout: Layout {
    enum Columns {
        case fixed(Int)
        case adaptive(minimum: CGFloat, maximum: CGFloat)
    }

    var columns: Columns
    var spacing: CGFloat = Space.s3

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let measurements = measure(width: proposal.width, subviews: subviews)
        return CGSize(width: measurements.width, height: measurements.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let measurements = measure(width: bounds.width, subviews: subviews)
        var rowY = bounds.minY
        for index in subviews.indices {
            let column = index % measurements.columnCount
            let height = measurements.heights[index]
            let offset = CGFloat(column) * (measurements.columnWidth + spacing)
            // SwiftUI mirrors custom-layout placement in right-to-left locales.
            // Place in its physical coordinate space to avoid mirroring twice.
            let x = bounds.minX + offset
            subviews[index].place(at: CGPoint(x: x, y: rowY), anchor: .topLeading,
                                  proposal: ProposedViewSize(width: measurements.columnWidth, height: height))
            if column == measurements.columnCount - 1 {
                rowY += height + spacing
            }
        }
    }

    private struct Measurements {
        let width: CGFloat
        let columnWidth: CGFloat
        let columnCount: Int
        let heights: [CGFloat]
        let height: CGFloat
    }

    private func measure(width proposedWidth: CGFloat?, subviews: Subviews) -> Measurements {
        let width = resolvedWidth(proposedWidth, subviews: subviews)
        let columnCount: Int
        let columnWidth: CGFloat
        switch columns {
        case .fixed(let count):
            columnCount = max(1, count)
            columnWidth = max(0, width - CGFloat(columnCount - 1) * spacing) / CGFloat(columnCount)
        case .adaptive(let minimum, let maximum):
            let fittingCount = floor((width + spacing) / (max(1, minimum) + spacing))
            columnCount = max(1, Int(min(CGFloat(subviews.count), fittingCount)))
            columnWidth = min(maximum, max(0, width - CGFloat(columnCount - 1) * spacing) / CGFloat(columnCount))
        }
        let intrinsicHeights = subviews.map {
            let height = $0.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height
            return height.isFinite ? max(0, height) : 0
        }
        let heights = columnCount == 1
            ? intrinsicHeights
            : Array(repeating: intrinsicHeights.max() ?? 0, count: subviews.count)
        let rowCount = (subviews.count + columnCount - 1) / columnCount
        let contentHeight = columnCount == 1
            ? heights.reduce(0, +)
            : CGFloat(rowCount) * (heights.first ?? 0)
        return Measurements(width: width, columnWidth: columnWidth, columnCount: columnCount,
                            heights: heights, height: contentHeight + CGFloat(rowCount - 1) * spacing)
    }

    /// SwiftUI also asks for ideal or unbounded sizes. Resolve those using the
    /// children's intrinsic widths rather than reporting an infinite grid size.
    private func resolvedWidth(_ proposedWidth: CGFloat?, subviews: Subviews) -> CGFloat {
        if let proposedWidth, proposedWidth.isFinite { return max(0, proposedWidth) }
        let intrinsicWidth = subviews.map {
            let width = $0.sizeThatFits(.unspecified).width
            return width.isFinite ? max(0, width) : 0
        }.max() ?? 0
        switch columns {
        case .fixed(let count):
            let count = max(1, count)
            return CGFloat(count) * intrinsicWidth + CGFloat(count - 1) * spacing
        case .adaptive(let minimum, let maximum):
            return min(maximum, max(minimum, intrinsicWidth))
        }
    }
}
