import Testing
@testable import Tract

@Suite("Numeral notations")
struct NumeralNotationTests {
    @Test("Letters count a to z then carry into aa")
    func lettersCarryPastZ() {
        #expect(NumeralNotation.letters(1) == "a")
        #expect(NumeralNotation.letters(26) == "z")
        #expect(NumeralNotation.letters(27) == "aa")
        #expect(NumeralNotation.letters(52) == "az")
        #expect(NumeralNotation.letters(53) == "ba")
    }

    @Test("Letters have no zero or negative form")
    func lettersRejectNonPositiveOrdinals() {
        #expect(NumeralNotation.letters(0) == nil)
        #expect(NumeralNotation.letters(-1) == nil)
    }

    @Test("Roman numerals use the subtractive spellings people actually write")
    func romanUsesSubtractiveForms() {
        #expect(NumeralNotation.roman(4) == "iv")
        #expect(NumeralNotation.roman(9) == "ix")
        #expect(NumeralNotation.roman(14) == "xiv")
        #expect(NumeralNotation.roman(40) == "xl")
        #expect(NumeralNotation.roman(1987) == "mcmlxxxvii")
    }

    @Test("Roman numerals cannot write zero or anything past 3999")
    func romanRejectsUnwritableOrdinals() {
        #expect(NumeralNotation.roman(0) == nil)
        #expect(NumeralNotation.roman(4000) == nil)
    }

    @Test("Every notation round trips from ordinal to text and back")
    func notationsRoundTrip() {
        for ordinal in 1 ... 200 {
            let letters = NumeralNotation.letters(ordinal)
            #expect(letters.flatMap(NumeralNotation.letterOrdinal) == ordinal)

            let roman = NumeralNotation.roman(ordinal)
            #expect(roman.flatMap(NumeralNotation.romanOrdinal) == ordinal)
        }
    }

    @Test("Non-canonical roman spellings are rejected rather than silently accepted")
    func nonCanonicalRomanIsRejected() {
        #expect(NumeralNotation.romanOrdinal("iiii") == nil)
        #expect(NumeralNotation.romanOrdinal("ic") == nil)
        #expect(NumeralNotation.romanOrdinal("hello") == nil)
        #expect(NumeralNotation.romanOrdinal("") == nil)
    }

    @Test("Parsing ignores case, so I and i are the same numeral")
    func romanParsingIsCaseInsensitive() {
        #expect(NumeralNotation.romanOrdinal("XIV") == 14)
        #expect(NumeralNotation.letterOrdinal("AB") == 28)
    }
}

@Suite("Problem label styles")
struct ProblemLabelStyleTests {
    @Test("Each built-in notation writes its ordinals the way it is named")
    func builtInStylesFormatAsAdvertised() {
        #expect(ProblemLabelStyle.number.text(for: 3) == "3")
        #expect(ProblemLabelStyle.lowercaseLetter.text(for: 3) == "c")
        #expect(ProblemLabelStyle.uppercaseLetter.text(for: 3) == "C")
        #expect(ProblemLabelStyle.lowercaseRoman.text(for: 3) == "iii")
        #expect(ProblemLabelStyle.uppercaseRoman.text(for: 3) == "III")
    }

    @Test("Every built-in notation is registered under its own id")
    func builtInStylesAreRegistered() {
        for (id, style) in ProblemLabelStyle.builtIn {
            #expect(style.id == id)
        }
    }
}

@Suite("Formatting a problem tag")
struct ProblemTagFormatterTests {
    @Test("Levels are joined outermost first")
    func levelsJoinOutermostFirst() {
        let tag: ProblemTag = [.number(1), .lowercaseLetter(2), .lowercaseRoman(3)]

        #expect(ProblemTagFormatter.standard.text(for: tag) == "1.b.iii")
    }

    @Test("The separator between levels is configurable")
    func separatorIsConfigurable() {
        let tag: ProblemTag = [.number(1), .lowercaseLetter(1)]
        let formatter = ProblemTagFormatter(levelSeparator: "")

        #expect(formatter.text(for: tag) == "1a")
    }

    @Test("Custom text overrides the notation for a level that follows no scheme")
    func customTextWins() {
        let tag: ProblemTag = [.number(4), .custom("Bonus", ordinal: 1)]

        #expect(ProblemTagFormatter.standard.text(for: tag) == "4.Bonus")
    }

    @Test("A notation this build does not know falls back to the bare ordinal")
    func unknownStyleFallsBackToOrdinal() {
        let tag = ProblemTag([ProblemLabelComponent(styleID: "greekLetter", ordinal: 7)])

        #expect(ProblemTagFormatter.standard.text(for: tag) == "7")
    }

    @Test("An ordinal the notation cannot write falls back to the bare ordinal")
    func unwritableOrdinalFallsBack() {
        let tag: ProblemTag = [.lowercaseRoman(5000)]

        #expect(ProblemTagFormatter.standard.text(for: tag) == "5000")
    }

    @Test("A caller can format with a notation the app does not ship")
    func extraStylesCanBeSupplied() {
        // The extension point: a new notation is a value, not a new enum case.
        let greek = ProblemLabelStyle(
            id: "greekLetter",
            displayName: "α, β, γ",
            format: { ["α", "β", "γ"][safe: $0 - 1] },
            parse: { ["α", "β", "γ"].firstIndex(of: $0).map { $0 + 1 } }
        )
        var styles = ProblemLabelStyle.builtIn
        styles[greek.id] = greek
        let formatter = ProblemTagFormatter(styles: styles)

        let tag = ProblemTag([.number(1), ProblemLabelComponent(styleID: greek.id, ordinal: 2)])

        #expect(formatter.text(for: tag) == "1.β")
    }

    @Test("An empty tag shows the placeholder rather than an empty heading")
    func emptyTagShowsPlaceholder() {
        #expect(ProblemTagFormatter.standard.text(for: ProblemTag()) == "Untitled")
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
