import Foundation

/// A notation a problem level can be written in: 1/2/3, a/b/c, i/ii/iii.
///
/// A struct with closures rather than an enum, so a new notation is a value
/// someone constructs — no case to add, no switch to exhaust, and nothing about
/// the stored format changes. `ProblemLabelComponent` refers to a style by `id`
/// alone, so an unrecognised id degrades to plain digits instead of failing.
struct ProblemLabelStyle: Sendable, Identifiable {
    let id: String
    let displayName: String

    /// Ordinal → written form. Nil when the ordinal is outside what the notation
    /// can express (roman numerals have no zero, and stop at 3999).
    private let format: @Sendable (Int) -> String?
    /// Written form → ordinal. Nil when the text is not valid in this notation.
    private let parse: @Sendable (String) -> Int?

    init(
        id: String,
        displayName: String,
        format: @escaping @Sendable (Int) -> String?,
        parse: @escaping @Sendable (String) -> Int?
    ) {
        self.id = id
        self.displayName = displayName
        self.format = format
        self.parse = parse
    }

    func text(for ordinal: Int) -> String? { format(ordinal) }

    func ordinal(for text: String) -> Int? { parse(text) }

    /// Reserved id for a level carrying literal text rather than a notation.
    /// No style is registered under it; the component's `customText` is used.
    static let customID = "custom"

    // MARK: - Built-in notations

    static let number = ProblemLabelStyle(
        id: "number",
        displayName: "1, 2, 3",
        format: { $0 >= 1 ? String($0) : nil },
        parse: { Int($0).flatMap { $0 >= 1 ? $0 : nil } }
    )

    static let lowercaseLetter = ProblemLabelStyle(
        id: "lowercaseLetter",
        displayName: "a, b, c",
        format: { NumeralNotation.letters($0) },
        parse: { NumeralNotation.letterOrdinal($0) }
    )

    static let uppercaseLetter = ProblemLabelStyle(
        id: "uppercaseLetter",
        displayName: "A, B, C",
        format: { NumeralNotation.letters($0)?.uppercased() },
        parse: { NumeralNotation.letterOrdinal($0) }
    )

    static let lowercaseRoman = ProblemLabelStyle(
        id: "lowercaseRoman",
        displayName: "i, ii, iii",
        format: { NumeralNotation.roman($0) },
        parse: { NumeralNotation.romanOrdinal($0) }
    )

    static let uppercaseRoman = ProblemLabelStyle(
        id: "uppercaseRoman",
        displayName: "I, II, III",
        format: { NumeralNotation.roman($0)?.uppercased() },
        parse: { NumeralNotation.romanOrdinal($0) }
    )

    /// The notations the app ships with, keyed by id for lookup during formatting.
    static let builtIn: [String: ProblemLabelStyle] = [
        number.id: number,
        lowercaseLetter.id: lowercaseLetter,
        uppercaseLetter.id: uppercaseLetter,
        lowercaseRoman.id: lowercaseRoman,
        uppercaseRoman.id: uppercaseRoman
    ]
}

/// Conversions between an ordinal and the ways people write it down.
enum NumeralNotation {
    /// 1 → "a", 26 → "z", 27 → "aa". Bijective base 26: there is no zero digit,
    /// which is why this is not a plain base conversion.
    static func letters(_ ordinal: Int) -> String? {
        guard ordinal >= 1 else { return nil }
        var remaining = ordinal
        var text = ""
        while remaining > 0 {
            let digit = (remaining - 1) % 26
            text = String(UnicodeScalar(UInt8(97 + digit))) + text
            remaining = (remaining - 1) / 26
        }
        return text
    }

    static func letterOrdinal(_ text: String) -> Int? {
        guard !text.isEmpty else { return nil }
        var ordinal = 0
        for character in text.lowercased() {
            guard let ascii = character.asciiValue, (97 ... 122).contains(ascii) else { return nil }
            ordinal = ordinal * 26 + Int(ascii - 96)
        }
        return ordinal
    }

    /// Largest-first symbol values, including the four subtractive pairs, so the
    /// greedy loop below emits canonical numerals (4 is "iv", never "iiii").
    private static let romanSymbols: [(value: Int, symbol: String)] = [
        (1000, "m"), (900, "cm"), (500, "d"), (400, "cd"),
        (100, "c"), (90, "xc"), (50, "l"), (40, "xl"),
        (10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i")
    ]

    private static let romanDigits: [Character: Int] = [
        "i": 1, "v": 5, "x": 10, "l": 50, "c": 100, "d": 500, "m": 1000
    ]

    /// Roman numerals cannot write zero, and above 3999 need overlines the app
    /// has no way to draw — both return nil rather than a wrong answer.
    static func roman(_ ordinal: Int) -> String? {
        guard (1 ... 3999).contains(ordinal) else { return nil }
        var remaining = ordinal
        var text = ""
        for (value, symbol) in romanSymbols {
            while remaining >= value {
                text += symbol
                remaining -= value
            }
        }
        return text
    }

    static func romanOrdinal(_ text: String) -> Int? {
        let lowered = text.lowercased()
        let characters = Array(lowered)
        guard !characters.isEmpty else { return nil }

        var ordinal = 0
        for (index, character) in characters.enumerated() {
            guard let value = romanDigits[character] else { return nil }
            // A smaller symbol before a larger one is subtractive: "ix" is 10 − 1.
            let next = index + 1 < characters.count ? romanDigits[characters[index + 1]] ?? 0 : 0
            ordinal += value < next ? -value : value
        }
        // Round-tripping rejects spellings that parse but nobody writes ("iiii", "ic").
        guard roman(ordinal) == lowered else { return nil }
        return ordinal
    }
}
