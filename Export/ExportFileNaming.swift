import Foundation

/// Turns a document title into a safe file name for an export.
enum ExportFileNaming {
    private static let placeholderName = "Drawing"

    /// A title is free text the user typed, so it can hold characters that mean
    /// something to the file system. A "/" is the dangerous one: passed to
    /// `URL.appending(path:)` it reads as a directory separator, so the write
    /// lands in a folder that does not exist and the export fails.
    ///
    /// - Returns: `<sanitised title>.<fileExtension>`, falling back to a
    ///   placeholder when the title has no usable characters left.
    static func fileName(title: String, fileExtension: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:")

        // Whether the title says anything is decided with the forbidden characters
        // *removed*, not replaced. Replacing first would turn "///" into "---",
        // which reads as a real name and would be used as the file's.
        let stripped = title
            .components(separatedBy: forbidden)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return "\(placeholderName).\(fileExtension)" }

        let sanitised = title
            .components(separatedBy: forbidden)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(sanitised).\(fileExtension)"
    }
}
