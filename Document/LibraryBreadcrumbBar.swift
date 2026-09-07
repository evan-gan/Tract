import SwiftUI

/// One entry in the displayed path.
enum LibraryCrumb: Identifiable, Hashable {
    /// The top level, always shown so there is always a way home.
    case root
    case folder(DocumentFolder)
    /// Stands in for levels that did not fit. Not tappable — it is a marker,
    /// not a destination.
    case elision

    var id: String {
        switch self {
        case .root: "root"
        case .folder(let folder): folder.id.uuidString
        case .elision: "elision"
        }
    }

    var name: String {
        switch self {
        case .root: "Documents"
        case .folder(let folder): folder.name
        case .elision: "…"
        }
    }

    var folderID: UUID? {
        if case .folder(let folder) = self { return folder.id }
        return nil
    }
}

/// Turns a folder chain into the crumbs actually drawn.
///
/// The bar lives in the navigation bar next to the buttons, so it cannot grow
/// without pushing them off: past a few levels the middle is dropped rather than
/// squeezing every name down to an initial. The top level and the folders nearest
/// the current one survive, because those are the ones worth jumping to.
enum LibraryBreadcrumbLayout {
    static func crumbs(for path: [DocumentFolder], maxFoldersShown: Int = 3) -> [LibraryCrumb] {
        guard path.count > maxFoldersShown else {
            return [.root] + path.map(LibraryCrumb.folder)
        }
        return [.root, .elision] + path.suffix(maxFoldersShown).map(LibraryCrumb.folder)
    }
}

/// The back button and the path the user is standing in
/// (`‹ Documents / Homework / Week 1`), laid out for the navigation bar's leading
/// edge so it sits on one row with the layout and add buttons.
///
/// Every crumb is a button *and* a drop target. That is the point of showing the
/// path rather than just a title: dragging something out of a folder needs
/// somewhere to drop it, and a crumb lets it go to any ancestor in one move.
struct LibraryBreadcrumbBar: View {
    /// The folders containing the current one, outermost first, ending with the
    /// current folder itself.
    let path: [DocumentFolder]
    let onBack: () -> Void
    /// Jump to a level. `nil` is the top level.
    let onSelect: (UUID?) -> Void
    /// Handle items dropped on a crumb. Returns whether anything moved.
    let onDrop: ([LibraryItemReference], UUID?) -> Bool

    var body: some View {
        HStack(spacing: 2) {
            backButton
            ForEach(Array(crumbs.enumerated()), id: \.element.id) { index, crumb in
                if index > 0 { separator }
                view(for: crumb, isCurrent: index == crumbs.count - 1)
            }
        }
        // A navigation bar hands a leading item almost no width and lets it
        // compress: without this the names are squeezed to a few points wide.
        // Elision in `LibraryBreadcrumbLayout` is what keeps that width bounded.
        .fixedSize(horizontal: true, vertical: false)
        // No identifier on this container — one here is inherited by every
        // element inside it, wiping out the back button's and each crumb's own.
    }

    private var crumbs: [LibraryCrumb] {
        LibraryBreadcrumbLayout.crumbs(for: path)
    }

    private var backButton: some View {
        Button(action: onBack) {
            Image(systemName: "chevron.backward")
                .font(.body.weight(.semibold))
                .frame(width: 32, height: 32)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("libraryBackButton")
    }

    private var separator: some View {
        Text("/")
            .font(.subheadline)
            .foregroundStyle(.tertiary)
    }

    @ViewBuilder
    private func view(for crumb: LibraryCrumb, isCurrent: Bool) -> some View {
        switch crumb {
        case .elision:
            Text(crumb.name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        case .root, .folder:
            BreadcrumbCrumb(
                name: crumb.name,
                isCurrent: isCurrent,
                onSelect: { onSelect(crumb.folderID) },
                onDrop: { onDrop($0, crumb.folderID) }
            )
        }
    }
}

/// One name in the path. Its own view because each crumb needs to know
/// separately whether a drag is hovering over it.
private struct BreadcrumbCrumb: View {
    let name: String
    let isCurrent: Bool
    let onSelect: () -> Void
    let onDrop: ([LibraryItemReference]) -> Bool

    @State private var isDropTargeted = false

    var body: some View {
        Button(action: onSelect) {
            Text(name)
                .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                .lineLimit(1)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(isDropTargeted ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.clear),
                            in: .rect(cornerRadius: 8))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(crumbStyle)
        .dropDestination(for: LibraryItemReference.self) { items, _ in
            onDrop(items)
        } isTargeted: { isDropTargeted = $0 }
        .animation(.easeOut(duration: 0.15), value: isDropTargeted)
        .accessibilityIdentifier("breadcrumb-\(name)")
    }

    private var crumbStyle: AnyShapeStyle {
        if isDropTargeted { return AnyShapeStyle(.tint) }
        return isCurrent ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
    }
}
