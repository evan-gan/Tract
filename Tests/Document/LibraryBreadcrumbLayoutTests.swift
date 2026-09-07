import Foundation
import Testing
@testable import Tract

@Suite("Breadcrumb layout")
struct LibraryBreadcrumbLayoutTests {
    private func chain(_ names: [String]) -> [DocumentFolder] {
        var folders: [DocumentFolder] = []
        for name in names {
            folders.append(DocumentFolder(name: name, parentID: folders.last?.id))
        }
        return folders
    }

    @Test("A shallow path is shown whole, starting at the top level")
    func shallowPathsAreShownWhole() {
        let crumbs = LibraryBreadcrumbLayout.crumbs(for: chain(["Maths", "Algebra"]))

        #expect(crumbs.map(\.name) == ["Documents", "Maths", "Algebra"])
    }

    @Test("The top level alone is shown when nothing is open")
    func anEmptyPathIsJustTheTopLevel() {
        #expect(LibraryBreadcrumbLayout.crumbs(for: []).map(\.name) == ["Documents"])
    }

    @Test("A path at the limit still shows every folder")
    func thePathIsNotElidedUntilItHasTo() {
        let crumbs = LibraryBreadcrumbLayout.crumbs(for: chain(["A", "B", "C"]))

        #expect(crumbs.map(\.name) == ["Documents", "A", "B", "C"])
    }

    @Test("A deep path keeps the top level and the folders nearest the current one")
    func deepPathsDropTheMiddle() {
        let crumbs = LibraryBreadcrumbLayout.crumbs(for: chain(["A", "B", "C", "D", "E"]))

        #expect(crumbs.map(\.name) == ["Documents", "…", "C", "D", "E"])
    }

    @Test("The elision marker is not a destination")
    func theElisionLeadsNowhere() {
        let crumbs = LibraryBreadcrumbLayout.crumbs(for: chain(["A", "B", "C", "D"]))
        let elision = crumbs.first { $0 == .elision }

        #expect(elision != nil)
        #expect(elision?.folderID == nil)
    }

    @Test("Every folder crumb carries the folder it jumps to")
    func folderCrumbsCarryTheirDestination() {
        let path = chain(["Maths", "Algebra"])
        let crumbs = LibraryBreadcrumbLayout.crumbs(for: path)

        #expect(crumbs.compactMap(\.folderID) == path.map(\.id))
        // The top level is reached with nil, not with an id.
        #expect(crumbs.first?.folderID == nil)
    }
}
