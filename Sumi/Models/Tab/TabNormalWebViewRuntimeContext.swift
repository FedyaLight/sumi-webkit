import Foundation
import WebKit

@MainActor
struct CreatedWebViewPreparationOptions {
    let enableVisitedLinkRecording: Bool
    let applyNavigationPreferences: Bool
    let installFaviconRuntime: Bool
    let prepareExtensionRuntime: Bool

    static let normal = Self()

    static func auxiliary(prepareExtensionRuntime: Bool) -> Self {
        Self(
            installFaviconRuntime: false,
            prepareExtensionRuntime: prepareExtensionRuntime
        )
    }

    static let auxiliaryOverride = Self(
        enableVisitedLinkRecording: false,
        applyNavigationPreferences: false
    )

    init(
        enableVisitedLinkRecording: Bool = true,
        applyNavigationPreferences: Bool = true,
        installFaviconRuntime: Bool = true,
        prepareExtensionRuntime: Bool = true
    ) {
        self.enableVisitedLinkRecording = enableVisitedLinkRecording
        self.applyNavigationPreferences = applyNavigationPreferences
        self.installFaviconRuntime = installFaviconRuntime
        self.prepareExtensionRuntime = prepareExtensionRuntime
    }
}

@MainActor
struct TabNormalWebViewConfigurationRuntime {
    let normalTabWebViewConfiguration: (
        URL,
        Profile,
        SumiNormalTabUserScripts,
        TabWebViewConfigurationContext
    ) -> WKWebViewConfiguration
    let auxiliaryOverrideConfiguration: (Profile, TabWebViewConfigurationContext) -> WKWebViewConfiguration?
    let applyWebViewConfigurationOverride: (
        WKWebViewConfiguration,
        UUID?,
        TabWebViewConfigurationContext
    ) -> Void
    let canReuseAsNormalTabWebView: (
        WKWebView,
        URL,
        Profile?,
        TabWebViewConfigurationContext
    ) -> Bool
}

@MainActor
struct TabNormalWebViewPreparationRuntime {
    let prepareCreatedFocusableWebView: (
        FocusableWKWebView,
        URL?,
        String,
        CreatedWebViewPreparationOptions
    ) -> Void
    let prepareAssignedWebView: (WKWebView) -> Void
    let prepareReusedOrExternallyCreatedWebView: (WKWebView) -> Void
    let applyOwnedWebViewNavPreferences: (WKWebView) -> Void
}

@MainActor
struct TabNormalWebViewRuntimeContext {
    let tabId: UUID
    let currentURL: () -> URL
    let isPopupHost: () -> Bool
    let currentWebView: () -> WKWebView?
    let parkedWebView: () -> WKWebView?
    let profileId: () -> UUID?
    let resolveProfile: () -> Profile?
    let deferWebViewUntilProfileAvailable: () -> Void
    let beginSuspendedRestoreIfNeeded: () -> Void
    let finishSuspendedRestoreIfNeeded: () -> Void
    let setupWebView: () -> Void
    let adoptParkedWebViewAsCurrent: (WKWebView) -> Void
    let clearParkedExistingWebView: () -> Void
    let replaceUntrackedWebView: (WKWebView) -> Void
    let assignPrimaryWebView: (WKWebView, UUID) -> Void
    let cleanupCloneWebView: (WKWebView) -> Void
    let configurationContext: () -> TabWebViewConfigurationContext
    let configurationRuntime: TabNormalWebViewConfigurationRuntime
    let preparationRuntime: TabNormalWebViewPreparationRuntime
    let normalTabUserScriptsProvider: (URL?) -> SumiNormalTabUserScripts
    let replaceNormalTabUserScripts: (WKUserContentController, URL?) async -> Void
    let loadMainFrameRequest: (WKWebView, URLRequest) -> Void
    let applyCachedFaviconOrPlaceholder: (URL) -> Void
    let registerTabWithExtensionRuntimeIfNeeded: (String) -> Void
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
