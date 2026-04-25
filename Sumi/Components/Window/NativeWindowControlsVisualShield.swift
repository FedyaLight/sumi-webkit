import AppKit

final class NativeWindowControlsVisualShieldView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

extension NSButton {
    func nativeWindowControlsSnapshotImage() -> NSImage? {
        layoutSubtreeIfNeeded()

        let snapshotBounds = bounds
        guard snapshotBounds.width > 0,
              snapshotBounds.height > 0,
              let representation = bitmapImageRepForCachingDisplay(in: snapshotBounds)
        else {
            return nil
        }

        cacheDisplay(in: snapshotBounds, to: representation)

        let image = NSImage(size: snapshotBounds.size)
        image.addRepresentation(representation)
        return image
    }
}

extension NSImage {
    static func nativeWindowControlsFallbackImage(
        for type: NSWindow.ButtonType,
        size: NSSize
    ) -> NSImage {
        let resolvedSize = NSSize(
            width: max(size.width, 14),
            height: max(size.height, 14)
        )
        return NSImage(size: resolvedSize, flipped: false) { rect in
            let color: NSColor
            switch type {
            case .closeButton:
                color = .systemRed
            case .miniaturizeButton:
                color = .systemYellow
            case .zoomButton:
                color = .systemGreen
            default:
                color = .controlAccentColor
            }

            color.setFill()
            let diameter = max(min(rect.width, rect.height) - 2, 1)
            let circleRect = NSRect(
                x: floor((rect.width - diameter) / 2),
                y: floor((rect.height - diameter) / 2),
                width: diameter,
                height: diameter
            )
            NSBezierPath(ovalIn: circleRect).fill()
            return true
        }
    }
}
