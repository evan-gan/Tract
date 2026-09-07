import CoreGraphics

/// The packer: drops each problem's tension outline onto the page as high as it
/// will go, against a running height map rather than against a grid.
///
/// The page is sliced into narrow columns and the height map records how far
/// down each column is occupied. A shape carries the same slicing of itself, so
/// it can be dropped until *some* column touches rather than until its corner
/// does. That is what lets a wedge-shaped problem slide under a slanted
/// neighbour and a short one sit in the notch beside a tall one; bounding boxes
/// cannot express it.
///
/// Clearance comes from the padding baked into each outline, not from gaps
/// between rows, so problems end up as close as the ink allows.
enum WorksheetNester {
    /// Column width for the height map. Finer nests tighter and costs search time.
    static let columnWidth: CGFloat = 3

    /// Lays every block out at one uniform scale, in reading order.
    ///
    /// Only the **newest** sheet is offered a block. Letting a later problem
    /// drop back onto an earlier page fills a few percent more paper — but it
    /// puts 1b behind 1c, and a worksheet that jumps about is worse than a page
    /// that is not quite full. `refit` gives that space back instead.
    static func nest(
        _ blocks: [WorksheetBlock],
        page: WorksheetPageGeometry,
        padding: CGFloat,
        scale: CGFloat
    ) -> [WorksheetSheet] {
        guard !blocks.isEmpty else { return [] }

        var sheets: [WorksheetSheet] = [WorksheetSheet()]
        var heightMaps: [WorksheetHeightMap] = [WorksheetHeightMap(page: page)]

        for block in blocks {
            let shape = PackedShape(block: block, padding: padding, scale: scale)

            var index = sheets.count - 1
            var spot = heightMaps[index].lowestSpot(for: shape.profile, page: page)
            // Nothing left on this sheet: start another, unless this one is
            // already blank — a fresh sheet would be no roomier.
            if spot == nil, !sheets[index].placements.isEmpty {
                sheets.append(WorksheetSheet())
                heightMaps.append(WorksheetHeightMap(page: page))
                index = sheets.count - 1
                spot = heightMaps[index].lowestSpot(for: shape.profile, page: page)
            }

            // A problem too big for an empty page still gets drawn, at the
            // content origin — refusing it would loop forever.
            let restingSpot = spot ?? WorksheetRestingSpot(column: 0, y: page.contentRect.minY)
            sheets[index].placements.append(shape.placement(at: restingSpot, page: page))
            heightMaps[index].raise(to: restingSpot, profile: shape.profile)
        }

        return sheets
    }

    /// Re-nests each page's own problems at the largest scale that still fits
    /// them on that page — the coarse half of expand-to-fill.
    ///
    /// The run-wide scale is set by whichever page is tightest, which leaves
    /// every other page holding smaller ink than it had room for. Page
    /// assignment is settled by now, so each page can be packed again on its own
    /// terms: same problems, same order, as large as they go.
    ///
    /// Re-nesting rather than scaling the arrangement up matters — at a bigger
    /// scale the shapes interlock differently, and the packer finds arrangements
    /// a uniform blow-up cannot.
    static func refit(
        _ sheets: [WorksheetSheet],
        page: WorksheetPageGeometry,
        padding: CGFloat,
        cap: CGFloat
    ) -> [WorksheetSheet] {
        sheets.map { refitOneSheet($0, page: page, padding: padding, cap: cap) }
    }

    private static let refitIterations = 18

    private static func refitOneSheet(
        _ sheet: WorksheetSheet,
        page: WorksheetPageGeometry,
        padding: CGFloat,
        cap: CGFloat
    ) -> WorksheetSheet {
        let blocks = sheet.placements.map(\.block)
        let currentScale = sheet.placements.map(\.scale).max() ?? 0
        guard !blocks.isEmpty, currentScale < cap else { return sheet }

        let fitOntoOneSheet = { (scale: CGFloat) in
            nestOntoOneSheet(blocks, page: page, padding: padding, scale: scale)
        }
        if let atCap = fitOntoOneSheet(cap) { return atCap }

        var best: WorksheetSheet?
        var largestThatFits = currentScale
        var smallestThatDoesNot = cap
        for _ in 0 ..< refitIterations {
            let candidate = (largestThatFits + smallestThatDoesNot) / 2
            if let fitted = fitOntoOneSheet(candidate) {
                best = fitted
                largestThatFits = candidate
            } else {
                smallestThatDoesNot = candidate
            }
        }
        return best ?? sheet
    }

