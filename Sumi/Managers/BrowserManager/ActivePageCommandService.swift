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
        toggleMute(resolver.resolveActiveWindow())
    }

    func toggleMute(_ page: ActivePageResolution?) {
        guard let page, !page.tab.representsSumiNativeSurface else { return }
        page.tab.toggleMute()
    }

    func canUseWebPage(_ page: ActivePageResolution?) -> Bool {
        guard let page else { return false }
        return page.tab.representsSumiNativeSurface == false
    }

    func canCopyURL(_ page: ActivePageResolution?) -> Bool {
        guard canUseWebPage(page),
              let scheme = page?.url.scheme?.lowercased() else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }

    func canInspect(_ page: ActivePageResolution?) -> Bool {
        canUseWebPage(page)
            && page?.presentationWebView != nil
            && inspector.canInspect
    }

    func canPrint(_ page: ActivePageResolution?) -> Bool {
        canUseWebPage(page) && page?.presentationWebView != nil
    }

    @discardableResult
    func copyActivePageURL() -> Bool {
        copyURL(resolver.resolveActiveWindow())
    }

    @discardableResult
    func copyURL(_ page: ActivePageResolution?) -> Bool {
        guard canCopyURL(page), let page else { return false }

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
        inspect(resolver.resolveActiveWindow())
    }

    @discardableResult
    func inspect(_ page: ActivePageResolution?) -> Bool {
        guard canInspect(page),
              let webView = page?.presentationWebView else { return false }
        return inspector.inspect(webView)
    }

    @discardableResult
    func printPage(_ page: ActivePageResolution?) -> Bool {
        guard canPrint(page),
              let webView = page?.presentationWebView else { return false }
        return ActivePagePrintService.print(webView)
    }
}
