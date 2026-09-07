import Foundation
import Testing
@testable import Tract

@Suite("Library view mode")
struct LibraryViewModeTests {
    /// Its own defaults domain, so the test never reads or writes the real
    /// preference the app stores.
    private func isolatedDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "LibraryViewModeTests-\(UUID().uuidString)"))
    }

    @Test("A library that has never been switched opens as a grid")
    func gridIsTheDefault() throws {
        #expect(LibraryViewMode.restored(from: try isolatedDefaults()) == .grid)
    }

    @Test("The chosen layout is remembered")
    func theChoiceIsRemembered() throws {
        let defaults = try isolatedDefaults()

        LibraryViewMode.persist(.list, to: defaults)

        #expect(LibraryViewMode.restored(from: defaults) == .list)
    }

    @Test("An unrecognised stored value falls back to the grid rather than nothing")
    func damagedValueFallsBack() throws {
        let defaults = try isolatedDefaults()
        defaults.set("carousel", forKey: LibraryViewMode.defaultsKey)

        #expect(LibraryViewMode.restored(from: defaults) == .grid)
    }

    @Test("Each mode offers the other one, and says so on the button")
    func toggleDescribesWhatItWillDo() {
        #expect(LibraryViewMode.grid.toggled == .list)
        #expect(LibraryViewMode.list.toggled == .grid)
        #expect(LibraryViewMode.grid.toggleLabel == "Show as list")
        #expect(LibraryViewMode.list.toggleLabel == "Show as grid")
    }
}
