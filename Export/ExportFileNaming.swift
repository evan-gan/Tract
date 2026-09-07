import Foundation

/// Turns a document title, and optionally the library folders it is filed in,
/// into a safe file name for an export.
enum ExportFileNaming {
    private static let placeholderName = "Drawing"

    /// Characters that mean something to the file system. "/" is the dangerous
    /// one: passed to `URL.appending(path:)` it reads as a directory separator,
    /// so the write lands in a folder that does not exist and the export fails.
    private static let forbidden = CharacterSet(charactersIn: "/\\:")

    /// - Parameters:
    ///   - title: The document's title, as the user typed it.
    ///   - folderPath: The library folders containing the document, outermost
    ///     first. Empty for a top-level document, which then gets no prefix.
    ///   - fileExtension: The exporter's extension, without a leading dot.
    /// - Returns: `<folders joined by ".">.<sanitised title>.<fileExtension>`,
    ///   falling back to a placeholder when the title has no usable characters.
    static func fileName(title: String, folderPath: [String] = [], fileExtension: String) -> String {
        let name = sanitisedTitle(title) ?? placeholderName
        let prefix = folderPath.compactMap(sanitisedPathComponent).joined(separator: ".")
        guard !prefix.isEmpty else { return "\(name).\(fileExtension)" }
        return "\(prefix).\(name).\(fileExtension)"
    }

    /// The title with forbidden characters replaced, or nil when it says nothing.
    ///
    /// Whether the title says anything is decided with the forbidden characters
    /// *removed*, not replaced. Replacing first would turn "///" into "---",
    /// which reads as a real name and would be used as the file's.
    private static func sanitisedTitle(_ title: String) -> String? {
        let stripped = title
            .components(separatedBy: forbidden)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return nil }

        return title
            .components(separatedBy: forbidden)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A folder name reduced to one segment of the dotted prefix.
    ///
    /// Periods are replaced along with the file-system characters: here the
    /// period is the separator between folders, so a folder called "Unit 1.2"
    /// would otherwise read back as two levels of nesting.
    private static func sanitisedPathComponent(_ folderName: String) -> String? {
        let separators = forbidden.union(CharacterSet(charactersIn: "."))
        let stripped = folderName
            .components(separatedBy: separators)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return nil }

        return folderName
            .components(separatedBy: separators)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
