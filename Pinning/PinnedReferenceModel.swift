import CoreGraphics
import Foundation
import Observation

/// The pins floating over the open document.
///
/// Pins are a way of *looking at* the page, like pan and zoom, not an edit to
/// it: nothing here touches the ink or the undo stack. Array order is stacking
/// order — the last pin is drawn on top.
@Observable
@MainActor
final class PinnedReferenceModel {
    private(set) var references: [PinnedReference] = []

    /// Pins ink at its starting size and place.
    ///
    /// - Parameters:
    ///   - strokeIDs: The ink to pin. Nothing is pinned when it is empty.
    ///   - inkSize: The ink's canvas-space size, which decides the card's aspect.
    ///   - viewport: The screen the pin will float over.
    /// - Returns: The new pin, or nil when there was no ink to pin.
    @discardableResult
    func pin(strokeIDs: Set<UUID>, inkSize: CGSize, viewport: CGSize) -> PinnedReference? {
        guard !strokeIDs.isEmpty else { return nil }
        let longestSide = PinnedReferenceGeometry.initialLongestSide(inkSize: inkSize, viewport: viewport)
        let cardSize = PinnedReferenceGeometry.cardSize(inkSize: inkSize, longestSide: longestSide)
        let center = PinnedReferenceGeometry.initialCenter(
            cardSize: cardSize,
            viewport: viewport,
            existingPinCount: references.count
        )
        let reference = PinnedReference(strokeIDs: strokeIDs, center: center, longestSide: longestSide)
        references.append(reference)
        return reference
    }

    /// A pin that has just been made and has yet to fly from the page into
    /// place. Never saved: a reopened document's pins are simply there.
    private(set) var arrival: PinArrival?

    func beginArrival(_ arrival: PinArrival) {
        guard references.contains(where: { $0.id == arrival.pinID }) else { return }
        self.arrival = arrival
    }

    /// Called once the flight lands, so a card rebuilt later — after its ink is
    /// erased and undone, say — appears in place instead of flying again.
    func finishArrival(of id: UUID) {
        if arrival?.pinID == id { arrival = nil }
    }

    /// The most recent request to show where a pin's ink lives on the page.
    /// Not cleared when the flash fades — the views fade it on their own clock,
    /// and keeping it means they never have to be torn down and rebuilt to
    /// replay it. Never saved: it is a moment, not a setting.
    private(set) var sourceHighlight: PinSourceHighlight?

    /// What the flash views key their animation on. Zero means none yet.
    var sourceHighlightSequence: Int { sourceHighlight?.sequence ?? 0 }

    /// Flashes the outline around a pin's source ink.
    ///
    /// - Parameters:
    ///   - id: The pin whose source to show.
    ///   - outlines: The traced shapes to flash, in stored canvas space.
    ///   - offscreenSourcePoint: Where the source ink is on screen, when it is
    ///     outside the screen's bounds — the pin points an arrow at it. Nil
    ///     when the ink is already in view and the outline alone will do.
    func highlightSource(of id: UUID, outlines: [PinSourceOutline], offscreenSourcePoint: CGPoint?) {
        guard references.contains(where: { $0.id == id }) else { return }
        sourceHighlight = PinSourceHighlight(
            pinID: id,
            sequence: sourceHighlightSequence + 1,
            outlines: outlines,
            offscreenSourcePoint: offscreenSourcePoint
        )
    }

    /// Moves a pin and raises it: the pin being handled is the one the user is
    /// looking at, so it must not end up tucked under another.
    func move(_ id: UUID, to center: CGPoint) {
        update(id) { $0.center = center }
    }

    /// Brings a pin in front of the others without changing it — what a tap on a
    /// half-covered pin is asking for.
    func raise(_ id: UUID) {
        guard references.last?.id != id else { return }
        update(id) { _ in }
    }

    func resize(_ id: UUID, longestSide: CGFloat, center: CGPoint) {
        update(id) {
            $0.longestSide = longestSide
            $0.center = center
        }
    }

    /// Retires the current flash's arrow without replaying the flash — the
    /// sequence is kept, so the outline carries on fading where it was.
    func clearSourceArrow() {
        guard let highlight = sourceHighlight, highlight.offscreenSourcePoint != nil else { return }
        sourceHighlight = PinSourceHighlight(
            pinID: highlight.pinID,
            sequence: highlight.sequence,
            outlines: highlight.outlines,
            offscreenSourcePoint: nil
        )
    }

    func unpin(_ id: UUID) {
        references.removeAll { $0.id == id }
        // A flash still fading for a pin that is gone would outline ink that
        // nothing on screen refers to any more.
        if sourceHighlight?.pinID == id { sourceHighlight = nil }
        finishArrival(of: id)
    }

    /// Replaces the pins with a document's saved ones.
    ///
    /// Ids for ink that is no longer in the document are dropped here, at load,
    /// rather than whenever ink is erased — an erase can be undone, and the pin
    /// has to still be there when its ink comes back.
    func restore(_ saved: [PinnedReference], keepingStrokeIDs liveStrokeIDs: Set<UUID>) {
        sourceHighlight = nil
        arrival = nil
        references = saved.compactMap { reference in
            var surviving = reference
            surviving.strokeIDs.formIntersection(liveStrokeIDs)
            return surviving.strokeIDs.isEmpty ? nil : surviving
        }
    }

    private func update(_ id: UUID, _ change: (inout PinnedReference) -> Void) {
        guard let index = references.firstIndex(where: { $0.id == id }) else { return }
        var reference = references.remove(at: index)
        change(&reference)
        references.append(reference)
    }
}

/// Where a new pin's ink sat on screen when it was pinned, so the card can
/// start there — the ink at the size it was drawn — and fly to its place.
struct PinArrival: Equatable {
    let pinID: UUID
    /// Centre of the ink as it was drawn, in screen points.
    let sourceInkCenter: CGPoint
    /// The canvas zoom at the moment of pinning: screen points per canvas point.
    let canvasScale: CGFloat
}

/// One flash of a pin's source outline.
struct PinSourceHighlight: Equatable {
    let pinID: UUID
    /// Bumped on every flash, so tapping the same pin twice replays the fade
    /// instead of comparing equal to the last one and doing nothing.
    let sequence: Int
    /// Traced once, when the pin is tapped: the shape is a distance-field trace,
    /// far too costly to redo on each frame of the fade.
    let outlines: [PinSourceOutline]
    /// The source ink's centre in screen points when it is off screen; nil
    /// when it is in view.
    let offscreenSourcePoint: CGPoint?
}

/// The shape around the part of a pin's source filed under one problem — the
/// same rolling-ball region the page draws around each problem.
///
/// Kept in stored space with the problem it belongs to, so the arrangement's
/// shift can be added as it is drawn and the flash follows the ink if the
/// layout moves while it fades.
struct PinSourceOutline: Equatable {
    let problemNodeID: UUID?
    let contours: [[CGPoint]]
}
