import AppKit
import SwiftUI

struct BrowserWindowBridge: NSViewRepresentable {
    let windowState: BrowserWindowState
    let windowRegistry: WindowRegistry

    func makeCoordinator() -> Coordinator {
        Coordinator(windowState: windowState, windowRegistry: windowRegistry)
    }

    func makeNSView(context: Context) -> BrowserWindowBridgeView {
        let view = BrowserWindowBridgeView()
        view.coordinator = context.coordinator
        view.attachToCurrentWindow()
        return view
    }

    func updateNSView(_ nsView: BrowserWindowBridgeView, context: Context) {
        nsView.coordinator = context.coordinator
        nsView.attachToCurrentWindow()
    }

    static func dismantleNSView(_ nsView: BrowserWindowBridgeView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject {
        let windowState: BrowserWindowState
        let windowRegistry: WindowRegistry

        private weak var window: NSWindow?
        private var keyObserver: Any?

        init(windowState: BrowserWindowState, windowRegistry: WindowRegistry) {
            self.windowState = windowState
            self.windowRegistry = windowRegistry
        }

        func attach(to window: NSWindow?) {
            guard self.window !== window else { return }

            detach()
            self.window = window
            windowState.window = window

            guard let window else { return }

            promoteToSumiBrowserWindowIfNeeded(window)
            window.hideNativeStandardWindowButtonsForBrowserChrome()
            window.applyBrowserWindowShellConfiguration(shouldApplyInitialSize: true)

            keyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.windowRegistry.setActive(self.windowState)
                }
            }

            if window.isKeyWindow {
                windowRegistry.setActive(windowState)
            }
        }

        func detach() {
            if let keyObserver {
                NotificationCenter.default.removeObserver(keyObserver)
                self.keyObserver = nil
            }

            windowState.window = nil
            window = nil
        }
    }
}

final class BrowserWindowBridgeView: NSView {
    weak var coordinator: BrowserWindowBridge.Coordinator?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attachToCurrentWindow()
    }

    func attachToCurrentWindow() {
        coordinator?.attach(to: window)
    }
}
