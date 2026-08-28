import SwiftUI

/// Parks the tool dock against a screen edge and lets the user drag it to a
/// different one. While dragging, the dock follows the finger and re-flows the
/// moment the finger crosses into another edge's quadrant; on release it drifts
/// into place against that edge.
struct FloatingToolDock: View {
    @Bindable var viewModel: CanvasViewModel
    let glassNamespace: Namespace.ID
    /// Height of the top chrome row the dock must sit below when parked on top.
    let topReserved: CGFloat

    /// Placement is view state, not model state: nothing outside this view needs
    /// it, and @State is what reliably re-lays-out the dock when it changes.
    @State private var parkedEdge: DockEdge = .bottom
    /// Edge the finger is currently over, which the dock previews by re-flowing.
    @State private var hoveredEdge: DockEdge?
    @State private var dragOffset: CGSize = .zero
    @State private var containerSize: CGSize = .zero

    private static let dockSpace = "toolDockSpace"
    private static let margin: CGFloat = 12
    private static let reflowAnimation: Animation = .smooth(duration: 0.32)
    private static let settleAnimation: Animation = .spring(response: 0.42, dampingFraction: 0.78)

    private var activeEdge: DockEdge { hoveredEdge ?? parkedEdge }

    var body: some View {
        ZStack(alignment: activeEdge.alignment) {
            ToolDockView(viewModel: viewModel, edge: activeEdge)
                .offset(dragOffset)
                .gesture(dragGesture)
                .glassEffectID("toolDock", in: glassNamespace)
        }
        // The alignment has to live on the filling frame: a single-child ZStack
        // sizes to its child, so its own alignment would never place anything.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: activeEdge.alignment)
        .coordinateSpace(.named(Self.dockSpace))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { containerSize = $0 }
        .padding(.top, topReserved)
        .padding(Self.margin)
    }

    private var dragGesture: some Gesture {
        // A minimum distance keeps taps on the dock's buttons from starting a drag.
        // Reading the location in the dock's own space is what lets the quadrant
        // test work directly against the container the dock moves inside.
        DragGesture(minimumDistance: 8, coordinateSpace: .named(Self.dockSpace))
            .onChanged { value in
                dragOffset = value.translation

                let target = DockEdge.nearest(to: value.location, in: containerSize)
                guard target != hoveredEdge else { return }
                withAnimation(Self.reflowAnimation) { hoveredEdge = target }
            }
            .onEnded { value in
                let target = DockEdge.nearest(to: value.location, in: containerSize)
                hoveredEdge = nil
                withAnimation(Self.settleAnimation) {
                    parkedEdge = target
                    // Dropping the offset hands placement back to the stack
                    // alignment, which is what produces the drift into place.
                    dragOffset = .zero
                }
            }
    }
}