    /// Nests everything onto a single sheet, or reports failure by returning nil.
    private static func nestOntoOneSheet(
        _ blocks: [WorksheetBlock],
        page: WorksheetPageGeometry,
        padding: CGFloat,
        scale: CGFloat
    ) -> WorksheetSheet? {
        var sheet = WorksheetSheet()
        var heightMap = WorksheetHeightMap(page: page)

        for block in blocks {
            let shape = PackedShape(block: block, padding: padding, scale: scale)
            guard let spot = heightMap.lowestSpot(for: shape.profile, page: page) else { return nil }
            sheet.placements.append(shape.placement(at: spot, page: page))
            heightMap.raise(to: spot, profile: shape.profile)
        }
        return sheet
    }
}

/// Where a shape came to rest: which column its left edge starts in, and how far
/// down the page its top ended up.
struct WorksheetRestingSpot {
    let column: Int
    let y: CGFloat
}

/// How far down each column of the content box is already occupied.
struct WorksheetHeightMap {
    private var columns: [CGFloat]

    init(page: WorksheetPageGeometry) {
        // The rightmost sliver narrower than a column is left unused rather than
        // letting a shape overhang the margin.
        let count = max(1, Int(page.contentRect.width / WorksheetNester.columnWidth))
        columns = [CGFloat](repeating: page.contentRect.minY, count: count)
    }

    /// Drops the profile down every column position and keeps the one where it
    /// comes to rest highest up the page, ties going leftwards.
    /// - Returns: Nil when the shape does not fit anywhere on this page.
    func lowestSpot(
        for profile: WorksheetColumnProfile,
        page: WorksheetPageGeometry
    ) -> WorksheetRestingSpot? {
        let contentBottom = page.contentRect.maxY
        var best: WorksheetRestingSpot?

        for column in 0 ... max(columns.count - profile.columnCount, 0) {
            guard column + profile.columnCount <= columns.count else { break }

            var restingY = -CGFloat.greatestFiniteMagnitude
            for offset in 0 ..< profile.columnCount {
                // Its upper edge in this column must clear whatever is already there.
                restingY = max(restingY, columns[column + offset] - profile.top[offset])
            }
            if restingY + profile.height > contentBottom { continue }
            if best == nil || restingY < best!.y {
                best = WorksheetRestingSpot(column: column, y: restingY)
            }
        }
        return best
    }

    mutating func raise(to spot: WorksheetRestingSpot, profile: WorksheetColumnProfile) {
        for offset in 0 ..< profile.columnCount where spot.column + offset < columns.count {
            columns[spot.column + offset] = spot.y + profile.bottom[offset]
        }
    }
}

/// A block's shape at one scale — ink, badge and clearance — sliced into columns
/// ready to drop onto a height map.
///
/// The badge is reserved here, before anything is placed, which is what stops it
/// ever having to sit on a neighbour's handwriting.
private struct PackedShape {
    let block: WorksheetBlock
    let scale: CGFloat
    /// The outline in scaled canvas space, not yet moved onto the page.
    let bounds: CGRect
    let profile: WorksheetColumnProfile

    init(block: WorksheetBlock, padding: CGFloat, scale: CGFloat) {
        let outline = WorksheetPolygon.dilated(
            WorksheetBadge.outlineWithBadge(
                WorksheetPolygon.scaled(block.hull, by: scale),
                label: block.label
            ),
            by: padding
        )
        self.block = block
        self.scale = scale
        self.bounds = WorksheetPolygon.bounds(of: outline)
        self.profile = WorksheetColumnProfile(polygon: outline, columnWidth: WorksheetNester.columnWidth)
    }

    /// Converts an outline's resting place into the painted-box placement the
    /// renderer works in: the outline's top-left sits at the resting spot, and
    /// the box sits wherever it does relative to that outline.
    func placement(at spot: WorksheetRestingSpot, page: WorksheetPageGeometry) -> WorksheetPlacement {
        let outlineX = page.contentRect.minX + CGFloat(spot.column) * WorksheetNester.columnWidth
        return WorksheetPlacement(
            block: block,
            origin: CGPoint(
                x: outlineX + (block.bounds.minX * scale - bounds.minX),
                y: spot.y + (block.bounds.minY * scale - bounds.minY)
            ),
            scale: scale
        )
    }
}
