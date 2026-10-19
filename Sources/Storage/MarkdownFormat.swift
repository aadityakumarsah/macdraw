import AppKit

/// Markdown-style auto-formatting for canvas text: type plain text and the
/// annotation renders as a document —
///
///     # Heading 1              → large bold heading
///     ## Heading 2             → medium bold heading
///     ### Heading 3            → small bold heading
///     - item                   → bullet list
///     1. step                  → numbered list
///     > note                   → italic quote
///     ---                      → thin divider
///     ``` ... ```              → syntax-highlighted code block
///     **bold**, *italic*, `code`, ~~strike~~ → inline styles
///
/// The user always types and edits the plain text; the styling is applied
/// automatically and kept as rich text on the annotation.

/// True when the text uses any markdown marker (headings, lists, quotes,
/// dividers, fenced code or inline emphasis).
func hasMarkdownFormatting(_ text: String) -> Bool {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    for line in lines {
        let t = String(line)
        if t.hasPrefix("```") { return true }
        if t.range(of: #"^\s{0,3}(#{1,6}\s|[-*+]\s|\d{1,3}[.)]\s|>\s|(?:---+|\*{3,}|_{3,})\s*$)"#, options: .regularExpression) != nil {
            return true
        }
    }
    if text.range(of: #"(\*\*[^*]+\*\*|\*[^*]+\*|`[^`]+`|~~[^~]+~~)"#, options: .regularExpression) != nil {
        return true
    }
    return false
}

