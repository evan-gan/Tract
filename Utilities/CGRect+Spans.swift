import CoreGraphics

extension CGRect {
    /// Whether this rect covers every point of another, *including* flat ones.
    ///
    /// `CGRect.contains(_:)` answers false for any rect with no width or height,
    /// which is exactly what a single mark or a perfectly straight stroke has —
    /// so it cannot be used to reject geometry that lies outside a region.
    func spans(_ other: CGRect) -> Bool {
        other.minX >= minX && other.maxX <= maxX
            && other.minY >= minY && other.maxY <= maxY
    }
}
