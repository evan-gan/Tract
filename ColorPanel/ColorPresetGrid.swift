import SwiftUI

/// 5×3 grid of 15 preset color dots. The selected dot gets a blue ring.
struct ColorPresetGrid: View {
    @Binding var selectedColor: SIMD4<Float>
    // nil when a custom color is active (preset ring is removed).
    @Binding var activePresetIndex: Int?

    private let columns = Array(repeating: GridItem(.fixed(28), spacing: 8), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(presetColors.indices, id: \.self) { idx in
                colorDot(at: idx)
            }
        }
    }

    private func colorDot(at index: Int) -> some View {
        let color = presetColors[index]
        let isSelected = activePresetIndex == index
        return Circle()
            .fill(color.swiftUIColor)
            .frame(width: 28, height: 28)
            .overlay {
                if isSelected {
                    Circle()
                        .strokeBorder(.blue, lineWidth: 2.5)
                        .frame(width: 34, height: 34)
                }
            }
            .onTapGesture { selectPreset(at: index) }
            .accessibilityLabel("Color preset \(index + 1)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func selectPreset(at index: Int) {
        selectedColor = presetColors[index]
        activePresetIndex = index
    }
}

/// 15 preset ink colors matching the spec's 5×3 grid.
let presetColors: [SIMD4<Float>] = [
    SIMD4(0.05, 0.05, 0.05, 1),   // Near-black
    SIMD4(0.3, 0.3, 0.3, 1),      // Dark gray
    SIMD4(0.6, 0.6, 0.6, 1),      // Mid gray
    SIMD4(0.85, 0.85, 0.85, 1),   // Light gray
    SIMD4(1, 1, 1, 1),             // White

    SIMD4(0.8, 0.1, 0.1, 1),      // Red
    SIMD4(0.9, 0.45, 0.05, 1),    // Orange
    SIMD4(0.95, 0.8, 0.05, 1),    // Yellow
    SIMD4(0.1, 0.7, 0.2, 1),      // Green
    SIMD4(0.05, 0.5, 0.9, 1),     // Blue

    SIMD4(0.35, 0.1, 0.8, 1),     // Purple
    SIMD4(0.9, 0.15, 0.55, 1),    // Pink
    SIMD4(0.5, 0.3, 0.1, 1),      // Brown
    SIMD4(0.05, 0.6, 0.6, 1),     // Teal
    SIMD4(0.15, 0.15, 0.5, 1),    // Navy
]
