import Foundation
import SumiWebRuntime

@MainActor
final class BrowserShellRuntime {
    private weak var tabManager: TabManager?
    private weak var splitQuery: WindowSplitQuery?
    weak var glanceManager: GlanceManager?
    let webViewSessions: WebViewSessionRepository
    let webViewProtection: WebViewProtectionRuntime
    let webViewCompositor: WebViewCompositorRuntime
    let visibleWebViewPreparation: WebViewVisiblePreparationService
    let webViewLifecycle: WebViewLifecycleService
    private var windowRegistryChanged: (@MainActor (WindowRegistry?) -> Void)?
    /// The shell runtime requires this registry for every window-scoped
    /// capability after attachment, so it owns the binding until explicit
    /// detachment or browser teardown.
    private var retainedWindowRegistry: WindowRegistry?
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
        },
        trackedTabIds: { [weak self] windowId in
            Set(
                self?.webViewSessions.trackedWebViews(in: windowId).map {
                    $0.0.tabID
                } ?? []
            )
        }
    )

    lazy var windowVisuals = BrowserWindowVisualCoordinator(
        hasActiveHistorySwipe: { [weak self] windowId in
            self?.webViewProtection
                .hasActiveHistorySwipe(in: windowId) == true
        },
        currentTab: { [weak self] windowState in
            self?.windowTabs.currentTab(for: windowState)
        },
        performImmediateVisualHandoffIfPossible: { [weak self] windowId in
            self?.webViewCompositor
                .performImmediateVisualHandoffIfPossible(in: windowId) ?? false
        },
        prepareVisibleWebViews: { [weak self] windowState in
            self?.visibleWebViewPreparation.prepare(for: windowState) ?? false
        },
        schedulePrepareVisibleWebViews: { [weak self] windowState in
            self?.visibleWebViewPreparation.schedule(for: windowState)
        }
    )

    init(
        tabManager: TabManager,
        splitQuery: WindowSplitQuery,
        glanceManager: GlanceManager,
        webViewSessions: WebViewSessionRepository,
        webViewProtection: WebViewProtectionRuntime,
        webViewCompositor: WebViewCompositorRuntime,
        visibleWebViewPreparation: WebViewVisiblePreparationService,
        webViewLifecycle: WebViewLifecycleService
    ) {
        self.tabManager = tabManager
        self.splitQuery = splitQuery
        self.glanceManager = glanceManager
        self.webViewSessions = webViewSessions
        self.webViewProtection = webViewProtection
        self.webViewCompositor = webViewCompositor
        self.visibleWebViewPreparation = visibleWebViewPreparation
        self.webViewLifecycle = webViewLifecycle
    }

    var windowRegistry: WindowRegistry? {
        retainedWindowRegistry
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
        windowRegistryChanged: @escaping @MainActor (WindowRegistry?) -> Void
    ) {
        self.windowRegistryChanged = windowRegistryChanged
        windowRegistryChanged(retainedWindowRegistry)
    }

    func bindWindowRegistry(_ registry: WindowRegistry?) {
        retainedWindowRegistry = registry
        windowRegistryChanged?(registry)
    }
}
