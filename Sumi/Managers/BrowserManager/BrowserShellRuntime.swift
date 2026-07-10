import Foundation

@MainActor
final class BrowserShellRuntime {
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

    func requireWebViewOwnershipService() -> WebViewOwnershipService {
        requireWebViewCoordinator().ownershipService
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
        adoptWebViewCoordinator: @escaping @MainActor (WebViewCoordinator?) -> Void,
        setDestructiveCleanupPreparer: @escaping @MainActor (WebViewCoordinator?) -> Void,
        windowRegistryChanged: @escaping @MainActor (WindowRegistry?) -> Void
    ) {
        self.adoptWebViewCoordinator = adoptWebViewCoordinator
        self.setDestructiveCleanupPreparer = setDestructiveCleanupPreparer
        self.windowRegistryChanged = windowRegistryChanged
        applyWebViewCoordinatorBinding(retainedWebViewCoordinator)
        windowRegistryChanged(retainedWindowRegistry)
    }

    func bindWebViewCoordinator(_ coordinator: WebViewCoordinator?) {
        guard let coordinator else {
            precondition(
                retainedWebViewCoordinator == nil,
                "The browser kernel WebViewCoordinator has process lifetime and cannot be detached"
            )
            return
        }
        if let retainedWebViewCoordinator {
            precondition(
                retainedWebViewCoordinator === coordinator,
                "The browser kernel WebViewCoordinator cannot be replaced"
            )
            return
        }
        retainedWebViewCoordinator = coordinator
        applyWebViewCoordinatorBinding(coordinator)
    }

    func bindWindowRegistry(_ registry: WindowRegistry?) {
        retainedWindowRegistry = registry
        windowRegistryChanged?(registry)
    }

    private func applyWebViewCoordinatorBinding(_ coordinator: WebViewCoordinator?) {
        guard let adoptWebViewCoordinator,
              let setDestructiveCleanupPreparer
        else { return }
        adoptWebViewCoordinator(coordinator)
        setDestructiveCleanupPreparer(coordinator)
    }
}
