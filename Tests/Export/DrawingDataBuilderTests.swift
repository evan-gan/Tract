import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import Tract

@Suite("Describing a document as raw export data")
struct DrawingDataBuilderTests {
    @Test("Every property of a pencil sample survives the export")
    func pencilTelemetryIsCarriedThrough() throws {
        let sample = StrokePoint(
            position: CGPoint(x: 12, y: 34),
            force: 0.75,
            azimuth: 1.25,
            altitude: 0.5,
            rollAngle: 2.0,
            estimatedPropertiesMask: 0,
            estimationUpdateIndex: nil,
            timestamp: 100
        )
        let export = DrawingDataBuilder.makeExport(from: document(with: [stroke(samples: [sample, sample])]))

        let exported = try #require(export.strokes.first?.points.first)
        #expect(exported.x == 12)
        #expect(exported.y == 34)
        #expect(exported.force == 0.75)
        #expect(exported.azimuth == 1.25)
        #expect(exported.altitude == 0.5)
        #expect(exported.rollAngle == 2.0)
    }

    @Test("Sample timing is reported as seconds since the stroke's first sample")
    func timingIsRelativeToTheStrokeStart() throws {
        // Absolute timestamps are device uptime, which means nothing to a reader
        // on another machine; the offsets are the part that describes the writing.
        let samples = [100.0, 100.25, 100.5].map { sample(at: 0, timestamp: $0) }
        let export = DrawingDataBuilder.makeExport(from: document(with: [stroke(samples: samples)]))

        let points = try #require(export.strokes.first?.points)
        #expect(points.map(\.timeOffset) == [0, 0.25, 0.5])
        #expect(points.map(\.deviceTimestamp) == [100, 100.25, 100.5])
    }

    @Test("A stroke recorded before per-sample timing existed exports without it")
    func untimedSamplesReportNoOffset() throws {
        // Documents written by older builds decode with no timestamps at all, and
        // must still export rather than fail or invent a timeline.
        let export = DrawingDataBuilder.makeExport(
            from: document(with: [StrokeFixtures.square(at: .zero)])
        )

        let points = try #require(export.strokes.first?.points)
        #expect(points.allSatisfy { $0.timeOffset == nil && $0.deviceTimestamp == nil })
    }

    @Test("Properties UIKit had not finalised are named rather than left as a bitmask")
    func estimatedPropertiesAreNamed() {
        let mask = UITouch.Properties([.force, .azimuth]).rawValue
        let point = StrokePoint(
            position: .zero,
            force: 0,
            azimuth: 0,
            altitude: 0,
            rollAngle: 0,
            estimatedPropertiesMask: mask,
            estimationUpdateIndex: 3,
            timestamp: nil
        )
        let export = DrawingDataBuilder.makeExport(from: document(with: [stroke(samples: [point])]))

        #expect(export.strokes[0].points[0].estimatedProperties == ["force", "azimuth"])
    }

    @Test("Strokes keep the order they were drawn in and carry that position")
    func strokesKeepDrawingOrder() {
        let first = StrokeFixtures.square(at: .zero)
        let second = StrokeFixtures.square(at: CGPoint(x: 400, y: 0))

        let export = DrawingDataBuilder.makeExport(from: document(with: [first, second]))

        #expect(export.strokes.map(\.id) == [first.id, second.id])
        #expect(export.strokes.map(\.index) == [0, 1])
    }

    @Test("A stroke's tag is resolved to the address the node holds today")
    func problemTagsAreResolved() throws {
        var builder = ProblemOutlineBuilder()
        let partB = builder.node([1, 2])
        let tagged = StrokeFixtures.square(at: .zero, problemNodeID: partB)

        let export = DrawingDataBuilder.makeExport(
            from: document(with: [tagged], outline: builder.outline)
        )

        let reference = try #require(export.strokes[0].problem)
        #expect(reference.nodeID == partB)
        #expect(reference.tag == "1.b")
        #expect(reference.path == [0, 1])
        #expect(reference.components?.map(\.text) == ["1", "b"])
    }