/// Styles a plain string as markdown. `baseFont`/`baseColor` are the
/// annotation's own style; `dark` picks the code/quote palettes. Fenced code
/// is highlighted with `codeHighlighter` (the app's syntax tokenizer).
///
/// Two renderings:
///   `display == false` — the live edit view. The text keeps every character
///   the user typed (markers stay visible); only fonts, colors and sizes are
///   styled.
///   `display == true` — the committed document. Markers are consumed:
///   "# Heading" renders "Heading", "- item" renders "•  item", "```" fences
///   collapse into a highlighted block and "**bold**" renders as bold.
func markdownStyled(
    _ text: String,
    baseFont: NSFont,
    baseColor: NSColor,
    dark: Bool,
    display: Bool = false,
    codeHighlighter: ((String, NSFont, Bool) -> NSAttributedString)? = nil
) -> NSAttributedString {
    let baseSize = baseFont.pointSize
    let secondary = dark
        ? NSColor(calibratedWhite: 0.6, alpha: 1)
        : NSColor(calibratedWhite: 0.42, alpha: 1)
    let codeBg = dark
        ? NSColor(calibratedWhite: 1, alpha: 0.10)
        : NSColor(calibratedWhite: 0, alpha: 0.055)
    let codeFont = Fonts.nsFont(for: "Cascadia Code", size: baseSize * 0.92)

    let plain: [NSAttributedString.Key: Any] = [
        .font: baseFont,
        .foregroundColor: baseColor,
    ]
    let headingFont = { (scale: CGFloat) -> NSFont in
        let d = baseFont.fontDescriptor
        let desc = d.withSymbolicTraits([.bold])
        if let f = NSFont(descriptor: desc, size: baseSize * scale) {
            return f
        }
        // The family has no bold face (e.g. the default handwriting font) —
        // fall back to the system bold so headings still read as headings.
        return NSFont.systemFont(ofSize: baseSize * scale, weight: .bold)
    }

    func paragraph(_ spacing: CGFloat, indent: CGFloat = 0, hanging: CGFloat = 0) -> NSMutableParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = baseSize * 0.16
        p.paragraphSpacing = spacing
        p.headIndent = indent
        if hanging > 0 {
            p.firstLineHeadIndent = hanging
        }
        p.lineBreakMode = .byWordWrapping
        return p
    }

    let result = NSMutableAttributedString()
    let lines = text.components(separatedBy: "\n")
    var inFence = false
    var fenceAccum = ""

    func flushFence() {
        guard !fenceAccum.isEmpty else { return }
        let styled: NSAttributedString
        if let hl = codeHighlighter {
            styled = hl(fenceAccum, codeFont, dark)
        } else {
            styled = NSAttributedString(string: fenceAccum, attributes: plain)
        }
        let withBg = NSMutableAttributedString(attributedString: styled)
        withBg.addAttribute(.backgroundColor, value: codeBg, range: NSRange(location: 0, length: withBg.length))
        withBg.addAttribute(.paragraphStyle, value: paragraph(0, indent: 0), range: NSRange(location: 0, length: withBg.length))
        result.append(withBg)
        result.append(NSAttributedString(string: "\n", attributes: plain))
        fenceAccum = ""
    }

    for rawLine in lines {
        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
        if line.hasPrefix("```") {
            if inFence {
                flushFence()
            }
            inFence.toggle()
            if !display {
                // Keep the marker line visible while typing (code-styled so it
                // reads as part of the block).
                let markerLine = NSAttributedString(string: "```\n", attributes: [
                    .font: codeFont,
                    .foregroundColor: secondary,
                ])
                result.append(markerLine)
            }
            continue
        }
        if inFence {
            // A fence line in the live view styles like the finished block.
            let lineStyled: NSAttributedString
            if let hl = codeHighlighter {
                lineStyled = hl(line, codeFont, dark)
            } else {
                lineStyled = NSAttributedString(string: line, attributes: [
                    .font: codeFont,
                    .foregroundColor: baseColor,
                ])
            }
            let withBg = NSMutableAttributedString(attributedString: lineStyled)
            withBg.addAttribute(.backgroundColor, value: codeBg, range: NSRange(location: 0, length: withBg.length))
            withBg.addAttribute(.paragraphStyle, value: paragraph(0), range: NSRange(location: 0, length: withBg.length))
            result.append(withBg)
            result.append(NSAttributedString(string: "\n", attributes: plain))
            continue
        }

        var content = line
        var scale: CGFloat = 1
        var color = baseColor
        var prefix = ""
        var headIndent: CGFloat = 0
        var isHeading = false

        // Heading levels.
        if line.range(of: #"^\s{0,3}#{1,6}\s"#, options: .regularExpression) != nil {
            isHeading = true
            let leading = line.drop { $0 == " " }
            let hashes = leading.prefix { $0 == "#" }.count
            let level = min(6, max(1, hashes))
            if display {
                content = String(leading.dropFirst(hashes).drop { $0 == " " })
            }
            switch level {
            case 1: scale = 1.85
            case 2: scale = 1.5
            case 3: scale = 1.25
            case 4: scale = 1.1
            case 5: scale = 1.0
            default: scale = 0.9
            }
        } else if line.range(of: #"^\s{0,3}>\s"#, options: .regularExpression) != nil {
            color = secondary
            if display {
                content = String(line.drop { $0 == ">" || $0 == " " }).trimmingCharacters(in: .whitespaces)
                prefix = "› "
            }
        } else if line.range(of: #"^\s{0,3}[-*+]\s"#, options: .regularExpression) != nil {
            if display {
                content = String(line.drop { $0 == "-" || $0 == "*" || $0 == "+" || $0 == " " }).trimmingCharacters(in: .whitespaces)
                prefix = "•  "
                headIndent = baseSize * 0.85
            }
        } else if line.range(of: #"^\s{0,3}\d{1,3}[.)]\s"#, options: .regularExpression) != nil {
            let matched = line.range(of: #"^\s{0,3}\d{1,3}[.)]\s"#, options: .regularExpression)!
            if display {
                prefix = String(line[matched])
                content = String(line[matched.upperBound]).trimmingCharacters(in: .whitespaces)
                headIndent = baseSize * 1.15
            }
        } else if line.range(of: #"^\s{0,3}(?:-{3,}|\*{3,}|_{3,})\s*$"#, options: .regularExpression) != nil {
            // Divider: a thin rule, like a horizontal line in a document.
            // In the live view the typed "---" itself becomes the rule.
            let rule = display ? String(repeating: "―", count: 42) : line
            result.append(NSAttributedString(string: rule + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: baseSize * 0.55, weight: .light),
                .foregroundColor: secondary.withAlphaComponent(0.55),
                .paragraphStyle: paragraph(baseSize * 0.5),
            ]))
            continue
        }

        if content.isEmpty {
            result.append(NSAttributedString(string: "\n", attributes: plain))
            continue
        }

        let lineAttrs: [NSAttributedString.Key: Any] = {
            var a: [NSAttributedString.Key: Any] = [.foregroundColor: color]
            a[.font] = isHeading ? headingFont(scale) : baseFont
            a[.paragraphStyle] = paragraph(baseSize * (scale > 1.2 ? 0.45 : 0.22), indent: headIndent, hanging: 0)
            return a
        }()

        let styledLine = inlineStyled(
            content,
            attrs: lineAttrs,
            codeFont: codeFont,
            codeBg: codeBg,
            strikeColor: color,
            stripMarkers: display
        )
        let prefixed = NSMutableAttributedString(string: prefix, attributes: lineAttrs)
        prefixed.append(styledLine)
        result.append(prefixed)
        result.append(NSAttributedString(string: "\n", attributes: plain))
    }
    flushFence()
    return result
}

