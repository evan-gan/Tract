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

    // Canvas-space positions of the two fingers captured at gesture start.
    // Held fixed for the duration of the gesture; each frame solves for the
    // transform that maps these canvas points back to the current finger positions.
    private var pinchCanvasAnchor0: CGPoint = .zero
    private var pinchCanvasAnchor1: CGPoint = .zero
    // Explicit validity flag — avoids stale values from a previous gesture
    // being used when .began fires with only 1 touch and our guard exits early.
    private var pinchAnchorsValid = false

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
        guard let viewModel else { return }

        // Invalidate anchors on gesture end so stale values can't bleed
        // into the next gesture. Must happen before the numberOfTouches
        // guard because terminal states often report fewer than 2 touches.
        guard gesture.state == .began || gesture.state == .changed else {
            pinchAnchorsValid = false
            return
        }

        guard gesture.numberOfTouches == 2 else { return }

        let curr0 = gesture.location(ofTouch: 0, in: self)
        let curr1 = gesture.location(ofTouch: 1, in: self)

        // All transform reads AND writes happen synchronously on the main
        // thread via assumeIsolated. Using async Tasks caused a race where
        // anchor capture read a stale transform that hadn't been updated by
        // the previous frame's queued Task yet.
        MainActor.assumeIsolated {
            // Capture anchors if not yet valid. Handles both:
            //   1. Normal: .began with 2 touches.
            //   2. Fallback: .began had 1 touch, so we capture lazily here.
            // First-frame computation is a no-op (produces the same transform).
            if !pinchAnchorsValid {
                pinchCanvasAnchor0 = viewModel.canvasTransform.toCanvas(curr0)
                pinchCanvasAnchor1 = viewModel.canvasTransform.toCanvas(curr1)
                pinchAnchorsValid = true
            }

            guard gesture.state == .changed else { return }

            let a0 = pinchCanvasAnchor0
            let a1 = pinchCanvasAnchor1
            let canvasDist = a0.distance(to: a1)
            guard canvasDist > 0 else { return }

            // Solve for the unique scale+translation that places canvas point
            // a0 at screen position curr0 and a1 at curr1. Absolute, not
            // incremental, so floating-point errors cannot accumulate.
            let newScale = curr0.distance(to: curr1) / canvasDist
            viewModel.canvasTransform.scale = newScale
            viewModel.canvasTransform.translation = CGPoint(
                x: curr0.x - a0.x * newScale,
                y: curr0.y - a0.y * newScale
            )
        }
    }
}

// MARK: - UIPencilInteractionDelegate

extension CanvasUIView: UIPencilInteractionDelegate {
    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        // Cycle to the next tool on Pencil Pro squeeze.
        Task { @MainActor in
            guard let viewModel else { return }
            let tools = ToolType.drawingTools
            let currentIndex = tools.firstIndex(of: viewModel.activeTool) ?? 0
            let nextIndex = (currentIndex + 1) % tools.count
            viewModel.activeTool = tools[nextIndex]
        }
    }
}
