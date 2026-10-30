import Foundation

/// The dialog box at the bottom of the Game Boy screen, in numbers: glyphs of 4 × 4 logical px,
/// 36 to a line (160 px less 8 px margin on each side) and 6 lines in the 48 px box. Battles and
/// the town page their text with these; lists, menus and the answer panel keep 8 px glyphs.
public enum DialogBox {
    public static let columns = 36
    public static let rows = 6
    /// Logical px per glyph, both ways.
    public static let glyph = 4
}
