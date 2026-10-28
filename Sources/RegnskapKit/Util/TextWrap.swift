import Foundation

/// Text for a fixed-width screen: word wrap into columns, pages of rows, plain text from the
/// content's Markdown, and truncation with an ellipsis. Counts `Character`s, so a glyph the
/// screen's font lacks still takes one column.
public enum TextWrap {
    /// Greedy word wrap. Explicit newlines are kept; a run of blank lines becomes one blank line;
    /// a word longer than a line is cut with a hyphen.
    public static func lines(_ text: String, columns: Int) -> [String] {
        precondition(columns > 1)
        var out: [String] = []
        var previousBlank = false
        for raw in text.components(separatedBy: "\n") {
            let words = raw.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            if words.isEmpty {
                if !previousBlank, !out.isEmpty { out.append("") }
                previousBlank = true
                continue
            }
            previousBlank = false
            var line = ""
            for word in words {
                var rest = word
                while rest.count > columns {
                    if !line.isEmpty { out.append(line); line = "" }
                    out.append(String(rest.prefix(columns - 1)) + "-")
                    rest = String(rest.dropFirst(columns - 1))
                }
                if line.isEmpty {
                    line = rest
                } else if line.count + 1 + rest.count <= columns {
                    line += " " + rest
                } else {
                    out.append(line)
                    line = rest
                }
            }
            out.append(line)
        }
        while out.last == "" { out.removeLast() }
        return out
    }

    /// Chunks of `rows` lines; an empty input is one empty page so a dialog always has a page.
    public static func pages(_ lines: [String], rows: Int) -> [[String]] {
        precondition(rows > 0)
        guard !lines.isEmpty else { return [[]] }
        return stride(from: 0, to: lines.count, by: rows).map { Array(lines[$0..<min($0 + rows, lines.count)]) }
    }

    /// The content's Markdown as lines of plain text: headings and paragraphs as their text,
    /// bullets as `- item`, table rows as cells joined by ` | `, inline marks and links removed.
    public static func plain(markdown: String) -> String {
        var lines: [String] = []
        for block in MarkdownBlocks.parse(markdown) {
            switch block {
            case .heading(_, let text): lines.append(text)
            case .paragraph(let text): lines.append(text)
            case .bullets(let items): lines += items.map { "- \($0)" }
            case .table(let header, let rows): lines += ([header] + rows).map { $0.joined(separator: " | ") }
            }
        }
        return lines.map(stripInline).joined(separator: "\n")
    }

    /// Keeps the text when it fits, else the first `columns - 1` characters and an ellipsis.
    public static func truncate(_ text: String, to columns: Int) -> String {
        guard text.count > columns else { return text }
        let head = String(text.prefix(columns - 1))
        return head.trimmingCharacters(in: .whitespaces) + "…"
    }

    private static let inlineMarks: [(pattern: String, replacement: String)] = [
        (#"\[([^\]]+)\]\([^)]*\)"#, "$1"),
        (#"\*\*(.+?)\*\*"#, "$1"),
        (#"__(.+?)__"#, "$1"),
        (#"\*(.+?)\*"#, "$1"),
        (#"(?<![\p{L}\d])_(.+?)_(?![\p{L}\d])"#, "$1"),
        (#"`([^`]*)`"#, "$1"),
    ]

    private static func stripInline(_ text: String) -> String {
        inlineMarks.reduce(text) { partial, mark in
            partial.replacingOccurrences(of: mark.pattern, with: mark.replacement, options: .regularExpression)
        }
    }
}
