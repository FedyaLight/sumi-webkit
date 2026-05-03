import AppKit
import SwiftUI

final class TransientChromePanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

enum TransientChromePanelConfiguration {
    static func makePanel() -> TransientChromePanelWindow {
        let panel = TransientChromePanelWindow(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.worksWhenModal = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [
            .fullScreenAuxiliary,
            .moveToActiveSpace,
            .ignoresCycle,
        ]
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = false
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView?.layer?.isOpaque = false
        return panel
    }

    static func configure(_ panel: TransientChromePanelWindow, for parentWindow: NSWindow) {
        panel.level = parentWindow.level
        panel.appearance = parentWindow.effectiveAppearance
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = false
    }
}

enum TransientChromePanelFrameResolver {
    static func parentContentScreenFrame(in parentWindow: NSWindow) -> NSRect? {
        guard let contentView = parentWindow.contentView else { return nil }
        let contentWindowFrame = contentView.convert(contentView.bounds, to: nil)
        return parentWindow.convertToScreen(contentWindowFrame)
    }

    static func anchorScreenFrame(_ anchorView: NSView, fallbackWindow: NSWindow?) -> NSRect? {
        guard let window = anchorView.window ?? fallbackWindow else { return nil }
        if !anchorView.bounds.isEmpty {
            let windowFrame = anchorView.convert(anchorView.bounds, to: nil)
            return window.convertToScreen(windowFrame)
        }
        return parentContentScreenFrame(in: window)
    }

    static func topStripFrame(
        in anchorView: NSView,
        fallbackWindow: NSWindow?,
        height: CGFloat
    ) -> NSRect? {
        guard let fullFrame = anchorScreenFrame(anchorView, fallbackWindow: fallbackWindow),
              fullFrame.width > 0,
              fullFrame.height > 0
        else { return nil }

        let stripHeight = min(max(height, 0), fullFrame.height)
        return NSRect(
            x: fullFrame.minX,
            y: fullFrame.maxY - stripHeight,
            width: fullFrame.width,
            height: stripHeight
        )
    }
}

@MainActor
final class TransientChromeParentWindowObserver {
    private weak var observedWindow: NSWindow?
    private var observers: [NSObjectProtocol] = []

    var parentWindow: NSWindow? {
        observedWindow
    }

    func bind(
        to parentWindow: NSWindow,
        onGeometryChange: @escaping @MainActor () -> Void,
        onWillClose: @escaping @MainActor () -> Void,
        onSheetBegin: @escaping @MainActor () -> Void,
        onSheetEnd: @escaping @MainActor () -> Void
    ) {
        guard observedWindow !== parentWindow else { return }
        unbind()
        observedWindow = parentWindow

        let center = NotificationCenter.default
        let geometryNotifications: [Notification.Name] = [
            NSWindow.didMoveNotification,
            NSWindow.didResizeNotification,
            NSWindow.didChangeScreenNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification,
        ]

        observers = geometryNotifications.map { name in
            center.addObserver(
                forName: name,
                object: parentWindow,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    onGeometryChange()
                }
            }
        }

        observers.append(
            center.addObserver(
                forName: NSWindow.willCloseNotification,
                object: parentWindow,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    onWillClose()
                }
            }
        )

        observers.append(
            center.addObserver(
                forName: NSWindow.willBeginSheetNotification,
                object: parentWindow,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    onSheetBegin()
                }
            }
        )

        observers.append(
            center.addObserver(
                forName: NSWindow.didEndSheetNotification,
                object: parentWindow,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    onSheetEnd()
                }
            }
        )

        if let contentView = parentWindow.contentView {
            contentView.postsFrameChangedNotifications = true
            observers.append(
                center.addObserver(
                    forName: NSView.frameDidChangeNotification,
                    object: contentView,
                    queue: .main
                ) { _ in
                    MainActor.assumeIsolated {
                        onGeometryChange()
                    }
                }
            )
        }
    }

    func unbind() {
        let center = NotificationCenter.default
        observers.forEach(center.removeObserver)
        observers = []
        observedWindow = nil
    }

    deinit {
        MainActor.assumeIsolated {
            unbind()
        }
    }
}

final class TransientChromePanelAnchorView: NSView {
    var onWindowChanged: ((NSWindow?) -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChanged?(window)
    }
}
