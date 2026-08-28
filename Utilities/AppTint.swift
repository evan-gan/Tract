import SwiftUI

/// The app's attention colour, shared by everything that has to say "this one".
/// Centralised so the active tool, the lasso, and the selection outline cannot
/// drift apart — and so re-skinning the app is a single edit.
enum AppTint {
    /// Red rather than the system accent: the accent blue is already spoken for by
    /// Export and by the system's own controls, and red is the one hue that holds
    /// up over both the white canvas and the dark chrome.
    static let active = Color(hex: "#ff3b30")!
}
