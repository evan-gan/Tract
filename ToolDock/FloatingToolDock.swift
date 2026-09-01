import SwiftUI

/// Parks the tool dock against a screen edge and lets the user drag it to a
/// different one. While dragging, the dock follows the finger or pencil exactly
/// and keeps the shape it started with; only on release does it glide to the
/// edge the drag ended in and re-flow to match it.
struct FloatingToolDock: View {
    @Bindable var viewModel: CanvasViewModel
    let glassNamespace: Namespace.ID
    /// Height of the top chrome row the dock must sit below when parked on top.
    let topReserved: CGFloat

    /// Placement is view state, not model state: nothing outside this view needs
    /// it, and @State is what reliably re-lays-out the dock when it changes.
    @State private var parkedEdge: DockEdge = .bottom
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var containerSize: CGSize = .zero

    private static let dockSpace = "toolDockSpace"
    private static let margin: CGFloat = 12

    /// Re-parking, re-flowing and the offset unwinding all ride this one spring,
    /// so the dock reads as a single object settling rather than several parts
    /// rearranging. Deliberately unhurried — the shape changes on this animation
    /// too, and at speed that reflow reads as a flicker.
    private static let settleAnimation: Animation = .spring(response: 0.84, dampingFraction: 0.82)

    /// Only the pick-up and put-down lift, which should land well before the
    /// dock finishes travelling.
    private static let liftAnimation: Animation = .smooth(duration: 0.28)

    /// Just enough to lift the dock off the canvas while it is in hand.
    private static let liftScale: CGFloat = 1.04

    var body: some View {
        ZStack(alignment: parkedEdge.alignment) {
            ToolDockView(viewModel: viewModel, edge: parkedEdge)
                .scaleEffect(isDragging ? Self.liftScale : 1)
                .offset(dragOffset)
                .highPriorityGesture(dragGesture)
                .glassEffectID("toolDock", in: glassNamespace)
        }
        // The alignment has to live on the filling frame: a single-child ZStack
        // sizes to its child, so its own alignment would never place anything.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: parkedEdge.alignment)
        .coordinateSpace(.named(Self.dockSpace))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { containerSize = $0 }
        .padding(.top, topReserved)
        .padding(Self.margin)
    }

    /// Attached as a **high-priority** gesture, which is what lets the dock be
    /// dragged from anywhere on the bar rather than only from the slivers between
    /// its controls. Nearly every point on the dock is a button, and a plain
    /// `.gesture` loses to its children: the drag would then only start in the
    /// slivers of padding, which a pencil tip can hit and a fingertip cannot.
    ///
    /// Taps survive because of the minimum distance — the drag never recognises
    /// without real movement, so the button underneath keeps the touch. Once it
    /// does recognise, that button's press is cancelled, so dropping the dock on
    /// a colour swatch cannot also change the ink.
    private var dragGesture: some Gesture {
        // Reading the location in the dock's own space is what lets the quadrant
        // test work directly against the container the dock moves inside.
        DragGesture(minimumDistance: 8, coordinateSpace: .named(Self.dockSpace))
            .onChanged { value in
                if !isDragging {
                    withAnimation(Self.liftAnimation) { isDragging = true }
                }
                // Assigned unanimated: the dock has to sit under the finger, and
                // any animation here would leave it trailing the touch.
                dragOffset = value.translation
            }
            .onEnded { value in
                let target = DockEdge.nearest(to: value.location, in: containerSize)
                withAnimation(Self.settleAnimation) {
                    isDragging = false
                    parkedEdge = target
                    // Dropping the offset hands placement back to the stack
                    // alignment, which is what produces the drift into place.
                    dragOffset = .zero
                }
            }
    }
}
