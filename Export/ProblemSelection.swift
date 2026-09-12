import Foundation

/// Which problems an export is limited to.
///
/// Held as tags rather than node ids because a tag is both what the picker shows
/// and what the exported file is named after. The outline resolves a stroke
/// either way, and an address stays meaningful in a file name long after the
/// node id behind it has stopped meaning anything to anyone.
///
/// Membership is by *full* address, not by prefix: the picker only offers
/// problems that have ink filed directly under them, so 1 and 1a are separate
/// choices and ticking 1 must not quietly drag 1a's work along with it.
struct ProblemSelection: Sendable, Hashable {
    /// The chosen problems' addresses. Empty means no limit at all — the whole
    /// document is exported, which is what every other layout wants.
    var tags: Set<ProblemTag>

    /// No limit: every stroke in the document.
    static let everything = ProblemSelection(tags: [])

    /// Past this many, the names are longer than the title they hang off, so the
    /// file is named by count instead.
    private static let maximumNamedProblems = 3

    init(tags: Set<ProblemTag> = []) {
        self.tags = tags
    }

    var limitsTheDocument: Bool { !tags.isEmpty }

    /// The document with every stroke outside the selection dropped, so the
    /// existing exporters render a subset without knowing anything about
    /// problems.
    ///
    /// - Parameter document: The document to narrow.
    /// - Returns: The document untouched when nothing is selected; otherwise a
    ///   copy carrying only the selected problems' strokes, in drawing order.
    func applied(to document: SplineDocument) -> SplineDocument {
        guard limitsTheDocument else { return document }

        let selectedNodeIDs = nodeIDs(matching: document.problemOutline)
        var limited = document
        limited.strokes = document.strokes.filter { stroke in
            guard let nodeID = stroke.problemNodeID else { return false }
            return selectedNodeIDs.contains(nodeID)
        }
        return limited
    }

    /// Appended to the document's title so a shared file says which problems are
    /// in it — "Set 3 1a.png" rather than another "Set 3.png".
    ///
    /// - Parameter formatter: Renders each tag; compact by default, because the
    ///   levels already change alphabet as they nest and a file name is tight.
    /// - Returns: The suffix, or nil when nothing is selected — which leaves the
    ///   adapter's own suffix in place.
    func fileNameSuffix(formatter: ProblemTagFormatter = .compact) -> String? {
        guard limitsTheDocument else { return nil }

        let labels = tags.sorted().map(formatter.text(for:))
        guard labels.count <= Self.maximumNamedProblems else {
            return " \(labels.count) problems"
        }
        return " " + labels.joined(separator: "-")
    }

    /// Ids of every node whose address is one of the selected tags.
    ///
    /// Resolved in a single walk of the tree rather than by asking the outline
    /// about each stroke: a page of work is thousands of strokes and that lookup
    /// is a depth-first search, so per-stroke resolution is quadratic.
    private func nodeIDs(matching outline: ProblemOutline) -> Set<UUID> {
        var matches: Set<UUID> = []

        func visit(_ siblings: [ProblemNode], under path: ProblemPath) {
            for (index, node) in siblings.enumerated() {
                let nodePath = path + [index]
                if tags.contains(outline.tag(at: nodePath)) { matches.insert(node.id) }
                visit(node.children, under: nodePath)
            }
        }

        visit(outline.roots, under: [])
        return matches
    }
}

/// One problem offered in the export picker's chooser.
struct ExportProblemOption: Identifiable, Hashable, Sendable {
    let tag: ProblemTag
    /// How the problem is written — "1", "1a", "2bIV".
    let label: String

    var id: ProblemTag { tag }

    /// Every problem in a document with ink filed directly under it, in reading
    /// order.
    ///
    /// Problems with no ink of their own are left out, including ancestors whose
    /// work all sits in their parts: there is nothing to export under them, and
    /// each of those parts is offered in its own right.
    ///
    /// - Parameters:
    ///   - document: The document being exported, snapshotted by the caller.
    ///   - formatter: Renders each problem's address into its chip label.
    /// - Returns: Options ordered 1, 1a, 1b, 2, 10 — the order the problems are
    ///   written in.
    static func options(
        in document: SplineDocument,
        formatter: ProblemTagFormatter = .compact
    ) -> [ExportProblemOption] {
        ProblemGrouping.groups(
            from: document.strokes,
            outline: document.problemOutline,
            formatter: formatter
        )
        .compactMap { group in
            // Untagged work carries no address to name or tick, and the grouping
            // only returns it when asked to — this is the type, not a filter.
            group.tag.map { ExportProblemOption(tag: $0, label: group.label) }
        }
    }
}
