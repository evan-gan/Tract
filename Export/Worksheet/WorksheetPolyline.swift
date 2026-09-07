import CoreGraphics

/// Polyline reduction — the "low poly" pass the worksheet runs over every stroke
/// before it does any geometry.
enum WorksheetPolyline {
    /// Ramer–Douglas–Peucker simplification.
    ///
    /// Handwriting is sampled at up to 240 Hz, so a stroke carries far more
    /// samples than a printed page can resolve. Dropping the ones that sit
    /// within `tolerance` of the chord keeps the shape, and everything
    /// downstream — hulls, packing, drawing — then works on a tenth of the
    /// points.
    ///
    /// - Parameters:
    ///   - points: Polyline in canvas points.
    ///   - tolerance: Largest perpendicular deviation to discard. 0 keeps every sample.
    /// - Returns: The kept points in order; the endpoints are always kept.
    static func simplified(_ points: [CGPoint], tolerance: CGFloat) -> [CGPoint] {
        guard tolerance > 0, points.count >= 3 else { return points }

        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true

        // An explicit stack rather than recursion: a single stroke can carry
        // hundreds of samples and the split nests as deep as it has points.
        var pendingRanges = [(start: 0, end: points.count - 1)]
        let toleranceSquared = tolerance * tolerance

        while let range = pendingRanges.popLast() {
            guard range.end - range.start >= 2 else { continue }

            var farthestIndex = -1
            var farthestDistanceSquared = toleranceSquared
            for index in (range.start + 1) ..< range.end {
                let distance = StrokeGeometry.distance(
                    from: points[index],
                    toSegment: points[range.start],
                    points[range.end]
                )
                if distance * distance > farthestDistanceSquared {
                    farthestDistanceSquared = distance * distance
                    farthestIndex = index
                }
            }

            guard farthestIndex != -1 else { continue }
            keep[farthestIndex] = true
            pendingRanges.append((range.start, farthestIndex))
            pendingRanges.append((farthestIndex, range.end))
        }

        return points.indices.filter { keep[$0] }.map { points[$0] }
    }
}
