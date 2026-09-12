import CoreGraphics
import Foundation

/// Turns a problem's traced bubble into the dashed box it becomes while it is
/// being edited, and every shape in between.
///
/// A cross-fade between the two would read as one shape disappearing and
/// another arriving. What is wanted is the boundary *travelling* — the bubble
/// letting go of the handwriting and opening out to the box — so both outlines
/// are resampled onto the same number of points and each point walks to its
/// opposite number.
///
/// The correspondence is the whole problem, and it is solved by putting both
/// loops into the same canonical form: wound the same way, sampled at even
/// spacing along their own perimeters, and started at the point that lies due
/// east of the loop's centre. Two shapes prepared that way line up without any
/// search for a best match, which is what keeps this cheap enough to evaluate
/// on every frame of the transition.
enum ProblemFocusFrame {

    /// How many points each outline is resampled onto. High enough that a
    /// rounded corner stays round, low enough that the blend is a few hundred
    /// multiplications a frame.
    static let sampleCount = 128

    /// The bubble reduced to the form the blend needs, ready to be kept.
    ///
    /// Worth doing once and holding on to: the focused problem's bubble is
    /// frozen for as long as it is focused, so resampling it again on every
    /// frame of the transition would produce the same 128 points each time out
    /// of a contour that can run to thousands.
    ///
    /// - Parameter contours: The traced bubble. The largest loop is the one
    ///   that morphs; a problem whose work sits in separate patches leaves the
    ///   rest behind rather than tearing them towards the box.
    static func canonicalLoop(in contours: [[CGPoint]]) -> [CGPoint] {
        guard let largest = largestLoop(in: contours) else { return [] }
        return canonical(largest)
    }

    /// The outline part way between a bubble and its box.
    ///
    /// - Parameters:
    ///   - bubble: The problem's bubble in canonical form, from
    ///     `canonicalLoop(in:)`. Empty is allowed and gives the box.
    ///   - box: The dashed box, in canvas space.
    ///   - cornerRadius: The box's corner radius, in canvas units.
    ///   - progress: 0 is the bubble, 1 is the box.
    /// - Returns: One closed loop. Empty only when there is no box to draw.
    static func outline(
        from bubble: [CGPoint],
        to box: CGRect,
        cornerRadius: CGFloat,
        progress: CGFloat
    ) -> [CGPoint] {
        guard !box.isNull, !box.isEmpty else { return [] }
        let clamped = min(max(progress, 0), 1)
        guard !bubble.isEmpty else {
            return canonical(roundedRectLoop(box, cornerRadius: cornerRadius))
        }
        guard clamped > 0 else { return bubble }

        let boxLoop = canonical(roundedRectLoop(box, cornerRadius: cornerRadius))
        guard clamped < 1, bubble.count == boxLoop.count else { return boxLoop }
        return zip(bubble, boxLoop).map { start, end in
            CGPoint(
                x: start.x + (end.x - start.x) * clamped,
                y: start.y + (end.y - start.y) * clamped
            )
        }
    }

    /// The contour holding the most area — the problem's main body, as opposed
    /// to a stray mark that traced its own little island.
    static func largestLoop(in contours: [[CGPoint]]) -> [CGPoint]? {
        contours
            .filter { $0.count >= 3 }
            .max { abs(signedArea(of: $0)) < abs(signedArea(of: $1)) }
    }

    // MARK: - Canonical form

    /// One loop wound consistently, evenly sampled, and rotated to start due
    /// east of its own centre. Two loops in this form correspond point for
    /// point, which is what the blend above relies on.
    static func canonical(_ loop: [CGPoint]) -> [CGPoint] {
        guard loop.count >= 3 else { return [] }
        let wound = signedArea(of: loop) < 0 ? Array(loop.reversed()) : loop
        let evenlySpaced = resampled(wound, count: sampleCount)
        return rotatedToStartDueEast(evenlySpaced)
    }

    /// Twice the enclosed area, signed by winding direction. Only the sign is
    /// used, to get both loops going the same way round before they are paired
    /// up — paired against opposite windings, the blend turns itself inside out.
    static func signedArea(of loop: [CGPoint]) -> CGFloat {
        guard loop.count >= 3 else { return 0 }
        var total: CGFloat = 0
        for index in loop.indices {
            let current = loop[index]
            let next = loop[(index + 1) % loop.count]
            total += current.x * next.y - next.x * current.y
        }
        return total
    }

