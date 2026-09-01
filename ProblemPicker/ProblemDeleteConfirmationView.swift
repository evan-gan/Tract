import SwiftUI

/// The little popover a held row puts up: one destructive action, named after
/// the exact problem it would remove.
///
/// Named rather than a bare "Delete" because the popover's arrow is the only
/// other thing saying which row is about to go, and a wheel row is 46 points
/// wide — the address is what makes the action safe to confirm.
struct ProblemDeleteConfirmationView: View {
    /// The address being removed, e.g. "1.b".
    let title: String
    let onDelete: () -> Void

    var body: some View {
        Button(role: .destructive, action: onDelete) {
            Label("Delete \(title)", systemImage: "trash")
                .font(.system(size: 15, weight: .medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.red)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityIdentifier("problemDelete-\(title)")
        .presentationCompactAdaptation(.popover)
    }
}
