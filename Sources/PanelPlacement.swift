import Foundation
import CoreGraphics

enum PanelPlacement {
    /// AppKit screen coordinates increase upward. Anchor the top below the menu bar.
    static func frame(anchor: CGRect, visible: CGRect, content: CGSize) -> CGRect {
        let safe = visible.insetBy(dx: 8, dy: 8)
        let width = min(content.width, safe.width)
        let height = min(content.height, safe.height)
        let x = min(max(anchor.midX - width / 2, safe.minX), safe.maxX - width)
        let top = min(anchor.minY - 6, safe.maxY)
        let y = max(safe.minY, top - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
