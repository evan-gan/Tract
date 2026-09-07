import CoreGraphics

/// A convex polygon sliced into fixed-width columns: per column, how far its
/// upper and lower edges sit below the polygon's own top.
///
/// This is what the nesting packer stacks shapes against. Offsets are relative
/// to the polygon's top-left, so one profile can be dropped at any position on
/// the page — which is what lets a shape fall until *some* column touches
/// rather than until its corner does.
struct WorksheetColumnProfile {
    let columnCount: Int
    /// Distance from the shape's top to its upper edge, per column.
    let top: [CGFloat]
    /// Distance from the shape's top to its lower edge, per column.
    let bottom: [CGFloat]
    let width: CGFloat
    let height: CGFloat

    /// - Parameters:
    ///   - polygon: Convex polygon in page points.
    ///   - columnWidth: Slice width; smaller nests tighter and costs search time.
    init(polygon: [CGPoint], columnWidth: CGFloat) {
        let bounds = WorksheetPolygon.bounds(of: polygon)
        guard !bounds.isNull, columnWidth > 0 else {
            self.init(columnCount: 1, top: [0], bottom: [0], width: 0, height: 0)
            return
        }

        let columnCount = max(1, Int((bounds.width / columnWidth).rounded(.up)))
        var top = [CGFloat](repeating: 0, count: columnCount)
        var bottom = [CGFloat](repeating: 0, count: columnCount)

        for column in 0 ..< columnCount {
            let from = bounds.minX + CGFloat(column) * columnWidth
            let to = min(from + columnWidth, bounds.maxX)
            let extent = Self.verticalExtent(of: polygon, fromX: from, toX: to)
            top[column] = extent.top - bounds.minY
            bottom[column] = extent.bottom - bounds.minY
        }

        self.init(
            columnCount: columnCount,
            top: top,
            bottom: bottom,
            width: bounds.width,
            height: bounds.height
        )
    }

    private init(columnCount: Int, top: [CGFloat], bottom: [CGFloat], width: CGFloat, height: CGFloat) {
        self.columnCount = columnCount
        self.top = top
        self.bottom = bottom
        self.width = width
        self.height = height
    }

    /// Highest and lowest the polygon reaches anywhere in an x slice: its own
    /// vertices inside the slice, plus where its edges cross the slice's sides.
    private static func verticalExtent(
        of polygon: [CGPoint],
        fromX: CGFloat,
        toX: CGFloat
    ) -> (top: CGFloat, bottom: CGFloat) {
        let slack = WorksheetPolygon.coincident
        var top = CGFloat.greatestFiniteMagnitude
        var bottom = -CGFloat.greatestFiniteMagnitude
        var found = false

        func record(_ y: CGFloat) {
            top = min(top, y)
            bottom = max(bottom, y)
            found = true
        }

        for vertex in polygon where vertex.x >= fromX - slack && vertex.x <= toX + slack {
            record(vertex.y)
        }
        for index in polygon.indices {
            let current = polygon[index]
            let next = polygon[(index + 1) % polygon.count]
            for edgeX in [fromX, toX] {
                if let y = edgeCrossingY(from: current, to: next, atX: edgeX) { record(y) }
            }
        }

        // Only possible for a degenerate polygon that misses the slice entirely.
        return found ? (top, bottom) : (0, 0)
    }

    private static func edgeCrossingY(from: CGPoint, to: CGPoint, atX x: CGFloat) -> CGFloat? {
        let slack = WorksheetPolygon.coincident
        let spanX = to.x - from.x
        guard abs(spanX) >= slack else { return abs(from.x - x) < slack ? from.y : nil }

        let along = (x - from.x) / spanX
        guard along >= -slack, along <= 1 + slack else { return nil }
        return from.y + along * (to.y - from.y)
    }
}
