import Foundation
import SumiWebRuntime

@MainActor
final class BrowserShellRuntime {
    weak var glanceManager: GlanceManager?
    let webViewSessions: WebViewSessionRepository
    let webViewProtection: WebViewProtectionRuntime
    let webViewCompositor: WebViewCompositorRuntime
    let visibleWebViewPreparation: WebViewVisiblePreparationService
    let webViewLifecycle: WebViewLifecycleService
    let windowRegistry: WindowRegistry
    var windowShellContentViewFactory: BrowserWindowShellService.ContentViewFactory?

    let windowSelection: ShellSelectionService
    lazy var activePageResolver = makeActivePageResolver()

    let windowTabs: BrowserWindowTabContext

    let windowVisuals: BrowserWindowVisualCoordinator

    init(
        windowSelection: ShellSelectionService,
        windowTabs: BrowserWindowTabContext,
        glanceManager: GlanceManager,
        windowRegistry: WindowRegistry,
        webViewSessions: WebViewSessionRepository,
        webViewProtection: WebViewProtectionRuntime,
        webViewCompositor: WebViewCompositorRuntime,
        visibleWebViewPreparation: WebViewVisiblePreparationService,
        webViewLifecycle: WebViewLifecycleService
    ) {
        self.glanceManager = glanceManager
        self.windowRegistry = windowRegistry
        self.webViewSessions = webViewSessions
        self.webViewProtection = webViewProtection
        self.webViewCompositor = webViewCompositor
        self.visibleWebViewPreparation = visibleWebViewPreparation
        self.webViewLifecycle = webViewLifecycle
        self.windowSelection = windowSelection
        self.windowTabs = windowTabs
        windowVisuals = BrowserWindowVisualCoordinator(
            protection: webViewProtection,
            windowTabs: windowTabs,
            compositor: webViewCompositor,
            visiblePreparation: visibleWebViewPreparation
        )
    }

    func requireWindowRegistry() -> WindowRegistry {
        windowRegistry
    }

    func requireWindowShellContentViewFactory() -> BrowserWindowShellService.ContentViewFactory {
        guard let windowShellContentViewFactory else {
            preconditionFailure(
                "BrowserShellRuntime.windowShellContentViewFactory is nil. Bind it before creating browser windows."
            )
        }
        return windowShellContentViewFactory
    }
}
