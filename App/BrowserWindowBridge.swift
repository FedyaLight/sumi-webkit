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
        private var notificationObservers: [(NotificationCenter, NSObjectProtocol)] = []

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
            window.applyBrowserWindowShellConfiguration(shouldApplyInitialSize: true)
            refreshWindowVisibilityState()

            addObserver(
                center: .default,
                forName: NSWindow.didBecomeKeyNotification,
                object: window
            ) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.windowRegistry.setActive(self.windowState)
                    self.refreshWindowVisibilityState()
                }
            }

            addObserver(
                center: .default,
                forName: NSWindow.didMiniaturizeNotification,
                object: window
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshWindowVisibilityState()
                }
            }

            addObserver(
                center: .default,
                forName: NSWindow.didDeminiaturizeNotification,
                object: window
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshWindowVisibilityState()
                }
            }

            addObserver(
                center: .default,
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: window
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshWindowVisibilityState()
                }
            }

            addObserver(
                center: NSWorkspace.shared.notificationCenter,
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    await Task.yield()
                    self?.refreshWindowVisibilityState()
                }
            }

            addObserver(
                center: .default,
                forName: NSWindow.willCloseNotification,
                object: window
            ) { [weak self] _ in
                guard let self else { return }
                MainActor.assumeIsolated {
                    self.handleWindowWillClose()
                }
            }

            if window.isKeyWindow {
                windowRegistry.setActive(windowState)
            }
        }

        func detach() {
            removeObservers()
            windowState.windowVisibilityState = .unknown
            windowState.window = nil
            window = nil
        }

        private func handleWindowWillClose() {
            windowRegistry.unregister(windowState.id)
            removeObservers()
            windowState.windowVisibilityState = .unknown
            windowState.window = nil
            window = nil
        }

        private func removeObservers() {
            for (center, observer) in notificationObservers {
                center.removeObserver(observer)
            }
            notificationObservers.removeAll()
        }

        private func addObserver(
            center: NotificationCenter,
            forName name: Notification.Name,
            object: Any?,
            using block: @escaping @Sendable (Notification) -> Void
        ) {
            let observer = center.addObserver(
                forName: name,
                object: object,
                queue: .main,
                using: block
            )
            notificationObservers.append((center, observer))
        }

        private func refreshWindowVisibilityState() {
            let newState = SumiWindowVisibilityState(window: window)
            guard windowState.windowVisibilityState != newState else { return }

            windowState.windowVisibilityState = newState
            windowRegistry.notifyWindowVisibilityChanged(windowState)
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
