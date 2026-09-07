import Foundation

/// Turns a `ProblemTag` into the text printed on a page.
///
/// Holds its own style table rather than reading a global one, so a caller can
/// format with extra notations — or override a built-in — without mutating
/// shared state. Styles it does not recognise still render, as digits, because a
/// document may legitimately carry a tag written by a newer build.
struct ProblemTagFormatter: Sendable {
    var styles: [String: ProblemLabelStyle]
    /// Placed between levels: "1.a.ii". Set to "" for "1aii".
    var levelSeparator: String
    /// Shown in place of an empty tag.
    var untitledText: String

    init(
        styles: [String: ProblemLabelStyle] = ProblemLabelStyle.builtIn,
        levelSeparator: String = ".",
        untitledText: String = "Untitled"
    ) {
        self.styles = styles
        self.levelSeparator = levelSeparator
        self.untitledText = untitledText
    }

    static let standard = ProblemTagFormatter()

    /// How a problem is written on a worksheet: "1", "1a", "1bIV". The levels
    /// already change alphabet as they nest (1 → a → I), so the separator only
    /// adds width to a heading that has to fit inside a small cell.
    static let compact = ProblemTagFormatter(levelSeparator: "")

    func text(for tag: ProblemTag) -> String {
        guard !tag.isEmpty else { return untitledText }
        return tag.components.map(text(for:)).joined(separator: levelSeparator)
    }

    /// Falls back through custom text, then the style's notation, then the bare
    /// ordinal — so a level always prints something a reader can act on, even
    /// when its notation is unknown here.
    func text(for component: ProblemLabelComponent) -> String {
        if let customText = component.customText, !customText.isEmpty { return customText }
        if let styled = styles[component.styleID]?.text(for: component.ordinal) { return styled }
        return String(component.ordinal)
    }
}
