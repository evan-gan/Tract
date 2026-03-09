# Spline — Technical Specification
*Infinite canvas vector note app for iPad*

---

## 1. Project Overview

Spline is an iPad-first, infinite canvas note-taking app built around raw vector stroke data. Every stroke stores full pencil telemetry (position, pressure, tilt, timing) to support AI features later. Export targets SVG, PDF, and PNG via an adapter pattern.

---

## 2. Tech Stack

**Minimum target: iPadOS 26**

| Layer | Choice | Reason |
|---|---|---|
| UI | SwiftUI | Modern, declarative, minimal boilerplate |
| Canvas input | UIKit `UIView` + `UIResponder` via `UIViewRepresentable` | Raw pencil access, full control over touch pipeline |
| Pencil input | `UITouch` API directly, filtered to `.pencil` type only | Fingers ignored at draw layer; full telemetry access |
| Rendering | SwiftUI `Canvas` (immediate mode) | Sufficient for stroke rendering; upgrade to Metal if needed later |
| Persistence | **Core Data** (not SwiftData) | SwiftData had serious instability through iOS 17/18; Core Data is battle-tested for complex data |
| Canvas transform | `CGAffineTransform` | Pan + zoom via concatenated translate/scale |
| Export | Manual serialization + `UIGraphicsImageRenderer` / `UIGraphicsPDFRenderer` | No dependencies needed for PNG/PDF; hand-roll SVG |
| Apple Pencil Pro | `rollAngle` on `UITouch`, `UICanvasFeedbackGenerator` for haptics | Barrel roll stored per point; squeeze for tool switching |

---

## 3. Component Architecture

**Everything is a component.** No view does more than one job. This keeps each file short, testable, and easy to swap out independently.

The rule: if a view has more than one distinct visual region or responsibility, it gets split.

```
Spline/
├── App/
│   ├── SplineApp.swift              # @main entry point, nothing else
│   └── AppDelegate.swift            # Optional: only if you need lifecycle hooks
│
├── Canvas/
│   ├── CanvasContainerView.swift    # Root of the drawing screen — composes all sub-components
│   ├── CanvasView.swift             # UIViewRepresentable wrapper only — no logic
│   ├── CanvasUIView.swift           # UIView subclass — pencil input + gesture recognizers only
│   ├── CanvasRenderer.swift         # All SwiftUI Canvas drawing logic — strokes → paths
│   ├── CanvasViewModel.swift        # @Observable: single source of truth for canvas state
│   └── CanvasTransform.swift        # Pan/zoom value type + CGAffineTransform helpers
│
├── Toolbar/                         # Top bar — each button group is its own component
│   ├── TopBarView.swift             # Assembles: title + undo/redo + select + export
│   ├── DocumentTitleView.swift      # Editable document title pill
│   ├── UndoRedoView.swift           # Undo + redo buttons
│   ├── SelectToolButton.swift       # Select mode toggle
│   └── ExportButton.swift           # Export trigger + format picker
│
├── Palette/                         # Left side tool palette — each tool is its own component
│   ├── PaletteView.swift            # Assembles all palette items in order
│   ├── PenToolButton.swift          # Pen tool button
│   ├── PencilToolButton.swift       # Pencil tool button
│   ├── MarkerToolButton.swift       # Marker tool button
│   ├── EraserToolButton.swift       # Eraser tool button
│   ├── LassoToolButton.swift        # Lasso select button
│   ├── StrokeWeightButton.swift     # Weight icon + flyout trigger
│   ├── StrokeWeightFlyout.swift     # Expanding weight picker (5 sizes)
│   └── ColorSwatchButton.swift      # Color swatch that opens the color panel
│
├── ColorPanel/                      # Color picker panel — floats beside palette
│   ├── ColorPanelView.swift         # Assembles preset grid + custom + opacity
│   ├── ColorPresetGrid.swift        # 15-color preset dot grid
│   ├── CustomColorRow.swift         # Native color picker + hex input field
│   └── OpacitySlider.swift          # Opacity control
│
├── Overlay/                         # Floating chrome that sits above the canvas
│   ├── ZoomIndicatorView.swift      # "100%" readout, bottom-right
│   └── SelectionBoxView.swift       # Blue selection rectangle + resize handles
│
├── Stroke/
│   ├── StrokePoint.swift            # Single point: position, force, azimuth, altitude, roll
│   ├── Stroke.swift                 # Complete stroke: points + startTime/endTime + style
│   └── StrokeStyle.swift            # Color, lineWidth, opacity, ToolType
│
├── Document/
│   ├── SplineDocument.swift         # Top-level document model
│   ├── DocumentStore.swift          # Core Data stack + CRUD
│   ├── DocumentListView.swift       # File browser / home screen
│   ├── DocumentListRow.swift        # Single document row component
│   └── Persistence.xcdatamodeld    # Core Data schema
│
├── Export/
│   ├── ExportAdapter.swift          # Protocol: all exporters conform to this
│   ├── ExportSheetView.swift        # Format picker sheet (SVG / PDF / PNG)
│   ├── SVGExporter.swift            # Stroke → SVG path serialization
│   ├── PDFExporter.swift            # UIGraphicsPDFRenderer
│   └── PNGExporter.swift            # UIGraphicsImageRenderer
│
└── Utilities/
    ├── CGPoint+Math.swift           # Vector math helpers
    ├── Color+Hex.swift              # Color ↔ hex string
    └── View+GlassCard.swift         # Shared frosted glass modifier used by all chrome
```

