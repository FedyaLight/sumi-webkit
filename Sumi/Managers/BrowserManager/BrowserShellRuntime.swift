import Foundation

@MainActor
final class BrowserShellRuntime {
    private var releaseWebViewCoordinator: (@MainActor (WebViewCoordinator?) -> Void)?
    private var adoptWebViewCoordinator: (@MainActor (WebViewCoordinator?) -> Void)?
    private var setDestructiveCleanupPreparer: (@MainActor (WebViewCoordinator?) -> Void)?
    private var windowRegistryChanged: (@MainActor (WindowRegistry?) -> Void)?
    private var retainedWebViewCoordinator: WebViewCoordinator?
    private weak var retainedWindowRegistry: WindowRegistry?
    var windowShellContentViewFactory: BrowserWindowShellService.ContentViewFactory?

    var webViewCoordinator: WebViewCoordinator? {
        retainedWebViewCoordinator
    }

    var windowRegistry: WindowRegistry? {
        retainedWindowRegistry
    }

    func requireWebViewCoordinator() -> WebViewCoordinator {
        guard let retainedWebViewCoordinator else {
            preconditionFailure(
                "BrowserShellRuntime.webViewCoordinator is nil. Bind it before WebView operations."
            )
        }
        return retainedWebViewCoordinator
    }

    func requireWindowRegistry() -> WindowRegistry {
        guard let retainedWindowRegistry else {
            preconditionFailure(
                "BrowserShellRuntime.windowRegistry is nil. Bind it before window operations."
            )
        }
        return retainedWindowRegistry
    }

    func requireWindowShellContentViewFactory() -> BrowserWindowShellService.ContentViewFactory {
        guard let windowShellContentViewFactory else {
            preconditionFailure(
                "BrowserShellRuntime.windowShellContentViewFactory is nil. Bind it before creating browser windows."
            )
        }
        return windowShellContentViewFactory
    }

    func attach(
        releaseWebViewCoordinator: @escaping @MainActor (WebViewCoordinator?) -> Void,
        adoptWebViewCoordinator: @escaping @MainActor (WebViewCoordinator?) -> Void,
        setDestructiveCleanupPreparer: @escaping @MainActor (WebViewCoordinator?) -> Void,
        windowRegistryChanged: @escaping @MainActor (WindowRegistry?) -> Void
    ) {
        self.releaseWebViewCoordinator = releaseWebViewCoordinator
        self.adoptWebViewCoordinator = adoptWebViewCoordinator
        self.setDestructiveCleanupPreparer = setDestructiveCleanupPreparer
        self.windowRegistryChanged = windowRegistryChanged
        applyWebViewCoordinatorBinding(oldValue: nil, newValue: retainedWebViewCoordinator)
        windowRegistryChanged(retainedWindowRegistry)
    }

    func bindWebViewCoordinator(_ coordinator: WebViewCoordinator?) {
        let oldValue = retainedWebViewCoordinator
        retainedWebViewCoordinator = coordinator
        applyWebViewCoordinatorBinding(oldValue: oldValue, newValue: coordinator)
    }

    func bindWindowRegistry(_ registry: WindowRegistry?) {
        retainedWindowRegistry = registry
        windowRegistryChanged?(registry)
    }

    private func applyWebViewCoordinatorBinding(
        oldValue: WebViewCoordinator?,
        newValue: WebViewCoordinator?
    ) {
        guard let releaseWebViewCoordinator,
              let adoptWebViewCoordinator,
              let setDestructiveCleanupPreparer
        else { return }
        releaseWebViewCoordinator(oldValue)
        adoptWebViewCoordinator(newValue)
        setDestructiveCleanupPreparer(newValue)
    }
}
