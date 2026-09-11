import SwiftUI

/// What the export sheet shows once a format has been picked: a spinner, the work
/// being done right now, and how far through the run that is.
///
/// It stands in for the option cards rather than sitting beneath them. The choice
/// has been made, and leaving the rows on screen invites a second tap on a
/// document that is already rendering.
struct ExportProgressView: View {
    let run: RunningExport

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)

            VStack(spacing: 4) {
                Text(run.message)
                    .font(.body.weight(.medium))
                    .multilineTextAlignment(.center)
                    // The stage lines differ in length; letting them wrap rather
                    // than truncate keeps the sheet from clipping the long one.
                    .fixedSize(horizontal: false, vertical: true)

                Text("Step \(run.stage.stepNumber) of \(ExportStage.stepCount)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(run.message)
        .accessibilityIdentifier("exportProgress")
    }
}
