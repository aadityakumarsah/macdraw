import AppKit

/// Recognizes tables on the clipboard and turns them into a table element.
///
/// Copying a table out of a chat answer, a spreadsheet or a Notion page used
/// to arrive as a wall of pipes and tabs in a single text block. The three
/// shapes below cover essentially everything that reaches the pasteboard:
///
/// - **HTML** (`public.html`) — what Notion, Google Sheets, Excel and most
///   web pages put on the clipboard alongside the plain text.
/// - **Markdown pipe tables** — what a chat answer gives you as plain text.
/// - **TSV** — what a spreadsheet puts in the *plain-text* flavour, and what
///   you get pasting between apps that strip HTML.
///
/// HTML is preferred when present because it carries the real cell
/// boundaries; the text forms are inferred and can be ambiguous.
enum TableImport {
    struct Table: Equatable {
        /// Row-major cells. Every row is padded to `columns`.
        var cells: [String]
        var columns: Int
        var rows: Int
        /// Whether the first row read as a header (a `<th>`, or a markdown
        /// separator line under it).
        var hasHeader: Bool

        func cell(row: Int, column: Int) -> String {
            let index = row * columns + column
            return cells.indices.contains(index) ? cells[index] : ""
        }
    }

    /// Smallest table worth rendering as a grid rather than as text.
    static let minimumCells = 4

    // MARK: - entry point

    /// Reads whichever flavour on the pasteboard describes a table.
    static func table(from pasteboard: NSPasteboard) -> Table? {
        if let html = pasteboard.string(forType: .html) ?? pasteboard.string(forType: NSPasteboard.PasteboardType("public.html")),
           let parsed = fromHTML(html) {
            return parsed
        }
        guard let text = pasteboard.string(forType: .string) else { return nil }
        return fromText(text)
    }

    /// Markdown first, then TSV: a markdown table's rows contain no tabs, so
    /// the two never compete for the same input.
    static func fromText(_ text: String) -> Table? {
        fromMarkdown(text) ?? fromTSV(text)
    }

    // MARK: - HTML

    static func fromHTML(_ html: String) -> Table? {
        guard let tableRange = rangeOfTag("table", in: html) else { return nil }
        let body = String(html[tableRange])

        var rows: [[String]] = []
        var sawHeaderCell = false
        var cursor = body.startIndex
        while let rowRange = rangeOfTag("tr", in: body, from: cursor) {
            let rowBody = String(body[rowRange])
            var cells: [String] = []
            var cellCursor = rowBody.startIndex
            while let (cellRange, isHeader) = rangeOfCell(in: rowBody, from: cellCursor) {
                if isHeader { sawHeaderCell = true }
                cells.append(plainText(String(rowBody[cellRange])))
                cellCursor = cellRange.upperBound
            }
            if !cells.isEmpty { rows.append(cells) }
            cursor = rowRange.upperBound
        }
        return assemble(rows, hasHeader: sawHeaderCell)
    }

    /// Inner range of the first `<tag …> … </tag>` at or after `from`.
    private static func rangeOfTag(
        _ tag: String, in html: String, from: String.Index? = nil
    ) -> Range<String.Index>? {
        let start = from ?? html.startIndex
        guard start < html.endIndex else { return nil }
        let scope = html[start...]
        guard let open = scope.range(of: "<\(tag)", options: [.caseInsensitive]),
              let openEnd = scope[open.upperBound...].firstIndex(of: ">") else { return nil }
        let contentStart = scope.index(after: openEnd)
        guard let close = scope.range(of: "</\(tag)", options: [.caseInsensitive], range: contentStart..<scope.endIndex) else {
            // An unclosed table still has usable rows.
            return contentStart..<scope.endIndex
        }
        return contentStart..<close.lowerBound
    }

    /// Inner range of the next `<td>` or `<th>`, and whether it was a `<th>`.
    private static func rangeOfCell(
        in row: String, from: String.Index
    ) -> (Range<String.Index>, Bool)? {
        let data = rangeOfTag("td", in: row, from: from)
        let header = rangeOfTag("th", in: row, from: from)
        switch (data, header) {
        case let (d?, h?):
            return d.lowerBound < h.lowerBound ? (d, false) : (h, true)
        case let (d?, nil):
            return (d, false)
        case let (nil, h?):
            return (h, true)
        case (nil, nil):
            return nil
        }
    }