### Component responsibilities

`CanvasContainerView` is the one view that knows about everything — it composes `CanvasView`, `TopBarView`, `PaletteView`, `ColorPanelView`, and the overlay components. Nothing else imports from multiple feature folders.

`CanvasViewModel` is the single shared state object passed down via the environment. Tool state, active stroke, all strokes, canvas transform — all live here. Components read from it and call methods on it; they don't own state themselves.

Each palette button (e.g. `PenToolButton`) takes a binding to the current tool and handles its own active/inactive appearance. `PaletteView` just stacks them.

`StrokeWeightFlyout` is entirely self-contained — it manages its own open/close animation and calls back with the selected weight value. `StrokeWeightButton` owns the flyout and triggers it on hover.

`ColorPanelView` is similarly self-contained. `ColorSwatchButton` owns it.

---

## 4. Data Structures

### StrokePoint
Every sample from the pencil during a stroke.

```swift
struct StrokePoint {
    let position: CGPoint       // Canvas-space coordinates (not screen-space)
    let force: CGFloat          // 0.0–1.0 (normalized)
    let azimuth: CGFloat        // Radians — rotation around vertical axis
    let altitude: CGFloat       // Radians — 0 = flat, π/2 = perpendicular
    let rollAngle: CGFloat      // Apple Pencil Pro barrel roll (radians), 0.0 for other pencils
    let estimatedPropertiesExpectingUpdates: UITouch.Properties // Track which props are still estimated
}
```

**Note on estimated properties:** Apple sends some touch data (force, azimuth) as estimates first, then delivers actual values via `touchesEstimatedPropertiesUpdated`. You need to handle this update cycle — store points by their `estimationUpdateIndex` so you can patch them when actuals arrive.

### Stroke
A complete pen-down to pen-up gesture.

```swift
struct Stroke: Identifiable {
    let id: UUID
    let sessionID: UUID          // Groups strokes from the same drawing session
    let startTime: Date          // Wall clock — when pen touched down
    let endTime: Date            // Wall clock — when pen lifted (set in touchesEnded)
    var points: [StrokePoint]
    var style: StrokeStyle
    var isComplete: Bool         // False while drawing, true after pen lifts
    var canvasBounds: CGRect     // Bounding box in canvas space (for spatial indexing)
}
```

