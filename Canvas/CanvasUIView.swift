#if canImport(UIKit)
import UIKit
#else
#error("This file requires UIKit and is designed for iOS/iPadOS only")
#endif

/// UIView subclass responsible for two things only:
///   1. Routing Apple Pencil touches to the view model.
///   2. Handling two-finger pan and pinch-to-zoom gestures.
///
/// Finger touches are intentionally ignored for drawing — they fall through
/// to the gesture recognizers, which are also configured to finger-only.
final class CanvasUIView: UIView {
    var viewModel: CanvasViewModel?

    // Pinch gesture handles both pan and zoom — a single recognizer for all
    // two-finger canvas navigation, eliminating any interference between
    // a separate pan recognizer and the pinch recognizer.
    private let pinchGesture = UIPinchGestureRecognizer()

    // Previous frame screen positions of the two pinch fingers.
    // Updated synchronously each frame so incremental deltas are always correct.
    private var pinchPrev0: CGPoint = .zero
    private var pinchPrev1: CGPoint = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureGestures()
        configurePencilInteraction()
        isMultipleTouchEnabled = true
    }

    required init?(coder: NSCoder) {
        fatalError("CanvasUIView must be created in code, not Interface Builder")
    }

    // MARK: - Setup

    private func configureGestures() {
        // Restrict to finger touches only so the recognizer doesn't eat pencil input.
        let fingerTouchType = NSNumber(value: UITouch.TouchType.direct.rawValue)
        pinchGesture.allowedTouchTypes = [fingerTouchType]
        pinchGesture.addTarget(self, action: #selector(handlePinch(_:)))
        addGestureRecognizer(pinchGesture)
    }

    private func configurePencilInteraction() {
        // Squeeze gesture for Pencil Pro tool switching.
        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = self
        addInteraction(pencilInteraction)
    }

    // MARK: - Pencil touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, touch.type == .pencil else { return }
        addStrokePoint(from: touch, event: event, phase: .began)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, touch.type == .pencil else { return }
        // Consume coalesced touches to capture all 240 Hz Pencil Pro samples.
        let samples = event?.coalescedTouches(for: touch) ?? [touch]
        for sample in samples {
            addStrokePoint(from: sample, event: event, phase: .moved)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, touch.type == .pencil else { return }
        addStrokePoint(from: touch, event: event, phase: .ended)
        Task { @MainActor in viewModel?.endStroke() }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard touches.first?.type == .pencil else { return }
        Task { @MainActor in viewModel?.cancelStroke() }
    }

    override func touchesEstimatedPropertiesUpdated(_ touches: Set<UITouch>) {
        for touch in touches {
            guard let index = touch.estimationUpdateIndex?.intValue else { continue }
            let point = makeStrokePoint(from: touch)
            Task { @MainActor in viewModel?.updateEstimatedPoint(updateIndex: index, with: point) }
        }
    }

    // MARK: - Point extraction

    private func addStrokePoint(from touch: UITouch, event: UIEvent?, phase: UITouch.Phase) {
        guard let viewModel else { return }
        let point = makeStrokePoint(from: touch)
        Task { @MainActor in
            if phase == .began {
                viewModel.beginStroke(
                    at: point.position,
                    force: point.force,
                    azimuth: point.azimuth,
                    altitude: point.altitude,
                    roll: point.rollAngle,
                    estimatedMask: point.estimatedPropertiesMask,
                    updateIndex: point.estimationUpdateIndex
                )
            } else if phase == .moved {
                viewModel.continueStroke(
                    at: point.position,
                    force: point.force,
                    azimuth: point.azimuth,
                    altitude: point.altitude,
                    roll: point.rollAngle,
                    estimatedMask: point.estimatedPropertiesMask,
                    updateIndex: point.estimationUpdateIndex
                )
            }
        }
    }

    private func makeStrokePoint(from touch: UITouch) -> StrokePoint {
        let screenPoint = touch.preciseLocation(in: self)
        // Transform from screen space into canvas space.
        let canvasPoint = viewModel?.canvasTransform.toCanvas(screenPoint) ?? screenPoint
        let updateIndex = touch.estimationUpdateIndex?.intValue
        return StrokePoint(
            position: canvasPoint,
            force: touch.force,
            azimuth: touch.azimuthAngle(in: self),
            altitude: touch.altitudeAngle,
            rollAngle: touch.rollAngle,
            estimatedPropertiesMask: touch.estimatedPropertiesExpectingUpdates.rawValue,
            estimationUpdateIndex: updateIndex
        )
    }

    // MARK: - Pinch gesture (handles pan + zoom)

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let viewModel, gesture.numberOfTouches == 2 else { return }

        let curr0 = gesture.location(ofTouch: 0, in: self)
        let curr1 = gesture.location(ofTouch: 1, in: self)

        switch gesture.state {
        case .began:
            // Seed previous positions synchronously so the first .changed frame
            // has valid data without depending on an async Task having run first.
            pinchPrev0 = curr0
            pinchPrev1 = curr1

        case .changed:
            // Capture and advance the stored positions before spawning the Task
            // so that each frame's delta is independent of Task scheduling.
            let prev0 = pinchPrev0
            let prev1 = pinchPrev1
            pinchPrev0 = curr0
            pinchPrev1 = curr1

            let prevDist = prev0.distance(to: prev1)
            guard prevDist > 0 else { return }

            let scaleFactor = curr0.distance(to: curr1) / prevDist
            let midPrev = prev0.midpoint(to: prev1)
            let midCurr = curr0.midpoint(to: curr1)

            Task { @MainActor in
                // Scale around the previous finger midpoint, keeping that
                // canvas point fixed under the fingers.
                viewModel.canvasTransform.zoom(by: scaleFactor, around: midPrev)
                // Then translate so the midpoint follows the fingers' movement.
                viewModel.canvasTransform.translation.x += midCurr.x - midPrev.x
                viewModel.canvasTransform.translation.y += midCurr.y - midPrev.y
            }

        default:
            break
        }
    }
}

// MARK: - UIPencilInteractionDelegate

extension CanvasUIView: UIPencilInteractionDelegate {
    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        // Cycle to the next tool on Pencil Pro squeeze.
        Task { @MainActor in
            guard let viewModel else { return }
            let tools = ToolType.allCases.filter { $0 != .lasso && $0 != .eraser }
            let currentIndex = tools.firstIndex(of: viewModel.activeTool) ?? 0
            let nextIndex = (currentIndex + 1) % tools.count
            viewModel.activeTool = tools[nextIndex]
        }
    }
}
