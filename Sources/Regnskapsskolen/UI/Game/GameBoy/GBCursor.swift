import Foundation
import RegnskapKit

/// A cursor over a list with a scrolling window of `visible` rows that always holds it.
struct GBCursor: Hashable {
    var index = 0
    var windowStart = 0
    let visible: Int

    init(visible: Int) { self.visible = visible }

    mutating func move(by delta: Int, count: Int) {
        index = min(max(0, count - 1), max(0, index + delta))
        follow()
    }

    mutating func set(_ value: Int, count: Int) {
        index = min(max(0, count - 1), max(0, value))
        follow()
    }

    mutating func reset() {
        index = 0
        windowStart = 0
    }

    func range(count: Int) -> Range<Int> {
        let start = min(windowStart, max(0, count - visible))
        return start..<min(count, start + visible)
    }

    private mutating func follow() {
        if index < windowStart { windowStart = index }
        if index >= windowStart + visible { windowStart = index - visible + 1 }
    }
}

/// The dialog pages for one text, in the battle's measure.
func gbPages(_ text: String) -> [[String]] {
    TextWrap.pages(TextWrap.lines(text, columns: BattleFlow.columns), rows: BattleFlow.rows)
}

/// Pages for several texts, one after the other.
func gbPages(_ texts: [String]) -> [[String]] {
    let pages = texts.flatMap { TextWrap.pages(TextWrap.lines($0, columns: BattleFlow.columns), rows: BattleFlow.rows) }
    return pages.isEmpty ? [[]] : pages
}
