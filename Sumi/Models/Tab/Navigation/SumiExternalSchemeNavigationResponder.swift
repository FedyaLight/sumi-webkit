import AppKit
import Foundation
import SumiDomain
import SumiWebRuntime
import WebKit

@MainActor
final class SumiExternalSchemeNavigationResponder:
    SumiNavigationActionSourceAndTargetWebViewResponding,
    SumiNavigationStartResponding,
    SumiNavigationCommitResponding,
    SumiNavigationCompletionResponding,
    SumiSameDocumentNavigationResponding {
    typealias TabContextProvider = @MainActor (WKWebView) -> SumiExternalSchemePermissionTabContext?
    typealias DocumentLeaseProvider = @MainActor (Tab, WKWebView) -> TabMainFrameDocumentLease?

    private struct WebViewStateReceipt {
        let webView: WKWebView
        let tab: Tab
        let residence: WebViewResidence
        let documentLease: TabMainFrameDocumentLease?
        let committedURL: URL?
        let lifecycleRevision: UInt64
    }

    private struct CloseReceipt {
        let source: WebViewStateReceipt
        let target: WebViewStateReceipt
        let targetClaim: ExternalSchemeTargetCloseLedger.Claim
        let isCurrentPermissionPage: @MainActor @Sendable () -> Bool
    }

    private weak var tab: Tab?
    private let permissionBridge: SumiExternalSchemePermissionBridge?
    private let tabContextProvider: TabContextProvider?
    private let documentLeaseProvider: DocumentLeaseProvider
    private let targetCloseLedger = ExternalSchemeTargetCloseLedger()

    init(
        tab: Tab,
        permissionBridge: SumiExternalSchemePermissionBridge? = nil,
        tabContextProvider: TabContextProvider? = nil,
        documentLeaseProvider: @escaping DocumentLeaseProvider = {
            tab, webView in
            tab.committedDocumentRuntime.lease(for: webView)
        }
    ) {
        self.tab = tab
        self.permissionBridge = permissionBridge
        self.tabContextProvider = tabContextProvider
        self.documentLeaseProvider = documentLeaseProvider
    }

    func decidePolicy(
        for navigationAction: SumiNavigationAction,
        sourceWebView: WKWebView?,
        targetWebView: WKWebView?,
        preferences _: inout SumiNavigationPreferences
    ) async -> SumiNavigationActionPolicy? {
        guard let externalURL = navigationAction.url,
              externalURL.sumiIsExternalSchemeLink,
              SumiExternalSchemePermissionRequest.isValidExternalSchemeURL(externalURL)
        else {
            recordNavigationAction(
                navigationAction,
                sourceWebView: sourceWebView,
                targetWebView: targetWebView
            )
            return .next
        }

        let signpostState = PerformanceTrace.beginInterval("NavigationPolicy.externalSchemeResponder")
        defer {
            PerformanceTrace.endInterval("NavigationPolicy.externalSchemeResponder", signpostState)
        }

        let initialAction = navigationAction.mainFrameNavigation
            .map { $0.redirectHistory.first ?? $0.navigationAction }
        let isUserEnteredNavigation = initialAction?.isUserEnteredURL == true

        let initialRequest = navigationAction.mainFrameNavigation?.redirectHistory.first?.request
            ?? navigationAction.mainFrameNavigation?.navigationAction.request
            ?? navigationAction.request
        if [.returnCacheDataElseLoad, .returnCacheDataDontLoad].contains(initialRequest.cachePolicy) {
            settleCloseCandidate(
                sourceWebView: sourceWebView,
                targetWebView: targetWebView
            )
            return .cancel
        }

        guard let sourceWebView else {
            return .cancel
        }
        let sourceTab = exactTab(for: sourceWebView)
        guard let bridge = permissionBridge
                ?? sourceTab?.navigationRuntime.navigationDelegateRuntime
                    .externalSchemePermissionBridge(),
              let tabContext = tabContextProvider?(sourceWebView)
                ?? sourceTab?.externalSchemePermissionTabContext(for: sourceWebView)
        else {
            settleCloseCandidate(
                sourceWebView: sourceWebView,
                targetWebView: targetWebView
            )
            return .cancel
        }

        let closeReceipt = isUserEnteredNavigation
            ? nil
            : makeCloseReceipt(
                sourceWebView: sourceWebView,
                targetWebView: targetWebView,
                tabContext: tabContext
            )
        if isUserEnteredNavigation {
            settleCloseCandidate(
                sourceWebView: sourceWebView,
                targetWebView: targetWebView
            )
        }

        let request = SumiExternalSchemePermissionRequest.fromSumiNavigationAction(navigationAction)
        let result = await bridge.evaluate(
            request,
            tabContext: tabContext,
            willOpen: {
                sourceWebView.window?.makeFirstResponder(nil)
            }
        )

        if result.didOpen,
           let closeReceipt,
           isCurrent(closeReceipt) {
            closeReceipt.target.webView.sumiCloseWindow()
        }

        return .cancel
    }

    func navigationWillStart(_ context: SumiNavigationContext) {
        recordLifecycleMutation(context, settlesProvisionalTarget: false)
    }

    func navigationDidStart(_ context: SumiNavigationContext) {
        recordLifecycleMutation(context, settlesProvisionalTarget: false)
    }

    func navigationDidCommit(_ context: SumiNavigationContext) {
        recordLifecycleMutation(context, settlesProvisionalTarget: true)
    }

    func navigationDidFinish(_ context: SumiNavigationContext?) {
        recordLifecycleMutation(context, settlesProvisionalTarget: true)
    }

    func navigationDidFail(_: WKError, context: SumiNavigationContext?) {
        recordLifecycleMutation(context, settlesProvisionalTarget: true)
    }

    func navigationDidSameDocumentNavigation(
        type _: SumiSameDocumentNavigationType,
        context: SumiNavigationContext?
    ) {
        recordLifecycleMutation(context, settlesProvisionalTarget: true)
    }

    private func makeCloseReceipt(
        sourceWebView: WKWebView,
        targetWebView: WKWebView?,
        tabContext: SumiExternalSchemePermissionTabContext
    ) -> CloseReceipt? {
        let targetWebView = targetWebView ?? sourceWebView
        guard let source = stateReceipt(for: sourceWebView),
              let target = stateReceipt(for: targetWebView),
              target.documentLease == nil,
              target.committedURL == nil,
              (sourceWebView === targetWebView || source.documentLease != nil),
              let isCurrentPermissionPage = tabContext.isCurrentPage,
              isCurrentPermissionPage(),
              let targetClaim = targetCloseLedger.claim(for: targetWebView)
        else {
            return nil
        }

        return CloseReceipt(
            source: source,
            target: target,
            targetClaim: targetClaim,
            isCurrentPermissionPage: isCurrentPermissionPage
        )
    }

    private func isCurrent(_ receipt: CloseReceipt) -> Bool {
        receipt.isCurrentPermissionPage()
            && isCurrent(receipt.source)
            && isCurrent(receipt.target)
            && targetCloseLedger.isCurrent(receipt.targetClaim)
    }

    private func isCurrent(_ receipt: WebViewStateReceipt) -> Bool {
        guard receipt.tab.webViewSession.owns(receipt.webView),
              receipt.tab.webViewSession.residence(of: receipt.webView) == receipt.residence,
              documentLeaseProvider(receipt.tab, receipt.webView) == receipt.documentLease,
              receipt.webView.committedURL == receipt.committedURL,
              targetCloseLedger.revision(for: receipt.webView) == receipt.lifecycleRevision
        else {
            return false
        }
        return true
    }

    private func stateReceipt(for webView: WKWebView) -> WebViewStateReceipt? {
        guard let tab = exactTab(for: webView),
              tab.webViewSession.owns(webView),
              let residence = tab.webViewSession.residence(of: webView)
        else {
            return nil
        }
        return WebViewStateReceipt(
            webView: webView,
            tab: tab,
            residence: residence,
            documentLease: documentLeaseProvider(tab, webView),
            committedURL: webView.committedURL,
            lifecycleRevision: targetCloseLedger.revision(for: webView)
        )
    }

    private func exactTab(for webView: WKWebView) -> Tab? {
        if let tab = (webView as? FocusableWKWebView)?.owningTab,
           tab.webViewSession.owns(webView) {
            return tab
        }
        guard let tab,
              tab.webViewSession.owns(webView) else {
            return nil
        }
        return tab
    }

    private func recordNavigationAction(
        _ navigationAction: SumiNavigationAction,
        sourceWebView: WKWebView?,
        targetWebView: WKWebView?
    ) {
        guard navigationAction.isForMainFrame,
              let webView = targetWebView ?? sourceWebView else {
            return
        }
        targetCloseLedger.recordNavigationMutation(
            on: webView,
            settlesProvisionalTarget: !navigationAction.redirectHistory.isEmpty
        )
    }

    private func settleCloseCandidate(
        sourceWebView: WKWebView?,
        targetWebView: WKWebView?
    ) {
        guard let webView = targetWebView ?? sourceWebView else { return }
        targetCloseLedger.recordNavigationMutation(
            on: webView,
            settlesProvisionalTarget: true
        )
    }

    private func recordLifecycleMutation(
        _ context: SumiNavigationContext?,
        settlesProvisionalTarget: Bool
    ) {
        guard context?.isMainFrame == true,
              let webView = context?.webView else {
            return
        }
        targetCloseLedger.recordNavigationMutation(
            on: webView,
            settlesProvisionalTarget: settlesProvisionalTarget
        )
    }
}

