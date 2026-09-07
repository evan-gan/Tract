import SwiftUI

/// The Export control: a prominent tinted button that expands *in place* into
/// its format options, then shares the chosen file.
///
/// Deliberately not a `Menu`. A menu floats a separate panel over the canvas,
/// which is one more surface on a screen whose whole design is a few pieces of
/// glass over paper. Here the button itself widens and its label gives way to the
/// formats, so nothing new appears on top of the drawing.
///
/// It is a filled capsule rather than its own glass, because it now sits *on*
/// the top bar's glass — and glass cannot sample glass, so a second surface
/// stacked on the first reads as a smear rather than a button.
///
/// It owns the whole flow — pick, write, share — rather than reporting a tap
/// upwards, so the canvas does not have to carry share-sheet and error state it
/// has no other use for.
struct ExportMenu: View {
    /// Snapshots the document at the moment a format is chosen, not on every
    /// canvas redraw. The document carries every stroke, so taking it as a value
    /// would copy the whole drawing on each frame while the user is drawing.
    let makeDocument: () -> SplineDocument

    /// The library folders holding this document, outermost first. Empty for a
    /// top-level document, which hides the path toggle entirely — there is no
    /// path to put in the name.
    var folderPath: [String] = []

    /// "Problems" is the same PDF exporter under its worksheet layout: every
    /// problem badged with its number and nested against its neighbours to fill
    /// the paper. It is offered as its own format rather than behind a second
    /// tap, because the choice is which document you want, not a setting on a
    /// document you already asked for.
    ///
    /// "JSON" is the raw capture — every pencil sample, tag and timing the app
    /// holds — and sits last because it is the only one that is not a picture of
    /// the drawing.
    private let adapters: [any ExportAdapter] = [
        SVGExporter(),
        PDFExporter(),
        PDFExporter(options: .problemSheet),
        PNGExporter(),
        JSONExporter()
    ]

    /// Both presentations are driven by an optional value rather than by a
    /// separate boolean. A boolean flipped in the same update as the value it
    /// depends on lets SwiftUI present before the value lands, which showed an
    /// empty sheet with nothing in it on the first export of a session.
    @State private var isExpanded = false
    @State private var exportedItem: ExportedFileItem?
    @State private var exportFailure: ExportFailure?

    /// Whether the folders the document is filed in are prefixed onto the file
    /// name. Remembered across documents and launches: someone exporting a
    /// term's worth of worksheets wants the same naming every time, and the
    /// alternative is re-picking it on every single export.
    @AppStorage("exportIncludesFolderPath") private var includesFolderPath = false

    /// The appearance the *device* is in, asked of the window rather than
    /// inherited from the environment.
    ///
    /// This control lives on the top bar's glass, and Liquid Glass reads the
    /// white canvas behind the bar as a light backdrop: it hands everything it
    /// hosts a light `colorScheme`, whatever the device is set to. That is
    /// invisible on the bar itself, because `glassChrome` gives its labels
    /// literal colours — but the share sheet is presented from in here and
    /// inherited that light scheme, so exporting on a dark device raised a
    /// bright white system sheet.
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

    var body: some View {
        HStack(spacing: 2) {
            if isExpanded {
                if !folderPath.isEmpty {
                    folderPathToggle
                }
                ForEach(adapters, id: \.displayName) { adapter in
                    formatButton(for: adapter)
                }
            } else {
                collapsedButton
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .foregroundStyle(.white)
        .background(Capsule().fill(Color.accentColor))
        // The surface itself grows; the labels inside cross-fade. Without the
        // transition the three formats pop in at full width before the glass has
        // finished widening, which reads as a flicker rather than an expansion.
        .animation(.snappy(duration: 0.3), value: isExpanded)
        // The sheet's appearance is stamped explicitly rather than inherited: see
        // `systemColorScheme`.
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

    private var collapsedButton: some View {
        Button {
            isExpanded = true
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
                .labelStyle(.titleAndIcon)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .contentShape(.capsule)
        .transition(.opacity)
    }

    private func formatButton(for adapter: any ExportAdapter) -> some View {
        Button {
            isExpanded = false
            runExport(using: adapter)
        } label: {
            Text(adapter.displayName)
                .fontWeight(.medium)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .contentShape(.capsule)
        .transition(.opacity)
        .accessibilityLabel("Export as \(adapter.displayName)")
    }

    /// Sits ahead of the formats because it changes what every one of them
    /// produces. It is a state you can see rather than a menu item: the filled
    /// folder on a lighter well means the next export carries its path.
    private var folderPathToggle: some View {
        Button {
            includesFolderPath.toggle()
        } label: {
            Image(systemName: includesFolderPath ? "folder.fill" : "folder")
                .fontWeight(.medium)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background {
                    Capsule()
                        .fill(.white.opacity(includesFolderPath ? 0.28 : 0))
                }
        }
        .buttonStyle(.plain)
        .contentShape(.capsule)
        .transition(.opacity)
        .accessibilityIdentifier("exportIncludeFolderPath")
        .accessibilityLabel("Include folder path in file name")
        .accessibilityValue(includesFolderPath ? folderPathPrefixDescription : "Off")
        // A named file is the whole point of the toggle, so say the name it
        // would produce rather than leaving the user to guess the format.
        .help("Name the file \(folderPathPrefixDescription)…")
    }

    private var folderPathPrefixDescription: String {
        folderPath.joined(separator: ".") + "."
    }

    /// The alert reads its message from `presenting:` rather than from state of
    /// its own, so the failure text can never lag a beat behind the flag.
    private var isPresentingFailure: Binding<Bool> {
        Binding(
            get: { exportFailure != nil },
            set: { isPresented in if !isPresented { exportFailure = nil } }
        )
    }

    private func runExport(using adapter: any ExportAdapter) {
        let document = makeDocument()
        do {
            let data = try adapter.export(document: document, viewport: nil)
            let fileName = ExportFileNaming.fileName(
                title: document.title + adapter.fileNameSuffix,
                folderPath: includesFolderPath ? folderPath : [],
                fileExtension: adapter.fileExtension
            )
            let temporaryURL = FileManager.default.temporaryDirectory.appending(path: fileName)
            try data.write(to: temporaryURL)
            exportedItem = ExportedFileItem(url: temporaryURL)
        } catch {
            exportFailure = ExportFailure(message: error.localizedDescription)
        }
    }
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
