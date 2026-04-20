import AppKit
import SwiftUI

final class MouseEventShieldNSView: NSView, SidebarTransientInteractionDisarmable {
    var onClick: (() -> Void)?
    private var trackingArea: NSTrackingArea?
    private(set) var isInteractive: Bool = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isInteractive, bounds.contains(point) else { return nil }
        return self
    }

    override var acceptsFirstResponder: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        isInteractive
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        clearTrackingArea()

        guard isInteractive else { return }

        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )

        if let trackingArea {
            addTrackingArea(trackingArea)
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard isInteractive else { return }
        addCursorRect(bounds, cursor: .arrow)
    }

    override func mouseDown(with event: NSEvent) {
        guard isInteractive else { return }
        onClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        guard isInteractive else { return }
        onClick?()
    }

    override func otherMouseDown(with event: NSEvent) {
        guard isInteractive else { return }
        onClick?()
    }

    override func mouseMoved(with event: NSEvent) {
        guard isInteractive else { return }
        NSCursor.arrow.set()
    }

    override func mouseEntered(with event: NSEvent) {
        guard isInteractive else { return }
        NSCursor.arrow.set()
    }

    override func scrollWheel(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func rightMouseDragged(with event: NSEvent) {}
    override func otherMouseDragged(with event: NSEvent) {}

    func update(onClick: (() -> Void)?, isInteractive: Bool) {
        self.onClick = onClick
        setTransientInteractionEnabled(isInteractive)
    }

    func setTransientInteractionEnabled(_ isEnabled: Bool) {
        if !isEnabled {
            onClick = nil
            clearTrackingArea()
        }

        guard isInteractive != isEnabled else {
            window?.invalidateCursorRects(for: self)
            return
        }

        isInteractive = isEnabled
        needsDisplay = true
        needsLayout = true
        window?.invalidateCursorRects(for: self)
        if isEnabled {
            updateTrackingAreas()
        }
    }

    private func clearTrackingArea() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
            self.trackingArea = nil
        }
    }
}

struct MouseEventShieldView: NSViewRepresentable {
    var onClick: (() -> Void)? = nil
    var isInteractive: Bool = true
    var handle: SidebarTransientInteractionHandle? = nil

    func makeNSView(context: Context) -> NSView {
        let view = MouseEventShieldNSView(frame: .zero)
        view.update(onClick: onClick, isInteractive: isInteractive)
        handle?.attach(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let shield = nsView as? MouseEventShieldNSView else { return }
        shield.update(onClick: onClick, isInteractive: isInteractive)
        handle?.attach(shield)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        guard let shield = nsView as? MouseEventShieldNSView else { return }
        shield.setTransientInteractionEnabled(false)
    }
}
