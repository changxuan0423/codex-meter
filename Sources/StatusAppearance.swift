import AppKit

/// Keep text in the native status button so AppKit handles its tint, baseline,
/// antialiasing, and selected appearance alongside the other menu bar items.
enum StatusAppearance {
    // Calibrated against the user's 2x Weather screenshot: 864 size/weight/phase
    // candidates. SF 13 regular reproduces its 44 x 21 px "5°C" ink bounds.
    static let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)

    static func icon() -> NSImage {
        // Use a standard 16 pt badge. Grow the image's layout width with its ink,
        // retaining the calibrated 0.5 pt trailing inset and native text spacing.
        let badge = MeterIcon.make(size: 16)
        badge.isTemplate = false
        let result = NSImage(size: NSSize(width: 16.5, height: 18), flipped: false) { _ in
            NSGraphicsContext.saveGraphicsState()
            badge.draw(in: NSRect(x: 0, y: 0.75, width: 16, height: 16))
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        result.isTemplate = true
        return result
    }

    static func title(percentage: String, resetTime: String?, stale: Bool) -> NSAttributedString {
        let result = NSMutableAttributedString()
        func gap(_ width: CGFloat) {
            let natural = NSAttributedString(string: " ", attributes: [.font: font]).size().width
            result.append(NSAttributedString(string: " ", attributes: [.font: font, .kern: width - natural]))
        }
        // AppKit's native image-title gap is 2 pt. Include the digit's side bearing
        // and icon's ink inset: the added 1 pt produces Weather's 4 pt ink gap.
        gap(1)
        result.append(NSAttributedString(string: percentage, attributes: [.font: font]))
        if let resetTime {
            gap(8)
            // The circular arrow exceeds the cap height at 13 pt. Its calibrated
            // 12.5 pt glyph has the same 21 px ink height as Weather at 2x.
            result.append(NSAttributedString(string: "↻", attributes: [
                .font: NSFont.systemFont(ofSize: 12.5, weight: .regular),
                .baselineOffset: -0.5
            ]))
            gap(3)
            result.append(NSAttributedString(string: resetTime, attributes: [.font: font]))
        }
        if stale {
            gap(5)
            result.append(NSAttributedString(string: "!", attributes: [.font: font]))
        }
        // No manual opacity or foreground color: use the native menu bar text style.
        return result
    }
}

enum MeterIcon {
    static func make(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let flower = NSBezierPath()
            let center = NSPoint(x: rect.midX, y: rect.midY)
            for index in 0..<120 {
                let angle = CGFloat(index) * 2 * .pi / 120
                let radius = size * (0.445 + 0.035 * cos(angle * 8))
                let point = NSPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                if index == 0 { flower.move(to: point) } else { flower.line(to: point) }
            }
            flower.close()
            NSColor.black.setFill()
            flower.fill()
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            let glyph = NSBezierPath()
            glyph.lineWidth = size * 0.075
            glyph.lineCapStyle = .round
            glyph.lineJoinStyle = .round
            glyph.move(to: NSPoint(x: size * 0.30, y: size * 0.65))
            glyph.line(to: NSPoint(x: size * 0.43, y: size * 0.50))
            glyph.line(to: NSPoint(x: size * 0.30, y: size * 0.35))
            glyph.move(to: NSPoint(x: size * 0.53, y: size * 0.35))
            glyph.line(to: NSPoint(x: size * 0.70, y: size * 0.35))
            glyph.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}

