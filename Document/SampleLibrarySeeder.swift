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

        for (title, strokes) in samples() {
            var document = SplineDocument(metadata: DocumentMetadata(title: title), strokes: strokes)
            document.metadata.modifiedAt = .now
            let thumbnail = ThumbnailRenderer.renderPNG(strokes: strokes)
            try? await store.save(document, thumbnail: thumbnail.map(ThumbnailUpdate.replace) ?? .unchanged)
        }
    }

    private static func samples() -> [(title: String, strokes: [Stroke])] {
        [
            ("Wave study", [sineStroke(color: InkColor.black, phase: 0),
                            sineStroke(color: InkColor.black, phase: .pi / 2)]),
            ("Grid sketch", gridStrokes()),
            ("Untitled", [])
        ]
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
