import Foundation

/// Which notation each level of the outline is written in: 1, then a, then I.
///
/// The depth limit lives here too, because the two are the same decision — the
/// app ships three notations, so the tree is three levels deep.
enum ProblemLevelNotation {
    /// Levels are 0-based, so the deepest legal level index is `maximumDepth - 1`.
    static let maximumDepth = 3

    private static let stylesByLevel: [ProblemLabelStyle] = [
        .number,          // 1, 2, 3
        .lowercaseLetter, // a, b, c
        .uppercaseRoman   // I, II, III
    ]

    /// Levels past the last notation fall back to plain digits rather than
    /// returning nil, so a deeper tree — should the limit ever be raised —
    /// still renders something a reader can act on.
    static func style(forLevel level: Int) -> ProblemLabelStyle {
        stylesByLevel.indices.contains(level) ? stylesByLevel[level] : .number
    }

    /// The label a node with `siblingIndex` would carry at `level`: (0, 0) → "1",
    /// (1, 1) → "b", (2, 2) → "III".
    static func label(level: Int, siblingIndex: Int) -> String {
        let component = component(level: level, siblingIndex: siblingIndex)
        return ProblemTagFormatter.standard.text(for: component)
    }

    static func component(level: Int, siblingIndex: Int) -> ProblemLabelComponent {
        ProblemLabelComponent(
            styleID: style(forLevel: level).id,
            ordinal: siblingIndex + 1
        )
    }
}
