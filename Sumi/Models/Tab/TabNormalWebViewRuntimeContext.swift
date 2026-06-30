import Foundation
import WebKit

@MainActor
struct TabNormalWebViewRuntimeContext {
    let tabId: UUID
    let currentURL: () -> URL
    let isPopupHost: () -> Bool
    let currentWebView: () -> WKWebView?
    let parkedWebView: () -> WKWebView?
    let profileId: () -> UUID?
    let resolveProfile: () -> Profile?
    let deferWebViewCreationUntilProfileAvailable: () -> Void
    let beginSuspendedRestoreIfNeeded: () -> Void
    let finishSuspendedRestoreIfNeeded: () -> Void
    let setupWebView: () -> Void
    let adoptParkedWebViewAsCurrent: (WKWebView) -> Void
    let clearParkedExistingWebView: () -> Void
    let replaceUntrackedWebView: (WKWebView) -> Void
    let assignPrimaryWebView: (WKWebView, UUID) -> Void
    let cleanupCloneWebView: (WKWebView) -> Void
    let configurationContext: () -> TabWebViewConfigurationContext
    let webViewConfigurationOwner: TabWebViewConfigurationOwner
    let ownedWebViewPreparationOwner: TabOwnedWebViewPreparationOwner
    let reloadPolicyStateOwner: TabReloadPolicyStateOwner
    let normalTabUserScriptsProvider: (URL?) -> SumiNormalTabUserScripts
    let replaceNormalTabUserScripts: (WKUserContentController, URL?) async -> Void
    let loadMainFrameRequest: (WKWebView, URLRequest) -> Void
    let applyCachedFaviconOrPlaceholder: (URL) -> Void
    let registerNormalTabWithExtensionRuntimeIfNeeded: (String) -> Void
    let scheduleInitialDocumentRuntimeHandoff: (
        WKWebView?,
        URL,
        UUID?,
        String,
        NormalTabInitialDocumentRuntimeHandoff.TabSetupRegistrationGuard
    ) -> Void

    var hasCurrentWebView: Bool {
        currentWebView() != nil
    }

    var hasParkedWebView: Bool {
        parkedWebView() != nil
    }
}
