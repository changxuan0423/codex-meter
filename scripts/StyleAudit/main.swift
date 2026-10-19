import AppKit

let _ = NSApplication.shared
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

func render(_ filename: String, size: NSSize, drawing: () -> Void) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2),
                                 pixelsHigh: Int(size.height * 2), bitsPerSample: 8,
                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor.black.setFill()
    NSRect(origin: .zero, size: size).fill()
    drawing()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(filename))
}

let fontProbe = NSAttributedString(string: "5°C", attributes: [
    .font: StatusAppearance.font, .foregroundColor: NSColor.white
])
try render("font-probe.png", size: NSSize(width: 70, height: 32)) {
    fontProbe.draw(at: NSPoint(x: 4.25, y: 5))
}

let icon = StatusAppearance.icon()
icon.isTemplate = false
let whiteIcon = NSImage(size: icon.size, flipped: false) { rect in
    icon.draw(in: rect)
    NSColor.white.setFill()
    rect.fill(using: .sourceIn)
    return true
}
try render("icon-probe.png", size: NSSize(width: 24, height: 22)) {
    whiteIcon.draw(at: NSPoint(x: 4, y: 2), from: .zero, operation: .sourceOver, fraction: 1)
}

let title = NSMutableAttributedString(attributedString:
    StatusAppearance.title(percentage: "36%", resetTime: "15:13", stale: false))
title.addAttribute(.foregroundColor, value: NSColor.white, range: NSRange(location: 0, length: title.length))

// Read AppKit's image/title spacing independently; don't duplicate a guessed gap.
let native = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 240, height: 22))
native.image = icon
native.imagePosition = .imageLeading
native.imageScaling = .scaleNone
native.font = StatusAppearance.font
native.attributedTitle = title
let imageRect = native.cell!.imageRect(forBounds: native.bounds)
let titleRect = native.cell!.titleRect(forBounds: native.bounds)
let nativeGap = titleRect.minX - imageRect.maxX
let rowSize = NSSize(width: ceil(8 + icon.size.width + nativeGap + title.size().width), height: 22)
try render("row-probe.png", size: rowSize) {
    whiteIcon.draw(at: NSPoint(x: 4, y: 2), from: .zero, operation: .sourceOver, fraction: 1)
    title.draw(at: NSPoint(x: 4 + icon.size.width + nativeGap, y: (22 - title.size().height) / 2))
}

let metrics: [String: Any] = [
    "fontPointSize": StatusAppearance.font.pointSize,
    "fontName": StatusAppearance.font.fontName,
    "nativeImageTitleGapPoints": nativeGap,
    "iconCanvasPoints": [icon.size.width, icon.size.height],
    "rowCanvasPoints": [rowSize.width, rowSize.height],
    "textAdvancePoints": title.size().width
]
try JSONSerialization.data(withJSONObject: metrics, options: [.prettyPrinted, .sortedKeys])
    .write(to: directory.appendingPathComponent("metrics.json"))
print(String(data: try JSONSerialization.data(withJSONObject: metrics, options: [.prettyPrinted]), encoding: .utf8)!)
