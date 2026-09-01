import SwiftUI

/// The dock's tool glyphs. Pen and lasso are hand-drawn rather than SF
/// Symbols because both need something a system glyph can't give them — the
/// pen a tip filled with the live ink colour, the lasso a dashed stroke.
/// Eraser has no such need, so it keeps the system symbol.
struct ToolIconView: View {
    let tool: ToolType
    let color: AnyShapeStyle
    /// Ink the pen would lay down right now. Ignored by the other tools.
    var inkColor: Color = .primary

    var body: some View {
        switch tool {
        case .pen:
            PencilIcon(color: color, inkColor: inkColor)
        case .eraser:
            Image(systemName: tool.iconName)
                .font(.system(size: 19))
                .foregroundStyle(color)
        case .lasso:
            LassoIcon(color: color)
        }
    }
}

/// Duotone pencil tilted 45°, drawn in a 24x24 box. The barrel carries a soft
/// fill so the glyph has a body rather than reading as bare outlines, and only
/// the graphite tip takes the ink colour — that keeps the pen matching the rest
/// of the dock's chrome while still showing what it will draw with.
private struct PencilIcon: View {
    let color: AnyShapeStyle
    let inkColor: Color

    private static let stroke = SwiftUI.StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
    private static let tipOutline = SwiftUI.StrokeStyle(lineWidth: 0.75, lineCap: .round, lineJoin: .round)

    var body: some View {
        ZStack {
            barrel.fill(color.opacity(0.16))
            barrel.stroke(color, style: Self.stroke)
            ferrule.stroke(color, style: Self.stroke)
            woodTaper.stroke(color, style: Self.stroke)
            graphiteTip.fill(inkColor)
            // Pale inks (white especially) would otherwise vanish into the glass.
            graphiteTip.stroke(color.opacity(0.5), style: Self.tipOutline)
        }
        .frame(width: 24, height: 24)
        .rotationEffect(.degrees(45))
    }

    private var barrel: Path {
        Path(CGRect(x: 9, y: 2, width: 6, height: 12))
    }

    private var ferrule: Path {
        Path { path in
            path.move(to: CGPoint(x: 9, y: 6))
            path.addLine(to: CGPoint(x: 15, y: 6))
        }
    }

    private var woodTaper: Path {
        Path { path in
            path.move(to: CGPoint(x: 9, y: 14))
            path.addLine(to: CGPoint(x: 15, y: 14))
            path.addLine(to: CGPoint(x: 12, y: 19))
            path.closeSubpath()
        }
    }

    private var graphiteTip: Path {
        Path { path in
            path.move(to: CGPoint(x: 10.4, y: 18))
            path.addLine(to: CGPoint(x: 13.6, y: 18))
            path.addLine(to: CGPoint(x: 12, y: 21))
            path.closeSubpath()
        }
    }
}

/// The lasso's loop dashed to read as the "marching ants" selection
/// convention. Static — the dock has no way to animate a stroke dash phase
/// without a per-frame timer, and the dashes alone carry the idea.
private struct LassoIcon: View {
    let color: AnyShapeStyle

    private static let dashed = SwiftUI.StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round, dash: [2, 2.4])
    private static let solid = SwiftUI.StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)

    var body: some View {
        ZStack {
            Ellipse()
                .stroke(color, style: Self.dashed)
                .frame(width: 15, height: 10.5)
                .offset(y: -2.5)
            tail.stroke(color, style: Self.solid)
            Circle()
                .fill(color)
                .frame(width: 2.6, height: 2.6)
                .offset(x: 2, y: 7)
        }
        .frame(width: 19, height: 19)
    }

    private var tail: Path {
        Path { path in
            path.move(to: CGPoint(x: -2, y: 2))
            path.addCurve(
                to: CGPoint(x: 2, y: 6.3),
                control1: CGPoint(x: -3.6, y: 5.4),
                control2: CGPoint(x: -0.6, y: 6.6)
            )
        }
    }
}
