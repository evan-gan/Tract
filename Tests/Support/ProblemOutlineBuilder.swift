import Foundation
@testable import Tract

/// Builds an outline from the addresses a person would write down, so a test
/// can say "tag this stroke 1b" instead of assembling nested nodes by hand.
///
/// Addresses are 1-based to match what the app prints: `[1, 2]` is 1b, and
/// `[2, 1, 3]` is 2a.III. Missing ancestors are created on the way down, which
/// is what lets a test name only the nodes it cares about.
struct ProblemOutlineBuilder {
    private(set) var outline = ProblemOutline()

    /// The id of the node at `address`, creating it and any gap before it.
    mutating func node(_ address: [Int]) -> UUID {
        var parentPath: ProblemPath = []
        for oneBasedIndex in address {
            let index = oneBasedIndex - 1
            while outline.children(under: parentPath).count <= index {
                outline.appendChild(under: parentPath)
            }
            parentPath.append(index)
        }
        return outline.node(at: parentPath)!.id
    }

    /// The path a previously built address resolves to.
    func path(_ address: [Int]) -> ProblemPath {
        address.map { $0 - 1 }
    }
}