/// Applies inline emphasis (`**bold**`, `*italic*`, `` `code` ``, `~~strike~~`)
/// to the given string, inheriting `attrs` for plain runs. When
/// `stripMarkers` is true the marker characters are consumed (rendering a
/// clean document); otherwise they stay visible (the live editing view).
private func inlineStyled(
    _ text: String,
    attrs: [NSAttributedString.Key: Any],
    codeFont: NSFont,
    codeBg: NSColor,
    strikeColor: NSColor,
    stripMarkers: Bool
) -> NSAttributedString {
    struct Style {
        let regex: NSRegularExpression
        /// Chars of the opening marker (also the closing marker's length).
        let marker: Int
        let apply: (NSMutableAttributedString, NSRange, NSFont, NSColor) -> Void
    }
    let styles: [Style] = [
        Style(regex: try! NSRegularExpression(pattern: #"\*\*\*(.+?)\*\*\*"#), marker: 3) { s, r, f, c in
            let cur = (s.attribute(.font, at: r.location, effectiveRange: nil) as? NSFont) ?? f
            s.addAttribute(.font, value: fontWithTrait(cur, trait: .bold, size: f.pointSize), range: r)
            let cur2 = (s.attribute(.font, at: r.location, effectiveRange: nil) as? NSFont) ?? f
            s.addAttribute(.font, value: fontWithTrait(cur2, trait: .italic, size: f.pointSize), range: r)
        },
        Style(regex: try! NSRegularExpression(pattern: #"\*\*(.+?)\*\*"#), marker: 2) { s, r, f, c in
            let cur = (s.attribute(.font, at: r.location, effectiveRange: nil) as? NSFont) ?? f
            s.addAttribute(.font, value: fontWithTrait(cur, trait: .bold, size: f.pointSize), range: r)
        },
        Style(regex: try! NSRegularExpression(pattern: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#), marker: 1) { s, r, f, c in
            let cur = (s.attribute(.font, at: r.location, effectiveRange: nil) as? NSFont) ?? f
            s.addAttribute(.font, value: fontWithTrait(cur, trait: .italic, size: f.pointSize), range: r)
        },
        Style(regex: try! NSRegularExpression(pattern: #"__(.+?)__"#), marker: 2) { s, r, f, c in
            let cur = (s.attribute(.font, at: r.location, effectiveRange: nil) as? NSFont) ?? f
            s.addAttribute(.font, value: fontWithTrait(cur, trait: .bold, size: f.pointSize), range: r)
        },
        Style(regex: try! NSRegularExpression(pattern: #"~~(.+?)~~"#), marker: 2) { s, r, f, c in
            s.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: r)
            s.addAttribute(.strikethroughColor, value: c, range: r)
        },
        Style(regex: try! NSRegularExpression(pattern: #"`([^`]+)`"#), marker: 1) { s, r, f, c in
            s.addAttribute(.font, value: codeFont, range: r)
            s.addAttribute(.backgroundColor, value: codeBg, range: r)
        },
    ]
    let plain = NSMutableAttributedString(string: text, attributes: attrs)
    var all: [(NSRange, Int)] = []
    for (i, st) in styles.enumerated() {
        let ns = text as NSString
        st.regex.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            if let m { all.append((m.range, i)) }
        }
    }
    // Longest match first at the same spot, then left-to-right. A style whose
    // range sits inside an already-styled range is skipped, so the `*italic*`
    // inside `**bold**` can't fight the bold.
    all.sort {
        if $0.0.location != $1.0.location { return $0.0.location < $1.0.location }
        return $0.0.length > $1.0.length
    }
    var covered: [NSRange] = []
    var offset = 0
    for (outer0, i) in all {
        let outer = NSRange(location: outer0.location + offset, length: outer0.length)
        if covered.contains(where: { NSIntersectionRange($0, outer).length > 0 }) { continue }
        covered.append(outer)
        let inner = NSRange(
            location: outer.location + styles[i].marker,
            length: max(0, outer.length - styles[i].marker * 2)
        )
        let probe = min(inner.location, max(0, plain.length - 1))
        let font = (plain.attributes(at: probe, effectiveRange: nil)[.font] as? NSFont) ?? boldFallback
        let color = (plain.attributes(at: probe, effectiveRange: nil)[.foregroundColor] as? NSColor) ?? strikeColor
        styles[i].apply(plain, inner, font, color)
        if stripMarkers {
            // Consume the markers: the outer range (markers + content) becomes
            // just the inner content. Later matches shift left accordingly.
            let sub = (plain.string as NSString).substring(with: inner)
            plain.replaceCharacters(in: outer, with: sub)
            offset -= styles[i].marker * 2
        }
    }
    return plain
}

private var boldFallback: NSFont {
    NSFont.boldSystemFont(ofSize: 13)
}

private func fontWithTrait(_ f: NSFont, trait: NSFontDescriptor.SymbolicTraits, size: CGFloat) -> NSFont {
    let desc = f.fontDescriptor.withSymbolicTraits(trait)
    if let b = NSFont(descriptor: desc, size: size) {
        return b
    }
    // The family can't synthesize this trait (e.g. no bold face shipped) —
    // fall back to the system face so **bold** and *italic* always show.
    var font = NSFont.systemFont(ofSize: size, weight: trait.contains(.bold) ? .bold : .regular)
    if trait.contains(.italic) {
        font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
    }
    return font
}
