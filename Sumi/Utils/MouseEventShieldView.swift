import AppKit
import SwiftUI

enum MouseEventShieldCursorPolicy {
    case none
    case arrow
}

@MainActor
final class MouseEventShieldNSView: WebContentHoverShieldingNSView {
    var onClick: (() -> Void)?
    private(set) var isInteractive: Bool = true
    private var cursorPolicy: MouseEventShieldCursorPolicy = .arrow
    private var blocksScrollWheel = true

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

    override func resetCursorRects() {
        super.resetCursorRects()
        guard isInteractive, cursorPolicy == .arrow else { return }
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
        super.mouseMoved(with: event)
        setCursorIfNeeded()
    }

    override func mouseEntered(with event: NSEvent) {
        guard isInteractive else { return }
        super.mouseEntered(with: event)
        setCursorIfNeeded()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        // The shield hit-tests its whole area, so a chrome surface that scrolls
        // its own content has to let the event continue up to the SwiftUI host.
        guard blocksScrollWheel else {
            super.scrollWheel(with: event)
            return
        }
    }

    override func mouseDragged(with event: NSEvent) {}
    override func rightMouseDragged(with event: NSEvent) {}
    override func otherMouseDragged(with event: NSEvent) {}

    func update(
        onClick: (() -> Void)?,
        isInteractive: Bool,
        suppressesUnderlyingWebContentHover: Bool,
        cursorPolicy: MouseEventShieldCursorPolicy,
        blocksScrollWheel: Bool
    ) {
        self.onClick = onClick
        self.blocksScrollWheel = blocksScrollWheel
        updateCursorPolicy(cursorPolicy)
        setInteractive(isInteractive)
        setHoverShieldEnabled(isInteractive && suppressesUnderlyingWebContentHover)
    }

    func setInteractive(_ isEnabled: Bool) {
        if !isEnabled {
            onClick = nil
            setHoverShieldEnabled(false)
        }

        guard isInteractive != isEnabled else {
            window?.invalidateCursorRects(for: self)
            return
        }

        isInteractive = isEnabled
        needsDisplay = true
        needsLayout = true
        window?.invalidateCursorRects(for: self)
    }

    private func updateCursorPolicy(_ cursorPolicy: MouseEventShieldCursorPolicy) {
        guard self.cursorPolicy != cursorPolicy else { return }
        self.cursorPolicy = cursorPolicy
        window?.invalidateCursorRects(for: self)
        setCursorIfNeeded()
    }

    private func setCursorIfNeeded() {
        guard isInteractive, cursorPolicy == .arrow else { return }
        sumi_chromeSetCursorIfMouseInside(.arrow)
    }

}

struct MouseEventShieldView: NSViewRepresentable {
    var onClick: (() -> Void)?
    var isInteractive: Bool = true
    var suppressesUnderlyingWebContentHover: Bool = false
    var cursorPolicy: MouseEventShieldCursorPolicy = .arrow
    /// Set false when the shielded surface scrolls its own content.
    var blocksScrollWheel: Bool = true
    func makeNSView(context: Context) -> NSView {
        let view = MouseEventShieldNSView(frame: .zero)
        view.update(
            onClick: onClick,
            isInteractive: isInteractive,
            suppressesUnderlyingWebContentHover: suppressesUnderlyingWebContentHover,
            cursorPolicy: cursorPolicy,
            blocksScrollWheel: blocksScrollWheel
        )
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let shield = nsView as? MouseEventShieldNSView else { return }
        shield.update(
            onClick: onClick,
            isInteractive: isInteractive,
            suppressesUnderlyingWebContentHover: suppressesUnderlyingWebContentHover,
            cursorPolicy: cursorPolicy,
            blocksScrollWheel: blocksScrollWheel
        )
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        guard let shield = nsView as? MouseEventShieldNSView else { return }
        shield.setInteractive(false)
        WebContentMouseTrackingShield.unregister(shield)
    }
}
