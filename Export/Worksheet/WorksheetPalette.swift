import UIKit

/// Colour tokens for the worksheet's furniture — badges, separators, guides.
///
/// The handwriting is **never** recoloured: its black, red and blue carry the
/// student's own meaning. Everything here is the page around it.
enum WorksheetPalette {
    /// Three hues, as far apart on the wheel as three can be, cycled by
    /// top-level problem number: 1-3 get red, blue, green and 4-6 get them again.
    ///
    /// Three strongly separated colours beat eight subtly separated ones here —
    /// the job is telling *this* problem's badge from the one next to it, and
    /// adjacent problems are always different. Neighbouring hues (red beside
    /// orange) failed that at a glance. They are dark and saturated because they
    /// print in mono as often as not.
    private static var groupColors: [UIColor] {
        [
            color(200, 30, 30),   // #C81E1E red
            color(29, 78, 216),   // #1D4ED8 blue
            color(21, 128, 61)    // #15803D green
        ]
    }

    /// Work nobody filed gets grey — present, but not claiming to be a problem.
    private static var untaggedColor: UIColor { color(113, 113, 122) } // #71717A

    /// The lines dividing the page. Darker than the margin guide: they are
    /// structure the reader is meant to follow, not a debugging aid.
    static var separator: UIColor { color(107, 107, 120) } // #6B6B78

    /// The badge plate. A tag has to be findable at a glance on a dense page,
    /// and against dark-on-light handwriting what stands out is a solid dark
    /// block with light text; the problem's colour stays as the ring.
    static var badgePlate: UIColor { color(63, 63, 70) } // #3F3F46
    static var badgeText: UIColor { .white }

    /// - Parameter groupIndex: 0-based top-level problem number; nil for untagged.
    static func color(forGroupIndex groupIndex: Int?) -> UIColor {
        guard let groupIndex, groupIndex >= 0 else { return untaggedColor }
        let colors = groupColors
        return colors[groupIndex % colors.count]
    }

    private static func color(_ red: Int, _ green: Int, _ blue: Int) -> UIColor {
        UIColor(
            red: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: 1
        )
    }
}
