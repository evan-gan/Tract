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
/// and error state it has no other use for.
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

    @State private var isPickerPresented = false
    /// What the picker was dismissed with. The export runs on the picker's
    /// *dismissal*, not on the tap: a share sheet raised while another sheet is
    /// still on screen either does not appear or comes up empty.
    @State private var pendingChoice: ExportChoice?

    /// Both presentations are driven by an optional value rather than by a
    /// separate boolean. A boolean flipped in the same update as the value it
    /// depends on lets SwiftUI present before the value lands, which showed an
    /// empty sheet with nothing in it on the first export of a session.
    @State private var exportedItem: ExportedFileItem?
    @State private var exportFailure: ExportFailure?

    var body: some View {
        Button {
            isPickerPresented = true
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
        .sheet(isPresented: $isPickerPresented, onDismiss: runPendingExport) {
            ExportPickerView(
                folderPath: folderPath,
                includesFolderPath: $includesFolderPath,
                onPick: { layout, format in
                    pendingChoice = ExportChoice(layout: layout, format: format)
                    isPickerPresented = false
                },
                onCancel: { isPickerPresented = false }
            )
            .environment(\.colorScheme, Self.systemColorScheme)
        }
        .sheet(item: $exportedItem) { item in
            ShareSheet(items: [item.url])
                .environment(\.colorScheme, Self.systemColorScheme)
        }
        .alert(
            "Export failed",
            isPresented: isPresentingFailure,
            presenting: exportFailure
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
            get: { exportFailure != nil },
            set: { isPresented in if !isPresented { exportFailure = nil } }
        )
    }

    /// Runs the pick the picker closed with, if it closed with one — a cancelled
    /// sheet leaves nothing pending and exports nothing.
    private func runPendingExport() {
        guard let choice = pendingChoice else { return }
        pendingChoice = nil

        do {
            exportedItem = ExportedFileItem(
                url: try ExportRunner.writeExport(
                    of: makeDocument(),
                    layout: choice.layout,
                    format: choice.format,
                    folderPath: includesFolderPath ? folderPath : []
                )
            )
        } catch {
            exportFailure = ExportFailure(message: error.localizedDescription)
        }
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

/// One picked export: what goes on the page, and the file it is written as.
private struct ExportChoice {
    let layout: ExportLayout
    let format: ExportFormat
}

private struct ExportedFileItem: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct ExportFailure: Identifiable {
    let message: String
    var id: String { message }
}

/// Wraps `UIActivityViewController` for sharing a file URL.
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
