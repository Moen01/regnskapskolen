import Foundation

/// The list windows over the screen (the town's menu, Fristnav, KART, portfolio, bag, rule cards,
/// archive, counter and choices; the battle's moves and answer panels; Paragrafjakten's lists), in
/// numbers. Rows use the dialog's 4 px glyphs, so long names fit: 34 to a row after the cursor
/// column, 7 px per row. The window's title keeps 8 px glyphs.
public enum ListBox {
    public static let columns = 34
    /// Logical px per row: a 4 px glyph and 3 px of air.
    public static let rowHeight = 7
    /// Logical px per glyph, both ways.
    public static let glyph = DialogBox.glyph
    /// A title in 8 px glyphs, like ARKIV or a panel's running sums.
    public static let titleColumns = 17
    /// Height left for rows in the 90 px window: 4 px padding on each side, the 8 px title and a 2 px gap.
    public static let windowRowSpace = 90 - 2 * 4 - 8 - 2

    /// How many rows fit in `height` logical px; at least one, so the cursor always shows.
    public static func rows(in height: Int) -> Int {
        max(1, height / rowHeight)
    }
}
