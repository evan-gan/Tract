import SwiftUI

/// Editable document title displayed as a pill in the top bar.
struct DocumentTitleView: View {
    @Binding var title: String
    @State private var isEditing = false
    @FocusState private var fieldIsFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                TextField("Document name", text: $title)
                    .focused($fieldIsFocused)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .frame(minWidth: 120, maxWidth: 240)
                    .onSubmit { commitEdit() }
            } else {
                Text(title.isEmpty ? "Untitled" : title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .onTapGesture { beginEdit() }
            }
        }
        .onChange(of: fieldIsFocused) { _, focused in
            if !focused { commitEdit() }
        }
    }

    private func beginEdit() {
        isEditing = true
        fieldIsFocused = true
    }

    private func commitEdit() {
        isEditing = false
        fieldIsFocused = false
        if title.isEmpty { title = "Untitled" }
    }
}
