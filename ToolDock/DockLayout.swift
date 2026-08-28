import SwiftUI

/// Shared layout helpers for anything that has to work in both dock axes.
enum DockLayout {
    static let itemSize: CGFloat = 40
    static let spacing: CGFloat = 6

    /// Stack that runs along the dock. Returning `AnyLayout` (rather than
    /// branching between HStack and VStack views) keeps child identity stable,
    /// so contents slide between axes instead of being torn down and rebuilt.
    static func stack(along axis: Axis, spacing: CGFloat = spacing) -> AnyLayout {
        axis == .horizontal
            ? AnyLayout(HStackLayout(spacing: spacing))
            : AnyLayout(VStackLayout(spacing: spacing))
    }
}

/// Hairline separator drawn across the dock, perpendicular to its axis.
struct DockDivider: View {
    let axis: Axis

    var body: some View {
        Divider()
            .frame(
                width: axis == .horizontal ? nil : 24,
                height: axis == .horizontal ? 24 : nil
            )
    }
}

/// Grip that marks where the dock can be dragged from. Purely an affordance —
/// the drag gesture covers the whole dock.
struct DockGrabHandle: View {
    let axis: Axis

    var body: some View {
        Capsule()
            .fill(.secondary.opacity(0.35))
            .frame(
                width: axis == .horizontal ? 5 : 22,
                height: axis == .horizontal ? 22 : 5
            )
            .frame(width: 16, height: 16)
            .accessibilityLabel("Drag to move the tool bar")
    }
}
