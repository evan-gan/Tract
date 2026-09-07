import CoreGraphics

/// Picks the one scale every problem is first drawn at.
///
/// One scale for all of them is the point — handwriting scaled per problem reads
/// as a different hand rather than as a layout. Enlarging past 1 is allowed and
/// often wanted: vector ink has no native size, so if three problems leave half
/// a sheet empty, the right answer is bigger writing, not whitespace.
///
/// The rule is **fewest pages first, then the largest text that still fits that
/// many pages.** Page count only ever falls as the scale falls, so the smallest
/// achievable count is the one at the readability floor, and the best scale is
/// found by bisecting against it.
enum WorksheetScaleSearch {
    private static let iterations = 40

    /// - Parameters:
    ///   - measurePageCount: Runs the layout at a scale and reports pages used.
    ///   - minimumScale: The readability floor. Must be greater than 0.
    ///   - maximumScale: How far ink may be enlarged.
    /// - Returns: The largest scale that still fits the page count achieved at
    ///   `minimumScale`. Falls back to `minimumScale` if the bisection finds
    ///   nothing, which can only happen if the page count is not monotonic.
    static func uniformScale(
        measurePageCount: (CGFloat) -> Int,
        minimumScale: CGFloat,
        maximumScale: CGFloat
    ) -> CGFloat {
        guard minimumScale > 0, maximumScale >= minimumScale else { return max(minimumScale, 0.01) }

        let targetPages = measurePageCount(minimumScale)
        if measurePageCount(maximumScale) <= targetPages { return maximumScale }

        var largestThatFits: CGFloat = 0
        var smallestThatDoesNot = maximumScale
        for _ in 0 ..< iterations {
            let candidate = (largestThatFits + smallestThatDoesNot) / 2
            if measurePageCount(candidate) <= targetPages {
                largestThatFits = candidate
            } else {
                smallestThatDoesNot = candidate
            }
        }
        return largestThatFits > 0 ? largestThatFits : minimumScale
    }
}
