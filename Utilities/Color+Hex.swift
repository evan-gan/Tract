import SwiftUI

extension Color {
    /// Initialise from a hex string like "#FF5500" or "FF5500".
    init?(hex: String) {
        let cleaned = hex.trimmingPrefix("#")
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
            return nil
        }
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }

    /// Returns a 6-character hex string (e.g. "FF5500"), without a leading #.
    var hexString: String {
        let uiColor = UIColor(self)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let r = Int(red * 255)
        let g = Int(green * 255)
        let b = Int(blue * 255)
        return String(format: "%02X%02X%02X", r, g, b)
    }
}

extension SIMD4<Float> {
    /// Converts to SwiftUI Color (ignores the alpha component — handled by StrokeStyle.opacity).
    var swiftUIColor: Color {
        Color(red: Double(x), green: Double(y), blue: Double(z))
    }

    /// Constructs from a SwiftUI Color, setting alpha to 1.
    init(color: Color) {
        let uiColor = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(Float(r), Float(g), Float(b), Float(a))
    }
}
