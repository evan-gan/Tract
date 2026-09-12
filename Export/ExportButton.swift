import SwiftUI

/// The Export control on the top bar: a filled capsule that opens the export
/// picker, then shares whatever the picker was asked for.
///
/// A filled capsule rather than its own glass, because it sits *on* the top
/// bar's glass — and glass cannot sample glass, so a second surface stacked on
/// the first reads as a smear rather than a button.
///
/// It owns the whole flow — present, render, share, report failures — rather
/// than reporting a tap upwards, so the canvas does not have to carry share-sheet
/// and error state it has no other use for. The sequencing of that flow lives in
/// `ExportSession`; this view is the button and the presentations.
struct ExportButton: View {
    /// Snapshots the document at the moment a format is chosen, not on every
    /// canvas redraw. The document carries every stroke, so taking it as a value
    /// would copy the whole drawing on each frame while the user is drawing.
    let makeDocument: () -> SplineDocument

    /// The library folders holding this document, outermost first. Empty for a
    /// top-level document, which hides the path toggle entirely.
    var folderPath: [String] = []

    /// Whether the folders the document is filed in are prefixed onto the file
    /// name. Remembered across documents and launches: someone exporting a
    /// term's worth of worksheets wants the same naming every time, and the
    /// alternative is re-picking it on every single export.
    @AppStorage("exportIncludesFolderPath") private var includesFolderPath = false

    /// Holds the picker, the run in flight and the finished file. The share sheet
    /// is still driven by an optional value rather than a separate boolean: a
    /// boolean flipped in the same update as the value it depends on lets SwiftUI
    /// present before the value lands, which showed an empty sheet with nothing
    /// in it on the first export of a session.
    @State private var session = ExportSession()

    /// The problems the open document has ink under, read once as the picker
    /// opens rather than tracked: the document is snapshotted, not observed, and
    /// a tap is the one moment it is cheap to look at.
    @State private var problemOptions: [ExportProblemOption] = []

    /// Which of those the user has ticked. Deliberately cleared on every open —
    /// a remembered selection would silently decide what a later export holds.
    @State private var selectedProblems: Set<ProblemTag> = []

    var body: some View {
        Button {
            problemOptions = ExportProblemOption.options(in: makeDocument())
            selectedProblems = []
            session.presentPicker()
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
                .labelStyle(.titleAndIcon)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .contentShape(.capsule)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .foregroundStyle(.white)
        .background(Capsule().fill(Color.accentColor))
        // Both sheets are presented from inside the bar's glass and have their
        // appearance stamped explicitly rather than inherited: see
        // `systemColorScheme`.
        .sheet(isPresented: $session.isPickerPresented, onDismiss: { session.pickerDismissed() }) {
            ExportPickerView(
                folderPath: folderPath,
                includesFolderPath: $includesFolderPath,
                problemOptions: problemOptions,
                selectedProblems: $selectedProblems,
                runningExport: session.runningExport,
                onPick: startExport,
                onCancel: { session.cancel() }
            )
            .environment(\.colorScheme, Self.systemColorScheme)
        }
        .sheet(item: $session.exportedItem) { item in
            ShareSheet(items: [item.url])
                .environment(\.colorScheme, Self.systemColorScheme)
        }
        .alert(
            "Export failed",
            isPresented: isPresentingFailure,
            presenting: session.failure
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { failure in
            Text(failure.message)
        }
    }

    /// The alert reads its message from `presenting:` rather than from state of
    /// its own, so the failure text can never lag a beat behind the flag.
    private var isPresentingFailure: Binding<Bool> {
        Binding(
            get: { session.failure != nil },
            set: { isPresented in if !isPresented { session.failure = nil } }
        )
    }

    /// Hands the pick to the session, snapshotting the document at this moment —
    /// the only moment the whole drawing needs to be copied.
    private func startExport(layout: ExportLayout, format: ExportFormat) {
        session.export(
            ExportRequest(
                document: makeDocument(),
                layout: layout,
                format: format,
                problems: layout.usesProblemSelection ? ProblemSelection(tags: selectedProblems) : .everything,
                folderPath: includesFolderPath ? folderPath : []
            )
        )
    }

    /// The appearance the *device* is in, asked of the window rather than
    /// inherited from the environment.
    ///
    /// This control lives on the top bar's glass, and Liquid Glass reads the
    /// white canvas behind the bar as a light backdrop: it hands everything it
    /// hosts a light `colorScheme`, whatever the device is set to. That is
    /// invisible on the bar itself, because `glassChrome` gives its labels
    /// literal colours — but the sheets are presented from in here and inherited
    /// that light scheme, so exporting on a dark device raised a bright white
    /// panel.
    ///
    /// The window sits above the glass and carries no override of its own, so
    /// its trait is the real setting. No window to ask means light, which is what
    /// an undecided appearance resolves to anyway.
    private static var systemColorScheme: ColorScheme {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let activeScene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let window = activeScene?.keyWindow ?? activeScene?.windows.first
        return window?.traitCollection.userInterfaceStyle == .dark ? .dark : .light
    }
}

/// Wraps `UIActivityViewController` for sharing a file URL.
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
