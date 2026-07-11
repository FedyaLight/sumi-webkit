import AppKit
import SumiWebRuntime

@MainActor
final class ActivePageCommandService {
    private let resolver: ActivePageResolver
    private let reloadSelectedPage: @MainActor (
        Tab,
        BrowserWindowState,
        String
    ) -> TabMainFrameReloadCommandOutcome
    private let reloadPreviewPage: @MainActor (Tab) -> TabMainFrameReloadCommandOutcome
    private let clipboard: BrowserURLClipboardService
    private let inspector: WebInspectorService

    init(
        resolver: ActivePageResolver,
        reloadSelectedPage: @escaping @MainActor (
            Tab,
            BrowserWindowState,
            String
        ) -> TabMainFrameReloadCommandOutcome,
        reloadPreviewPage: @escaping @MainActor (Tab) -> TabMainFrameReloadCommandOutcome,
        clipboard: BrowserURLClipboardService,
        inspector: WebInspectorService
    ) {
        self.resolver = resolver
        self.reloadSelectedPage = reloadSelectedPage
        self.reloadPreviewPage = reloadPreviewPage
        self.clipboard = clipboard
        self.inspector = inspector
    }

    @discardableResult
    func reloadActivePage() -> TabMainFrameReloadCommandOutcome {
        guard let page = resolver.resolveActiveWindow() else { return .failed }
        return reload(page, reason: "ActivePage.reload")
    }

    @discardableResult
    func reload(
        _ page: ActivePageResolution,
        reason: String
    ) -> TabMainFrameReloadCommandOutcome {
        guard !page.tab.representsSumiNativeSurface else { return .failed }

        switch page.source {
        case .glancePreview:
            return reloadPreviewPage(page.tab)
        case .selectedTab:
            return reloadSelectedPage(page.tab, page.windowState, reason)
        }
    }

    func toggleMuteForActivePage() {
        guard let page = resolver.resolveActiveWindow(),
              !page.tab.representsSumiNativeSurface
        else { return }
        page.tab.toggleMute()
    }

    @discardableResult
    func copyActivePageURL() -> Bool {
        guard let page = resolver.resolveActiveWindow(),
              !page.tab.representsSumiNativeSurface,
              let scheme = page.url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return false }

        let didCopy = clipboard.copy(
            page.url.absoluteString,
            in: page.windowState
        )
        if didCopy {
            NSHapticFeedbackManager.defaultPerformer.perform(
                .generic,
                performanceTime: .drawCompleted
            )
        }
        return didCopy
    }

    @discardableResult
    func inspectActivePage() -> Bool {
        guard let page = resolver.resolveActiveWindow(),
              !page.tab.representsSumiNativeSurface,
              let webView = page.presentationWebView
        else { return false }
        return inspector.inspect(webView)
    }
}
