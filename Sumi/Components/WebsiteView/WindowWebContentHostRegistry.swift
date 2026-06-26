import Foundation
import WebKit

enum WindowWebContentPaneSlot: Hashable {
    case single
    case split(UUID)
}

@MainActor
final class WindowWebContentHostRegistry {
    private var singlePaneHost: SumiWebViewContainerView?
    private var splitPaneHostsByTabId: [UUID: SumiWebViewContainerView] = [:]
    private var parkedProtectedHosts: [ObjectIdentifier: SumiWebViewContainerView] = [:]

    var splitPaneTabIds: [UUID] {
        Array(splitPaneHostsByTabId.keys)
    }

    var displayedHosts: [SumiWebViewContainerView] {
        [singlePaneHost].compactMap { $0 } + Array(splitPaneHostsByTabId.values)
    }

    func displayedHosts(excluding incomingTabIDs: Set<UUID>) -> [SumiWebViewContainerView] {
        displayedHosts.filter { !incomingTabIDs.contains($0.tabID) }
    }

    func host(for slot: WindowWebContentPaneSlot) -> SumiWebViewContainerView? {
        switch slot {
        case .single:
            return singlePaneHost
        case .split(let tabId):
            return splitPaneHostsByTabId[tabId]
        }
    }

    func setHost(_ host: SumiWebViewContainerView, for slot: WindowWebContentPaneSlot) {
        switch slot {
        case .single:
            singlePaneHost = host
        case .split(let tabId):
            splitPaneHostsByTabId[tabId] = host
        }
    }

    func removeSinglePaneHost() -> SumiWebViewContainerView? {
        let host = singlePaneHost
        singlePaneHost = nil
        return host
    }

    func removeSplitPaneHost(for tabId: UUID) -> SumiWebViewContainerView? {
        splitPaneHostsByTabId.removeValue(forKey: tabId)
    }

    func displayedHost(for tabId: UUID) -> SumiWebViewContainerView? {
        if singlePaneHost?.tabID == tabId { return singlePaneHost }
        return splitPaneHostsByTabId[tabId]
    }

    func protectedHost(for webView: WKWebView) -> SumiWebViewContainerView? {
        let webViewID = ObjectIdentifier(webView)
        if let parkedHost = parkedProtectedHosts[webViewID] {
            return parkedHost
        }

        if let singlePaneHost, singlePaneHost.webView === webView {
            parkedProtectedHosts[webViewID] = singlePaneHost
            return singlePaneHost
        }

        for currentHost in splitPaneHostsByTabId.values where currentHost.webView === webView {
            parkedProtectedHosts[webViewID] = currentHost
            return currentHost
        }

        return nil
    }

    func parkProtectedHost(_ host: SumiWebViewContainerView) {
        parkedProtectedHosts[ObjectIdentifier(host.webView)] = host
    }

    func removeParkedProtectedHost(for webView: WKWebView) {
        removeParkedProtectedHost(for: ObjectIdentifier(webView))
    }

    func removeParkedProtectedHost(for webViewID: ObjectIdentifier) {
        parkedProtectedHosts.removeValue(forKey: webViewID)
    }

    func clearReferences(to host: SumiWebViewContainerView) {
        if singlePaneHost === host {
            singlePaneHost = nil
        }
        for (tabId, currentHost) in splitPaneHostsByTabId where currentHost === host {
            splitPaneHostsByTabId[tabId] = nil
        }
    }
}
