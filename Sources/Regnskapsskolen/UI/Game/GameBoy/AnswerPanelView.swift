import RegnskapKit
import SwiftUI

/// The answer panel over the battle field: the model's title and rows, or its entry field.
struct AnswerPanelView: View {
    @Environment(\.gbScale) private var scale
    let panel: AnswerPanel
    var hitLine: Int? = nil
    let onClick: (Int) -> Void

    private var headline: String {
        // While the voucher's lines are listed, the title gives way to the running sums.
        if panel.isListingLines, let sums = panel.sums {
            return TextWrap.truncate("BILAG D\(AnswerPanel.amountText(sums.debet)) K\(AnswerPanel.amountText(sums.kredit))", to: AnswerPanel.columns)
        }
        return panel.title
    }

    var body: some View {
        GBBox(x: 4, y: 4, width: 152, height: 90, padding: 4) {
            VStack(alignment: .leading, spacing: 2 * scale) {
                GBText(headline)
                if let entry = panel.entry {
                    GBEntry(label: panel.entryLabel, text: entry)
                    GBText(panel.puzzle.kind == .frist ? "dd.mm.åååå" : "Enter = slå", color: GBPalette.dark)
                } else {
                    GBList(rows: panel.rows, cursor: panel.cursor, visible: panel.visibleRange, highlight: hitLine, onClick: onClick)
                }
            }
        }
    }
}
