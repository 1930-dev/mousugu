import SwiftUI

/// Geometry of an overlap row — where each concurrent block sits inside the
/// band. Columns say *that* two events overlap; the vertical offset says *when*
/// each one starts, so a meeting beginning 45 minutes into the row is drawn
/// lower instead of level with the block it overlaps.
///
/// Pure value math on purpose: no EventKit, no views, so the placement can be
/// reasoned about (and checked) on its own.
enum OverlapLayout {
    /// How far a block drops per hour of delay. One row height per hour keeps a
    /// half-hour stagger plainly visible without turning a menu-bar popover
    /// into a full day grid.
    static let pointsPerHour: CGFloat = DesignSystem.Layout.eventRowHeight

    /// Any delay at all earns at least this much offset. Two meetings five
    /// minutes apart would otherwise round to the same line and read as
    /// simultaneous — the exact confusion this layout exists to remove.
    static let minimumStagger: CGFloat = DesignSystem.Spacing.md

    /// Ceiling for the row's total stagger. A row can span hours (a long
    /// meeting that keeps its width because it carries a join link), and the
    /// list compresses free time everywhere else too — between clusters a gap
    /// row states the duration rather than reserving it. Past this the scale
    /// shrinks uniformly, so the order and the proportions inside the row
    /// survive even though the absolute minutes no longer map to points.
    static let maximumStagger: CGFloat = 1.5 * DesignSystem.Layout.eventRowHeight

    /// Vertical offset for each block, given how long after the row's first
    /// start it begins. Monotonic in the delay: a later start is never drawn
    /// higher than an earlier one.
    static func offsets(delays: [TimeInterval]) -> [CGFloat] {
        let longest = delays.max() ?? 0
        guard longest > 0 else { return delays.map { _ in 0 } }
        let scale = min(pointsPerHour / 3600, maximumStagger / longest)
        return delays.map { $0 > 0 ? max(minimumStagger, CGFloat($0) * scale) : 0 }
    }

    /// Frames for one overlap row. Blocks must arrive column-major and in start
    /// order within each column, which is what greedy interval coloring
    /// produces.
    ///
    /// The time offset is a floor, not a fixed position: two events that share
    /// a column never overlap in time, so the later one is pushed below its
    /// predecessor whenever the scale would have drawn them on top of each
    /// other.
    static func frames(
        offsets: [CGFloat], heights: [CGFloat], columns: [Int],
        columnCount: Int, columnWidth: CGFloat, spacing: CGFloat
    ) -> [CGRect] {
        let count = max(columnCount, 1)
        var bottoms = [CGFloat](repeating: -spacing, count: count)
        var frames: [CGRect] = []
        for index in offsets.indices {
            let column = min(max(columns[index], 0), count - 1)
            let frame = CGRect(
                x: CGFloat(column) * (columnWidth + spacing),
                y: max(offsets[index], bottoms[column] + spacing),
                width: columnWidth,
                height: heights[index]
            )
            bottoms[column] = frame.maxY
            frames.append(frame)
        }
        return frames
    }
}

// The layout keys are read while SwiftUI measures, off the main actor, so they
// opt out of the project's default MainActor isolation (`SWIFT_DEFAULT_ACTOR_
// ISOLATION`) — an isolated conformance here is a hard error under Swift 6.

/// Column index a block belongs to inside its overlap row.
private nonisolated struct OverlapColumnKey: LayoutValueKey {
    static let defaultValue: Int = 0
}

/// Points the block drops to land on its own start time.
private nonisolated struct OverlapOffsetKey: LayoutValueKey {
    static let defaultValue: CGFloat = 0
}

extension View {
    /// Places this block in an overlap row: which column it shares the width
    /// with, and how far down its start time puts it.
    func overlapSlot(column: Int, offset: CGFloat) -> some View {
        layoutValue(key: OverlapColumnKey.self, value: column)
            .layoutValue(key: OverlapOffsetKey.self, value: offset)
    }
}

/// Lays overlapping events out like a day view's columns: equal-width columns
/// side by side, each block at the height its start time earns. Heights stay
/// intrinsic — a block is as tall as its content needs, not as tall as its
/// duration, so a 15-minute meeting keeps its title, time and join button.
struct TimeStaggeredColumns: Layout {
    let columnCount: Int
    var spacing: CGFloat = DesignSystem.Spacing.xs

    func sizeThatFits(
        proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) -> CGSize {
        let width = resolvedWidth(proposal, subviews: subviews)
        let height = frames(width: width, subviews: subviews).map(\.maxY).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        for (subview, frame) in zip(subviews, frames(width: bounds.width, subviews: subviews)) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    /// The row takes whatever width it is proposed. Asked for its ideal
    /// instead, it answers with one column's worth of ideal block per column —
    /// never a hardcoded popover width, which would inflate the ideal width of
    /// every stack above it.
    private func resolvedWidth(_ proposal: ProposedViewSize, subviews: Subviews) -> CGFloat {
        if let width = proposal.width { return width }
        let count = max(columnCount, 1)
        let widest = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        return widest * CGFloat(count) + spacing * CGFloat(count - 1)
    }

    private func frames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        let count = max(columnCount, 1)
        let columnWidth = max((width - spacing * CGFloat(count - 1)) / CGFloat(count), 0)
        return OverlapLayout.frames(
            offsets: subviews.map { $0[OverlapOffsetKey.self] },
            heights: subviews.map {
                $0.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height
            },
            columns: subviews.map { $0[OverlapColumnKey.self] },
            columnCount: count,
            columnWidth: columnWidth,
            spacing: spacing
        )
    }
}
