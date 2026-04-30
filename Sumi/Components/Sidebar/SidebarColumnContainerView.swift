import AppKit
import SwiftUI

// MARK: - Phase 1: AppKit-owned sidebar column

final class SidebarColumnContainerView: NSView {
    var onWindowChanged: ((NSWindow?) -> Void)?
    var onGeometryChanged: (() -> Void)?
    weak var hostedSidebarView: NSView?
    weak var contextMenuController: SidebarContextMenuController?
    var capturesPanelBackgroundPointerEvents = false

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
