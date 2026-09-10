import SwiftUI

/// The export sheet: every way this document can leave the app, grouped by what
/// lands on the page and then by the file it is written as.
///
/// It replaced a capsule that expanded into a flat run of format names. That
/// worked at three options and stopped working at five: "PDF" and "Problems" sat
/// side by side as if they were the same kind of choice, when one is a format
/// and the other is a *layout* that happens to be a PDF. Splitting the two
/// questions apart is the whole point of this screen — pick what you want on the
/// page, then pick the file.
///
/// It reports the pick upwards rather than exporting itself, so the sheet can be
/// dismissed before the share sheet is raised; two sheets fighting over the same
/// presentation is how the old control ended up with an empty one.
struct ExportPickerView: View {
    /// The library folders holding the document, outermost first. Empty hides
    /// the naming toggle — there is no path to put in the name.
    let folderPath: [String]
    /// Whether those folders are prefixed onto the exported file's name.
    @Binding var includesFolderPath: Bool
    let onPick: (ExportLayout, ExportFormat) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 22) {
                ForEach(ExportLayout.allCases) { layout in
                    layoutCard(layout)
                }
                if !folderPath.isEmpty {
                    folderPathCard
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGroupedBackground))
        // The sheet is as tall as the options in it and no taller. Every option
        // has to be visible at a glance for the grouping to do its job, and a
        // fixed-height form sheet either scrolls them out of sight or leaves a
        // slab of empty space under them.
        .presentationSizing(.form.fitted(horizontal: false, vertical: true))
    }

    /// A plain row rather than a navigation bar. A `NavigationStack` lays itself
    /// out to whatever space it is given and reports no height of its own, so the
    /// fitted sheet sized itself to almost nothing and clipped the options.
    private var header: some View {
        ZStack {
            Text("Export")
                .font(.headline)
            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 4)
    }

    private func layoutCard(_ layout: ExportLayout) -> some View {
        ExportGroupCard(title: layout.name, symbolName: layout.symbolName, summary: layout.summary) {
            ForEach(Array(layout.formats.enumerated()), id: \.element) { index, format in
                if index > 0 {
                    ExportRowDivider()
                }
                ExportFormatRow(format: format, layoutName: layout.name) {
                    onPick(layout, format)
                }
                .accessibilityIdentifier("exportOption-\(layout.id)-\(format.id)")
            }
        }
    }

    /// Sits last because it changes how every option above is named, rather than
    /// being one of them.
    private var folderPathCard: some View {
        ExportGroupCard(
            title: "File name",
            symbolName: "textformat",
            // A named file is the point of the toggle, so show the name it would
            // produce rather than leaving the user to guess the shape.
            summary: "Files are named “\(includesFolderPath ? folderPathPrefix : "")Title.pdf”."
        ) {
            Toggle(isOn: $includesFolderPath) {
                Label("Include folder path", systemImage: "folder")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .accessibilityIdentifier("exportIncludeFolderPath")
        }
    }

    private var folderPathPrefix: String {
        folderPath.joined(separator: ".") + "."
    }
}
