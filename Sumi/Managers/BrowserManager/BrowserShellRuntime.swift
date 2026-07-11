import Foundation
import SumiWebRuntime

@MainActor
final class BrowserShellRuntime {
    private weak var tabManager: TabManager?
    private weak var splitQuery: WindowSplitQuery?
    weak var glanceManager: GlanceManager?
    let webViewSessions: WebViewSessionRepository
    private var adoptWebViewCoordinator: (@MainActor (WebViewCoordinator?) -> Void)?
    private var setDestructiveCleanupPreparer: (@MainActor (WebViewCoordinator?) -> Void)?
    private var windowRegistryChanged: (@MainActor (WindowRegistry?) -> Void)?
    private var retainedWebViewCoordinator: WebViewCoordinator?
    private weak var retainedWindowRegistry: WindowRegistry?
    var windowShellContentViewFactory: BrowserWindowShellService.ContentViewFactory?

    lazy var windowSelection = ShellSelectionService { [weak self] windowId in
        self?.splitQuery?.visibleTabIDs(in: windowId) ?? []
    }
    lazy var activePageResolver = makeActivePageResolver()

    lazy var windowTabs = BrowserWindowTabContext(
        selectionService: { [weak self] in self?.windowSelection },
        tabStore: { [weak self] in self?.tabManager?.runtimeStore },
        windows: { [weak self] in
            self?.retainedWindowRegistry.map {
                Array($0.windows.values)
            } ?? []
        },
        liveShortcutTabs: { [weak self] windowId in
            self?.tabManager?.shortcutPresentationOwner
                .liveShortcutTabs(in: windowId) ?? []
        },
        visibleSplitTabIds: { [weak self] windowId in
            Set(self?.splitQuery?.visibleTabIDs(in: windowId) ?? [])
        }
    )

    lazy var windowVisuals = BrowserWindowVisualCoordinator(
        hasActiveHistorySwipe: { [weak self] windowId in
            self?.retainedWebViewCoordinator?.protectionRuntime
                .hasActiveHistorySwipe(in: windowId) == true
        },
        currentTab: { [weak self] windowState in
            self?.windowTabs.currentTab(for: windowState)
        },
        performImmediateVisualHandoffIfPossible: { [weak self] windowId in
            self?.retainedWebViewCoordinator?.compositorRuntime
                .performImmediateVisualHandoffIfPossible(in: windowId) ?? false
        },
        prepareVisibleWebViews: { [weak self] windowState in
            guard let self else { return false }
            return requireWebViewCoordinator().visiblePreparationService
                .prepare(for: windowState)
        },
        schedulePrepareVisibleWebViews: { [weak self] windowState in
            guard let self else { return }
            requireWebViewCoordinator().visiblePreparationService
                .schedule(for: windowState)
        }
    )

    init(
        tabManager: TabManager,
        splitQuery: WindowSplitQuery,
        glanceManager: GlanceManager,
        webViewSessions: WebViewSessionRepository
    ) {
        self.tabManager = tabManager
        self.splitQuery = splitQuery
        self.glanceManager = glanceManager
        self.webViewSessions = webViewSessions
    }

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
