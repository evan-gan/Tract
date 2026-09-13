import CoreGraphics
import Foundation

/// One undoable change to the ink, carrying just enough to replay it either way.
///
/// Undo used to snapshot the whole stroke list before every edit, so history cost
/// page size × edit count and a move of one mark copied the entire page. Each
/// entry here holds only what the edit touched: the strokes it added or removed,
/// the ids and distance of a move, or the tags it swapped. Moves are replayed
/// through `Stroke.translate(by:)`, which shifts positions and nothing else, so
/// the Apple Pencil telemetry on every sample survives any number of round trips.
///
/// `apply(to:)` and `revert(on:)` assume the list is in exactly the state the
/// edit left it in (or found it in) — which the undo and redo stacks guarantee by
/// only ever replaying entries in order.
enum CanvasEdit {
    /// Strokes appended to the end of the list.
    case added([Stroke])
    /// Strokes taken out of the list, in the order they were removed.
    case removed([RemovedStroke])
    /// Strokes slid rigidly by one offset.
    case moved(strokeIDs: Set<UUID>, offset: CGPoint)
    /// Strokes re-filed under a different problem, keyed by stroke id.
    case retagged([UUID: TagChange])

    /// A stroke removed from the list, with where it sat at the moment it went.
    ///
    /// The index is the one it had *after* every earlier removal in the same
    /// entry, so reinserting in reverse order puts each mark back at its original
    /// depth — erasing never reshuffles what draws on top of what.
    struct RemovedStroke {
        let index: Int
        let stroke: Stroke
    }

    struct TagChange {
        let from: UUID?
        let to: UUID?
    }

    /// Replays the edit forwards — what redo does.
    func apply(to strokes: inout [Stroke]) {
        switch self {
        case .added(let addedStrokes):
            strokes.append(contentsOf: addedStrokes)
        case .removed(let removals):
            let removedIDs = Set(removals.map(\.stroke.id))
            strokes.removeAll { removedIDs.contains($0.id) }
        case .moved(let strokeIDs, let offset):
            Self.translate(&strokes, strokeIDs: strokeIDs, by: offset)
        case .retagged(let changes):
            Self.retag(&strokes, changes: changes, takingNewTag: true)
        }
    }

    /// Replays the edit backwards — what undo does.
    func revert(on strokes: inout [Stroke]) {
        switch self {
        case .added(let addedStrokes):
            let addedIDs = Set(addedStrokes.map(\.id))
            strokes.removeAll { addedIDs.contains($0.id) }
        case .removed(let removals):
            for removal in removals.reversed() {
                // Clamped only as a guard against a list that has drifted from
                // the one the entry was recorded against; in order it never fires.
                strokes.insert(removal.stroke, at: min(removal.index, strokes.count))
            }
        case .moved(let strokeIDs, let offset):
            Self.translate(&strokes, strokeIDs: strokeIDs, by: CGPoint(x: -offset.x, y: -offset.y))
        case .retagged(let changes):
            Self.retag(&strokes, changes: changes, takingNewTag: false)
        }
    }

    /// Removes every stroke matching a predicate in one pass, and reports each
    /// one with the index it would have had if they were taken out one by one.
    ///
    /// - Parameters:
    ///   - strokes: the list to remove from.
    ///   - shouldRemove: whether a stroke goes.
    /// - Returns: the removals, in list order, ready for a `.removed` entry. Empty
    ///   when nothing matched.
    static func removeStrokes(
        from strokes: inout [Stroke],
        where shouldRemove: (Stroke) -> Bool
    ) -> [RemovedStroke] {
        var removals: [RemovedStroke] = []
        var keptStrokes: [Stroke] = []
        keptStrokes.reserveCapacity(strokes.count)
        for (originalIndex, stroke) in strokes.enumerated() {
            if shouldRemove(stroke) {
                // Every earlier removal has already shifted this one down a slot.
                removals.append(RemovedStroke(index: originalIndex - removals.count, stroke: stroke))
            } else {
                keptStrokes.append(stroke)
            }
        }
        // Left alone when nothing matched, so an eraser pass over blank paper
        // does not publish a stroke-list change to every observer.
        if !removals.isEmpty { strokes = keptStrokes }
        return removals
    }

    private static func translate(_ strokes: inout [Stroke], strokeIDs: Set<UUID>, by offset: CGPoint) {
        for index in strokes.indices where strokeIDs.contains(strokes[index].id) {
            strokes[index].translate(by: offset)
        }
    }

    private static func retag(_ strokes: inout [Stroke], changes: [UUID: TagChange], takingNewTag: Bool) {
        for index in strokes.indices {
            guard let change = changes[strokes[index].id] else { continue }
            strokes[index].problemNodeID = takingNewTag ? change.to : change.from
        }
    }
}