    /// `count` points spaced evenly along the loop's perimeter.
    ///
    /// Even spacing by *arc length* rather than by index is what makes the two
    /// outlines comparable: a marching-squares contour has its points bunched
    /// wherever the grid happened to cut it, and pairing raw indices would drag
    /// a crowded stretch of bubble onto a whole side of the box.
    static func resampled(_ loop: [CGPoint], count: Int) -> [CGPoint] {
        guard loop.count >= 3, count >= 3 else { return [] }
        let closed = loop + [loop[0]]

        var cumulativeLengths: [CGFloat] = [0]
        cumulativeLengths.reserveCapacity(closed.count)
        for index in 1 ..< closed.count {
            cumulativeLengths.append(
                cumulativeLengths[index - 1] + closed[index - 1].distance(to: closed[index])
            )
        }
        guard let perimeter = cumulativeLengths.last, perimeter > 0 else { return [] }

        var samples: [CGPoint] = []
        samples.reserveCapacity(count)
        // Walks forward with the target distance, so the whole resample is one
        // pass over the loop rather than a search per sample.
        var segment = 1
        for step in 0 ..< count {
            let target = perimeter * CGFloat(step) / CGFloat(count)
            while segment < cumulativeLengths.count - 1, cumulativeLengths[segment] < target {
                segment += 1
            }
            let spanStart = cumulativeLengths[segment - 1]
            let spanLength = cumulativeLengths[segment] - spanStart
            let fraction = spanLength > 0 ? (target - spanStart) / spanLength : 0
            let from = closed[segment - 1]
            let to = closed[segment]
            samples.append(CGPoint(
                x: from.x + (to.x - from.x) * fraction,
                y: from.y + (to.y - from.y) * fraction
            ))
        }
        return samples
    }

    /// Rotates the samples so the one lying closest to due east of the centroid
    /// comes first. An arbitrary but *shared* starting point: both loops pick
    /// theirs the same way, so the bubble's right-hand side travels to the box's
    /// right-hand side instead of the outline spinning as it opens out.
    static func rotatedToStartDueEast(_ samples: [CGPoint]) -> [CGPoint] {
        guard samples.count >= 3 else { return samples }
        let centre = centroid(of: samples)
        var bestIndex = 0
        var bestAngle = CGFloat.greatestFiniteMagnitude
        for (index, sample) in samples.enumerated() {
            // atan2 measured from +x, folded to a distance from zero so the
            // wrap at ±π cannot make two neighbouring points look far apart.
            let angle = abs(atan2(sample.y - centre.y, sample.x - centre.x))
            if angle < bestAngle {
                bestAngle = angle
                bestIndex = index
            }
        }
        return Array(samples[bestIndex...] + samples[..<bestIndex])
    }

    static func centroid(of points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let sum = points.reduce(CGPoint.zero) { $0 + $1 }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    // MARK: - The box as a loop

    /// A rounded rectangle traced as a polygon, densely enough that the
    /// resampler above sees smooth corners rather than chamfers.
    static func roundedRectLoop(_ rect: CGRect, cornerRadius: CGFloat) -> [CGPoint] {
        let radius = min(cornerRadius, min(rect.width, rect.height) / 2)
        guard radius > 0 else {
            return [
                CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.maxY),
                CGPoint(x: rect.minX, y: rect.maxY)
            ]
        }

        let cornersClockwiseFromTopLeft: [(centre: CGPoint, startAngle: CGFloat)] = [
            (CGPoint(x: rect.minX + radius, y: rect.minY + radius), .pi),
            (CGPoint(x: rect.maxX - radius, y: rect.minY + radius), -.pi / 2),
            (CGPoint(x: rect.maxX - radius, y: rect.maxY - radius), 0),
            (CGPoint(x: rect.minX + radius, y: rect.maxY - radius), .pi / 2)
        ]

        let stepsPerCorner = 10
        var loop: [CGPoint] = []
        loop.reserveCapacity(cornersClockwiseFromTopLeft.count * (stepsPerCorner + 1))
        for corner in cornersClockwiseFromTopLeft {
            for step in 0 ... stepsPerCorner {
                let angle = corner.startAngle
                    + (.pi / 2) * CGFloat(step) / CGFloat(stepsPerCorner)
                loop.append(CGPoint(
                    x: corner.centre.x + cos(angle) * radius,
                    y: corner.centre.y + sin(angle) * radius
                ))
            }
        }
        return loop
    }
}
