import CoreGraphics

/// Pure sizing and placement maths for pinned references. Everything is in
/// screen points except `inkBounds`, which is canvas space.
enum PinnedReferenceGeometry {
    /// A new pin's longer side, as a fraction of the screen along the same axis
    /// — a quarter of the width for wide ink, of the height for tall ink — so it
    /// is big enough to read and small enough to leave room to write.
    static let initialScreenFraction: CGFloat = 0.25
    /// Below this a pin stops being legible, and stops being easy to grab.
    static let minimumLongestSide: CGFloat = 96
    /// Fraction of the screen's shorter side a pin may grow to, so a pin can
    /// always be dragged somewhere it does not cover the work it is for.
    static let maximumScreenFraction: CGFloat = 0.9
    /// Floor on the shorter side: a single line of ink would otherwise make a
    /// sliver too thin to grab, or to fit the close and resize controls on.
    static let minimumShortSide: CGFloat = 64
    /// Breathing room between the ink and the card's edge.
    static let inkInset: CGFloat = 10
    /// A pin's highest possible enlargement of its ink. Without a ceiling, pinning
    /// a single tick mark would blow its nib up to fill the card.
    static let maximumInkScale: CGFloat = 40

    /// Where new pins land: under the top bar, at the leading edge, each
    /// subsequent one stepped down and in so none hides another.
    static let initialTopInset: CGFloat = 96
    static let initialEdgeMargin: CGFloat = 16
    static let cascadeStep: CGFloat = 24
    static let cascadeLength = 5

    static func initialLongestSide(inkSize: CGSize, viewport: CGSize) -> CGFloat {
        let isWide = inkSize.width >= inkSize.height
        let screenExtent = isWide ? viewport.width : viewport.height
        return clampedLongestSide(screenExtent * initialScreenFraction, viewport: viewport)
    }

    static func clampedLongestSide(_ proposed: CGFloat, viewport: CGSize) -> CGFloat {
        let screenLimit = min(viewport.width, viewport.height) * maximumScreenFraction
        let maximum = max(minimumLongestSide, screenLimit)
        return min(max(proposed, minimumLongestSide), maximum)
    }

    /// The card's size: the ink's aspect ratio with its longer side set to
    /// `longestSide`, and the shorter one floored at `minimumShortSide`.
    static func cardSize(inkSize: CGSize, longestSide: CGFloat) -> CGSize {
        let longInkSide = max(inkSize.width, inkSize.height)
        guard longInkSide > 0 else { return CGSize(width: longestSide, height: longestSide) }

        let proportionalShortSide = longestSide * min(inkSize.width, inkSize.height) / longInkSide
        let shortSide = max(proportionalShortSide, min(minimumShortSide, longestSide))
        return inkSize.width >= inkSize.height
            ? CGSize(width: longestSide, height: shortSide)
            : CGSize(width: shortSide, height: longestSide)
    }

    /// Pulls a centre back so the whole card stays on screen: a pin pushed at an
    /// edge stops against it rather than sliding partly out of frame.
    static func clampedCenter(_ proposed: CGPoint, cardSize: CGSize, viewport: CGSize) -> CGPoint {
        // Before the canvas has been measured there is nothing to clamp into.
        guard viewport.width > 0, viewport.height > 0 else { return proposed }
        return CGPoint(
            x: clamp(proposed.x, cardExtent: cardSize.width, screenExtent: viewport.width),
            y: clamp(proposed.y, cardExtent: cardSize.height, screenExtent: viewport.height)
        )
    }

    /// A card wider than the screen — only possible on a viewport shrunk after
    /// the pin was sized — is pinned to the leading edge rather than centred, so
    /// its × stays reachable.
    private static func clamp(_ center: CGFloat, cardExtent: CGFloat, screenExtent: CGFloat) -> CGFloat {
        let lowest = cardExtent / 2
        let highest = max(lowest, screenExtent - cardExtent / 2)
        return min(max(center, lowest), highest)
    }

    /// Where the `existingPinCount`-th pin goes when it is first made.
    static func initialCenter(cardSize: CGSize, viewport: CGSize, existingPinCount: Int) -> CGPoint {
        let cascade = CGFloat(existingPinCount % cascadeLength) * cascadeStep
        let proposed = CGPoint(
            x: initialEdgeMargin + cardSize.width / 2 + cascade,
            y: initialTopInset + cardSize.height / 2 + cascade
        )
        return clampedCenter(proposed, cardSize: cardSize, viewport: viewport)
    }

