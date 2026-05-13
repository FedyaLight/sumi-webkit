import AppKit
import SwiftUI

enum MouseEventShieldCursorPolicy {
    case none
    case arrow
}

@MainActor
final class MouseEventShieldNSView: NSView, SidebarTransientInteractionDisarmable {
    var onClick: (() -> Void)?
    private var trackingArea: NSTrackingArea?
    private(set) var isInteractive: Bool = true
    private var cursorPolicy: MouseEventShieldCursorPolicy = .arrow
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
        updateUnderlyingWebContentHoverSuppression(refreshIfAlreadySuppressed: true)
    }

    override func layout() {
        super.layout()
        updateUnderlyingWebContentHoverSuppression(refreshIfAlreadySuppressed: true)
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
        updateUnderlyingWebContentHoverSuppression(refreshIfAlreadySuppressed: true)
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
        updateUnderlyingWebContentHoverSuppression(refreshIfAlreadySuppressed: false)
        setCursorIfNeeded()
    }

    override func mouseEntered(with event: NSEvent) {
        guard isInteractive else { return }
        updateUnderlyingWebContentHoverSuppression(refreshIfAlreadySuppressed: false)
        setCursorIfNeeded()
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
        suppressesUnderlyingWebContentHover: Bool,
        cursorPolicy: MouseEventShieldCursorPolicy
    ) {
        self.onClick = onClick
        self.suppressesUnderlyingWebContentHover = suppressesUnderlyingWebContentHover
        updateCursorPolicy(cursorPolicy)
        setTransientInteractionEnabled(isInteractive)
        updateUnderlyingWebContentHoverSuppression(refreshIfAlreadySuppressed: true)
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
        updateUnderlyingWebContentHoverSuppression(refreshIfAlreadySuppressed: true)
    }

    private func clearTrackingArea() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
            self.trackingArea = nil
        }
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

    private func updateUnderlyingWebContentHoverSuppression(refreshIfAlreadySuppressed: Bool) {
        guard isInteractive,
              suppressesUnderlyingWebContentHover,
              let window
        else {
            setUnderlyingWebContentHoverSuppressed(false)
            return
        }

        let location = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        setUnderlyingWebContentHoverSuppressed(
            bounds.contains(location),
            refreshIfUnchanged: refreshIfAlreadySuppressed
        )
    }

    private func setUnderlyingWebContentHoverSuppressed(
        _ isSuppressed: Bool,
        refreshIfUnchanged: Bool = false
    ) {
        guard isSuppressingUnderlyingWebContentHover != isSuppressed else {
            if isSuppressed, refreshIfUnchanged {
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
    var cursorPolicy: MouseEventShieldCursorPolicy = .arrow
    var handle: SidebarTransientInteractionHandle? = nil

    func makeNSView(context: Context) -> NSView {
        let view = MouseEventShieldNSView(frame: .zero)
        view.update(
            onClick: onClick,
            isInteractive: isInteractive,
            suppressesUnderlyingWebContentHover: suppressesUnderlyingWebContentHover,
            cursorPolicy: cursorPolicy
        )
        handle?.attach(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let shield = nsView as? MouseEventShieldNSView else { return }
        shield.update(
            onClick: onClick,
            isInteractive: isInteractive,
            suppressesUnderlyingWebContentHover: suppressesUnderlyingWebContentHover,
            cursorPolicy: cursorPolicy
        )
        handle?.attach(shield)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        guard let shield = nsView as? MouseEventShieldNSView else { return }
        shield.setTransientInteractionEnabled(false)
        WebContentMouseTrackingShield.unregister(shield)
    }
}
