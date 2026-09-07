import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// What a drag in the library carries: which thing is being moved, and whether
/// it is a document or a folder.
///
/// Only the identifier travels, never the document itself — a drag must not cost
/// a stroke decode, and the drop only ever needs to know what to re-file.
///
/// Carried as JSON because the app declares no exported UTType of its own (the
/// Info.plist is generated, so there is nowhere to declare one). The cost is
/// that a JSON file dragged in from another app is offered to these drop
/// targets; it simply fails to decode into this shape and the drop is refused,
/// which is why every drop handler treats an empty item list as "not ours".
struct LibraryItemReference: Codable, Hashable, Sendable, Transferable {
    enum Kind: String, Codable, Sendable {
        case document
        case folder
    }

    let kind: Kind
    let id: UUID

    static func document(_ id: UUID) -> LibraryItemReference {
        LibraryItemReference(kind: .document, id: id)
    }

    static func folder(_ id: UUID) -> LibraryItemReference {
        LibraryItemReference(kind: .folder, id: id)
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}
