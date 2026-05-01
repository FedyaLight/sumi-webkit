import AppKit
import SwiftUI

final class CollapsedSidebarCursorOwnerNSView: NSView {
    private var trackingArea: NSTrackingArea?
    private weak var sidebarHostView: NSView?
    private var isCursorOwnerEnabled = true

    override var isOpaque: Bool {
        false
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func update(isEnabled: Bool) {
        isCursorOwnerEnabled = isEnabled
        resolveSidebarHostView()
        window?.invalidateCursorRects(for: self)
        updateTrackingAreas()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        resolveSidebarHostView()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        resolveSidebarHostView()
        window?.invalidateCursorRects(for: self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        guard isCursorOwnerEnabled else {
            trackingArea = nil
            return
        }

        let options: NSTrackingArea.Options = [
            .activeAlways,
            .inVisibleRect,
            .mouseMoved,
        ]
        let nextTrackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        trackingArea = nextTrackingArea
        addTrackingArea(nextTrackingArea)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard isCursorOwnerEnabled else { return }
        addCursorRect(bounds, cursor: .arrow)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        setArrowIfNeeded(for: event)
    }

    override func cursorUpdate(with event: NSEvent) {
        super.cursorUpdate(with: event)
        setArrowIfNeeded(for: event)
    }

    private func setArrowIfNeeded(for event: NSEvent) {
        guard isCursorOwnerEnabled,
              bounds.contains(convert(event.locationInWindow, from: nil)),
              !isSidebarTextInput(at: event.locationInWindow)
        else {
            return
        }

        NSCursor.arrow.set()
    }

    private func resolveSidebarHostView() {
        guard let superview else {
            sidebarHostView = nil
            return
        }

        sidebarHostView = superview.subviews
            .filter { $0 !== self }
            .reversed()
            .first { candidate in
                candidate.frame.intersects(frame)
                    && candidate.firstCursorOwnerDescendant(of: SidebarColumnContainerView.self) != nil
            }
    }

    private func isSidebarTextInput(at windowPoint: NSPoint) -> Bool {
        guard let sidebarHostView else { return false }

        let hostPoint = sidebarHostView.convert(windowPoint, from: nil)
        guard let hitView = sidebarHostView.hitTest(hostPoint) else { return false }

        if hitView.nearestCursorOwnerAncestor(of: NSTextView.self) != nil {
            return true
        }

        if let textField = hitView.nearestCursorOwnerAncestor(of: NSTextField.self),
           textField.isEditable || textField.isSelectable
        {
            return true
        }

        return false
    }
}

struct CollapsedSidebarCursorOwnerRepresentable: NSViewRepresentable {
    var isEnabled: Bool

    func makeNSView(context: Context) -> CollapsedSidebarCursorOwnerNSView {
        let view = CollapsedSidebarCursorOwnerNSView(frame: .zero)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.isOpaque = false
        view.update(isEnabled: isEnabled)
        return view
    }

    func updateNSView(_ nsView: CollapsedSidebarCursorOwnerNSView, context: Context) {
        nsView.update(isEnabled: isEnabled)
    }
}

private extension NSView {
    func nearestCursorOwnerAncestor<T: NSView>(of type: T.Type) -> T? {
        var current: NSView? = self
        while let view = current {
            if let match = view as? T {
                return match
            }
            current = view.superview
        }
        return nil
    }

    func firstCursorOwnerDescendant<T: NSView>(of type: T.Type) -> T? {
        for subview in subviews {
            if let match = subview as? T {
                return match
            }

            if let match = subview.firstCursorOwnerDescendant(of: type) {
                return match
            }
        }

        return nil
    }
}
