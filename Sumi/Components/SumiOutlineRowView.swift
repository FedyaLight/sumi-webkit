import AppKit

/// Safari-style outline rows separate real content without extending a
/// horizontal grid through the empty table area.
@MainActor
final class SumiOutlineRowView: NSTableRowView {
    var separatorLeadingInset: CGFloat = 0

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let scale = window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
        let thickness = 1 / scale
        let separatorRect = NSRect(
            x: separatorLeadingInset,
            y: isFlipped ? bounds.maxY - thickness : bounds.minY,
            width: max(0, bounds.width - separatorLeadingInset),
            height: thickness
        )
        guard dirtyRect.intersects(separatorRect) else { return }
        NSColor.separatorColor.setFill()
        separatorRect.fill()
    }
}