    @Test("A stroke tagged against a deleted node keeps the id but reports no address")
    func deletedNodesLeaveTheIDBehind() throws {
        var builder = ProblemOutlineBuilder()
        let doomed = builder.node([1])
        let stroke = StrokeFixtures.square(at: .zero, problemNodeID: doomed)

        // The node is gone; the stroke still remembers what it once belonged to.
        let export = DrawingDataBuilder.makeExport(from: document(with: [stroke]))

        let reference = try #require(export.strokes[0].problem)
        #expect(reference.nodeID == doomed)
        #expect(reference.tag == nil)
        #expect(reference.path == nil)
    }

    @Test("Untagged work exports with no problem at all")
    func untaggedStrokesHaveNoProblem() {
        let export = DrawingDataBuilder.makeExport(from: document(with: [StrokeFixtures.square(at: .zero)]))

        #expect(export.strokes[0].problem == nil)
    }

    @Test("The problem tree is exported with its nesting and today's labels")
    func problemTreeIsExported() throws {
        var builder = ProblemOutlineBuilder()
        _ = builder.node([1, 1, 2])
        _ = builder.node([2])

        let export = DrawingDataBuilder.makeExport(from: document(with: [], outline: builder.outline))

        #expect(export.problems.map(\.label) == ["1", "2"])
        let partA = try #require(export.problems.first?.children.first)
        #expect(partA.tag == "1.a")
        #expect(partA.children.map(\.tag) == ["1.a.I", "1.a.II"])
    }

    @Test("Style is exported as both channel values and a hex string")
    func styleCarriesColourInBothForms() {
        var stroke = StrokeFixtures.square(at: .zero)
        stroke.style = StrokeStyle(color: InkColor.red, lineWidth: 7, opacity: 0.5, tool: .pen)

        let style = DrawingDataBuilder.makeExport(from: document(with: [stroke])).strokes[0].style

        #expect(style.colorHex == "#D92626")
        #expect(style.color.red == InkColor.red.x)
        #expect(style.lineWidth == 7)
        #expect(style.opacity == 0.5)
        #expect(style.tool == "pen")
    }

    @Test("A viewport keeps only the strokes that touch it")
    func viewportClipsStrokes() {
        let inside = StrokeFixtures.square(at: .zero, side: 100)
        let outside = StrokeFixtures.square(at: CGPoint(x: 5_000, y: 5_000), side: 100)

        let export = DrawingDataBuilder.makeExport(
            from: document(with: [inside, outside]),
            viewport: CGRect(x: -10, y: -10, width: 200, height: 200)
        )

        #expect(export.strokes.map(\.id) == [inside.id])
        #expect(export.document.strokeCount == 1)
    }

    @Test("The document's ink bounds stand off by half the widest nib")
    func inkBoundsIncludeTheNib() throws {
        // The same box the PNG and PDF exports fit to, so a consumer laying the
        // drawing out gets the same framing rather than a clipped outer edge.
        let export = DrawingDataBuilder.makeExport(
            from: document(with: [StrokeFixtures.square(at: .zero, side: 100)])
        )

        let bounds = try #require(export.document.inkBounds)
        #expect(bounds.x == -2)
        #expect(bounds.width == 104)
    }

    // MARK: - Fixtures

    private func document(with strokes: [Stroke], outline: ProblemOutline? = nil) -> SplineDocument {
        SplineDocument(
            metadata: DocumentMetadata(title: "Data study", problemOutline: outline),
            strokes: strokes
        )
    }

    private func stroke(samples: [StrokePoint]) -> Stroke {
        var stroke = Stroke(sessionID: UUID(), style: .default)
        for sample in samples { stroke.appendPoint(sample) }
        stroke.isComplete = true
        return stroke
    }

    private func sample(at x: CGFloat, timestamp: TimeInterval) -> StrokePoint {
        StrokePoint(
            position: CGPoint(x: x, y: 0),
            force: 1,
            azimuth: 0,
            altitude: .pi / 2,
            rollAngle: 0,
            estimatedPropertiesMask: 0,
            estimationUpdateIndex: nil,
            timestamp: timestamp
        )
    }
}
