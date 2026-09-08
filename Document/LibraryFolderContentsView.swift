import SwiftUI

/// The contents of one library folder, as a grid of tiles or an indented outline.
///
/// The same view renders the top level (`folderID == nil`) and every folder below
/// it, which is what makes nesting free: drilling in pushes another copy of this
/// onto the navigation stack.
struct LibraryFolderContentsView: View {
    let library: DocumentLibrary
    let uiState: LibraryUIState
    /// Which folder is being shown; nil is the top level.
    let folderID: UUID?
    @Binding var path: [LibraryRoute]

    /// Wide enough that a preview reads at a glance, narrow enough for four
    /// columns on an 11-inch iPad in landscape.
    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 24)]

    var body: some View {
        contents
            // Inside a folder the breadcrumb *is* the title, so the bar goes
            // inline and the path shares its one row with the add buttons.
            .navigationTitle(folderID == nil ? "Documents" : "")
            .navigationBarTitleDisplayMode(folderID == nil ? .large : .inline)
            // The breadcrumb already carries a back button, and two of them
            // sitting side by side is one too many.
            .navigationBarBackButtonHidden(folderID != nil)
            .toolbar {
                breadcrumb
                toolbarButtons
            }
    }

    // MARK: - Layouts

    @ViewBuilder
    private var contents: some View {
        if isEmpty {
            ScrollView {
                emptyState
                    .frame(maxWidth: .infinity)
                    .padding(.top, 96)
            }
        } else {
            switch uiState.viewMode {
            case .grid: gridView
            case .list: listView
            }
        }
    }

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 28) {
                ForEach(library.folders(in: folderID)) { folder in
                    FolderCard(
                        folder: folder,
                        itemCount: library.itemCount(in: folder.id),
                        onOpen: { navigateInto(folder) },
                        onRename: { uiState.ask(.renameFolder(folder)) },
                        onDelete: { uiState.requestDeletion(of: .folder(folder), in: library) },
                        onDrop: { drop($0, into: folder.id) }
                    )
                }
                ForEach(library.documents(in: folderID)) { metadata in
                    DocumentCard(
                        metadata: metadata,
                        store: library.store,
                        onOpen: { open(metadata) },
                        onRename: { uiState.ask(.renameDocument(metadata)) },
                        onDelete: { uiState.deletion = .document(metadata) }
                    )
                }
            }
            .padding(24)
        }
    }

    private var listView: some View {
        LibraryListView(
            library: library,
            uiState: uiState,
            folderID: folderID,
            onOpenDocument: open,
            onOpenFolder: navigateInto,
            onDrop: drop
        )
    }

    @ViewBuilder
    private var emptyState: some View {
        if library.isLoading {
            ProgressView()
        } else {
            ContentUnavailableView(
                folderID == nil ? "No documents" : "Empty folder",
                systemImage: folderID == nil ? "doc.text" : "folder",
                description: Text("Tap + to start drawing, or the folder button to file things away.")
            )
        }
    }

    @ToolbarContentBuilder
    private var breadcrumb: some ToolbarContent {
        if folderID != nil {
            ToolbarItem(placement: .topBarLeading) {
                LibraryBreadcrumbBar(
                    path: breadcrumbPath,
                    onBack: goUp,
                    onSelect: navigate(to:),
                    onDrop: drop
                )
            }
        }
    }

    /// Two plain buttons for adding rather than one "+" menu: making a folder and
    /// making a document are the only two things you can add here, and a menu
    /// would put a tap in front of both of them.
    @ToolbarContentBuilder
    private var toolbarButtons: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button(uiState.viewMode.toggleLabel, systemImage: uiState.viewMode.toggleSystemImage) {
                uiState.viewMode = uiState.viewMode.toggled
            }
            .accessibilityIdentifier("libraryViewModeToggle")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("New folder", systemImage: "folder.badge.plus") {
                uiState.ask(.newFolder(parentID: folderID))
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("New document", systemImage: "plus", action: createDocument)
        }
    }

    // MARK: - Contents

    private var currentFolder: DocumentFolder? {
        folderID.flatMap { library.folder(id: $0) }
    }

    /// The chain of folders from the top level down to this one.
    private var breadcrumbPath: [DocumentFolder] {
        folderID.map { library.tree.path(to: $0) } ?? []
    }

    private var isEmpty: Bool {
        library.folders(in: folderID).isEmpty && library.documents(in: folderID).isEmpty
    }

    // MARK: - Actions

    private func createDocument() {
        Task {
            guard let metadata = await library.createDocument(in: folderID) else { return }
            open(metadata)
        }
    }

    private func open(_ metadata: DocumentMetadata) {
        uiState.editorSession = DocumentEditorSession(
            metadata: metadata,
            store: library.store,
            folderPath: metadata.folderID.map { library.tree.path(to: $0).map(\.name) } ?? [],
            // Folding each save back into the list is what keeps a card's date and
            // preview correct without re-reading the whole library on dismissal.
            onSaved: { library.applySavedMetadata($0) }
        )
    }

    private func navigateInto(_ folder: DocumentFolder) {
        path.append(LibraryRoute(folderID: folder.id))
    }

    private func goUp() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    /// Jumps to any level in the breadcrumb.
    ///
    /// The stack always mirrors the folder chain — you can only descend one level
    /// at a time — so a jump is just that chain truncated at the crumb tapped.
    private func navigate(to destinationID: UUID?) {
        guard let destinationID else {
            path.removeAll()
            return
        }
        guard let index = breadcrumbPath.firstIndex(where: { $0.id == destinationID }) else { return }
        path = breadcrumbPath.prefix(through: index).map { LibraryRoute(folderID: $0.id) }
    }

    /// Files dropped items into `destination`.
    ///
    /// Legality is checked here as well as in the library, because the drop
    /// gesture wants its answer immediately and the move is asynchronous:
    /// refusing up front is what makes an illegal drag animate back to where it
    /// came from instead of appearing to work.
    private func drop(_ items: [LibraryItemReference], into destination: UUID?) -> Bool {
        let movable = items.filter { canAccept($0, into: destination) }
        guard !movable.isEmpty else { return false }
        Task { await library.move(movable, into: destination) }
        return true
    }

    private func canAccept(_ item: LibraryItemReference, into destination: UUID?) -> Bool {
        switch item.kind {
        case .document: true
        case .folder: item.id != destination && library.tree.canMove(folderID: item.id, into: destination)
        }
    }
}

/// One step in the library's navigation stack. A plain `UUID` would work, but a
/// named route keeps the destination unambiguous if the stack ever carries
/// anything else.
struct LibraryRoute: Hashable {
    let folderID: UUID
}
