import CoreGraphics

/// The worksheet pipeline, end to end: group the ink into problems, pick one
/// scale for the run, nest them, then expand what was left small to fill the
/// paper.
///
/// It is deterministic — the same document and the same options give the same
/// sheets every time — which is what makes the layout testable at all.
enum WorksheetLayoutEngine {
    /// Lays a document out. Returns an empty array when nothing would put ink on
    /// the page, which the caller should treat as "nothing to export".
    static func sheets(
        for document: SplineDocument,
        viewport: CGRect?,
        page: WorksheetPageGeometry,
        options: WorksheetOptions
    ) -> [WorksheetSheet] {
        sheets(
            for: WorksheetBlockBuilder.blocks(from: document, viewport: viewport, options: options),
            page: page,
            options: options
        )
    }

    /// The layout half on its own, so a test can hand it blocks it built itself.
    static func sheets(
        for blocks: [WorksheetBlock],
        page: WorksheetPageGeometry,
        options: WorksheetOptions
    ) -> [WorksheetSheet] {
        guard !blocks.isEmpty else { return [] }

        let fittingScales = blocks.map {
            WorksheetNester.largestScaleFittingEmptyPage(
                $0,
                page: page,
                padding: options.padding,
                ceiling: options.maximumScale
            )
        }
        let segments = segments(of: blocks, fittingScales: fittingScales, minimumScale: options.minimumScale)
        // The page-count search alone would happily pick a scale that pushes a
        // big problem off the paper, since an overflowing problem still counts
        // as one page. Capping it at the tightest problem's own limit means every
        // problem sharing the uniform scale is guaranteed to fit.
        let uniformCeiling = fittingScales
            .compactMap { $0 }
            .filter { $0 >= options.minimumScale }
            .min() ?? options.maximumScale

        let uniformScale = WorksheetScaleSearch.uniformScale(
            measurePageCount: { scale in
                nest(segments, page: page, padding: options.padding, uniformScale: scale).count
            },
            minimumScale: options.minimumScale,
            maximumScale: uniformCeiling
        )

        var sheets = nest(segments, page: page, padding: options.padding, uniformScale: uniformScale)
        // Coarse then fine: re-nest each page at the largest scale its own
        // problems allow, then grow individual problems into what is still free.
        if options.refitsPages {
            sheets = WorksheetNester.refit(
                sheets,
                page: page,
                padding: options.padding,
                cap: options.growthCap
            )
        }
        if options.growsProblems {
            sheets = WorksheetRelaxer.grown(
                sheets,
                page: page,
                padding: options.padding,
                cap: options.growthCap
            )
        }
        return sheets
    }

    /// Splits the reading order into runs that share the uniform scale, broken
    /// by any problem too big to fit a page at the readability floor. Those get
    /// a sheet to themselves, shrunk to fit — smaller than the floor, but whole,
    /// which beats a problem cut off at the margin.
    private static func segments(
        of blocks: [WorksheetBlock],
        fittingScales: [CGFloat?],
        minimumScale: CGFloat
    ) -> [WorksheetSegment] {
        var segments: [WorksheetSegment] = []
        var run: [WorksheetBlock] = []

        for (block, fittingScale) in zip(blocks, fittingScales) {
            if let fittingScale, fittingScale >= minimumScale {
                run.append(block)
                continue
            }
            if !run.isEmpty {
                segments.append(.shared(run))
                run = []
            }
            // A problem that fits at no scale at all keeps the old fallback:
            // drawn at the floor from the content origin, rather than dropped.
            segments.append(.alone(block, scale: fittingScale ?? minimumScale))
        }
        if !run.isEmpty { segments.append(.shared(run)) }
        return segments
    }

    /// Lays each segment out in order, so pages still read 1a, 1b, 1c … even
    /// with an oversized problem's own page between them.
    private static func nest(
        _ segments: [WorksheetSegment],
        page: WorksheetPageGeometry,
        padding: CGFloat,
        uniformScale: CGFloat
    ) -> [WorksheetSheet] {
        segments.flatMap { segment in
            switch segment {
            case .shared(let blocks):
                WorksheetNester.nest(blocks, page: page, padding: padding, scale: uniformScale)
            case .alone(let block, let scale):
                WorksheetNester.nest([block], page: page, padding: padding, scale: scale)
            }
        }
    }
}

/// A stretch of the reading order and how it is scaled.
private enum WorksheetSegment {
    /// Problems nested together at the run-wide uniform scale.
    case shared([WorksheetBlock])
    /// One problem too big for the uniform scale, on its own sheet at the
    /// largest scale that fits it.
    case alone(WorksheetBlock, scale: CGFloat)
}
