import Foundation
import Observation

/// Owns one open document for as long as the canvas is on screen: it loads the
/// strokes in, hands them to `CanvasViewModel`, and is the only thing that ever
/// writes them back.
///
/// The rules that keep saving predictable:
///
/// - **Nothing is written until the load has finished.** Saving an empty canvas
///   over a document that simply had not finished loading is the one failure
///   that loses real work, so `loadState` gates every write.
/// - **A failed load never becomes a save.** If the strokes file could not be
///   decoded the session stays in `.failed` and refuses to overwrite it.
/// - **Edits are coalesced.** Each edit restarts a short timer; a burst of
///   strokes costs one write, not one per stroke.
/// - **Leaving always flushes.** Closing the document and backgrounding the app
///   both save immediately rather than waiting out the timer.
@Observable
@MainActor
final class DocumentEditorSession: Identifiable {
    /// Immutable and `nonisolated` so SwiftUI's `fullScreenCover(item:)` can read
    /// it without hopping actors.
    nonisolated let id: UUID

    enum LoadState: Equatable {
        case loading
        case ready
        case failed(String)
    }

    /// How long the canvas must be still before an autosave fires. Long enough
    /// that a run of quick strokes coalesces, short enough that a hard crash
    /// costs at most a couple of seconds of ink.
    private static let autosaveDelay: Duration = .seconds(2)

    private(set) var loadState: LoadState = .loading
    private(set) var metadata: DocumentMetadata
    private(set) var lastSaveError: String?
    /// True between an edit and the write that captures it — the top bar shows
    /// it so the user is never guessing whether their work is on disk.
    private(set) var hasUnsavedChanges = false

    let viewModel: CanvasViewModel

    var title: String {
        get { metadata.title }
        set {
            guard newValue != metadata.title else { return }
            metadata.title = newValue
            markEdited()
        }
    }

    private let store: DocumentFileStore
    /// Called after every successful save so the library card updates in place.
    private let onSaved: (DocumentMetadata) -> Void
    private var autosaveTask: Task<Void, Never>?
    /// `CanvasViewModel.revision` as of the last successful write, so a save with
    /// nothing new to record can be skipped.
    private var savedRevision = 0

    init(
        metadata: DocumentMetadata,
        store: DocumentFileStore,
        viewModel: CanvasViewModel = CanvasViewModel(),
        onSaved: @escaping (DocumentMetadata) -> Void = { _ in }
    ) {
        self.id = metadata.id
        self.metadata = metadata
        self.store = store
        self.viewModel = viewModel
        self.onSaved = onSaved
    }

    // MARK: - Loading

    func load() async {
        do {
            let document = try await store.loadDocument(id: metadata.id)
            metadata = document.metadata
            viewModel.restore(
                strokes: document.strokes,
                outline: document.problemOutline,
                origin: document.metadata.canvasOrigin,
                scale: document.metadata.canvasScale
            )
            savedRevision = viewModel.revision
            loadState = .ready
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Saving

    /// Records that something changed and restarts the autosave timer.
    func markEdited() {
        hasUnsavedChanges = true
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.autosaveDelay)
            guard !Task.isCancelled else { return }
            await self?.save()
        }
    }

    /// Writes immediately, cancelling any pending autosave. Call when the
    /// document closes or the app leaves the foreground.
    func saveNow() async {
        autosaveTask?.cancel()
        autosaveTask = nil
        await save()
    }

    private func save() async {
        guard loadState == .ready else { return }

        // Pan and zoom are not tracked as edits — that would fire a write on every
        // frame of a pinch — so they ride along with whatever save happens next,
        // including the flush that always runs on close.
        let transform = viewModel.canvasTransform
        // The picker's last-visited memory changes the stored outline without
        // being an edit to the drawing, so it rides along here with pan and zoom
        // rather than stamping a new modifiedAt on the document.
        let outline = viewModel.problems.outline
        let viewChanged = metadata.canvasOrigin != transform.translation
            || metadata.canvasScale != transform.scale
            || metadata.problemOutline != outline
        let revisionBeingSaved = viewModel.revision
        let contentChanged = hasUnsavedChanges || revisionBeingSaved != savedRevision
        guard contentChanged || viewChanged else { return }

        metadata.canvasOrigin = transform.translation
        metadata.canvasScale = transform.scale
        metadata.problemOutline = outline
        // Merely looking at a document — panning, zooming — must not push it to the
        // front of the library as if it had been edited.
        if contentChanged { metadata.modifiedAt = .now }

        let document = SplineDocument(metadata: metadata, strokes: viewModel.strokes)

        do {
            try await store.save(document, thumbnail: await thumbnailUpdate(for: document.strokes))
            metadata.strokeCount = document.strokes.count
            savedRevision = revisionBeingSaved
            // An edit made while the write was in flight must not be marked clean.
            hasUnsavedChanges = viewModel.revision != revisionBeingSaved
            lastSaveError = nil
            onSaved(metadata)
        } catch {
            lastSaveError = error.localizedDescription
        }
    }

    /// Re-rendering the preview on a view-only save would be wasted work, but an
    /// emptied document must lose its old preview rather than keep advertising
    /// ink that is no longer there.
    private func thumbnailUpdate(for strokes: [Stroke]) async -> ThumbnailUpdate {
        guard let data = await renderThumbnail(for: strokes) else { return .remove }
        return .replace(data)
    }

    /// Rasterising happens off the main actor: a busy page is thousands of
    /// Bézier segments, and the canvas must not stutter while a save runs.
    private nonisolated func renderThumbnail(for strokes: [Stroke]) async -> Data? {
        await Task.detached(priority: .utility) {
            ThumbnailRenderer.renderPNG(strokes: strokes)
        }.value
    }
}