    /// Scales a card about the point between the user's fingers, so the part of
    /// the ink being pinched stays under them — the way the canvas itself zooms.
    ///
    /// - Parameters:
    ///   - center: The card's centre before the pinch.
    ///   - longestSide: The card's longer side before the pinch.
    ///   - inkSize: The pinned ink's canvas size, which decides the aspect.
    ///   - magnification: How far the pinch has scaled, 1 being unchanged.
    ///   - anchor: Where the pinch started, as a fraction of the card's width and
    ///     height from its top-leading corner (0...1 on each axis).
    ///   - viewport: The screen the card lives on.
    /// - Returns: The card's new centre and longer side, before edge clamping.
    static func resizedAboutAnchor(
        center: CGPoint,
        longestSide: CGFloat,
        inkSize: CGSize,
        magnification: CGFloat,
        anchor: CGPoint,
        viewport: CGSize
    ) -> (center: CGPoint, longestSide: CGFloat) {
        let size = cardSize(inkSize: inkSize, longestSide: longestSide)
        let resizedLongestSide = clampedLongestSide(longestSide * magnification, viewport: viewport)
        let resizedSize = cardSize(inkSize: inkSize, longestSide: resizedLongestSide)
        // Held as a fraction rather than a ratio of sizes: the short side's floor
        // means the card does not always scale evenly, and the same fraction of
        // the new card is still the point that was under the fingers.
        let anchorOnScreen = CGPoint(
            x: center.x - size.width / 2 + anchor.x * size.width,
            y: center.y - size.height / 2 + anchor.y * size.height
        )
        let resizedCenter = CGPoint(
            x: anchorOnScreen.x + (0.5 - anchor.x) * resizedSize.width,
            y: anchorOnScreen.y + (0.5 - anchor.y) * resizedSize.height
        )
        return (resizedCenter, resizedLongestSide)
    }

    /// Resizes a card by its bottom-trailing handle. The top-leading corner
    /// stays where it is and the handle follows the finger, which is how every
    /// corner handle the user has met behaves.
    ///
    /// - Parameters:
    ///   - center: The card's centre before the drag.
    ///   - longestSide: The card's longer side before the drag.
    ///   - inkSize: The pinned ink's canvas size, which decides the aspect.
    ///   - dragTranslation: How far the handle has been dragged.
    ///   - viewport: The screen the card lives on.
    /// - Returns: The card's new centre and longer side.
    static func resizedFromCorner(
        center: CGPoint,
        longestSide: CGFloat,
        inkSize: CGSize,
        dragTranslation: CGSize,
        viewport: CGSize
    ) -> (center: CGPoint, longestSide: CGFloat) {
        let size = cardSize(inkSize: inkSize, longestSide: longestSide)
        // Projected onto the card's diagonal so a drag straight right grows the
        // card as surely as a drag along the corner's own direction, and a drag
        // across the diagonal changes nothing.
        let diagonalLengthSquared = size.width * size.width + size.height * size.height
        let alongDiagonal = dragTranslation.width * size.width + dragTranslation.height * size.height
        let growth = 1 + alongDiagonal / diagonalLengthSquared

        let resizedLongestSide = clampedLongestSide(longestSide * growth, viewport: viewport)
        let resizedSize = cardSize(inkSize: inkSize, longestSide: resizedLongestSide)
        let topLeading = CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        let resizedCenter = CGPoint(
            x: topLeading.x + resizedSize.width / 2,
            y: topLeading.y + resizedSize.height / 2
        )
        return (resizedCenter, resizedLongestSide)
    }

    /// Traces the shapes framing a pin's source ink — the same rolling-ball
    /// region the page draws around each problem — one per problem the ink is
    /// filed under.
    ///
    /// One shape per problem rather than one around everything: when the
    /// arrangement moves two problems apart, a single shape would span the gap
    /// between them and frame ink that was never pinned.
    ///
    /// - Parameters:
    ///   - strokes: The pinned ink, at its stored positions.
    ///   - padding: How far the shape stands off the ink, in canvas points.
    ///   - curveRadius: How much the shape refuses to follow the ink into gaps.
    /// - Returns: Stored-space outlines; empty when there is no ink.
    static func sourceOutlines(of strokes: [Stroke], padding: CGFloat, curveRadius: CGFloat) -> [PinSourceOutline] {
        Dictionary(grouping: strokes, by: \.problemNodeID).compactMap { nodeID, group in
            let contours = ProblemRegion.contours(
                around: group.map { $0.points.map(\.position) },
                padding: padding,
                curveRadius: curveRadius
            )
            return contours.isEmpty ? nil : PinSourceOutline(problemNodeID: nodeID, contours: contours)
        }
    }

