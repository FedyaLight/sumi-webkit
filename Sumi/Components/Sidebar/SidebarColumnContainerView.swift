import AppKit
import SwiftUI

// MARK: - Phase 1: AppKit-owned sidebar column

class SidebarColumnBaseContainerView: NSView {
    var onWindowChanged: ((NSWindow?) -> Void)?
    var onGeometryChanged: (() -> Void)?
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

    override func rightMouseDown(with event: NSEvent) {
        guard contextMenuController?.presentBackgroundMenu(
            trigger: .rightMouseDown,
            event: event,
            in: self
        ) == true else {
            super.rightMouseDown(with: event)
            return
        }
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
}

final class CollapsedSidebarPanelRootView: SidebarColumnBaseContainerView {
    var isPanelHitTestingEnabled = false {
        didSet {
            guard oldValue != isPanelHitTestingEnabled else { return }
            window?.invalidateCursorRects(for: self)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = superview.map { convert(point, from: $0) } ?? point
        guard isPanelHitTestingEnabled,
              !isHidden,
              alphaValue > 0.01,
              bounds.contains(localPoint)
        else {
            return nil
        }

        return super.hitTest(point) ?? self
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard isPanelHitTestingEnabled else { return }
        addCursorRect(bounds, cursor: .arrow)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }
}

enum SidebarColumnPaintlessChrome {
    static func configure(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.isOpaque = false
    }
}

private final class SidebarHostingView<Content: View>: NSHostingView<Content> {
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
}

final class SidebarHostingController<Content: View>: NSViewController {
    var rootView: Content {
        didSet {
            hostingView.rootView = rootView
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
