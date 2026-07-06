import AppKit
import SwiftUI

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
