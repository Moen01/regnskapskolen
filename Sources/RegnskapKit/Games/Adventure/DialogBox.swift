import Foundation

/// The dialog box at the bottom of the Game Boy screen, in numbers: glyphs of 4 × 4 logical px,
/// 36 to a line (160 px less 8 px margin on each side) and 4 lines in the 32 px box. Battles and
/// the town page their text with these; list rows have their own numbers in `ListBox`.
public enum DialogBox {
    public static let columns = 36
    public static let rows = 4
    /// Logical px per glyph, both ways.
    public static let glyph = 4
}
