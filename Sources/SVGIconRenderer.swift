import AppKit

/// Renders the excalidraw toolbar SVGs (copy-here/shapes) into NSImages.
final class SVGIconRenderer {
    private static let commandChars = Set("MmLlHhVvCcSsQqTtAaZz")

    static func image(named name: String, tint: NSColor, target: CGFloat = 22) -> NSImage {
        guard
            let url = Resources.url("Icons", "\(name).svg"),
            let svg = try? String(contentsOf: url, encoding: .utf8)
        else {
            return NSImage(size: NSSize(width: target, height: target))
        }

        let path = NSBezierPath()
        parse(svg: svg, path: path)

        guard !path.isEmpty else {
            return NSImage(size: NSSize(width: target, height: target))
        }

        if let vb = viewBox(of: svg) {
            let s = target / vb.w
            let t = NSAffineTransform()
            t.scale(by: s)
            path.transform(using: t as AffineTransform)
        }

        let image = NSImage(size: NSSize(width: target, height: target))
        image.lockFocus()
        NSRect(x: 0, y: 0, width: target, height: target).fill(using: .copy)
        tint.setStroke()
        path.lineWidth = strokeWidth(of: svg)
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
        image.unlockFocus()
        return image
    }

    // MARK: - element parsing

    private static func parse(svg: String, path: NSBezierPath) {
        for tag in matches(pattern: "<path[^>]*>", in: svg) {
            if let d = attr("d", in: tag) {
                parsePathData(d, path: path)
            }
        }
        for tag in matches(pattern: "<rect[^>]*>", in: svg) {
            let x = numAttr("x", in: tag) ?? 0
            let y = numAttr("y", in: tag) ?? 0
            let w = numAttr("width", in: tag) ?? 0
            let h = numAttr("height", in: tag) ?? 0
            path.appendRect(NSRect(x: x, y: y, width: w, height: h))
        }
        for tag in matches(pattern: "<circle[^>]*>", in: svg) {
            let cx = numAttr("cx", in: tag) ?? 0
            let cy = numAttr("cy", in: tag) ?? 0
            let r = numAttr("r", in: tag) ?? 0
            path.appendOval(in: NSRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        }
        for tag in matches(pattern: "<line[^>]*>", in: svg) {
            let x1 = numAttr("x1", in: tag) ?? 0
            let y1 = numAttr("y1", in: tag) ?? 0
            let x2 = numAttr("x2", in: tag) ?? 0
            let y2 = numAttr("y2", in: tag) ?? 0
            path.move(to: CGPoint(x: x1, y: y1))
            path.line(to: CGPoint(x: x2, y: y2))
        }
        for tag in matches(pattern: "<polyline[^>]*>", in: svg) {
            guard let pts = attr("points", in: tag) else { continue }
            let nums = pts.split(separator: " ").compactMap { Double($0) }
            for i in stride(from: 0, to: nums.count - 1, by: 2) {
                let p = CGPoint(x: nums[i], y: nums[i + 1])
                if i == 0 { path.move(to: p) } else { path.line(to: p) }
            }
        }

        // group transform: rotate(angle cx cy)
        if let m = matches(pattern: "rotate\\([^)]*\\)", in: svg).first {
            let inner = m.dropFirst("rotate(".count).dropLast(1)
            let nums = inner.split(whereSeparator: { $0 == "," || $0.isWhitespace }).compactMap { Double($0) }
            if let deg = nums.first {
                let cx = nums.count > 1 ? nums[1] : 0
                let cy = nums.count > 2 ? nums[2] : 0
                let t = NSAffineTransform()
                t.translateX(by: CGFloat(cx), yBy: CGFloat(cy))
                t.rotate(byDegrees: CGFloat(deg))
                t.translateX(by: -CGFloat(cx), yBy: -CGFloat(cy))
                path.transform(using: t as AffineTransform)
            }
        }

        // flip y: SVG is y-down, AppKit paths are y-up
        if let vb = viewBox(of: svg) {
            let t = NSAffineTransform()
            t.translateX(by: 0, yBy: vb.h)
            t.scaleX(by: 1, yBy: -1)
            path.transform(using: t as AffineTransform)
        }
    }

    // MARK: - path data

    private static func parsePathData(_ d: String, path: NSBezierPath) {
        let chars = Array(d)
        var i = 0
        var cmd: Character = "M"
        var firstPair = true
        var start = CGPoint.zero
        var cursor = CGPoint.zero
        var lastCtrl: CGPoint?
        var lastWasCurve = false

        func num() -> CGFloat? {
            while i < chars.count && chars[i].isWhitespace {
                i += 1
            }
            guard i < chars.count else { return nil }
            var s = ""
            if chars[i] == "-" || chars[i] == "+" {
                s.append(chars[i])
                i += 1
            }
            var hasDigits = false
            while i < chars.count {
                let c = chars[i]
                if c.isNumber {
                    s.append(c)
                    i += 1
                    hasDigits = true
                } else if c == "." {
                    s.append(c)
                    i += 1
                } else if (c == "e" || c == "E") && i + 1 < chars.count {
                    s.append(c)
                    i += 1
                    if chars[i] == "-" || chars[i] == "+" {
                        s.append(chars[i])
                        i += 1
                    }
                } else {
                    break
                }
            }
            return hasDigits ? (Double(s).map { CGFloat($0) }) : nil
        }

        func rel(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: cursor.x + x, y: cursor.y + y)
        }

        while i < chars.count {
            let ch = chars[i]
            if commandChars.contains(ch) {
                cmd = ch
                i += 1
                firstPair = true
                if ch == "Z" || ch == "z" {
                    path.close()
                    cursor = start
                    lastCtrl = nil
                    lastWasCurve = false
                }
                continue
            }

            let isRel = cmd.isLowercase
            switch cmd.uppercased() {
            case "M", "L":
                guard let a = num(), let b = num() else { return }
                let p = isRel ? rel(a, b) : CGPoint(x: a, y: b)
                if cmd == "M" || cmd == "m" {
                    if firstPair {
                        path.move(to: p)
                        start = p
                    } else {
                        path.line(to: p)
                    }
                } else {
                    path.line(to: p)
                }
                cursor = p
                lastCtrl = nil
            case "H":
                guard let a = num() else { return }
                cursor = CGPoint(x: isRel ? cursor.x + a : a, y: cursor.y)
                path.line(to: cursor)
                lastCtrl = nil
            case "V":
                guard let b = num() else { return }
                cursor = CGPoint(x: cursor.x, y: isRel ? cursor.y + b : b)
                path.line(to: cursor)
                lastCtrl = nil
            case "C":
                guard
                    let c1x = num(), let c1y = num(),
                    let c2x = num(), let c2y = num(),
                    let x = num(), let y = num()
                else { return }
                let c1 = isRel ? rel(c1x, c1y) : CGPoint(x: c1x, y: c1y)
                let c2 = isRel ? rel(c2x, c2y) : CGPoint(x: c2x, y: c2y)
                let p = isRel ? rel(x, y) : CGPoint(x: x, y: y)
                path.curve(to: p, controlPoint1: c1, controlPoint2: c2)
                lastCtrl = c2
                cursor = p
            case "S":
                guard let c2x = num(), let c2y = num(), let x = num(), let y = num() else { return }
                let c1: CGPoint
                if lastWasCurve, let lc = lastCtrl {
                    c1 = CGPoint(x: 2 * cursor.x - lc.x, y: 2 * cursor.y - lc.y)
                } else {
                    c1 = cursor
                }
                let c2 = isRel ? rel(c2x, c2y) : CGPoint(x: c2x, y: c2y)
                let p = isRel ? rel(x, y) : CGPoint(x: x, y: y)
                path.curve(to: p, controlPoint1: c1, controlPoint2: c2)
                lastCtrl = c2
                cursor = p
            case "Q":
                guard let qx = num(), let qy = num(), let x = num(), let y = num() else { return }
                let q = isRel ? rel(qx, qy) : CGPoint(x: qx, y: qy)
                let p = isRel ? rel(x, y) : CGPoint(x: x, y: y)
                quadTo(path, from: cursor, q: q, to: p)
                lastCtrl = q
                cursor = p
            case "T":
                guard let x = num(), let y = num() else { return }
                let q: CGPoint
                if lastWasCurve, let lc = lastCtrl {
                    q = CGPoint(x: 2 * cursor.x - lc.x, y: 2 * cursor.y - lc.y)
                } else {
                    q = cursor
                }
                let p = isRel ? rel(x, y) : CGPoint(x: x, y: y)
                quadTo(path, from: cursor, q: q, to: p)
                lastCtrl = q
                cursor = p
            case "A":
                guard
                    let rx = num(), let ry = num(),
                    let rot = num(), let fa = num(), let fs = num(),
                    let x = num(), let y = num()
                else { return }
                let end = isRel ? rel(x, y) : CGPoint(x: x, y: y)
                appendArc(from: cursor, to: end, rx: rx, ry: ry, phi: rot, large: fa != 0, sweep: fs != 0, path: path)
                cursor = end
            default:
                return
            }
            firstPair = false
            lastWasCurve = ["C", "S", "Q", "T"].contains(cmd.uppercased())
        }
    }

