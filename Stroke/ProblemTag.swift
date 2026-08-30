import Foundation

/// One level of a problem's address — the "1" in 1, the "a" in 1a, the "ii" in 1a(ii).
///
/// Deliberately stores an *ordinal* rather than the text it renders as. Sorting
/// reads only the ordinal, so a level numbered in roman numerals orders correctly
/// (vi before ix) where comparing the written form never could, and a style added
/// years from now sorts correctly without any change to the sorting code.
struct ProblemLabelComponent: Codable, Hashable, Sendable {
    /// Which notation this level is written in, as a plain string rather than a
    /// closed enum. That is what keeps the stored format open: a build that has
    /// never heard of a style still decodes, sorts, and re-saves the component
    /// intact instead of failing to read the document at all.
    var styleID: String
    /// 1-based position within this level: 1, 2, 3 → "1"/"a"/"i", "2"/"b"/"ii", …
    var ordinal: Int
    /// Verbatim text that overrides the style's notation, for a level that follows
    /// no scheme ("Bonus", "★"). Nil for ordinary levels.
    var customText: String?

    init(styleID: String, ordinal: Int, customText: String? = nil) {
        self.styleID = styleID
        self.ordinal = ordinal
        self.customText = customText
    }
}

extension ProblemLabelComponent {
    static func number(_ ordinal: Int) -> Self {
        Self(styleID: ProblemLabelStyle.number.id, ordinal: ordinal)
    }

    static func lowercaseLetter(_ ordinal: Int) -> Self {
        Self(styleID: ProblemLabelStyle.lowercaseLetter.id, ordinal: ordinal)
    }

    static func uppercaseLetter(_ ordinal: Int) -> Self {
        Self(styleID: ProblemLabelStyle.uppercaseLetter.id, ordinal: ordinal)
    }

    static func lowercaseRoman(_ ordinal: Int) -> Self {
        Self(styleID: ProblemLabelStyle.lowercaseRoman.id, ordinal: ordinal)
    }

    static func uppercaseRoman(_ ordinal: Int) -> Self {
        Self(styleID: ProblemLabelStyle.uppercaseRoman.id, ordinal: ordinal)
    }

    /// A level written as literal text, outside any numbering scheme. `ordinal`
    /// still decides where it sorts among its siblings.
    static func custom(_ text: String, ordinal: Int) -> Self {
        Self(styleID: ProblemLabelStyle.customID, ordinal: ordinal, customText: text)
    }
}

/// Which problem a stroke belongs to, addressed from the outermost level inwards:
/// `[1, a, ii]` is problem 1, part a, sub-part ii.
///
/// The array is the extension point. Levels are not named or typed — adding a
/// fourth or fifth level of nesting, or a new notation at any level, needs no
/// change to the stored format, so documents written today keep loading.
struct ProblemTag: Codable, Hashable, Sendable, Comparable {
    /// Outermost level first. Empty means untagged.
    var components: [ProblemLabelComponent]

    init(_ components: [ProblemLabelComponent] = []) {
        self.components = components
    }

    var isEmpty: Bool { components.isEmpty }

    /// How many levels deep this tag is addressed.
    var depth: Int { components.count }

    /// The first `levels` levels — the address of an ancestor. `[1, a, ii]` cut to
    /// 1 level is `[1]`, which is how every part of problem 1 collapses onto one
    /// heading when an export groups by problem rather than by part.
    func prefix(_ levels: Int) -> ProblemTag {
        ProblemTag(Array(components.prefix(max(levels, 0))))
    }

    func appending(_ component: ProblemLabelComponent) -> ProblemTag {
        ProblemTag(components + [component])
    }

    /// Orders parent before child and sibling by ordinal, comparing outermost
    /// level first — so 1, 1a, 1a(i), 1a(ii), 1b, 2, 10 come out in that order
    /// whatever notation each level is written in.
    static func < (lhs: ProblemTag, rhs: ProblemTag) -> Bool {
        for (left, right) in zip(lhs.components, rhs.components) {
            if left.ordinal != right.ordinal { return left.ordinal < right.ordinal }
            // Siblings sharing an ordinal are only possible across different
            // notations; these two tiebreaks exist to keep the order stable, and
            // carry no meaning of their own.
            if left.styleID != right.styleID { return left.styleID < right.styleID }
            let leftText = left.customText ?? ""
            let rightText = right.customText ?? ""
            if leftText != rightText { return leftText < rightText }
        }
        // Everything shared so far is equal, so the shorter address is the ancestor.
        return lhs.components.count < rhs.components.count
    }
}

extension ProblemTag: ExpressibleByArrayLiteral {
    init(arrayLiteral elements: ProblemLabelComponent...) {
        self.init(elements)
    }
}
