import SwiftUI
import UIKit

/// The paper a document is drawn on. Stored with the document rather than as an
/// app-wide setting: a blueprint sheet and a page of ruled notes are different
/// kinds of work, and a user who has both open should not have to re-pick the
/// paper every time they switch.
///
/// The raw values are written to disk — never rename one.
enum CanvasBackgroundStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    /// Faint dots on white. The app's original paper, and still the default.
    case dots
    case blank
    /// Squared paper: a light lattice with a heavier line every few cells.
    case grid
    /// Horizontal rules on white, with a margin rule down the canvas origin.
    case ruled
    /// Ruled, on the yellow of a legal pad.
    case legalPad
    /// White lines on deep blue drafting paper.
    case blueprint

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dots: "Dot grid"
        case .blank: "Blank"
        case .grid: "Graph"
        case .ruled: "Ruled"
        case .legalPad: "Legal pad"
        case .blueprint: "Blueprint"
        }
    }

    var paper: CanvasPaperStyle {
        switch self {
        case .dots:
            CanvasPaperStyle(sheet: .paperWhite, pattern: .dots(color: .inkFaint))
        case .blank:
            CanvasPaperStyle(sheet: .paperWhite, pattern: .blank)
        case .grid:
            CanvasPaperStyle(
                sheet: .paperWhite,
                pattern: .grid(minor: .inkFaintest, major: .inkFaint, majorEvery: 4)
            )
        case .ruled:
            CanvasPaperStyle(sheet: .paperWhite, pattern: .ruled(rule: .ruleBlue, margin: .marginRed))
        case .legalPad:
            CanvasPaperStyle(sheet: .paperYellow, pattern: .ruled(rule: .ruleBlue, margin: .marginRed))
        case .blueprint:
            CanvasPaperStyle(
                sheet: .blueprintBlue,
                pattern: .grid(minor: .blueprintLineFaint, major: .blueprintLine, majorEvery: 4)
            )
        }
    }

    /// The sheet colour for the UIKit rasterisers — thumbnails and exports draw
    /// with `CGContext`, not with SwiftUI's `Canvas`.
    var sheetUIColor: UIColor { UIColor(paper.sheet) }

    /// True when the sheet is dark enough that black ink would disappear into it.
    /// The canvas uses it to pick the colour a fresh stroke starts with.
    var needsLightInk: Bool {
        self == .blueprint
    }
}

/// What `CanvasPaperPainter` needs to draw one sheet: its colour and the pattern
/// printed on it. Kept separate from the style cases so a new paper is a palette
/// entry rather than a new branch in the renderer.
struct CanvasPaperStyle: Equatable {
    var sheet: Color
    var pattern: CanvasPaperPattern
}

/// A repeating pattern printed on the paper, in canvas space — it pans and zooms
/// with the ink rather than sitting still behind it.
enum CanvasPaperPattern: Equatable {
    case blank
    case dots(color: Color)
    /// A full lattice. `majorEvery` counts full-density cells between heavy lines.
    case grid(minor: Color, major: Color, majorEvery: Int)
    /// Horizontal rules only, with an optional vertical margin rule standing on
    /// canvas x = 0 — the infinite canvas has no page edge to hang it off.
    case ruled(rule: Color, margin: Color?)
}

/// Paper palette. Centralised here so every sheet can be re-skinned in one place
/// instead of hunting literals through the renderer and the swatches.
private extension Color {
    static let paperWhite = Color.white
    static let paperYellow = Color(red: 0.99, green: 0.96, blue: 0.80)
    static let blueprintBlue = Color(red: 0.06, green: 0.20, blue: 0.42)

    static let inkFaint = Color.black.opacity(0.08)
    static let inkFaintest = Color.black.opacity(0.05)
    static let ruleBlue = Color(red: 0.36, green: 0.51, blue: 0.73).opacity(0.45)
    static let marginRed = Color(red: 0.85, green: 0.36, blue: 0.38).opacity(0.55)
    static let blueprintLine = Color.white.opacity(0.30)
    static let blueprintLineFaint = Color.white.opacity(0.14)
}