    private static func quadTo(_ path: NSBezierPath, from p0: CGPoint, q: CGPoint, to p1: CGPoint) {
        let c1 = CGPoint(x: p0.x + 2.0 / 3.0 * (q.x - p0.x), y: p0.y + 2.0 / 3.0 * (q.y - p0.y))
        let c2 = CGPoint(x: p1.x + 2.0 / 3.0 * (q.x - p1.x), y: p1.y + 2.0 / 3.0 * (q.y - p1.y))
        path.curve(to: p1, controlPoint1: c1, controlPoint2: c2)
    }

    private static func appendArc(
        from p1: CGPoint, to p2: CGPoint, rx: CGFloat, ry: CGFloat,
        phi: CGFloat, large: Bool, sweep: Bool, path: NSBezierPath
    ) {
        var rx = abs(rx)
        var ry = abs(ry)
        if rx == 0 || ry == 0 || p1 == p2 {
            path.line(to: p2)
            return
        }
        let phiR = phi * .pi / 180
        let cosP = cos(phiR)
        let sinP = sin(phiR)
        let dx = (p1.x - p2.x) / 2
        let dy = (p1.y - p2.y) / 2
        let x1p = cosP * dx + sinP * dy
        let y1p = -sinP * dx + cosP * dy
        let lambda = x1p * x1p / (rx * rx) + y1p * y1p / (ry * ry)
        if lambda > 1 {
            let s = sqrt(lambda)
            rx *= s
            ry *= s
        }
        let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        let coef = (den == 0 ? 0 : sqrt(max(0, num / den))) * (large == sweep ? -1 : 1)
        let cxp = coef * rx * y1p / ry
        let cyp = coef * -ry * x1p / rx
        let cx = cosP * cxp - sinP * cyp + (p1.x + p2.x) / 2
        let cy = sinP * cxp + cosP * cyp + (p1.y + p2.y) / 2
        let ux = (x1p - cxp) / rx
        let uy = (y1p - cyp) / ry
        let vx = (-x1p - cxp) / rx
        let vy = (-y1p - cyp) / ry
        let theta1 = atan2(uy, ux)
        var dTheta = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        if !sweep && dTheta > 0 { dTheta -= 2 * .pi }
        if sweep && dTheta < 0 { dTheta += 2 * .pi }
        let n = max(2, min(96, Int(ceil(abs(dTheta) / (.pi / 12)))))
        for k in 1...n {
            let t = CGFloat(k) / CGFloat(n)
            let ang = theta1 + dTheta * t
            let ex = rx * cos(ang)
            let ey = ry * sin(ang)
            let x = cosP * ex - sinP * ey + cx
            let y = sinP * ex + cosP * ey + cy
            path.line(to: CGPoint(x: x, y: y))
        }
    }

    // MARK: - helpers

    private static func viewBox(of svg: String) -> (w: CGFloat, h: CGFloat)? {
        guard let m = firstMatch("viewBox\\s*=\\s*\"([^\"]+)\"", svg) else { return nil }
        let nums = m.components(separatedBy: .whitespacesAndNewlines).compactMap { Double($0) }
        guard nums.count == 4 else { return nil }
        return (CGFloat(nums[2]), CGFloat(nums[3]))
    }

    private static func strokeWidth(of svg: String) -> CGFloat {
        firstMatch("stroke-width\\s*=\\s*\"([0-9.]+)\"", svg).flatMap { Double($0) }.map { CGFloat($0) } ?? 1.5
    }

    private static func numAttr(_ name: String, in tag: String) -> CGFloat? {
        attr(name, in: tag).flatMap { Double($0) }.map { CGFloat($0) }
    }

    private static func attr(_ name: String, in tag: String) -> String? {
        firstMatch("\(name)\\s*=\\s*\"([^\"]*)\"", tag)
    }

    private static func matches(pattern: String, in s: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range)
        }
    }

    private static func firstMatch(_ pattern: String, _ s: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = s as NSString
        guard let r = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        return ns.substring(with: r.range(at: 1))
    }
}
