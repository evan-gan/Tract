import Foundation
import Testing
@testable import Tract

@Suite("Library outline")
struct LibraryOutlineTests {
    private let maths: DocumentFolder
    private let science: DocumentFolder
    private let algebra: DocumentFolder
    private let tree: FolderTree
    private let documents: [DocumentMetadata]

    init() {
        let maths = DocumentFolder(name: "Maths")
        let science = DocumentFolder(name: "Science")
        let algebra = DocumentFolder(name: "Algebra", parentID: maths.id)
        self.maths = maths
        self.science = science
        self.algebra = algebra
        self.tree = FolderTree([maths, science, algebra])
        self.documents = [
            DocumentMetadata(title: "Loose page", modifiedAt: .now),
            DocumentMetadata(title: "Homework", modifiedAt: .now.addingTimeInterval(-60), folderID: maths.id),
            DocumentMetadata(title: "Quadratics", modifiedAt: .now, folderID: algebra.id)
        ]
    }

    private func names(_ rows: [LibraryOutlineRow]) -> [String] {
        rows.map { row in
            switch row.item {
            case .folder(let folder): folder.name
            case .document(let metadata): metadata.title
            }
        }
    }

    @Test("A collapsed outline lists only the top level, folders before documents")
    func collapsedOutlineShowsOneLevel() {
        let rows = LibraryOutline.rows(tree: tree, documents: documents)

        #expect(names(rows) == ["Maths", "Science", "Loose page"])
        #expect(rows.allSatisfy { $0.depth == 0 })
    }

    @Test("Expanding a folder lists its contents beneath it, indented one level")
    func expandingAFolderRevealsItsContents() {
        let rows = LibraryOutline.rows(tree: tree, documents: documents, expandedFolderIDs: [maths.id])

        #expect(names(rows) == ["Maths", "Algebra", "Homework", "Science", "Loose page"])
        #expect(rows.first { $0.folder?.id == algebra.id }?.depth == 1)
        #expect(rows.first { $0.document?.title == "Homework" }?.depth == 1)
        // The sibling folder and the loose document stay where they were.
        #expect(rows.first { $0.folder?.id == science.id }?.depth == 0)
    }

    @Test("Nested folders keep nesting, each level indented one deeper")
    func expansionIsRecursive() {
        let rows = LibraryOutline.rows(
            tree: tree,
            documents: documents,
            expandedFolderIDs: [maths.id, algebra.id]
        )

        #expect(names(rows) == ["Maths", "Algebra", "Quadratics", "Homework", "Science", "Loose page"])
        #expect(rows.first { $0.document?.title == "Quadratics" }?.depth == 2)
    }

    @Test("Expanding a folder that is not showing changes nothing")
    func expandingACollapsedAncestorsChildIsIgnored() {
        // Algebra is open, but Maths — which contains it — is not, so nothing of
        // Algebra's should appear.
        let rows = LibraryOutline.rows(tree: tree, documents: documents, expandedFolderIDs: [algebra.id])

        #expect(names(rows) == ["Maths", "Science", "Loose page"])
    }

    @Test("An outline rooted inside a folder starts from that folder's contents")
    func outlineCanBeRootedInAFolder() {
        let rows = LibraryOutline.rows(tree: tree, documents: documents, in: maths.id)

        #expect(names(rows) == ["Algebra", "Homework"])
        #expect(rows.allSatisfy { $0.depth == 0 })
    }

    @Test("Documents in a folder are listed newest edit first")
    func documentsAreNewestFirst() {
        let folder = DocumentFolder(name: "Notes")
        let older = DocumentMetadata(title: "Older", modifiedAt: .now.addingTimeInterval(-600), folderID: folder.id)
        let newer = DocumentMetadata(title: "Newer", modifiedAt: .now, folderID: folder.id)

        let rows = LibraryOutline.rows(
            tree: FolderTree([folder]),
            documents: [older, newer],
            expandedFolderIDs: [folder.id]
        )

        #expect(names(rows) == ["Notes", "Newer", "Older"])
    }

    @Test("A folder cycle in damaged data does not expand forever")
    func cyclesTerminate() {
        let firstID = UUID()
        let secondID = UUID()
        let cyclic = FolderTree([
            DocumentFolder(id: firstID, name: "First", parentID: secondID),
            DocumentFolder(id: secondID, name: "Second", parentID: firstID)
        ])

        let rows = LibraryOutline.rows(
            tree: cyclic,
            documents: [],
            in: firstID,
            expandedFolderIDs: [firstID, secondID]
        )

        #expect(rows.count < 10)
    }
}
