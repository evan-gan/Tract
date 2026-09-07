import Foundation

/// How the library lays its contents out.
///
/// The choice is remembered across launches: it is a preference about how the
/// user likes to work, and having it snap back to a grid every morning would be
/// worse than not offering it at all.
enum LibraryViewMode: String, CaseIterable, Sendable {
    /// A shelf of preview tiles. Shows one folder at a time.
    case grid
    /// An indented outline. Folders expand in place, so a whole hierarchy can be
    /// read without navigating into it.
    case list

    /// The mode this one switches to, and the control that offers the switch.
    var toggled: LibraryViewMode {
        self == .grid ? .list : .grid
    }

    /// Describes what tapping the control *will do*, not what is showing now —
    /// a toolbar button is labelled by its action.
    var toggleLabel: String {
        toggled == .list ? "Show as list" : "Show as grid"
    }

    var toggleSystemImage: String {
        toggled == .list ? "list.bullet" : "square.grid.2x2"
    }

    // MARK: - Persistence

    /// Also the name a UI test passes as a launch argument (`-libraryViewMode
    /// grid`) to pin the starting layout: `UserDefaults` reads the argument
    /// domain first, so a test never inherits the mode an earlier test left
    /// behind. The seeder cannot do this job — it runs from a `.task`, long
    /// after `LibraryUIState` has already read the stored value.
    static let defaultsKey = "libraryViewMode"

    static func restored(from defaults: UserDefaults = .standard) -> LibraryViewMode {
        defaults.string(forKey: defaultsKey).flatMap(LibraryViewMode.init(rawValue:)) ?? .grid
    }

    static func persist(_ mode: LibraryViewMode, to defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: defaultsKey)
    }
}
