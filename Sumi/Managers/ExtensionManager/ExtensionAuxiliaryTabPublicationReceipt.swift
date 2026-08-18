import Foundation
import WebKit

/// Exact single-use receipt for the owner-context Tab half of an auxiliary
/// window. Prepared state is reversible and queryable but silent; committed
/// state owns the sole matching `didCloseTab` callback.
@available(macOS 15.5, *)
@MainActor
final class ExtensionAuxiliaryTabPublicationReceipt {
    private enum Phase {
        case prepared
        case committed
        case finished
    }

    private let runtimePublicationEvidence:
        ExtensionRuntimePublicationEvidenceIssuer
    private let profileRuntime: ExtensionProfileRuntime
    private let browserProfiles: ExtensionBrowserProfileQuery
    private let tabProfiles: any ExtensionTabProfileResolving
    private let adapterStore: ExtensionBrowserAdapterStore
    private let controllers: any ExtensionTabControllerQuery
    private let webViews: ExtensionExactTabWebViewQuery
    private let extensionsLoaded: @MainActor () -> Bool
    private let tab: Tab
    private let webView: WKWebView
    private let dataStore: WKWebsiteDataStore
    let profileID: UUID
    let ownerExtensionID: String
    let ownerContext: WKWebExtensionContext
    private let controller: WKWebExtensionController
    let adapter: ExtensionTabAdapter
    private let runtimePublication: ExtensionRuntimePublicationEvidence
    private let contextBindingGeneration: UInt64
    private let createdAdapter: Bool
    private let stateToken: TabExtensionPrepublicationToken
    private var phase = Phase.prepared

    init(
        runtimePublicationEvidence:
            ExtensionRuntimePublicationEvidenceIssuer,
        profileRuntime: ExtensionProfileRuntime,
        browserProfiles: ExtensionBrowserProfileQuery,
        tabProfiles: any ExtensionTabProfileResolving,
        adapterStore: ExtensionBrowserAdapterStore,
        controllers: any ExtensionTabControllerQuery,
        webViews: ExtensionExactTabWebViewQuery,
        extensionsLoaded: @escaping @MainActor () -> Bool,
        tab: Tab,
        webView: WKWebView,
        dataStore: WKWebsiteDataStore,
        profileID: UUID,
        ownerExtensionID: String,
        ownerContext: WKWebExtensionContext,
        controller: WKWebExtensionController,
        adapter: ExtensionTabAdapter,
        runtimePublication: ExtensionRuntimePublicationEvidence,
        contextBindingGeneration: UInt64,
        createdAdapter: Bool,
        stateToken: TabExtensionPrepublicationToken
    ) {
        self.runtimePublicationEvidence = runtimePublicationEvidence
        self.profileRuntime = profileRuntime
        self.browserProfiles = browserProfiles
        self.tabProfiles = tabProfiles
        self.adapterStore = adapterStore
        self.controllers = controllers
        self.webViews = webViews
        self.extensionsLoaded = extensionsLoaded
        self.tab = tab
        self.webView = webView
        self.dataStore = dataStore
        self.profileID = profileID
        self.ownerExtensionID = ownerExtensionID
        self.ownerContext = ownerContext
        self.controller = controller
        self.adapter = adapter
        self.runtimePublication = runtimePublication
        self.contextBindingGeneration = contextBindingGeneration
        self.createdAdapter = createdAdapter
        self.stateToken = stateToken
    }

    var isPrepared: Bool { phase == .prepared }
    var isCommitted: Bool { phase == .committed }
    var generation: ExtensionTabPublicationRevision {
        runtimePublication.tabPublication
    }

    func represents(tab: Tab, webView: WKWebView) -> Bool {
        self.tab === tab && self.webView === webView
    }

    func isCurrent() -> Bool {
        switch phase {
        case .prepared:
            isExactRuntimeStateCurrent()
                && tab.extensionPageRuntimeOwner
                    .canCommitWindowPrepublication(stateToken)
                && tab.extensionPageRuntimeOwner
                    .hasDidOpenTabNotification(for: generation) == false
        case .committed:
            isExactRuntimeStateCurrent()
                && tab.extensionPageRuntimeOwner
                    .isCommittedWindowPrepublicationCurrent(
                        stateToken,
                        generation: generation
                    )
                && ownerContext.openTabs.contains { openTab in
                    (openTab as AnyObject) === adapter
                }
        case .finished:
            false
        }
    }

