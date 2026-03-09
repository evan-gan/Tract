# Spline — Project Context

Infinite canvas vector note-taking app for iPad. Every stroke stores full Apple Pencil telemetry (position, pressure, tilt, timing) for future AI features. Target: iPadOS 26+.

Open `Tract.xcodeproj` in Xcode 26.

---

## Key architectural rules

- `CanvasViewModel` is the single source of truth for all canvas state. Every component reads from it or calls methods on it.
- `CanvasContainerView` is the only view that imports from multiple feature folders. Everything else stays within its own folder.
- `@Observable @MainActor` throughout — no `ObservableObject` or `@Published`.
- Pencil draws; fingers pan/zoom only.

---

## Codebase map

```
Tract/
├── Tract.xcodeproj/              # Xcode project (regenerate via generate_project.py if needed)
├── generate_project.py           # Regenerates project.pbxproj — run after adding/removing files
│
├── App/
│   └── SplineApp.swift           # @main entry point → DocumentListView
│
├── Canvas/                       # Core drawing engine
│   ├── CanvasContainerView.swift # Root screen — composes everything, owns CanvasViewModel
│   ├── CanvasView.swift          # UIViewRepresentable wrapper (no logic)
│   ├── CanvasUIView.swift        # UIView — pencil touches + pan/pinch gestures
│   ├── CanvasRenderer.swift      # SwiftUI Canvas — strokes → screen paths
│   ├── CanvasViewModel.swift     # @Observable: all canvas state + undo/redo
│   └── CanvasTransform.swift     # Pan/zoom value type + screen↔canvas conversion
│
├── Toolbar/                      # Top floating bar
│   ├── TopBarView.swift          # Assembles all toolbar pieces
│   ├── DocumentTitleView.swift   # Editable title pill
│   ├── UndoRedoView.swift        # Undo + redo buttons
│   ├── SelectToolButton.swift    # Selection mode toggle
│   └── ExportButton.swift        # Opens ExportSheetView
│
├── Palette/                      # Left side tool palette
│   ├── PaletteView.swift         # Stacks tool buttons with separators; hosts ColorPanelView
│   ├── ToolButton.swift          # Shared active/inactive button base
│   ├── PenToolButton.swift
│   ├── PencilToolButton.swift
│   ├── MarkerToolButton.swift
│   ├── EraserToolButton.swift
│   ├── LassoToolButton.swift
│   ├── StrokeWeightButton.swift  # Icon + flyout trigger
│   ├── StrokeWeightFlyout.swift  # 5-option weight picker (self-contained)
│   └── ColorSwatchButton.swift   # Opens ColorPanelView
│
├── ColorPanel/                   # Color picker panel (floats right of palette)
│   ├── ColorPanelView.swift      # Assembles grid + custom + opacity
│   ├── ColorPresetGrid.swift     # 15 preset color dots
│   ├── CustomColorRow.swift      # Native picker + hex input
│   └── OpacitySlider.swift
│
├── Overlay/                      # Floating chrome above canvas
│   ├── ZoomIndicatorView.swift   # "100%" readout, bottom-right. Tap → reset zoom.
│   └── SelectionBoxView.swift    # Blue selection rect + 8 handles
│
├── Stroke/                       # Pure data types — no UIKit/SwiftUI imports
│   ├── StrokePoint.swift         # Single pencil sample (position, force, azimuth, altitude, roll)
│   ├── Stroke.swift              # Full pen-down→pen-up gesture
│   └── StrokeStyle.swift         # Color (SIMD4<Float>), width, opacity, ToolType
│
├── Document/                     # Document model + persistence
│   ├── SplineDocument.swift      # In-memory top-level document model
│   ├── DocumentStore.swift       # @Observable Core Data stack + CRUD
│   ├── DocumentListView.swift    # Home screen — NavigationSplitView
│   └── DocumentListRow.swift     # Single document row
│
├── Export/
│   ├── ExportAdapter.swift       # Protocol all exporters conform to
│   ├── ExportSheetView.swift     # Format picker → system share sheet
│   ├── SVGExporter.swift         # Strokes → SVG paths with data-* AI attributes
│   ├── PDFExporter.swift         # UIGraphicsPDFRenderer
│   └── PNGExporter.swift         # UIGraphicsImageRenderer
│
├── Utilities/
│   ├── CGPoint+Math.swift        # +, -, *, distance, midpoint
│   ├── Color+Hex.swift           # Color(hex:), hexString, SIMD4<Float>(color:)
│   └── View+GlassCard.swift      # .glassCard() modifier — shared frosted glass style
│
├── Assets.xcassets/              # AccentColor + AppIcon slots
└── Persistence.xcdatamodeld/     # Core Data schema: DocumentEntity + StrokeEntity
```

---

## Core Data schema

| Entity | Key fields |
|---|---|
| `DocumentEntity` | id, title, createdAt, modifiedAt, canvasOriginX/Y, canvasScale, → strokes (to-many) |
| `StrokeEntity` | id, sessionID, startTime, endTime, colorR/G/B/A, lineWidth, opacity, tool, pointsData (JSON-encoded `[StrokePoint]`), → document |

Points are stored as binary JSON, not individual entities — a stroke can have thousands of points.

---

## Input pipeline

```
Apple Pencil → UIView.touchesBegan/Moved/Ended
  → guard touch.type == .pencil
  → coalescedTouches(for:)  ← captures all 240 Hz samples
  → StrokePoint (screen → canvas via CanvasTransform.toCanvas)
  → CanvasViewModel.beginStroke / continueStroke / endStroke
  → SwiftUI Canvas re-renders
```

---

## Where to make common changes

| Change | File |
|---|---|
| Add a new tool | `ToolType` in `StrokeStyle.swift`, new `*ToolButton.swift`, add to `PaletteView.swift` |
| Change canvas background | `CanvasBackgroundView` in `CanvasContainerView.swift` |
| Add a new export format | New `*Exporter.swift` conforming to `ExportAdapter`, add to `ExportSheetView.adapters` |
| Change frosted glass style | `View+GlassCard.swift` |
| Change preset colors | `presetColors` array in `ColorPresetGrid.swift` |
| Change stroke smoothing | `CanvasRenderer.buildPath(for:)` |
| Swap renderer for Metal | Replace `CanvasRenderer.swift` with an `MTKView` wrapper — data model unchanged |
| Add AI feature | Read from `Stroke.points` (telemetry), `startTime`/`endTime`, `sessionID` |
