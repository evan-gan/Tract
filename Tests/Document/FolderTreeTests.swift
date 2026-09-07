import Foundation
import Testing
@testable import Tract

@Suite("Folder tree")
struct FolderTreeTests {
    /// A three-level tree: Maths ▸ Algebra ▸ Quadratics, plus a sibling Science.
    private struct Fixture {
        let maths: DocumentFolder
        let science: DocumentFolder
        let algebra: DocumentFolder
        let quadratics: DocumentFolder
        let tree: FolderTree

        init() {
            let maths = DocumentFolder(name: "Maths")
            let science = DocumentFolder(name: "Science")
            let algebra = DocumentFolder(name: "Algebra", parentID: maths.id)
            let quadratics = DocumentFolder(name: "Quadratics", parentID: algebra.id)
            self.maths = maths
            self.science = science
            self.algebra = algebra
            self.quadratics = quadratics
            self.tree = FolderTree([maths, science, algebra, quadratics])
        }
    }

    @Test("Children are the folders directly inside a parent, name-sorted")
    func childrenAreDirectAndSorted() {
        let fixture = Fixture()

        #expect(fixture.tree.children(of: nil).map(\.name) == ["Maths", "Science"])
        #expect(fixture.tree.children(of: fixture.maths.id).map(\.name) == ["Algebra"])
        #expect(fixture.tree.children(of: fixture.quadratics.id).isEmpty)
    }

    @Test("A folder's path runs from the top level down to the folder itself")
    func pathIsRootFirst() {
        let fixture = Fixture()

        #expect(fixture.tree.path(to: fixture.quadratics.id).map(\.name) == ["Maths", "Algebra", "Quadratics"])
        #expect(fixture.tree.path(to: fixture.maths.id).map(\.name) == ["Maths"])
        #expect(fixture.tree.path(to: UUID()).isEmpty)
    }

    @Test("Descendants reach every level of nesting, not just the first")
    func descendantsAreRecursive() {
        let fixture = Fixture()

        #expect(Set(fixture.tree.descendants(of: fixture.maths.id)) == [fixture.algebra.id, fixture.quadratics.id])
        #expect(fixture.tree.descendants(of: fixture.science.id).isEmpty)
    }

    @Test("A folder cannot be moved into itself or into anything nested inside it")
    func movesThatWouldMakeACycleAreRejected() {
        let fixture = Fixture()

        #expect(fixture.tree.canMove(folderID: fixture.maths.id, into: fixture.maths.id) == false)
        #expect(fixture.tree.canMove(folderID: fixture.maths.id, into: fixture.algebra.id) == false)
        #expect(fixture.tree.canMove(folderID: fixture.maths.id, into: fixture.quadratics.id) == false)
    }

    @Test("Moving into a sibling, an unrelated folder, or the top level is allowed")
    func legalMovesAreAccepted() {
        let fixture = Fixture()

        #expect(fixture.tree.canMove(folderID: fixture.maths.id, into: fixture.science.id))
        #expect(fixture.tree.canMove(folderID: fixture.quadratics.id, into: nil))
        #expect(fixture.tree.canMove(folderID: fixture.quadratics.id, into: fixture.science.id))
    }

    @Test("Moving into a folder that does not exist is rejected")
    func unknownDestinationIsRejected() {
        let fixture = Fixture()

        #expect(fixture.tree.canMove(folderID: fixture.maths.id, into: UUID()) == false)
        #expect(fixture.tree.canMove(folderID: UUID(), into: nil) == false)
    }

    @Test("A folder whose parent is missing is shown at the top level rather than lost")
    func orphansSurfaceAtTheTopLevel() {
        let orphan = DocumentFolder(name: "Stranded", parentID: UUID())
        let tree = FolderTree([orphan])

        #expect(tree.children(of: nil).map(\.id) == [orphan.id])
        #expect(tree.path(to: orphan.id).map(\.id) == [orphan.id])
    }

    @Test("A parent cycle in damaged data terminates instead of hanging")
    func cyclesInStoredDataDoNotHang() {
        // Only reachable from a hand-edited or half-written folders.json, but a
        // tree walk that loops forever takes the whole library down with it.
        let firstID = UUID()
        let secondID = UUID()
        let tree = FolderTree([
            DocumentFolder(id: firstID, name: "First", parentID: secondID),
            DocumentFolder(id: secondID, name: "Second", parentID: firstID)
        ])

        #expect(tree.path(to: firstID).count == 2)
        #expect(tree.descendants(of: firstID) == [secondID])
    }
}