Timing is intentionally simple: just two `Date` values per stroke. This gives you duration, sequence, and session grouping — everything needed for AI temporal features — without per-point timestamp overhead.

### StrokeStyle

```swift
struct StrokeStyle {
    var color: SIMD4<Float>      // RGBA — SIMD for future Metal rendering
    var lineWidth: CGFloat       // Base width (modulated by force at render time)
    var opacity: CGFloat
    var tool: ToolType
}

enum ToolType: String, CaseIterable {
    case pen, pencil, marker, eraser
}
```

### SplineDocument

```swift
class SplineDocument: ObservableObject {
    var id: UUID
    var title: String
    var createdAt: Date
    var modifiedAt: Date
    var strokes: [Stroke]        // Ordered by startTime
    var canvasOrigin: CGPoint    // Last known pan position (restore on reopen)
    var canvasScale: CGFloat     // Last known zoom level
}
```

---

## 5. Input Pipeline (Pencil Only)

The app ignores all finger/touch input for drawing. Fingers only drive pan/zoom via gesture recognizers. The pencil exclusively creates strokes.

```
Apple Pencil touches UIView
        ↓
touchesBegan / touchesMoved / touchesEnded
        ↓
Guard: touch.type == .pencil — drop everything else, return immediately
        ↓
Extract: preciseLocationInView, force, azimuthAngle, altitudeAngle, rollAngle
        ↓
Coordinate transform: screen → canvas space (apply inverse of CGAffineTransform)
        ↓
Append StrokePoint to active Stroke
        ↓
Publish change → SwiftUI Canvas re-renders
        ↓
touchesEnded: stamp endTime (Date()), mark stroke complete, persist to Core Data
```

**The filter is one line:**
```swift
override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard let touch = touches.first, touch.type == .pencil else { return }
    beginStroke(at: touch, event: event)
}
```

Apply this guard to `touchesBegan`, `touchesMoved`, `touchesEnded`, and `touchesCancelled`. Finger touches fall through to the gesture recognizers for pan/zoom as normal — the UIView just never acts on them for drawing.

**Gesture recognizer touch type restriction** — configure pan/zoom recognizers to only respond to fingers so they don't interfere with the pencil:
```swift
panGesture.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
pinchGesture.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
```

**Coalesced touches:** Always consume `coalescedTouches(for:)` to capture all intermediate pencil samples between frames. The Apple Pencil Pro samples at 240Hz but UIKit delivers events at display refresh rate — without coalescing you silently drop most of your data.

```swift
override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard let touch = touches.first, touch.type == .pencil else { return }
    
    let coalesced = event?.coalescedTouches(for: touch) ?? [touch]
    for t in coalesced {
        appendPoint(from: t)
    }
}
```

---

## 6. Infinite Canvas

The canvas has no fixed size. Everything lives in **canvas space**. The viewport is a window into canvas space controlled by a `CGAffineTransform`.

```swift
struct CanvasTransform {
    var scale: CGFloat = 1.0            // Zoom level
    var translation: CGPoint = .zero    // Pan offset
    
    var matrix: CGAffineTransform {
        CGAffineTransform.identity
            .translatedBy(x: translation.x, y: translation.y)
            .scaledBy(x: scale, y: scale)
    }
    
    var inverse: CGAffineTransform {
        matrix.inverted()
    }
    
    // Convert screen point → canvas point
    func toCanvas(_ screenPoint: CGPoint) -> CGPoint {
        screenPoint.applying(inverse)
    }
}
```

Gestures:
- **Two-finger pan:** `UIPanGestureRecognizer` with `minimumNumberOfTouches = 2`
- **Pinch to zoom:** `UIPinchGestureRecognizer`
- **One-finger draw:** Handled in `touchesBegan/Moved/Ended` directly on the UIView, not via gesture recognizer (avoids conflict)

Prevent gesture recognizers from eating pencil touches by setting `requiresExclusiveTouchType = false` and checking touch type in the handler.

---

## 7. Rendering

