import Testing
import CoreGraphics
@testable import Tract

/// The frame morph is only as good as the correspondence between its two
/// outlines, so these tests are mostly about the canonical form: same point
/// count, same winding, even spacing, and a shared starting point. Get those
/// right and the blend is a lerp.
@Suite("Problem focus frame")
struct ProblemFocusFrameTests {

    private let box = CGRect(x: 0, y: 0, width: 400, height: 200)

    /// A blob offset well away from the box, so a test can tell the two apart
    /// by position alone.
    private func blob() -> [CGPoint] {
        (0 ..< 40).map { step in
            let angle = 2 * CGFloat.pi * CGFloat(step) / 40
            return CGPoint(x: 1000 + cos(angle) * 50, y: 1000 + sin(angle) * 30)
        }
    }

    private func boundingBox(of loop: [CGPoint]) -> CGRect {
        let xs = loop.map(\.x)
        let ys = loop.map(\.y)
        return CGRect(
            x: xs.min()!,
            y: ys.min()!,
            width: xs.max()! - xs.min()!,
            height: ys.max()! - ys.min()!
        )
    }

    // MARK: - Canonical form

    @Test("Both outlines are resampled onto the same number of points")
    func canonicalFormsMatchInCount() {
        let bubble = ProblemFocusFrame.canonical(blob())
        let rect = ProblemFocusFrame.canonical(
            ProblemFocusFrame.roundedRectLoop(box, cornerRadius: 20)
        )

        #expect(bubble.count == ProblemFocusFrame.sampleCount)
        #expect(rect.count == bubble.count)
    }

    @Test("A loop wound the wrong way is turned round before it is used")
    func windingIsNormalised() {
        let forwards = ProblemFocusFrame.canonical(blob())
        let backwards = ProblemFocusFrame.canonical(Array(blob().reversed()))

        #expect(ProblemFocusFrame.signedArea(of: forwards) > 0)
        #expect(ProblemFocusFrame.signedArea(of: backwards) > 0)
    }

    /// Without this the blend drags a crowded stretch of a marching-squares
    /// contour across a whole side of the box.
    @Test("Samples are spaced evenly along the perimeter, not by index")
    func resamplingIsEvenlySpaced() {
        // Points deliberately bunched along one edge of a square.
        let lopsided = [
            CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 2, y: 0),
            CGPoint(x: 3, y: 0), CGPoint(x: 100, y: 0),
            CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100)
        ]
        let samples = ProblemFocusFrame.resampled(lopsided, count: 64)
        let gaps = samples.indices.map {
            samples[$0].distance(to: samples[($0 + 1) % samples.count])
        }

        #expect(abs(gaps.max()! - gaps.min()!) < 0.001)
    }

    @Test("Both outlines start from the same side of their own shape")
    func startPointsCorrespond() {
        let bubble = ProblemFocusFrame.canonical(blob())
        let rect = ProblemFocusFrame.canonical(
            ProblemFocusFrame.roundedRectLoop(box, cornerRadius: 20)
        )

        // Each first sample should sit to the right of its own centre.
        #expect(bubble[0].x > ProblemFocusFrame.centroid(of: bubble).x)
        #expect(rect[0].x > ProblemFocusFrame.centroid(of: rect).x)
    }

    @Test("The biggest patch of a problem is the one that becomes the box")
    func largestLoopWins() {
        let small = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1)]
        let large = blob()

        let picked = ProblemFocusFrame.largestLoop(in: [small, large])
        #expect(picked?.count == large.count)
    }

    // MARK: - The morph

    @Test("At the start the outline is the problem's own bubble")
    func progressZeroIsTheBubble() {
        let bubble = ProblemFocusFrame.canonicalLoop(in: [blob()])
        let outline = ProblemFocusFrame.outline(
            from: bubble,
            to: box,
            cornerRadius: 20,
            progress: 0
        )

        #expect(outline == bubble)
    }

    @Test("At the end the outline is the box")
    func progressOneIsTheBox() {
        let outline = ProblemFocusFrame.outline(
            from: ProblemFocusFrame.canonicalLoop(in: [blob()]),
            to: box,
            cornerRadius: 20,
            progress: 1
        )

        let bounds = boundingBox(of: outline)
        #expect(abs(bounds.width - box.width) < 1)
        #expect(abs(bounds.height - box.height) < 1)
        #expect(abs(bounds.midX - box.midX) < 1)
    }

    @Test("Half way through, the outline is between the two")
    func progressHalfIsBetween() {
        let outline = ProblemFocusFrame.outline(
            from: ProblemFocusFrame.canonicalLoop(in: [blob()]),
            to: box,
            cornerRadius: 20,
            progress: 0.5
        )
        let bounds = boundingBox(of: outline)

        // The blob is centred at 1000, the box at 200; half way is between.
        #expect(bounds.midX > box.midX)
        #expect(bounds.midX < 1000)
    }

    @Test("A problem with no traced bubble opens straight to the box")
    func noBubbleGivesTheBox() {
        let outline = ProblemFocusFrame.outline(
            from: [],
            to: box,
            cornerRadius: 20,
            progress: 0
        )

        #expect(outline.count == ProblemFocusFrame.sampleCount)
        #expect(abs(boundingBox(of: outline).width - box.width) < 1)
    }

    @Test("No box means nothing to draw")
    func noBoxGivesNoOutline() {
        #expect(
            ProblemFocusFrame
                .outline(from: blob(), to: .null, cornerRadius: 20, progress: 1)
                .isEmpty
        )
    }

    @Test("The corner radius never exceeds half the shorter side")
    func cornerRadiusIsClamped() {
        let thin = CGRect(x: 0, y: 0, width: 100, height: 10)
        let loop = ProblemFocusFrame.roundedRectLoop(thin, cornerRadius: 500)

        #expect(boundingBox(of: loop).height <= thin.height + 0.001)
        #expect(boundingBox(of: loop).width <= thin.width + 0.001)
    }
}
