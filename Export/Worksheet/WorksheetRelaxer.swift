import CoreGraphics

/// The un-shrink pass — the fine half of expanding a layout to fill its pages.
///
/// The coarse half runs first (`WorksheetNester.refit`): each page is packed
/// again at the largest scale its own problems allow. What that cannot reach is
/// the space *between* problems, because re-nesting keeps everything one size.
/// This pass takes that: each problem grows on its own into whatever room its
/// neighbours and the margins actually leave.
///
/// Growth runs round-robin in small steps so the free space is *shared* rather
/// than eaten by whichever problem the reading order puts first, with a final
/// bisection per problem to take up the slack the step size leaves. Nothing
/// grows past the cap, and ink is never allowed to overlap ink.
enum WorksheetRelaxer {
    private static let growthStep: CGFloat = 1.04
    private static let maximumRounds = 60
    private static let squeezeIterations = 12
    private static let epsilon: CGFloat = 1e-6

    /// How far a problem may also *slide* as it grows, in page points.
    ///
    /// Anchors alone only let a problem expand away from one of its own corners,
    /// and free space on a page is rarely lined up with a corner — a problem
    /// with a bare patch down and to its left stays stuck because growing from
    /// any single corner runs into a neighbour first. The drift is bounded, and
    /// reading order is unaffected: the layout has already decided who sits where.
    private static let slideDistances: [CGFloat] = [6, 14, 26]

    private static let slideDirections: [CGPoint] = [
        CGPoint(x: -1, y: 0), CGPoint(x: 0, y: -1), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1),
        CGPoint(x: -1, y: -1), CGPoint(x: 1, y: -1), CGPoint(x: -1, y: 1), CGPoint(x: 1, y: 1)
    ]

    static func grown(
        _ sheets: [WorksheetSheet],
        page: WorksheetPageGeometry,
        padding: CGFloat,
        cap: CGFloat
    ) -> [WorksheetSheet] {
        sheets.map { sheet in
            WorksheetSheet(placements: grow(sheet.placements, page: page, padding: padding, cap: cap))
        }
    }

    private static func grow(
        _ placements: [WorksheetPlacement],
        page: WorksheetPageGeometry,
        padding: CGFloat,
        cap: CGFloat
    ) -> [WorksheetPlacement] {
        // Each entry caches its padded outline and its bare ink hull, so a
        // rejected candidate costs two hulls and no re-derivation.
        var state = placements.map { placement in
            Neighbour(
                placement: placement,
                outline: placement.outline(padding: padding),
                ink: placement.outline(padding: 0)
            )
        }
        let limits = Limits(
            page: page,
            padding: padding,
            // A packer can hand over neighbours already closer than the
            // clearance. Freezing those pairs would stop the whole page growing,
            // so they keep whatever spacing they arrived with and are held only
            // to the rule that always applies: ink must never overlap ink.
            alreadyTouching: touchingPairs(in: state)
        )

        for _ in 0 ..< maximumRounds {
            var anyGrew = false
            for index in state.indices {
                let stepped = min(state[index].placement.scale * growthStep, cap)
                if growTo(stepped, index: index, in: &state, limits: limits) { anyGrew = true }
            }
            if !anyGrew { break }
        }

        squeezeRemainingSlack(in: &state, limits: limits, cap: cap)
        return state.map(\.placement)
    }

    /// Bisection mops up the fraction of a step the round-robin could not take.
    private static func squeezeRemainingSlack(
        in state: inout [Neighbour],
        limits: Limits,
        cap: CGFloat
    ) {
        for index in state.indices {
            var largestThatFits = state[index].placement.scale
            var smallestThatDoesNot = cap
            guard largestThatFits < cap - epsilon else { continue }

            for _ in 0 ..< squeezeIterations {
                let candidate = (largestThatFits + smallestThatDoesNot) / 2
                if growTo(candidate, index: index, in: &state, limits: limits) {
                    largestThatFits = candidate
                } else {
                    smallestThatDoesNot = candidate
                }
            }
        }
    }

    /// Commits a bigger scale for one placement if any repositioning leaves the
    /// grown outline inside the margins and clear of every other problem.
    private static func growTo(
        _ candidateScale: CGFloat,
        index: Int,
        in state: inout [Neighbour],
        limits: Limits
    ) -> Bool {
        guard candidateScale > state[index].placement.scale + epsilon else { return false }

        for candidate in repositionings(of: state[index].placement, to: candidateScale) {
            let outline = candidate.outline(padding: limits.padding)
            guard isInsideContentBox(outline, page: limits.page) else { continue }

            let ink = candidate.outline(padding: 0)
            let grown = Neighbour(placement: candidate, outline: outline, ink: ink)
            guard !collides(grown, at: index, with: state, alreadyTouching: limits.alreadyTouching) else {
                continue
            }

            state[index] = grown
            return true
        }
        return false
    }

    /// Ways this problem could sit at the bigger scale, cheapest first: grow from
    /// each corner, then from the centre, then allow it to drift as well.
    private static func repositionings(
        of placement: WorksheetPlacement,
        to scale: CGFloat
    ) -> [WorksheetPlacement] {
        var candidates = WorksheetGrowthAnchor.allCases.map {
            placement.resized(to: scale, anchor: $0)
        }
        let centred = placement.resized(to: scale, anchor: .center)
        for distance in slideDistances {
            for direction in slideDirections {
                var drifted = centred
                drifted.origin = CGPoint(
                    x: centred.origin.x + direction.x * distance,
                    y: centred.origin.y + direction.y * distance
                )
                candidates.append(drifted)
            }
        }
        return candidates
    }

    private static func touchingPairs(in state: [Neighbour]) -> Set<NeighbourPair> {
        var touching: Set<NeighbourPair> = []
        for index in state.indices {
            for other in state.indices where other > index {
                if WorksheetPolygon.intersect(state[index].outline, state[other].outline) {
                    touching.insert(NeighbourPair(index, other))
                }
            }
        }
        return touching
    }

    private static func collides(
        _ candidate: Neighbour,
        at index: Int,
        with state: [Neighbour],
        alreadyTouching: Set<NeighbourPair>
    ) -> Bool {
        for other in state.indices where other != index {
            if alreadyTouching.contains(NeighbourPair(index, other)) {
                if WorksheetPolygon.intersect(candidate.ink, state[other].ink) { return true }
            } else if WorksheetPolygon.intersect(candidate.outline, state[other].outline) {
                return true
            }
        }
        return false
    }

    private static func isInsideContentBox(_ outline: [CGPoint], page: WorksheetPageGeometry) -> Bool {
        let bounds = WorksheetPolygon.bounds(of: outline)
        guard !bounds.isNull else { return true }
        let content = page.contentRect
        return bounds.minX >= content.minX - epsilon
            && bounds.minY >= content.minY - epsilon
            && bounds.maxX <= content.maxX + epsilon
            && bounds.maxY <= content.maxY + epsilon
    }

    /// One problem on the page as the growth pass holds it: where it sits, plus
    /// the two hulls every collision test needs.
    private struct Neighbour {
        var placement: WorksheetPlacement
        var outline: [CGPoint]
        var ink: [CGPoint]
    }

    private struct Limits {
        let page: WorksheetPageGeometry
        let padding: CGFloat
        let alreadyTouching: Set<NeighbourPair>
    }

    /// An unordered pair of placements on one page.
    private struct NeighbourPair: Hashable {
        let lower: Int
        let upper: Int

        init(_ first: Int, _ second: Int) {
            lower = min(first, second)
            upper = max(first, second)
        }
    }
}
