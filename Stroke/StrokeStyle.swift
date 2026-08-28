import SwiftUI

/// The visual appearance of a stroke, independent of its geometry.
struct StrokeStyle: Codable, Sendable {
    /// RGBA stored as SIMD for future Metal rendering compatibility.
    var color: SIMD4<Float>
    /// Base line width; the renderer modulates this by per-point force.
    var lineWidth: CGFloat
    var opacity: CGFloat
    var tool: ToolType

    /// Converts the SIMD4 color to SwiftUI Color for Canvas rendering.
    var swiftUIColor: Color {
        Color(
            red: Double(color.x),
            green: Double(color.y),
            blue: Double(color.z),
            opacity: Double(color.w) * Double(opacity)
        )
    }

    static let `default` = StrokeStyle(
        color: SIMD4(0, 0, 0, 1),
        lineWidth: 2.0,
        opacity: 1.0,
        tool: .pen
    )
}

enum ToolType: String, CaseIterable, Codable, Sendable {
    case pen, eraser, lasso

    /// Tools that lay down ink. Only these carry a stroke colour, so the colour
    /// picker shows nothing selected while any other tool is active.
    static let drawingTools: [ToolType] = allCases.filter(\.isDrawingTool)

    var isDrawingTool: Bool {
        switch self {
        case .pen: true
        case .eraser, .lasso: false
        }
    }

    var iconName: String {
        switch self {
        case .pen: "pencil.tip"
        case .eraser: "eraser"
        case .lasso: "lasso"
        }
    }

    var displayName: String {
        switch self {
        case .pen: "Pen"
        case .eraser: "Eraser"
        case .lasso: "Lasso"
        }
    }
}