@MainActor
private final class ExternalSchemeTargetCloseLedger {
    struct Claim: Equatable {
        let webViewID: ObjectIdentifier
        let revision: UInt64
        let id: UUID
    }

    private final class WeakWebViewReference {
        weak var webView: WKWebView?

        init(_ webView: WKWebView) {
            self.webView = webView
        }
    }

    private struct Entry {
        let webViewReference: WeakWebViewReference
        var revision: UInt64
        var hasSettledNavigation: Bool
        var claimID: UUID?
    }

    private var entries: [ObjectIdentifier: Entry] = [:]

    func revision(for webView: WKWebView) -> UInt64 {
        entry(for: webView).revision
    }

    func claim(for webView: WKWebView) -> Claim? {
        let webViewID = ObjectIdentifier(webView)
        var entry = entry(for: webView)
        guard !entry.hasSettledNavigation else { return nil }
        guard entry.claimID == nil else {
            entry.revision &+= 1
            entry.hasSettledNavigation = true
            entry.claimID = nil
            entries[webViewID] = entry
            return nil
        }
        let claimID = UUID()
        entry.claimID = claimID
        entries[webViewID] = entry
        return Claim(
            webViewID: webViewID,
            revision: entry.revision,
            id: claimID
        )
    }

    func isCurrent(_ claim: Claim) -> Bool {
        guard let entry = entries[claim.webViewID],
              entry.webViewReference.webView.map(ObjectIdentifier.init) == claim.webViewID else {
            entries.removeValue(forKey: claim.webViewID)
            return false
        }
        return entry.revision == claim.revision
            && entry.claimID == claim.id
            && !entry.hasSettledNavigation
    }

    func recordNavigationMutation(
        on webView: WKWebView,
        settlesProvisionalTarget: Bool
    ) {
        let webViewID = ObjectIdentifier(webView)
        var entry = entry(for: webView)
        entry.revision &+= 1
        entry.hasSettledNavigation = entry.hasSettledNavigation
            || settlesProvisionalTarget
        entry.claimID = nil
        entries[webViewID] = entry
    }

    private func entry(for webView: WKWebView) -> Entry {
        let webViewID = ObjectIdentifier(webView)
        if let entry = entries[webViewID],
           entry.webViewReference.webView === webView {
            return entry
        }
        let entry = Entry(
            webViewReference: WeakWebViewReference(webView),
            revision: 0,
            hasSettledNavigation: false,
            claimID: nil
        )
        entries[webViewID] = entry
        return entry
    }
}