Use SwiftUI's `Canvas` view for the initial implementation. It redraws on every state change and handles stroke-level drawing efficiently.

```swift
Canvas { context, size in
    for stroke in viewModel.strokes {
        let path = strokeToPath(stroke, transform: viewModel.canvasTransform.matrix)
        context.stroke(path, with: .color(stroke.style.swiftUIColor),
                       lineWidth: stroke.style.lineWidth)
    }
    
    // Draw active (in-progress) stroke on top
    if let active = viewModel.activeStroke {
        let path = strokeToPath(active, transform: viewModel.canvasTransform.matrix)
        context.stroke(path, with: .color(active.style.swiftUIColor),
                       lineWidth: active.style.lineWidth)
    }
}
```

**Upgrade path to Metal:** If you hit frame rate issues (likely around 5,000+ complex strokes), replace the `Canvas` view with a `MTKView`. The data model doesn't need to change — only the renderer.

---

## 8. Persistence (Core Data)

Avoid SwiftData. It had serious performance and stability issues on iOS 17/18. Core Data is the right call for a data-heavy app where correctness matters.

Schema design:

```
DocumentEntity
  ├── id: UUID
  ├── title: String
  ├── createdAt: Date
  ├── modifiedAt: Date
  └── strokes: [StrokeEntity]   (to-many, ordered)

StrokeEntity
  ├── id: UUID
  ├── sessionID: UUID
  ├── startTime: Date
  ├── endTime: Date
  ├── colorR/G/B/A: Float
  ├── lineWidth: Float
  ├── tool: String
  └── pointsData: Data          (encode [StrokePoint] as binary — don't make points a separate entity)
```

Store `StrokePoint` arrays as binary data (encode with `JSONEncoder` or a custom binary format) rather than individual Core Data entities. A single stroke can have thousands of points — individual entities would make queries slow and the object graph enormous.

---

## 9. Export Adapters

```swift
protocol ExportAdapter {
    func export(document: SplineDocument, viewport: CGRect?) throws -> Data
    var fileExtension: String { get }
    var mimeType: String { get }
}
```

### SVG
Serialize each stroke as an SVG `<path>` element with a cubic Bézier (`C` command) fit through the stroke points. Store force/time as custom `data-*` attributes for AI use later.

```xml
<path 
  d="M 100,200 C 105,198 110,205 115,210 ..."
  stroke="#000000"
  stroke-width="2.5"
  fill="none"
  data-start-time="1700000000.123"
  data-end-time="1700000001.456"
/>
```

No third-party library needed. Generating SVG path strings from `UIBezierPath` control points is straightforward.

### PDF
```swift
UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
    context.beginPage()
    // draw strokes into context using Core Graphics
}
```

### PNG
```swift
UIGraphicsImageRenderer(size: size).pngData { context in
    // draw strokes into context
}
```

---

## 10. Apple Pencil Pro Support

The Pencil Pro adds barrel roll (rotation) and squeeze. Both are useful for a note app.

```swift
// Barrel roll — already in UITouch via rollAngle
let roll = touch.rollAngle  // radians

// Squeeze gesture
let interaction = UIPencilInteraction()
interaction.delegate = self

func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
    // Switch tools, show palette, etc.
}
```

Store `rollAngle` in `StrokePoint` for all pencils (just 0.0 for non-Pro). This keeps the data model uniform.

---

## 11. AI Readiness

The data model stores everything needed for AI features without any schema changes:

| Feature | Data Available |
|---|---|
| Stroke order / sequence | `startTime` ordering across strokes |
| Stroke duration | `endTime - startTime` per stroke |
| Pen pressure patterns | `force` per point |
| Pen angle / shading | `azimuth` + `altitude` per point |
| Spatial layout | `canvasBounds` per stroke, `position` per point |
| Session grouping | `sessionID` groups strokes from one sitting |
| Temporal gaps | Time between `endTime` of one stroke and `startTime` of next |