    @discardableResult
    func commitOpen() -> Bool {
        guard phase == .prepared,
              isCurrent(),
              tab.extensionPageRuntimeOwner.commitWindowPrepublication(
                  stateToken,
                  willEmitOpen: true
              )
        else {
            return false
        }

        tab.extensionPageRuntimeOwner.noteOpenNotification(
            extensionContextBindingGeneration: contextBindingGeneration,
            contextReadiness: .loaded
        )
        guard let openClaim = tab.extensionPageRuntimeOwner.reserveDidOpenTab(
            generation: generation,
            committedWindowPrepublication: stateToken,
            publisher: controller,
            adapter: adapter
        ) else {
            _ = tab.extensionPageRuntimeOwner
                .abortCommittedWindowPrepublicationBeforeOpen(stateToken)
            phase = .finished
            removeCreatedAdapter()
            return false
        }

        // Commit before entering WebKit so nested teardown owns the matching
        // close and cannot observe this receipt as merely prepared.
        phase = .committed
        ownerContext.didOpenTab(adapter)
        return isCurrent()
            && tab.extensionPageRuntimeOwner.settleDidOpenTabNotification(
                openClaim,
                generation: generation
            )
    }

    @discardableResult
    func cancelBeforeWindowPublication() -> Bool {
        cancel(removingCreatedAdapter: true)
    }

    @discardableResult
    func cancelForWindowRetirement() -> Bool {
        guard phase == .prepared else { return false }
        let wasImplicitlyVisibleThroughWindow = ownerContext.openTabs.contains {
            ($0 as AnyObject) === adapter
        }
        let restored = tab.extensionPageRuntimeOwner
            .rollbackWindowPrepublication(stateToken)
        phase = .finished
        if wasImplicitlyVisibleThroughWindow {
            // WebKit exposes a Window's initial Tab as soon as didOpenWindow
            // returns, before Sumi commits the explicit didOpenTab half. This
            // is physical rollback of that implicit projection, not a close
            // event for a committed Tab publication.
            ownerContext.didCloseTab(adapter, windowIsClosing: true)
        }
        return restored
    }

    private func cancel(removingCreatedAdapter: Bool) -> Bool {
        guard phase == .prepared else { return false }
        let restored = tab.extensionPageRuntimeOwner
            .rollbackWindowPrepublication(stateToken)
        phase = .finished
        if restored && removingCreatedAdapter {
            removeCreatedAdapter()
        }
        return restored
    }

    /// Balances the exact owner-context Tab publication. The receipt is
    /// tombstoned before WebKit so nested teardown cannot emit a second close.
    @discardableResult
    func closePublishedTabForWindowRetirement() -> Bool {
        guard phase == .committed,
              tab.extensionPageRuntimeOwner
                .revokeCommittedWindowPrepublication(
                    stateToken,
                    openGeneration: generation
                )
        else {
            return false
        }
        phase = .finished
        ownerContext.didCloseTab(adapter, windowIsClosing: true)
        return true
    }

    private func isExactRuntimeStateCurrent() -> Bool {
        extensionsLoaded()
            && runtimePublicationEvidence.isCurrent(runtimePublication)
            && tabProfiles.profileID(for: tab) == profileID
            && browserProfiles.anyProfile(profileID)?.dataStore === dataStore
            && webView.configuration.websiteDataStore === dataStore
            && profileRuntime.controller(for: profileID) === controller
            && profileRuntime.owns(
                ownerContext,
                extensionID: ownerExtensionID,
                in: profileID
            )
            && profileRuntime.contextBindingGeneration(for: profileID)
                == contextBindingGeneration
            && controllers.existingController(for: tab) === controller
            && webViews.untrackedWebView(for: tab)
                === webView
            && webView.configuration.webExtensionController === controller
            && adapterStore.tabAdapters[tab.id] === adapter
            && tab.extensionPageRuntimeOwner.isEligible(for: generation)
    }

    private func removeCreatedAdapter() {
        guard createdAdapter else { return }
        _ = adapterStore.removeTabAdapter(
            for: tab.id,
            ifIdenticalTo: adapter
        )
    }
}
