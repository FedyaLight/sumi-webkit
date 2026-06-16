import AppKit
import WebKit

@MainActor
enum URLBarHubScreenshotRegionSelector {
    private static let minimumSelectionSize: CGFloat = 4
    private static var activeSession: SelectionSession?

    static func selectRegion(
        in webView: WKWebView,
        completion: @escaping @MainActor (CGRect?) -> Void
    ) {
        activeSession?.finish(with: nil)

        guard
            let parentWindow = webView.window,
            let screenFrame = screenFrame(for: webView, in: parentWindow),
            !screenFrame.isEmpty
        else {
            completion(nil)
            return
        }

        let session = SelectionSession(
            webView: webView,
            parentWindow: parentWindow,
            screenFrame: screenFrame
        ) { rect in
            activeSession = nil
            completion(rect)
        }
        activeSession = session
        session.begin()
    }

    private static func screenFrame(for webView: WKWebView, in window: NSWindow) -> CGRect? {
        let visibleRect = webView.visibleRect.intersection(webView.bounds)
        guard !visibleRect.isEmpty else { return nil }

        let windowRect = webView.convert(visibleRect, to: nil)
        return window.convertToScreen(windowRect)
    }

    @MainActor
    private final class SelectionSession: NSObject, NSWindowDelegate {
        private weak var webView: WKWebView?
        private weak var parentWindow: NSWindow?
        private let window: SelectionWindow
        private let completion: @MainActor (CGRect?) -> Void
        private var isFinished = false

        init(
            webView: WKWebView,
            parentWindow: NSWindow,
            screenFrame: CGRect,
            completion: @escaping @MainActor (CGRect?) -> Void
        ) {
            self.webView = webView
            self.parentWindow = parentWindow
            self.window = SelectionWindow(
                contentRect: screenFrame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            self.completion = completion
            super.init()

            let contentView = SelectionView()
            contentView.onCancel = { [weak self] in
                self?.finish(with: nil)
            }
            contentView.onSelect = { [weak self, weak contentView] rect in
                guard
                    let self,
                    let contentView,
                    let selectedRect = self.webViewRect(for: rect, in: contentView)
                else {
                    self?.finish(with: nil)
                    return
                }
                self.finish(with: selectedRect)
            }

            window.delegate = self
            window.contentView = contentView
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        }

        func begin() {
            parentWindow?.addChildWindow(window, ordered: .above)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(window.contentView)
        }

        func finish(with rect: CGRect?) {
            guard !isFinished else { return }
            isFinished = true

            parentWindow?.removeChildWindow(window)
            window.orderOut(nil)
            completion(rect)
        }

        func windowWillClose(_ notification: Notification) {
            finish(with: nil)
        }

        private func webViewRect(for rect: CGRect, in selectionView: NSView) -> CGRect? {
            guard let overlayWindow = selectionView.window, let webView else { return nil }

            let overlayWindowRect = selectionView.convert(rect, to: nil)
            let screenRect = overlayWindow.convertToScreen(overlayWindowRect)
            guard let webViewWindow = webView.window else { return nil }

            let webViewWindowRect = webViewWindow.convertFromScreen(screenRect)
            return webView.convert(webViewWindowRect, from: nil)
                .standardized
                .intersection(webView.bounds)
        }
    }

    private final class SelectionWindow: NSWindow {
        override var canBecomeKey: Bool { true }
        override var canBecomeMain: Bool { false }
    }

    private final class SelectionView: NSView {
        var onCancel: (() -> Void)?
        var onSelect: ((CGRect) -> Void)?

        private var startPoint: CGPoint?
        private var currentPoint: CGPoint?

        override var acceptsFirstResponder: Bool { true }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .crosshair)
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 0x35 {
                onCancel?()
            } else {
                super.keyDown(with: event)
            }
        }

        override func mouseDown(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            startPoint = point
            currentPoint = point
            needsDisplay = true
        }

        override func mouseDragged(with event: NSEvent) {
            currentPoint = convert(event.locationInWindow, from: nil)
            needsDisplay = true
        }

        override func mouseUp(with event: NSEvent) {
            currentPoint = convert(event.locationInWindow, from: nil)

            guard
                let rect = selectionRect,
                rect.width >= minimumSelectionSize,
                rect.height >= minimumSelectionSize
            else {
                onCancel?()
                return
            }

            onSelect?(rect)
        }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.black.withAlphaComponent(0.08).setFill()
            dirtyRect.fill()

            guard let rect = selectionRect else { return }

            NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
            rect.fill()

            let path = NSBezierPath(rect: rect)
            path.lineWidth = 2
            NSColor.controlAccentColor.setStroke()
            path.stroke()
        }

        private var selectionRect: CGRect? {
            guard let startPoint, let currentPoint else { return nil }
            return CGRect(
                x: min(startPoint.x, currentPoint.x),
                y: min(startPoint.y, currentPoint.y),
                width: abs(currentPoint.x - startPoint.x),
                height: abs(currentPoint.y - startPoint.y)
            )
        }
    }
}