When you're ready to add AI: serialize strokes to JSON and send to your model. The SVG export with `data-*` attributes also gives you a format that's straightforward to feed into a vision model.

---

## 12. UI Design

### Visual language

The app uses a **frosted glass** aesthetic consistent with iPadOS 26's Liquid Glass design language. All chrome (toolbar, palette, panels) floats above the canvas as translucent pills with backdrop blur. The canvas itself uses a warm off-white (`#f5f4f0`) with a dot grid and a faint large grid to give spatial grounding.

A shared `View+GlassCard` SwiftUI modifier handles `background(.ultraThinMaterial)`, `border`, `cornerRadius`, and `shadow` consistently across every chrome element. Nothing hardcodes these values inline.

Dark mode inverts to a near-black canvas (`#141414`) with dark glass panels. All color tokens are CSS/SwiftUI variables so dark mode is a single token swap.

### Layout

```
┌─────────────────────────────────────────────────────┐
│            [TopBarView — floating pill]              │
│                                                      │
│  [Palette]     · · · · · infinite canvas · · · ·    │
│  [left, v-     · · · · · · · · · · · · · · · · ·    │
│   centered]    · · · · strokes live here · · · ·    │
│                · · · · · · · · · · · · · · · · ·    │
│                                          [100%]      │
└─────────────────────────────────────────────────────┘
```

### TopBarView

Floating pill, horizontally centered at the top. Contains left-to-right:

- `DocumentTitleView` — editable document name
- Vertical separator
- `UndoRedoView` — undo + redo icon buttons
- Vertical separator
- `SelectToolButton` — toggles selection mode
- Vertical separator
- `ExportButton` — accent-colored, opens `ExportSheetView`

### PaletteView

Floating pill, vertically centered on the left edge. Items top to bottom:

1. `PenToolButton`
2. `PencilToolButton`
3. `MarkerToolButton`
4. — separator —
5. `EraserToolButton`
6. `LassoToolButton`
7. — separator —
8. `StrokeWeightButton` — three horizontal lines of increasing thickness as the icon. Hover expands `StrokeWeightFlyout` downward from this button, showing 5 dot sizes. Mouse-out with a short delay closes it.
9. — separator —
10. `ColorSwatchButton` — filled circle in the current ink color. Tap opens `ColorPanelView`.

Active tool gets a filled dark pill background. Inactive tools are transparent with hover state.

### ColorPanelView

Floats to the right of the palette, vertically centered. Contains:

- Section label: "Ink color"
- `ColorPresetGrid` — 5×3 grid of 15 preset color dots. Selected dot gets a blue ring.
- Horizontal separator
- `CustomColorRow` — "Custom" label + native `colorPicker` swatch + hex text field. Typing a valid hex or using the picker updates the swatch and deselects presets.
- `OpacitySlider` — range 0–100%, updates stroke opacity.

### ZoomIndicatorView

Small glass pill, bottom-right corner. Displays current zoom level (e.g. "100%"). Tapping resets to 100%.

### SelectionBoxView

Rendered above strokes when selection mode is active. Blue `#3d6bff` border with 8 white square handles (corners + edge midpoints). Hidden when not selecting.

---

## 13. What to Build First (Suggested Order)

1. `SplineApp.swift` + bare `CanvasContainerView` with a gray background
2. `CanvasUIView` with raw pencil touch capture (just print to console first)
3. `StrokePoint` / `Stroke` data model
4. `CanvasRenderer` — live rendering via SwiftUI `Canvas`
5. `CanvasTransform` — pan/zoom via `CGAffineTransform`
6. Core Data persistence
7. `PaletteView` + all tool buttons
8. `ColorPanelView` + `StrokeWeightFlyout`
9. `TopBarView` + `ExportButton` + `ExportSheetView`
10. SVG export, then PDF + PNG
11. `DocumentListView` — file browser / home screen
12. `ZoomIndicatorView` + `SelectionBoxView`
13. Apple Pencil Pro extras (squeeze gesture, haptics)
