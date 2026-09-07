import CoreGraphics
import Foundation

/// The wire format of the raw-data export — everything Tract records about a
/// drawing, as plain JSON another program can read.
///
/// It is a *separate* set of types from `Stroke` and friends rather than an
/// encoding of them, and deliberately so. The stored document format is free to
/// change shape whenever the app needs it to; this one is a published contract
/// that outside tooling parses, so it changes only with `formatVersion`. Nothing
/// here is ever decoded back into the app — reading a drawing is what
/// `DocumentFileStore` does — so these types exist purely to be written.
///
/// Everything is resolved on the way out: colours come as floats *and* hex,
/// problem tags as ids *and* the label they print as today, per-point timing as
/// seconds since the stroke began. A consumer should never have to reimplement
/// one of Tract's rules to read its data.
struct DrawingDataExport: Codable, Sendable {
    /// Bumped when a field changes meaning or disappears. Adding a field does not
    /// bump it: a reader that ignores unknown keys keeps working either way.
    static let currentFormatVersion = 1
    /// Identifies the file for a reader that has only the bytes.
    static let formatIdentifier = "tract.drawing"

    var format: String = DrawingDataExport.formatIdentifier
    var formatVersion: Int = DrawingDataExport.currentFormatVersion
    let exportedAt: Date
    let document: ExportedDocumentInfo
    /// The problem tree, roots first, each node carrying its children. Empty for
    /// a document whose work was never tagged.
    let problems: [ExportedProblemNode]
    /// In the order they were drawn, which is the order they must be painted in.
    let strokes: [ExportedStroke]
}

/// The document's own card: what the library shows, plus where the canvas was
/// parked when it was last saved.
struct ExportedDocumentInfo: Codable, Sendable {
    let id: UUID
    let title: String
    let createdAt: Date
    let modifiedAt: Date
    let strokeCount: Int
    /// Canvas pan/zoom at the last save. Not needed to read the ink — stroke
    /// positions are already in canvas space — but it is what the user was
    /// looking at, so a viewer can open on the same view.
    let canvasOrigin: ExportedPoint
    let canvasScale: CGFloat
    /// The box containing the painted ink, nib width included. Null-bounds
    /// documents (no ink at all) report nil rather than an infinite rect.
    let inkBounds: ExportedRect?
}

/// One node of the problem tree. `id` is what a stroke points at; `label` and
/// `tag` are what that node is *called* right now, which is a function of where
/// it sits and changes the moment the tree is reordered.
struct ExportedProblemNode: Codable, Sendable {
    let id: UUID
    /// This level's own text: "1", "b", "III".
    let label: String
    /// The full address including ancestors, as printed: "1.b.III".
    let tag: String
    /// Sibling indices from the outermost level inwards — `[0, 1]` is 1b.
    let path: [Int]
    /// The address level by level, so a consumer can re-render it in its own
    /// notation instead of parsing the joined string.
    let components: [ExportedTagComponent]
    let children: [ExportedProblemNode]
}

/// One level of a problem's address, as stored rather than as printed: the
/// ordinal is what sorts, the style is what turns it into "b" or "III".
struct ExportedTagComponent: Codable, Sendable {
    let styleID: String
    let ordinal: Int
    /// Verbatim text for a level that follows no numbering scheme. Nil normally.
    let customText: String?
    /// What this level prints as, with the style already applied.
    let text: String
}

struct ExportedStroke: Codable, Sendable {
    let id: UUID
    /// Shared by every stroke drawn in one continuous run of the app.
    let sessionID: UUID
    /// Position in the document's paint order, 0-based.
    let index: Int
    /// Wall-clock, from the pencil going down to it lifting.
    let startTime: Date
    let endTime: Date
    /// `endTime - startTime`, in seconds. Wall-clock, so it is only as precise as
    /// the two `Date`s — per-sample timing is on the points and is far finer.
    let durationSeconds: TimeInterval
    /// False for a stroke captured mid-gesture, which an export can only be if
    /// the document was saved with the pencil still down.
    let isComplete: Bool
    let style: ExportedStrokeStyle
    /// The centreline box, as stored — the nib is *not* added here, unlike
    /// `ExportedDocumentInfo.inkBounds`.
    let bounds: ExportedRect?
    /// The problem this stroke was filed under, or nil if it was never tagged
    /// (or was tagged against a node since deleted, which reads the same way).
    let problem: ExportedProblemReference?
    let pointCount: Int
    let points: [ExportedStrokePoint]
}

struct ExportedStrokeStyle: Codable, Sendable {
    let tool: String
    /// Straight RGBA in 0…1, the values the renderer works in.
    let color: ExportedColor
    /// `#RRGGBB`, for anything that would rather not do the arithmetic.
    let colorHex: String
    /// Width in canvas points. Every renderer in the app paints the whole stroke
    /// at this width — force is captured per sample but does not thin the line —
    /// so it is the painted width, not a nominal one.
    let lineWidth: CGFloat
    /// Multiplies the colour's own alpha at paint time.
    let opacity: CGFloat
}

struct ExportedColor: Codable, Sendable {
    let red: Float
    let green: Float
    let blue: Float
    let alpha: Float
}

/// Which problem a stroke belongs to, given every way a consumer might want it.
struct ExportedProblemReference: Codable, Sendable {
    /// The node id stored on the stroke — the only part of this that is durable.
    let nodeID: UUID
    /// The address as printed today: "1.b". Nil when the node no longer exists.
    let tag: String?
    let path: [Int]?
    let components: [ExportedTagComponent]?
}

/// One Apple Pencil sample, with every property the hardware reported.
struct ExportedStrokePoint: Codable, Sendable {
    /// Canvas space, the same space every other coordinate in this file is in.
    let x: CGFloat
    let y: CGFloat
    /// Nib pressure. 1.0 is "normal" force; a finger or a non-force stylus reads 0.
    let force: CGFloat
    /// Radians. Which way the pencil points across the screen.
    let azimuth: CGFloat
    /// Radians. 0 is flat against the glass, π/2 is straight up.
    let altitude: CGFloat
    /// Radians. Apple Pencil Pro barrel roll; always 0 on other pencils.
    let rollAngle: CGFloat
    /// Seconds since this stroke's first sample. Nil for a stroke recorded
    /// before per-sample timing was captured, or built synthetically.
    let timeOffset: TimeInterval?
    /// The raw device clock this sample was stamped with — seconds since boot,
    /// so it compares across strokes in one session and means nothing across two.
    let deviceTimestamp: TimeInterval?
    /// Properties UIKit had not finalised when the sample arrived, by name:
    /// "force", "azimuth", "altitude", "location". Usually empty — a value here
    /// means that field is an estimate the app never received a correction for.
    let estimatedProperties: [String]
}

struct ExportedPoint: Codable, Sendable {
    let x: CGFloat
    let y: CGFloat

    init(_ point: CGPoint) {
        self.x = point.x
        self.y = point.y
    }
}

struct ExportedRect: Codable, Sendable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    /// Nil for `.null` — a rect with no area to describe. Encoding one would put
    /// `infinity` in the JSON, which most parsers reject outright.
    init?(_ rect: CGRect) {
        guard !rect.isNull, !rect.isInfinite else { return nil }
        self.x = rect.origin.x
        self.y = rect.origin.y
        self.width = rect.width
        self.height = rect.height
    }
}
