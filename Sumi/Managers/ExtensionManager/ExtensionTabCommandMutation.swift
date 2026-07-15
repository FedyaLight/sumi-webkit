import Foundation
import SumiWebRuntime
import WebKit

@available(macOS 15.5, *)
@MainActor
protocol ExtensionTabWindowLocationQuery: AnyObject {
    func preferredExtensionWindowState(
        containing tab: Tab
    ) -> BrowserWindowState?
}

@available(macOS 15.5, *)
@MainActor
final class ExtensionTabCommandMutation {
    private let evidence: ExtensionTabCurrentPublicationEvidence
    private let projection: ExtensionTabReadProjection
    private weak var windowQuery: (any ExtensionTabWindowLocationQuery)?
    private weak var tabMutation: (any ExtensionTabCommandRouting)?
    private weak var webViewHosting: (any ExtensionTabReloadHosting)?
    private weak var auxiliaryWindows: (any ExtensionAuxiliaryTabClosing)?

    init(
        evidence: ExtensionTabCurrentPublicationEvidence,
        projection: ExtensionTabReadProjection,
        windowQuery: any ExtensionTabWindowLocationQuery,
        tabMutation: any ExtensionTabCommandRouting,
        webViewHosting: any ExtensionTabReloadHosting,
        auxiliaryWindows: any ExtensionAuxiliaryTabClosing
    ) {
        self.evidence = evidence
        self.projection = projection
        self.windowQuery = windowQuery
        self.tabMutation = tabMutation
        self.webViewHosting = webViewHosting
        self.auxiliaryWindows = auxiliaryWindows
    }

    private var tabUnavailableUntilReloadError: NSError {
        ExtensionBridgeAdapterCallbackError.tabUnavailableUntilReload.nsError()
    }

    private var tabUnavailableError: NSError {
        if evidence.currentTab != nil {
            return tabUnavailableUntilReloadError
        }
        return ExtensionBridgeAdapterCallbackError.tabUnavailable.nsError()
    }

    private func complete(
        _ completion: @escaping (Error?) -> Void,
        error: Error?
    ) {
        ExtensionBridgeCallbackSupport.complete(
            completion,
            api: .tabAdapterCompletion,
            error: error
        )
    }

    func activate(
        for context: WKWebExtensionContext,
        completion: @escaping (Error?) -> Void
    ) {
        guard let tabMutation,
              let publication = evidence.currentPublication(visibleTo: context)
        else { complete(completion, error: tabUnavailableError); return }
        let tab = publication.tab
        guard let window = windowQuery?.preferredExtensionWindowState(
            containing: tab
        ) else {
            complete(
                completion,
                error: ExtensionBridgeAdapterCallbackError.tabWindowUnavailable
                    .nsError()
            )
            return
        }
        _ = tabMutation.promoteTransientExtensionTab(tab)
        guard evidence.isCurrent(publication, visibleTo: context),
              windowQuery?.preferredExtensionWindowState(containing: tab)
                === window
        else {
            complete(completion, error: tabUnavailableUntilReloadError)
            return
        }
        tabMutation.selectExtensionTab(tab, in: window)
        complete(completion, error: nil)
    }

    func close(
        for context: WKWebExtensionContext,
        completion: @escaping (Error?) -> Void
    ) {
        guard let publication = evidence.currentPublication(visibleTo: context)
        else {
            complete(completion, error: tabUnavailableUntilReloadError)
            return
        }
        if publication.isAuxiliary {
            guard let auxiliaryWindows,
                  let session = auxiliaryWindows.auxiliaryWindowSession(
                    for: publication.tab
                  ),
                  session.tab === publication.tab,
                  let receipt = auxiliaryWindows
                    .auxiliaryWindowSessionReceipt(for: session)
            else {
                complete(completion, error: tabUnavailableUntilReloadError)
                return
            }
            auxiliaryWindows.closeAuxiliaryWindowSession(receipt)
            complete(completion, error: nil)
            return
        }
        publication.tab.closeTab()
        complete(completion, error: nil)
    }

    func reload(
        fromOrigin: Bool,
        for context: WKWebExtensionContext,
        completion: @escaping (Error?) -> Void
    ) {
        guard let publication = evidence.currentPublication(visibleTo: context)
        else {
            complete(completion, error: tabUnavailableUntilReloadError)
            return
        }
        let tab = publication.tab
        guard let webView = projection.webView(for: context) else {
            complete(
                completion,
                error: ExtensionBridgeAdapterCallbackError.tabWebViewUnavailable
                    .nsError()
            )
            return
        }
        guard evidence.isCurrent(publication, visibleTo: context) else {
            complete(completion, error: tabUnavailableUntilReloadError)
            return
        }
        guard let webViewHosting else {
            complete(completion, error: tabUnavailableError)
            return
        }
        let outcome = webViewHosting.reloadExtensionTab(
            tab,
            webView: webView,
            in: windowQuery?.preferredExtensionWindowState(containing: tab),
            policy: fromOrigin ? .fromOrigin : .standard
        )
        guard outcome != .failed else {
            complete(
                completion,
                error: ExtensionBridgeAdapterCallbackError.tabReloadFailed
                    .nsError()
            )
            return
        }
        complete(completion, error: nil)
    }

    func loadURL(
        _ url: URL,
        for context: WKWebExtensionContext,
        completion: @escaping (Error?) -> Void
    ) {
        guard let publication = evidence.currentPublication(visibleTo: context)
        else {
            complete(completion, error: tabUnavailableUntilReloadError)
            return
        }
        let tab = publication.tab
        if ExtensionURLIdentity.isOwned(url) == false {
            _ = tabMutation?.promoteTransientExtensionTab(tab)
            guard evidence.isCurrent(publication, visibleTo: context) else {
                complete(completion, error: tabUnavailableUntilReloadError)
                return
            }
        }
        tab.loadURL(url)
        complete(completion, error: nil)
    }

    func setMuted(
        _ muted: Bool,
        for context: WKWebExtensionContext,
        completion: @escaping (Error?) -> Void
    ) {
        guard let tab = evidence.currentPublication(visibleTo: context)?.tab
        else {
            complete(completion, error: tabUnavailableUntilReloadError)
            return
        }
        tab.setMuted(muted)
        complete(completion, error: nil)
    }

    func setZoomFactor(
        _ zoomFactor: Double,
        for context: WKWebExtensionContext,
        completion: @escaping (Error?) -> Void
    ) {
        guard let publication = evidence.currentPublication(visibleTo: context),
              let webView = projection.webView(for: context)
        else {
            complete(completion, error: tabUnavailableError)
            return
        }
        guard evidence.isCurrent(publication, visibleTo: context) else {
            complete(completion, error: tabUnavailableUntilReloadError)
            return
        }
        webView.pageZoom = zoomFactor
        complete(completion, error: nil)
    }
}
