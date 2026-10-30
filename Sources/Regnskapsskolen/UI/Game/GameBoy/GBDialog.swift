import SwiftUI

/// The dialog box at the bottom of the screen: four lines of 36 characters in 4 px letters
/// (`DialogBox`), typed out at 30 characters a second, a ▼ that blinks when there is more (`TAB▼` when Tab turns the page).
/// A click on the box shows the rest of the page, then turns it.
struct GBDialog: View {
    @Environment(\.gbScale) private var scale
    let pages: [[String]]
    let page: Int
    var typing = true
    var tabTurns = false
    /// The marker shows even on the last page: A moves the story on.
    var showsMarker = false
    /// Bumped by the owner when Enter or space should show the rest of the page at once.
    var reveal = 0
    var onComplete: ((Bool) -> Void)? = nil
    let onTurn: () -> Void
    @State private var shown = Int.max
    @State private var blink = true

    private var lines: [String] { pages.indices.contains(page) ? pages[page] : [] }
    private var total: Int { lines.reduce(0) { $0 + $1.count } }
    private var complete: Bool { !typing || shown >= total }
    private var hasMore: Bool { page < pages.count - 1 }

    var body: some View {
        GBBox(x: 0, y: 112, width: 160, height: 32, padding: 0, fill: GBTheme.dialogFill) {
            ZStack(alignment: .bottomTrailing) {
                // GBBox draws its inner border 1 px thick at y 2 and y 29 (height − 3), so the free
                // inside is y 3–28. Four 4 px lines at a 5 px pitch: y 5, 10, 15, 20, the last
                // ending at 24. The marker's 4 px cell is y 25–28, under line four and clear of the
                // border at 29. All whole logical pixels, so every integer scale lands on device pixels.
                // An accent on a capital (`GBText`) reaches 1 px up: on line one it stays below the
                // border, on the others inside the 1 px gap.
                VStack(alignment: .leading, spacing: 1 * scale) {
                    ForEach(Array(visibleLines.enumerated()), id: \.offset) { _, line in
                        GBText(line, size: .small, color: GBTheme.dialogText)
                    }
                }
                .padding(.top, 5 * scale)
                .padding(.leading, 8 * scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                if complete, hasMore || tabTurns || showsMarker {
                    GBText(tabTurns && !showsMarker ? "TAB▼" : "▼", size: .small, color: GBTheme.cursor)
                        .opacity(blink || !typing ? 1 : 0)
                        .padding(.trailing, 3 * scale)
                        .padding(.bottom, 3 * scale)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if complete { onTurn() } else { shown = total }
        }
        .onChange(of: pages) { restart() }
        .onChange(of: page) { restart() }
        .onChange(of: reveal) { shown = total }
        .onChange(of: complete) { onComplete?(complete) }
        .onAppear { restart() }
        .task(id: typing) {
            guard typing else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                if shown < total { shown += 1 }
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                blink.toggle()
            }
        }
    }

    /// The page's lines cut to the characters typed so far.
    private var visibleLines: [String] {
        guard typing else { return lines }
        var budget = shown
        return lines.map { line in
            let take = min(line.count, max(0, budget))
            budget -= line.count
            return String(line.prefix(take))
        }
    }

    private func restart() {
        shown = typing ? 0 : Int.max
    }
}
