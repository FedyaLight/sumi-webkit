import Foundation
import SumiWebRuntime
import WebKit

@available(macOS 15.5, *)
@MainActor
final class BrowserExtensionWebViewAdapter: ExtensionTabWebViewHosting {
    private let liveWebView: @MainActor (Tab) -> WKWebView?
    private let materializeVisible: @MainActor (
        Tab,
        BrowserWindowState
    ) -> Void
    private let windowOwnedWebView: @MainActor (Tab, UUID) -> WKWebView?
    private let replaceLiveWebView: @MainActor (
        Tab,
        UUID?,
        String,
        ((WKWebViewConfiguration, UUID) -> Void)?,
        ((WKWebView) -> Void)?,
        ((WKWebView) -> Bool)?
    ) -> WKWebView?
    private let reload: @MainActor (
        Tab,
        WKWebView,
        BrowserWindowState?,
        WebRuntimeMainFrameReloadPolicy
    ) -> TabMainFrameReloadCommandOutcome

    init(
        liveWebView: @escaping @MainActor (Tab) -> WKWebView?,
        materializeVisible: @escaping @MainActor (
            Tab,
            BrowserWindowState
        ) -> Void,
        windowOwnedWebView: @escaping @MainActor (Tab, UUID) -> WKWebView?,
        replaceLiveWebView: @escaping @MainActor (
            Tab,
            UUID?,
            String,
            ((WKWebViewConfiguration, UUID) -> Void)?,
            ((WKWebView) -> Void)?,
            ((WKWebView) -> Bool)?
        ) -> WKWebView?,
        reload: @escaping @MainActor (
            Tab,
            WKWebView,
            BrowserWindowState?,
            WebRuntimeMainFrameReloadPolicy
        ) -> TabMainFrameReloadCommandOutcome
    ) {
        self.liveWebView = liveWebView
        self.materializeVisible = materializeVisible
        self.windowOwnedWebView = windowOwnedWebView
        self.replaceLiveWebView = replaceLiveWebView
        self.reload = reload
    }

    func extensionLiveWebView(for tab: Tab) -> WKWebView? {
        liveWebView(tab)
    }

    func materializeVisibleExtensionTabWebViewIfNeeded(
        _ tab: Tab,
        in windowState: BrowserWindowState
    ) {
        materializeVisible(tab, windowState)
    }

    func extensionWindowOwnedWebView(
        for tab: Tab,
        in windowId: UUID
    ) -> WKWebView? {
        windowOwnedWebView(tab, windowId)
    }

    func replaceExtensionLiveWebView(
        for tab: Tab,
        in windowState: BrowserWindowState?,
        reason: String,
        prepareCandidateConfiguration: ((WKWebViewConfiguration, UUID) -> Void)?,
        prepareCommittedReplacement: ((WKWebView) -> Void)?,
        validate: ((WKWebView) -> Bool)?
    ) -> WKWebView? {
        replaceLiveWebView(
            tab,
            windowState?.id,
            reason,
            prepareCandidateConfiguration,
            prepareCommittedReplacement,
            validate
        )
    }

    func reloadExtensionTab(
        _ tab: Tab,
        webView: WKWebView,
        in windowState: BrowserWindowState?,
        policy: WebRuntimeMainFrameReloadPolicy
    ) -> TabMainFrameReloadCommandOutcome {
        reload(tab, webView, windowState, policy)
    }
}
