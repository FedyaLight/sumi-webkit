import AppKit
import SwiftUI

@MainActor
final class MouseEventShieldNSView: NSView, SidebarTransientInteractionDisarmable {
    var onClick: (() -> Void)?
    private var trackingArea: NSTrackingArea?
    private(set) var isInteractive: Bool = true
    private var suppressesUnderlyingWebContentHover = false
    private var isSuppressingUnderlyingWebContentHover = false

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

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            setUnderlyingWebContentHoverSuppressed(false)
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateUnderlyingWebContentHoverSuppression()
    }

    override func layout() {
        super.layout()
        updateUnderlyingWebContentHoverSuppression()
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
        updateUnderlyingWebContentHoverSuppression()
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
        updateUnderlyingWebContentHoverSuppression()
        NSCursor.arrow.set()
    }

    override func mouseEntered(with event: NSEvent) {
        guard isInteractive else { return }
        updateUnderlyingWebContentHoverSuppression()
        NSCursor.arrow.set()
    }

    override func mouseExited(with event: NSEvent) {
        setUnderlyingWebContentHoverSuppressed(false)
    }

    override func scrollWheel(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func rightMouseDragged(with event: NSEvent) {}
    override func otherMouseDragged(with event: NSEvent) {}

    func update(
        onClick: (() -> Void)?,
        isInteractive: Bool,
        suppressesUnderlyingWebContentHover: Bool
    ) {
        self.onClick = onClick
        self.suppressesUnderlyingWebContentHover = suppressesUnderlyingWebContentHover
        setTransientInteractionEnabled(isInteractive)
        updateUnderlyingWebContentHoverSuppression()
    }

    func setTransientInteractionEnabled(_ isEnabled: Bool) {
        if !isEnabled {
            onClick = nil
            clearTrackingArea()
            setUnderlyingWebContentHoverSuppressed(false)
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
        updateUnderlyingWebContentHoverSuppression()
    }

    private func clearTrackingArea() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
            self.trackingArea = nil
        }
    }

    private func updateUnderlyingWebContentHoverSuppression() {
        guard isInteractive,
              suppressesUnderlyingWebContentHover,
              let window
        else {
            setUnderlyingWebContentHoverSuppressed(false)
            return
        }

        let location = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        setUnderlyingWebContentHoverSuppressed(bounds.contains(location))
    }

    private func setUnderlyingWebContentHoverSuppressed(_ isSuppressed: Bool) {
        guard isSuppressingUnderlyingWebContentHover != isSuppressed else {
            if isSuppressed {
                WebContentMouseTrackingShield.refresh(for: self)
            }
            return
        }
        isSuppressingUnderlyingWebContentHover = isSuppressed
        WebContentMouseTrackingShield.setActive(isSuppressed, for: self)
    }
}

struct MouseEventShieldView: NSViewRepresentable {
    var onClick: (() -> Void)? = nil
    var isInteractive: Bool = true
    var suppressesUnderlyingWebContentHover: Bool = false
    var handle: SidebarTransientInteractionHandle? = nil

    func makeNSView(context: Context) -> NSView {
        let view = MouseEventShieldNSView(frame: .zero)
        view.update(
            onClick: onClick,
            isInteractive: isInteractive,
            suppressesUnderlyingWebContentHover: suppressesUnderlyingWebContentHover
        )
        handle?.attach(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let shield = nsView as? MouseEventShieldNSView else { return }
        shield.update(
            onClick: onClick,
            isInteractive: isInteractive,
            suppressesUnderlyingWebContentHover: suppressesUnderlyingWebContentHover
        )
        handle?.attach(shield)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        guard let shield = nsView as? MouseEventShieldNSView else { return }
        shield.setTransientInteractionEnabled(false)
        WebContentMouseTrackingShield.unregister(shield)
    }
}
