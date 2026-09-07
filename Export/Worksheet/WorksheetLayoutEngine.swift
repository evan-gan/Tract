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

        let uniformScale = WorksheetScaleSearch.uniformScale(
            measurePageCount: { scale in
                WorksheetNester.nest(blocks, page: page, padding: options.padding, scale: scale).count
            },
            minimumScale: options.minimumScale,
            maximumScale: options.maximumScale
        )

        var sheets = WorksheetNester.nest(
            blocks,
            page: page,
            padding: options.padding,
            scale: uniformScale
        )
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
}
