import SwiftUI

/// Native color picker + hex input field. Using either clears the preset selection.
struct CustomColorRow: View {
    @Binding var selectedColor: SIMD4<Float>
    @Binding var activePresetIndex: Int?

    @State private var hexInput: String = ""
    @State private var pickerColor: Color = .black

    var body: some View {
        HStack(spacing: 10) {
            Text("Custom")
                .font(.caption)
                .foregroundStyle(.secondary)

            ColorPicker("Custom color", selection: $pickerColor, supportsOpacity: false)
                .labelsHidden()
                .onChange(of: pickerColor) { _, newColor in
                    applyColorFromPicker(newColor)
                }

            TextField("Hex", text: $hexInput)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 64)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .onSubmit { applyColorFromHex() }
        }
        .onAppear { syncFromModel() }
        .onChange(of: selectedColor) { _, _ in syncFromModel() }
    }

    private func syncFromModel() {
        pickerColor = selectedColor.swiftUIColor
        hexInput = pickerColor.hexString
    }

    private func applyColorFromPicker(_ color: Color) {
        selectedColor = SIMD4<Float>(color: color)
        hexInput = color.hexString
        activePresetIndex = nil
    }

    private func applyColorFromHex() {
        guard let color = Color(hex: hexInput) else { return }
        selectedColor = SIMD4<Float>(color: color)
        pickerColor = color
        activePresetIndex = nil
    }
}
