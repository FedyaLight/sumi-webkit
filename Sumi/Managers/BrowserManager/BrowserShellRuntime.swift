import Foundation

@MainActor
final class BrowserShellRuntime {
    struct Dependencies {
        let releaseWebViewCoordinator: @MainActor (WebViewCoordinator?) -> Void
        let adoptWebViewCoordinator: @MainActor (WebViewCoordinator?) -> Void
        let setDestructiveCleanupPreparer: @MainActor (WebViewCoordinator?) -> Void
        let windowRegistryChanged: @MainActor (WindowRegistry?) -> Void
    }

    private var dependencies: Dependencies?
    private var retainedWebViewCoordinator: WebViewCoordinator?
    private weak var retainedWindowRegistry: WindowRegistry?
    var windowShellContentViewFactory: BrowserWindowShellService.ContentViewFactory?

    var webViewCoordinator: WebViewCoordinator? {
        retainedWebViewCoordinator
    }

    var windowRegistry: WindowRegistry? {
        retainedWindowRegistry
    }

    func attach(dependencies: Dependencies) {
        self.dependencies = dependencies
        applyWebViewCoordinatorBinding(oldValue: nil, newValue: retainedWebViewCoordinator)
        dependencies.windowRegistryChanged(retainedWindowRegistry)
    }

    func bindWebViewCoordinator(_ coordinator: WebViewCoordinator?) {
        let oldValue = retainedWebViewCoordinator
        retainedWebViewCoordinator = coordinator
        applyWebViewCoordinatorBinding(oldValue: oldValue, newValue: coordinator)
    }

    func bindWindowRegistry(_ registry: WindowRegistry?) {
        retainedWindowRegistry = registry
        dependencies?.windowRegistryChanged(registry)
    }

    private func applyWebViewCoordinatorBinding(
        oldValue: WebViewCoordinator?,
        newValue: WebViewCoordinator?
    ) {
        guard let dependencies else { return }
        dependencies.releaseWebViewCoordinator(oldValue)
        dependencies.adoptWebViewCoordinator(newValue)
        dependencies.setDestructiveCleanupPreparer(newValue)
    }
}
