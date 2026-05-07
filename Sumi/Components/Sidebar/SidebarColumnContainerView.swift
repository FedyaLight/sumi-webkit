import AppKit
import SwiftUI

// MARK: - Phase 1: AppKit-owned sidebar column

class SidebarColumnBaseContainerView: NSView {
    var onWindowChanged: ((NSWindow?) -> Void)?
    var onGeometryChanged: (() -> Void)?
    var onPointerDown: (() -> Void)?
    weak var hostedSidebarView: NSView?
    weak var contextMenuController: SidebarContextMenuController?

    override var isOpaque: Bool {
        false
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func draw(_ dirtyRect: NSRect) {
        // Paintless AppKit shell. SwiftUI resolved chrome owns sidebar background.
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        onPointerDown?()
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        onPointerDown?()
        guard contextMenuController?.presentBackgroundMenu(
            trigger: .rightMouseDown,
            event: event,
            in: self
        ) == true else {
            super.rightMouseDown(with: event)
            return
        }
    }

    override func otherMouseDown(with event: NSEvent) {
        onPointerDown?()
        super.otherMouseDown(with: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        SidebarColumnPaintlessChrome.configure(self)
        onWindowChanged?(window)
        onGeometryChanged?()
    }

    override func layout() {
        super.layout()
        onGeometryChanged?()
    }
}

final class SidebarColumnContainerView: SidebarColumnBaseContainerView {
    var capturesPanelBackgroundPointerEvents = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return SidebarColumnHitTestRouting.routedHit(
            point: point,
            in: self,
            originalHit: hit,
            hostedSidebarView: hostedSidebarView,
            contextMenuController: contextMenuController,
            eventType: window?.currentEvent?.type,
            capturesPanelBackgroundPointerEvents: capturesPanelBackgroundPointerEvents
        )
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2,
           SidebarColumnBackgroundClickPolicy.shouldHandleWindowZoom(
            event: event,
            in: self,
            hostedSidebarView: hostedSidebarView
           ),
           let targetWindow = window
        {
            onPointerDown?()
            targetWindow.performZoom(nil)
            return
        }

        super.mouseDown(with: event)
    }
}

final class CollapsedSidebarPanelRootView: SidebarColumnBaseContainerView {
    var isPanelHitTestingEnabled = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint: NSPoint
        if bounds.contains(point) {
            localPoint = point
        } else if let superview {
            localPoint = convert(point, from: superview)
        } else {
            localPoint = point
        }

        guard isPanelHitTestingEnabled,
              !isHidden,
              alphaValue > 0.01,
              bounds.contains(localPoint)
        else {
            return nil
        }

        let hit = super.hitTest(localPoint)
        if hit === hostedSidebarView {
            return self
        }

        return hit ?? self
    }

    override func mouseDown(with event: NSEvent) {
        guard let parentWindow = window?.parent else {
            super.mouseDown(with: event)
            return
        }

        if event.clickCount == 2 {
            onPointerDown?()
            parentWindow.performZoom(nil)
            return
        }

        guard event.clickCount == 1 else {
            super.mouseDown(with: event)
            return
        }

        onPointerDown?()
        parentWindow.performDrag(with: event)
    }
}

private enum SidebarColumnBackgroundClickPolicy {
    static func shouldHandleWindowZoom(
        event: NSEvent,
        in containerView: NSView,
        hostedSidebarView: NSView?
    ) -> Bool {
        let localPoint = containerView.convert(event.locationInWindow, from: nil)
        guard containerView.bounds.contains(localPoint) else { return false }

        guard let hit = containerView.hitTest(localPoint) else {
            return true
        }

        guard let hostedSidebarView,
              hit === hostedSidebarView || hit.isDescendant(of: hostedSidebarView)
        else {
            return hit === containerView
        }

        return hit.nearestAncestor(of: SidebarInteractiveItemView.self) == nil
            && hit.nearestAncestor(of: NSControl.self) == nil
    }
}

enum SidebarColumnPaintlessChrome {
    @MainActor
    static func configure(_ view: NSView) {
        let clearBackground = NSColor.clear.cgColor
        if !view.wantsLayer {
            view.wantsLayer = true
        }
        if view.layer?.backgroundColor != clearBackground {
            view.layer?.backgroundColor = clearBackground
        }
        if view.layer?.isOpaque != false {
            view.layer?.isOpaque = false
        }
    }
}

private extension NSView {
    func nearestAncestor<T: NSView>(of type: T.Type) -> T? {
        var current: NSView? = self
        while let view = current {
            if let match = view as? T {
                return match
            }
            current = view.superview
        }
        return nil
    }
}

private final class SidebarHostingView<Content: View>: NSHostingView<Content> {
    var onPointerDown: (() -> Void)?

    override var isOpaque: Bool {
        false
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        SidebarColumnPaintlessChrome.configure(self)
    }

    override func mouseDown(with event: NSEvent) {
        onPointerDown?()
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        onPointerDown?()
        super.rightMouseDown(with: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        onPointerDown?()
        super.otherMouseDown(with: event)
    }
}

final class SidebarHostingController<Content: View>: NSViewController {
    var rootView: Content {
        didSet {
            hostingView.rootView = rootView
        }
    }

    var onPointerDown: (() -> Void)? {
        didSet {
            hostingView.onPointerDown = onPointerDown
        }
    }

    private let hostingView: SidebarHostingView<Content>

    init(rootView: Content) {
        self.rootView = rootView
        self.hostingView = SidebarHostingView(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
        SidebarColumnPaintlessChrome.configure(hostingView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = hostingView
    }
}
