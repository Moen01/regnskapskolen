import Foundation

/// What the Game Boy understands: the D-pad, A (Enter), B (Esc), Tab for the dialog, Delete,
/// and typed characters for the entry fields.
public enum GameKey: Hashable, Sendable {
    case up, down, left, right, a, b, tab, delete
    case character(Character)
}

/// One row in a panel list, already cut to the screen's width. `full` carries the whole text
/// when it was cut, so the dialog can show it.
public struct PanelRow: Hashable, Sendable, Identifiable {
    public let id: String
    public let text: String
    public let full: String?
    public let marked: Bool

    public init(id: String, text: String, full: String? = nil, marked: Bool = false) {
        self.id = id; self.text = text; self.full = full; self.marked = marked
    }

    /// A row from a text longer than the panel allows; `full` is set only when it was cut.
    public static func fitting(id: String, _ text: String, columns: Int, marked: Bool = false) -> PanelRow {
        let cut = TextWrap.truncate(text, to: columns)
        return PanelRow(id: id, text: cut, full: cut == text ? nil : text, marked: marked)
    }
}

public enum PanelEvent: Hashable, Sendable {
    case none
    case attack
    case back
    case invalid(String)
}
