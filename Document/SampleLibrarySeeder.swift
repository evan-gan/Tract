#if DEBUG
import Foundation

/// Fills the library with drawn documents on launch when
/// `-TractSeedSampleDocuments` is passed.
///
/// It exists because XCUITest cannot draw: the canvas takes Apple Pencil touches
/// only, and a simulated finger drag pans instead of inking. Without this there
/// is no way to screenshot a document card with a real preview on it.
/// DEBUG-only, so it cannot ship or run on a device build.
enum SampleLibrarySeeder {
    static let launchArgument = "-TractSeedSampleDocuments"

    static func seedIfRequested(into store: DocumentFileStore) async {
        guard ProcessInfo.processInfo.arguments.contains(launchArgument) else { return }

        // Clears first so a screenshot shows the same library every run, whatever
        // earlier UI tests left behind in the simulator.
        for existing in await ((try? store.listMetadata()) ?? []) {
            try? await store.deleteDocument(id: existing.id)
        }

        // One folder, with one document filed inside it, so the library shot shows
        // both kinds of tile and the UI tests have something to drag onto.
        let sampleFolder = DocumentFolder(name: "Homework")
        try? await store.saveFolders([sampleFolder])

        for sample in samples(folderID: sampleFolder.id) {
            var document = SplineDocument(
                metadata: DocumentMetadata(title: sample.title, folderID: sample.folderID),
                strokes: sample.strokes
            )
            document.metadata.modifiedAt = .now
            document.metadata.problemOutline = sample.outline
            let thumbnail = ThumbnailRenderer.renderPNG(strokes: sample.strokes)
            try? await store.save(document, thumbnail: thumbnail.map(ThumbnailUpdate.replace) ?? .unchanged)
        }
    }

    private typealias Sample = (
        title: String,
        strokes: [Stroke],
        folderID: UUID?,
        outline: ProblemOutline?
    )

    private static func samples(folderID: UUID) -> [Sample] {
        let problemSet = taggedProblemSet()
        return [
            ("Wave study", [sineStroke(color: InkColor.black, phase: 0),
                            sineStroke(color: InkColor.black, phase: .pi / 2)], nil, nil),
            ("Grid sketch", gridStrokes(), nil, nil),
            ("Untitled", [], nil, nil),
            ("Problem set", problemSet.strokes, nil, problemSet.outline),
            ("Filed away", gridStrokes(), folderID, nil)
        ]
    }

    /// A page of work filed under two problems, plus a patch of untagged ink.
    ///
    /// This is the fixture the problem-region shot is of: the regions are built
    /// from tagged strokes, so every other sample document draws none. The
    /// untagged patch is in there on purpose — it must come back unframed.
    private static func taggedProblemSet() -> (strokes: [Stroke], outline: ProblemOutline) {
        var outline = ProblemOutline()
        outline.appendChild(under: [])
        outline.appendChild(under: [])
        let firstProblem = outline.node(at: [0])?.id
        let secondProblem = outline.node(at: [1])?.id

        // Laid out in canvas coordinates, which a freshly opened document shows
        // one-to-one from the top left, so the work lands in the middle of the
        // screen rather than under the top bar.
        let strokes = writingStrokes(at: CGPoint(x: 170, y: 190), lines: 3, tag: firstProblem)
            + writingStrokes(at: CGPoint(x: 170, y: 470), lines: 2, tag: secondProblem)
            + writingStrokes(at: CGPoint(x: 700, y: 300), lines: 2, tag: nil)
        return (strokes, outline)
    }

    /// Stands in for a few lines of handwriting: a zigzag per line, spaced the
    /// way written lines are, so the region has real gaps to bridge rather than
    /// one solid bar of ink.
    private static func writingStrokes(
        at origin: CGPoint,
        lines: Int,
        tag problemNodeID: UUID?
    ) -> [Stroke] {
        (0 ..< lines).map { line in
            let baselineY = origin.y + CGFloat(line) * 46
            let positions = stride(from: 0.0, through: 300.0, by: 15.0).map { offsetX in
                CGPoint(
                    x: origin.x + offsetX,
                    y: baselineY + (offsetX.truncatingRemainder(dividingBy: 30) == 0 ? -9 : 9)
                )
            }
            var stroke = stroke(through: positions, color: InkColor.black, lineWidth: 3)
            stroke.problemNodeID = problemNodeID
            return stroke
        }
    }

    private static func sineStroke(color: SIMD4<Float>, phase: CGFloat) -> Stroke {
        let positions = stride(from: 0.0, through: 360.0, by: 4.0).map { x in
            CGPoint(x: x, y: 120 + sin(x / 40 + phase) * 70)
        }
        return stroke(through: positions, color: color, lineWidth: 3)
    }

    private static func gridStrokes() -> [Stroke] {
        let lines = stride(from: 0.0, through: 240.0, by: 40.0)
        let vertical = lines.map { x in
            stroke(through: [CGPoint(x: x, y: 0), CGPoint(x: x, y: 240)], color: InkColor.black, lineWidth: 2)
        }
        let horizontal = lines.map { y in
            stroke(through: [CGPoint(x: 0, y: y), CGPoint(x: 240, y: y)], color: InkColor.black, lineWidth: 2)
        }
        return vertical + horizontal
    }

    private static func stroke(through positions: [CGPoint], color: SIMD4<Float>, lineWidth: CGFloat) -> Stroke {
        var stroke = Stroke(
            sessionID: UUID(),
            style: StrokeStyle(color: color, lineWidth: lineWidth, opacity: 1, tool: .pen)
        )
        for position in positions {
            stroke.appendPoint(StrokePoint(
                position: position,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2,
                rollAngle: 0,
                estimatedPropertiesMask: 0,
                estimationUpdateIndex: nil
            ))
        }
        stroke.isComplete = true
        return stroke
    }
}
#endif
