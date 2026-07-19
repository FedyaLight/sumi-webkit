import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
protocol ExtensionTabWebViewProjectionQuery: AnyObject {
    func extensionWebView(
        for tab: Tab,
        extensionContext: WKWebExtensionContext
    ) -> WKWebView?
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionTabWindowProjectionQuery:
    ExtensionTabWindowLocationQuery {
    func currentExtensionTab(in windowState: BrowserWindowState) -> Tab?
    func tabsForExtensionWindow(_ windowState: BrowserWindowState) -> [Tab]
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionTabPinningQuery: AnyObject {
    func isPinnedExtensionTab(_ tab: Tab) -> Bool
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionAuxiliaryTabSessionQuery: AnyObject {
    func auxiliaryWindowSession(for tab: Tab) -> AuxiliaryWindowSession?
}

@available(macOS 15.5, *)
@MainActor
protocol ExtensionWindowAdapterPublicationQuery: AnyObject {
    func publishedWindowAdapter(
        for windowState: BrowserWindowState,
        profileID: UUID
    ) -> ExtensionWindowAdapter?
}

/// Read projection used by the WKWebExtensionTab shell. WebView access crosses
/// one exact-identity resolver and is revalidated before the view escapes.
@available(macOS 15.5, *)
@MainActor
final class ExtensionTabReadProjection {
    private let evidence: ExtensionTabCurrentPublicationEvidence
    private weak var windowQuery: (any ExtensionTabWindowProjectionQuery)?
    private weak var tabQuery: (any ExtensionTabPinningQuery)?
    private weak var webViews: (any ExtensionTabWebViewProjectionQuery)?
    private weak var auxiliaryWindows: (any ExtensionAuxiliaryTabSessionQuery)?
    private weak var windowPublications:
        (any ExtensionWindowAdapterPublicationQuery)?

    init(
        evidence: ExtensionTabCurrentPublicationEvidence,
        windowQuery: any ExtensionTabWindowProjectionQuery,
        tabQuery: any ExtensionTabPinningQuery,
        webViews: any ExtensionTabWebViewProjectionQuery,
        auxiliaryWindows: any ExtensionAuxiliaryTabSessionQuery,
        windowPublications: any ExtensionWindowAdapterPublicationQuery
    ) {
        self.evidence = evidence
        self.windowQuery = windowQuery
        self.tabQuery = tabQuery
        self.webViews = webViews
        self.auxiliaryWindows = auxiliaryWindows
        self.windowPublications = windowPublications
    }

    func url(for context: WKWebExtensionContext) -> URL? {
        evidence.currentPublication(visibleTo: context)?.tab.url
    }

    func pendingURL(for context: WKWebExtensionContext) -> URL? {
        guard let tab = evidence.currentPublication(visibleTo: context)?.tab,
              tab.isLoading
        else { return nil }
        return tab.mainFrameLoads.currentIntent.targetURL
    }

    func title(for context: WKWebExtensionContext) -> String? {
        evidence.currentPublication(visibleTo: context)?.tab.name
    }

    func isSelected(for context: WKWebExtensionContext) -> Bool {
        guard let publication = evidence.currentPublication(visibleTo: context),
              let windowQuery,
              let window = windowQuery.preferredExtensionWindowState(
                containing: publication.tab
              )
        else { return false }
        return windowQuery.currentExtensionTab(in: window) === publication.tab
    }

    func indexInWindow(for context: WKWebExtensionContext) -> Int {
        guard let publication = evidence.currentPublication(visibleTo: context),
              let windowQuery,
              let window = windowQuery.preferredExtensionWindowState(
                containing: publication.tab
              )
        else { return 0 }
        return windowQuery.tabsForExtensionWindow(window)
            .firstIndex(where: { $0 === publication.tab }) ?? 0
    }

    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool {
        evidence.currentPublication(visibleTo: context)?.tab.isLoading == false
    }

    func isPinned(for context: WKWebExtensionContext) -> Bool {
        guard let tab = evidence.currentPublication(visibleTo: context)?.tab
        else { return false }
        return tabQuery?.isPinnedExtensionTab(tab) == true
    }

    func isMuted(for context: WKWebExtensionContext) -> Bool {
        evidence.currentPublication(visibleTo: context)?.tab.audioState.isMuted
            ?? false
    }

    func isPlayingAudio(for context: WKWebExtensionContext) -> Bool {
        evidence.currentPublication(visibleTo: context)?.tab.audioState
            .isPlayingAudio ?? false
    }

    func webView(for context: WKWebExtensionContext) -> WKWebView? {
        guard let publication = evidence.currentPublication(visibleTo: context)
        else {
            SafariExtensionAutofillFillDiagnostics.recordFrameResolution(
                resolved: false,
                extensionId: nil,
                reason: "tabAdapterWebViewUnavailable"
            )
            return nil
        }
        guard let webView = webViews?.extensionWebView(
            for: publication.tab,
            extensionContext: context
        ), evidence.isCurrent(publication, visibleTo: context) else {
            SafariExtensionAutofillFillDiagnostics.recordFrameResolution(
                resolved: false,
                extensionId: publication.contextIdentity.extensionID,
                reason: "tabAdapterWebViewBecameStale"
            )
            return nil
        }
        SafariExtensionAutofillFillDiagnostics.recordFrameResolution(
            resolved: true,
            extensionId: publication.contextIdentity.extensionID,
            reason: "tabAdapterWebView"
        )
        return webView
    }

    func zoomFactor(for context: WKWebExtensionContext) -> Double {
        Double(webView(for: context)?.pageZoom ?? 1)
    }

    func size(for context: WKWebExtensionContext) -> CGSize {
        webView(for: context)?.bounds.size ?? .zero
    }

    func window(
        for context: WKWebExtensionContext
    ) -> (any WKWebExtensionWindow)? {
        guard let publication = evidence.currentPublication(visibleTo: context)
        else { return nil }
        if publication.isAuxiliary {
            return auxiliaryWindows?.auxiliaryWindowSession(for: publication.tab)?
                .miniWindowAdapter
        }
        guard let windowQuery,
              let window = windowQuery.preferredExtensionWindowState(
                containing: publication.tab
              ),
              let adapter = windowPublications?.publishedWindowAdapter(
                for: window,
                profileID: publication.contextIdentity.profileID
              ),
              adapter.represents(window)
        else { return nil }
        return adapter
    }
}

@available(macOS 15.5, *)
extension ExtensionWindowPublicationQuery:
    ExtensionTabPublicationEvidenceQuery,
    ExtensionWindowAdapterPublicationQuery {}