    /// The canvas-space box an outline covers once the arrangement has moved it.
    static func laidOutBounds(of outline: PinSourceOutline, placement: ProblemLayoutPlacement) -> CGRect? {
        guard let bounds = SelectionRegion.boundingBox(of: outline.contours) else { return nil }
        let offset = placement.offset(forNode: outline.problemNodeID)
        return bounds.offsetBy(dx: offset.x, dy: offset.y)
    }

    /// Where the "your ink is over there" arrow sits on a card, and which way it
    /// points: on the line from the card's centre to the off-screen ink, just
    /// inside the edge that line leaves through.
    ///
    /// Inside rather than outside the edge because a card can be parked against
    /// the screen's edge, and an arrow hanging past it would be cut off.
    ///
    /// - Parameters:
    ///   - cardCenter: The card's centre, in screen points.
    ///   - cardSize: The card's size.
    ///   - target: The source ink's centre, in screen points.
    ///   - inset: How far in from the edge the arrow's centre sits.
    /// - Returns: The arrow's centre and its direction in radians (0 = pointing
    ///   right, increasing clockwise as screen y runs down), or nil when the
    ///   target is the card's own centre and there is no direction to point.
    static func sourceArrowPlacement(
        cardCenter: CGPoint,
        cardSize: CGSize,
        toward target: CGPoint,
        inset: CGFloat
    ) -> (center: CGPoint, angle: CGFloat)? {
        let deltaX = target.x - cardCenter.x
        let deltaY = target.y - cardCenter.y
        guard deltaX != 0 || deltaY != 0 else { return nil }

        // How far along the ray the rectangle's edge is, measured by whichever
        // side — vertical or horizontal — the ray reaches first.
        let halfWidth = max(cardSize.width / 2 - inset, 0)
        let halfHeight = max(cardSize.height / 2 - inset, 0)
        let reachToSide = deltaX == 0 ? CGFloat.infinity : halfWidth / abs(deltaX)
        let reachToTopOrBottom = deltaY == 0 ? CGFloat.infinity : halfHeight / abs(deltaY)
        let reach = min(reachToSide, reachToTopOrBottom)

        let center = CGPoint(x: cardCenter.x + deltaX * reach, y: cardCenter.y + deltaY * reach)
        return (center, atan2(deltaY, deltaX))
    }

    /// The box a set of ink covers where it is *drawn* — the arrangement's shift
    /// applied problem by problem — nib width included.
    static func laidOutInkBounds(of strokes: [Stroke], placement: ProblemLayoutPlacement) -> CGRect {
        Dictionary(grouping: strokes, by: \.problemNodeID).reduce(CGRect.null) { union, group in
            let bounds = StrokeRasterizer.inkedBounds(of: group.value)
            guard !bounds.isNull else { return union }
            let offset = placement.offset(forNode: group.key)
            return union.union(bounds.offsetBy(dx: offset.x, dy: offset.y))
        }
    }

    /// How many card points one canvas point of ink becomes inside a card of
    /// `cardSize` — what a new pin's flight scales from, so the ink leaves the
    /// page at exactly the size it was drawn on screen.
    static func inkFitScale(inkBounds: CGRect, cardSize: CGSize) -> CGFloat {
        inkTransform(inkBounds: inkBounds, cardSize: cardSize).a
    }

    /// Maps canvas-space ink into a card of `cardSize`: scaled to fill the
    /// inset card and centred in it. Scaling through the transform rather than
    /// the points also scales nib width, so the ink keeps its weight.
    static func inkTransform(inkBounds: CGRect, cardSize: CGSize) -> CGAffineTransform {
        let target = CGRect(origin: .zero, size: cardSize).insetBy(dx: inkInset, dy: inkInset)
        let fit = InkFitTransform.centring(inkBounds, in: target, maximumScale: maximumInkScale)
        // `centring` expects ink already moved to start at the origin.
        return CGAffineTransform(translationX: -inkBounds.minX, y: -inkBounds.minY)
            .concatenating(fit)
    }
}
