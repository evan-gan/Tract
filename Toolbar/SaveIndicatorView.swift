import SwiftUI

/// A small dot beside the title that fills while there is unsaved work and
/// fades once it has been written.
///
/// Kept deliberately quiet: a spinner or a "Saved" label would pull attention
/// away from the drawing every couple of seconds. The dot is only there so the
/// question "did that get saved?" has an answer on screen.
struct SaveIndicatorView: View {
    let isSaving: Bool

    var body: some View {
        Circle()
            .fill(.secondary)
            .frame(width: 6, height: 6)
            .opacity(isSaving ? 1 : 0)
            .animation(.easeInOut(duration: 0.25), value: isSaving)
            .accessibilityLabel(isSaving ? "Saving" : "All changes saved")
            // Reserved whether or not it is showing, so the title never shifts
            // sideways as saves come and go.
            .frame(width: 6)
    }
}
