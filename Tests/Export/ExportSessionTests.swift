import Testing
import Foundation
@testable import Tract

/// The session's *sequencing* — progress up, picker down, share sheet after —
/// tested against a stand-in renderer the test drives by hand, so nothing here
/// depends on how long a real PDF takes to draw.
@MainActor
@Suite("Sequencing an export run")
struct ExportSessionTests {
    @Test("A pick keeps the picker up and reports every stage as it happens")
    func reportsStagesWhileThePickerStaysUp() async throws {
        let renderer = StubRenderer()
        let session = ExportSession(performExport: renderer.export)
        try await startRun(on: session, with: renderer)

        #expect(session.isPickerPresented,
                "The picker is where progress is shown, so it must stay up during the run.")

        await renderer.report(.rendering)
        #expect(session.runningExport?.stage == .rendering)
        await renderer.report(.writingFile)
        #expect(session.runningExport?.stage == .writingFile)

        await renderer.finish(with: .success(writtenFile))
        await settle(untilTrue: { session.runningExport == nil })

        #expect(session.runningExport == nil, "A finished run should stop showing progress.")
        #expect(!session.isPickerPresented, "The picker closes itself once the file exists.")
    }

    @Test("The share sheet is raised only once the picker is off screen")
    func sharesOnlyAfterThePickerHasGone() async throws {
        let renderer = StubRenderer()
        let session = ExportSession(performExport: renderer.export)
        try await startRun(on: session, with: renderer)

        await renderer.finish(with: .success(writtenFile))
        await settle(untilTrue: { !session.isPickerPresented })

        #expect(session.exportedItem == nil,
                "Presenting the share sheet before the picker's dismissal is how it came up empty.")

        session.pickerDismissed()
        #expect(session.exportedItem?.url == writtenFile)
    }

    @Test("A failed render surfaces as an alert naming the cause, not as a shared file")
    func failureSurfacesAfterDismissal() async throws {
        let renderer = StubRenderer()
        let session = ExportSession(performExport: renderer.export)
        try await startRun(on: session, with: renderer)

        await renderer.finish(with: .failure(ExportError.noStrokes))
        await settle(untilTrue: { !session.isPickerPresented })
        session.pickerDismissed()

        #expect(session.exportedItem == nil)
        #expect(session.failure?.message == ExportError.noStrokes.localizedDescription)
    }

    @Test("Cancelling mid-render shares nothing, even though the render still finishes")
    func cancellingMidRenderSharesNothing() async throws {
        let renderer = StubRenderer()
        let session = ExportSession(performExport: renderer.export)
        try await startRun(on: session, with: renderer)

        session.cancel()
        #expect(session.runningExport == nil)
        #expect(!session.isPickerPresented)

        // The work underneath cannot be interrupted, so it completes regardless.
        await renderer.finish(with: .success(writtenFile))
        await letTasksRun()
        session.pickerDismissed()

        #expect(session.exportedItem == nil,
                "A cancelled export must not raise a share sheet for a file nobody asked for.")
    }

    @Test("A second pick while one is rendering does not start a duplicate run")
    func ignoresASecondPickWhileRunning() async throws {
        let renderer = StubRenderer()
        let session = ExportSession(performExport: renderer.export)
        try await startRun(on: session, with: renderer, format: .pdf)

        session.export(request(format: .png))
        await letTasksRun()

        #expect(session.runningExport?.format == .pdf,
                "The first pick owns the run; a second should be ignored, not queued.")
        #expect(await renderer.startCount == 1)
    }

    // MARK: - Steps

    /// Picks a format and waits for the stub renderer to be holding the run, so a
    /// test can then drive it stage by stage.
    private func startRun(
        on session: ExportSession,
        with renderer: StubRenderer,
        format: ExportFormat = .pdf
    ) async throws {
        session.presentPicker()
        session.export(request(format: format))

        #expect(session.runningExport?.stage == .preparing,
                "A run should report progress before the renderer has said anything.")

        let started = await renderer.waitUntilStarted()
        try #require(started, "The stub renderer was never handed the run.")
    }

    /// Gives the session's own task room to run until the expectation holds. The
    /// run finishes on a task of its own, so its effects do not land in the same
    /// turn the test resumed on.
    private func settle(untilTrue condition: () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            await Task.yield()
        }
    }

    /// For the cases where the expectation is that *nothing* happens: gives every
    /// other task a turn first, so "nothing happened" is a finding rather than a
    /// race the test won.
    private func letTasksRun() async {
        for _ in 0..<200 { await Task.yield() }
    }

    // MARK: - Fixtures

    private var writtenFile: URL { URL(fileURLWithPath: "/tmp/Set 3.pdf") }

    private func request(format: ExportFormat = .pdf) -> ExportRequest {
        ExportRequest(
            document: SplineDocument(
                metadata: DocumentMetadata(title: "Set 3"),
                strokes: [StrokeFixtures.square(at: .zero, side: 200)]
            ),
            layout: .wholeDrawing,
            format: format
        )
    }
}

/// A renderer that renders nothing: it hands its stage callback and its
/// completion back to the test, which decides when each one fires.
private actor StubRenderer {
    private(set) var startCount = 0
    private var stageCallback: (@MainActor @Sendable (ExportStage) -> Void)?
    private var completion: CheckedContinuation<URL, Error>?

    nonisolated var export: ExportWork {
        { [self] _, onStage in
            try await withCheckedThrowingContinuation { continuation in
                Task { await begin(onStage: onStage, completion: continuation) }
            }
        }
    }

    /// - Returns: True once the session's task has handed over a run; false if it
    ///   never did, so the caller fails rather than hanging.
    func waitUntilStarted() async -> Bool {
        for _ in 0..<200 {
            if stageCallback != nil { return true }
            await Task.yield()
        }
        return false
    }

    /// Pushes a stage through the session's callback and waits for it to land, so
    /// the caller can assert on it immediately afterwards.
    func report(_ stage: ExportStage) async {
        let callback = stageCallback
        await MainActor.run { callback?(stage) }
    }

    func finish(with result: Result<URL, Error>) {
        let pending = completion
        completion = nil
        pending?.resume(with: result)
    }

    private func begin(
        onStage: @escaping @MainActor @Sendable (ExportStage) -> Void,
        completion: CheckedContinuation<URL, Error>
    ) {
        startCount += 1
        stageCallback = onStage
        self.completion = completion
    }
}