    /// Strips markup and decodes the handful of entities that actually show
    /// up in clipboard HTML.
    static func plainText(_ fragment: String) -> String {
        var out = ""
        var insideTag = false
        for character in fragment {
            if character == "<" { insideTag = true; continue }
            if character == ">" { insideTag = false; continue }
            if !insideTag { out.append(character) }
        }
        let entities = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&mdash;": "—",
            "&ndash;": "–", "&hellip;": "…",
        ]
        for (entity, replacement) in entities {
            out = out.replacingOccurrences(of: entity, with: replacement)
        }
        return out
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - markdown

    static func fromMarkdown(_ text: String) -> Table? {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        // Every row of a markdown table contains a pipe, and at least two
        // lines are needed for one to exist at all.
        let candidates = lines.filter { $0.contains("|") }
        guard candidates.count >= 2 else { return nil }

        var rows: [[String]] = []
        var hasHeader = false
        for (offset, line) in candidates.enumerated() {
            if isSeparatorRow(line) {
                // A separator directly under the first row marks it a header.
                if offset == 1 { hasHeader = true }
                continue
            }
            rows.append(splitPipeRow(line))
        }
        guard rows.count >= 1 else { return nil }
        return assemble(rows, hasHeader: hasHeader)
    }

    /// `|---|:--:|` and friends.
    private static func isSeparatorRow(_ line: String) -> Bool {
        let stripped = line.filter { !" |".contains($0) }
        guard !stripped.isEmpty else { return false }
        return stripped.allSatisfy { $0 == "-" || $0 == ":" }
    }

    private static func splitPipeRow(_ line: String) -> [String] {
        var body = line
        if body.hasPrefix("|") { body.removeFirst() }
        if body.hasSuffix("|") { body.removeLast() }
        return body
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: - TSV

    static func fromTSV(_ text: String) -> Table? {
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.count >= 2 else { return nil }
        // Require a tab in every line, so prose with one stray tab is not
        // mistaken for a table.
        guard lines.allSatisfy({ $0.contains("\t") }) else { return nil }
        let rows = lines.map { line in
            line.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        // Spreadsheets emit a consistent column count; ragged input is more
        // likely to be something else.
        let widths = Set(rows.map(\.count))
        guard widths.count == 1 else { return nil }
        return assemble(rows, hasHeader: false)
    }

    // MARK: - shared

    /// Pads every row to the widest, drops fully empty trailing rows, and
    /// rejects anything too small to be worth a grid.
    private static func assemble(_ rows: [[String]], hasHeader: Bool) -> Table? {
        var rows = rows
        while let last = rows.last, last.allSatisfy({ $0.isEmpty }) { rows.removeLast() }
        guard let columns = rows.map(\.count).max(), columns >= 2, rows.count >= 2 else { return nil }
        var cells: [String] = []
        cells.reserveCapacity(rows.count * columns)
        for row in rows {
            for column in 0..<columns {
                cells.append(column < row.count ? row[column] : "")
            }
        }
        guard cells.count >= minimumCells else { return nil }
        guard cells.contains(where: { !$0.isEmpty }) else { return nil }
        return Table(cells: cells, columns: columns, rows: rows.count, hasHeader: hasHeader)
    }

    // MARK: - layout

    /// Column widths proportional to the widest cell in each column, so a
    /// table of one long column and three short ones does not come out as
    /// four equal stripes.
    static func columnWidths(for table: Table, font: NSFont, totalWidth: CGFloat) -> [CGFloat] {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        var intrinsic = [CGFloat](repeating: 0, count: table.columns)
        for row in 0..<table.rows {
            for column in 0..<table.columns {
                let text = table.cell(row: row, column: column) as NSString
                intrinsic[column] = max(intrinsic[column], text.size(withAttributes: attributes).width)
            }
        }
        let padding: CGFloat = 20
        let minimum: CGFloat = 56
        let wanted = intrinsic.map { max($0 + padding, minimum) }
        let sum = wanted.reduce(0, +)
        guard sum > 0 else {
            return [CGFloat](repeating: totalWidth / CGFloat(max(table.columns, 1)), count: table.columns)
        }
        // Scale to the element's width, keeping the proportions.
        return wanted.map { $0 / sum * totalWidth }
    }

    /// The size a table wants at a given font, before it is placed.
    static func naturalSize(for table: Table, font: NSFont) -> CGSize {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        var width: CGFloat = 0
        for column in 0..<table.columns {
            var widest: CGFloat = 0
            for row in 0..<table.rows {
                let text = table.cell(row: row, column: column) as NSString
                widest = max(widest, text.size(withAttributes: attributes).width)
            }
            width += max(widest + 20, 56)
        }
        let rowHeight = max(font.ascender - font.descender + 14, 28)
        return CGSize(
            width: min(max(width, 160), 1600),
            height: rowHeight * CGFloat(table.rows)
        )
    }
}
