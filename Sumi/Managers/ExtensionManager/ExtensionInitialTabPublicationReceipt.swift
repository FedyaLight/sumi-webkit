import Foundation
import SumiWebRuntime
import WebKit

/// The extension subsystem either has no resident runtime to participate in
/// this window transaction, prepares an exact reversible receipt, or rejects
/// publication because an active runtime cannot represent the initial Tab.
@MainActor
enum InitialTabExtensionPreparation {
    case notParticipating
    /// Private browser windows do not participate in the normal profile
    /// extension runtime, but their native window transaction remains valid.
    case privateWindow
    case prepared(any InitialTabExtensionPublication)
    /// A resident runtime cannot honestly project this physical window/Tab
    /// profile combination. Browser UI may continue, but no extension window
    /// lifecycle may be published for it.
    case suppressed
    case rejected
}

/// Exact two-phase capability retained by the window-registration transaction.
/// Preparation is silent; publication is allowed only after the exact window
/// has entered WindowRegistry.
@MainActor
protocol InitialTabExtensionPublication: AnyObject {
    func matches(
        window: BrowserWindowState,
        tab: Tab,
        webView: FocusableWKWebView
    ) -> Bool
    func validateBeforeWindowPublication() -> Bool
    @discardableResult
    func publishInitialTab(afterWindowOpened window: BrowserWindowState) -> Bool
    @discardableResult
    func cancel() -> Bool
    @discardableResult
    func revokePublishedIfCurrent() -> Bool
}

extension InitialTabExtensionPublication {
    @discardableResult
    func revokePublishedIfCurrent() -> Bool { false }
}

/// Binds one same-profile initial Tab and its exact physical WebView to the
/// current extension generation before its browser window becomes observable.
/// No WebKit lifecycle event is emitted by `prepare`.
@MainActor
final class ExtensionInitialTabPublicationReceipt:
    InitialTabExtensionPublication {
    private enum Phase {
        case prepared
        case published
        case cancelled
    }

    private weak var manager: ExtensionManager?
    private let window: BrowserWindowState
    private let tab: Tab
    private let webView: FocusableWKWebView
    private let profileID: UUID
    private let extensionLoadGeneration: UInt64
    private let generation: UInt64
    private let adapter: ExtensionTabAdapter
    private let controller: WKWebExtensionController
    private let contextBindingGeneration: UInt64
    private let createdAdapter: Bool
    private let stateToken: TabExtensionPrepublicationToken
    private let reason: String
    private var phase = Phase.prepared
    private var didEmitOpen = false

    private init(
        manager: ExtensionManager,
        window: BrowserWindowState,
        tab: Tab,
        webView: FocusableWKWebView,
        profileID: UUID,
        extensionLoadGeneration: UInt64,
        generation: UInt64,
        adapter: ExtensionTabAdapter,
        controller: WKWebExtensionController,
        contextBindingGeneration: UInt64,
        createdAdapter: Bool,
        stateToken: TabExtensionPrepublicationToken,
        reason: String
    ) {
        self.manager = manager
        self.window = window
        self.tab = tab
        self.webView = webView
        self.profileID = profileID
        self.extensionLoadGeneration = extensionLoadGeneration
        self.generation = generation
        self.adapter = adapter
        self.controller = controller
        self.contextBindingGeneration = contextBindingGeneration
        self.createdAdapter = createdAdapter
        self.stateToken = stateToken
        self.reason = reason
    }

    static func prepare(
        manager: ExtensionManager,
        window: BrowserWindowState,
        tab: Tab,
        webView: FocusableWKWebView,
        reason: String
    ) -> ExtensionInitialTabPublicationReceipt? {
        guard manager.extensionsLoaded,
              exactResidenceMatches(window: window, tab: tab, webView: webView),
              let windowProfileID = manager.resolvedProfileId(for: window),
              let tabProfileID = manager.resolvedProfileId(for: tab),
              windowProfileID == tabProfileID,
              manager.profileNeedsInitialDocumentExtensionContextLoad(
                  profileId: tabProfileID
              ) == false,
              manager.resolvedLiveWebView(for: tab) === webView
        else {
            return nil
        }

        let generation = manager.runtimeSession.tabOpenNotificationGeneration
        let previousAdapter = manager.adapterStore.tabAdapters[tab.id]
        let stateToken = tab.extensionPageRuntimeOwner
            .prepareForWindowPrepublication(generation: generation)

        guard manager.attachExtensionControllerIfNeeded(
            to: webView,
            for: tab
        ), let expectedController = manager.extensionController(for: tab),
           webView.configuration.webExtensionController === expectedController,
           let adapter = manager.adapterResolutionOwner.stableAdapter(for: tab)
        else {
            _ = tab.extensionPageRuntimeOwner.rollbackWindowPrepublication(
                stateToken
            )
            if let createdAdapter = manager.adapterStore.tabAdapters[tab.id],
               previousAdapter == nil {
                _ = manager.adapterStore.removeTabAdapter(
                    for: tab.id,
                    ifIdenticalTo: createdAdapter
                )
            }
            return nil
        }

        return ExtensionInitialTabPublicationReceipt(
            manager: manager,
            window: window,
            tab: tab,
            webView: webView,
            profileID: tabProfileID,
            extensionLoadGeneration: manager.runtimeSession
                .extensionLoadGeneration,
            generation: generation,
            adapter: adapter,
            controller: expectedController,
            contextBindingGeneration: manager
                .extensionContextBindingGeneration(for: tabProfileID),
            createdAdapter: previousAdapter == nil,
            stateToken: stateToken,
            reason: reason
        )
    }

    func matches(
        window: BrowserWindowState,
        tab: Tab,
        webView: FocusableWKWebView
    ) -> Bool {
        phase == .prepared
            && self.window === window
            && self.tab === tab
            && self.webView === webView
    }

    func validateBeforeWindowPublication() -> Bool {
        phase == .prepared
            && isCurrentExactState(requiresRegisteredWindow: false)
    }

    @discardableResult
    func publishInitialTab(
        afterWindowOpened publishedWindow: BrowserWindowState
    ) -> Bool {
        guard publishedWindow === window,
              phase == .prepared,
              isCurrentExactState(requiresRegisteredWindow: true)
        else {
            return false
        }

        let willEmitOpen = tab.extensionPageRuntimeOwner
            .hasDidOpenTabNotification(for: generation) == false
        guard tab.extensionPageRuntimeOwner.commitWindowPrepublication(
            stateToken,
            willEmitOpen: willEmitOpen
        ) else {
            return false
        }
        phase = .published

        // `didOpenWindow` is an external synchronous callback. It may have
        // re-entered normal Tab registration while this receipt was waiting
        // to emit the ordered Tab event. In that case the exact generation is
        // already published and this transaction must not duplicate it.
        if willEmitOpen == false {
            return true
        }

        tab.extensionPageRuntimeOwner.noteOpenNotification(
            extensionContextBindingGeneration: contextBindingGeneration,
            contextReadiness: .loaded
        )
        // Reserve the generation before crossing the WebKit callback boundary.
        // Reentrant registration now observes a completed logical transition
        // instead of delivering a second didOpenTab for the same generation.
        guard tab.extensionPageRuntimeOwner.markDidOpenTab(
            generation: generation,
            committedWindowPrepublication: stateToken
        ) else {
            _ = tab.extensionPageRuntimeOwner
                .abortCommittedWindowPrepublicationBeforeOpen(stateToken)
            phase = .cancelled
            return false
        }
        didEmitOpen = true
        controller.didOpenTab(adapter)
        if let manager {
            #if DEBUG
                manager.testHooks.didOpenTab?(tab.id)
            #endif
            manager.runtimeDiagnostics.trace(
                "initialTabWindowPublication marked reason=\(reason) generation=\(generation) tab=\(tab.id.uuidString.prefix(8)) window=\(window.id.uuidString.prefix(8))"
            )
        }
        return true
    }

    @discardableResult
    func cancel() -> Bool {
        guard phase == .prepared else { return false }
        let restored = tab.extensionPageRuntimeOwner
            .rollbackWindowPrepublication(stateToken)
        let adapterRestored: Bool
        if restored,
           createdAdapter,
           let manager,
           manager.runtimeSession.tabOpenNotificationGeneration
           == generation {
            adapterRestored = manager.adapterStore.removeTabAdapter(
                for: tab.id,
                ifIdenticalTo: adapter
            )
        } else if restored, createdAdapter {
            adapterRestored = false
        } else if restored == false {
            adapterRestored = false
        } else {
            adapterRestored = true
        }
        phase = .cancelled
        return restored && adapterRestored
    }

    @discardableResult
    func revokePublishedIfCurrent() -> Bool {
        guard phase == .published, didEmitOpen else { return false }
        phase = .cancelled

        guard let manager,
              manager.runtimeSession.tabOpenNotificationGeneration
                == generation,
              manager.profileRuntime.controllersByProfile[profileID]
                === controller,
              manager.extensionController(for: tab) === controller,
              manager.adapterStore.tabAdapters[tab.id] === adapter,
              manager.profileRuntime.contexts(for: profileID).values.contains(
                  where: { context in
                      context.openTabs.contains { openTab in
                          (openTab as AnyObject) === adapter
                      }
                  }
              ),
              tab.extensionPageRuntimeOwner
                .revokeCommittedWindowPrepublication(
                    stateToken,
                    openGeneration: generation
                )
        else {
            return false
        }

        controller.didCloseTab(adapter, windowIsClosing: true)
        #if DEBUG
            manager.testHooks.didCloseTab?(tab.id)
        #endif
        if createdAdapter,
           manager.adapterStore.tabAdapters[tab.id] === adapter,
           tab.extensionPageRuntimeOwner
            .hasDidOpenTabNotification(for: generation) == false {
            _ = manager.adapterStore.removeTabAdapter(
                for: tab.id,
                ifIdenticalTo: adapter
            )
        }
        manager.runtimeDiagnostics.trace(
            "initialTabWindowPublication revoked reason=\(reason) generation=\(generation) tab=\(tab.id.uuidString.prefix(8)) window=\(window.id.uuidString.prefix(8))"
        )
        return true
    }

    private func isCurrentExactState(
        requiresRegisteredWindow: Bool
    ) -> Bool {
        guard let manager,
              manager.extensionsLoaded,
              manager.runtimeSession.extensionLoadGeneration
                == extensionLoadGeneration,
              manager.runtimeSession.tabOpenNotificationGeneration
                == generation,
              manager.resolvedProfileId(for: window) == profileID,
              manager.resolvedProfileId(for: tab) == profileID,
              manager.profileNeedsInitialDocumentExtensionContextLoad(
                  profileId: profileID
              ) == false,
              manager.extensionContextBindingGeneration(for: profileID)
                == contextBindingGeneration,
              manager.extensionController(for: tab) === controller,
              Self.exactResidenceMatches(
                  window: window,
                  tab: tab,
                  webView: webView
              ),
              manager.resolvedLiveWebView(for: tab) === webView,
              tab.extensionPageRuntimeOwner.isEligible(for: generation),
              manager.adapterStore.tabAdapters[tab.id] === adapter,
              webView.configuration.webExtensionController === controller,
              tab.extensionPageRuntimeOwner.canCommitWindowPrepublication(
                  stateToken
              )
        else {
            return false
        }

        if requiresRegisteredWindow {
            guard manager.extensionWindowQuery?
                .extensionWindowState(for: window.id) === window
            else {
                return false
            }
        }
        return true
    }

    private static func exactResidenceMatches(
        window: BrowserWindowState,
        tab: Tab,
        webView: FocusableWKWebView
    ) -> Bool {
        guard window.isIncognito == false,
              window.currentTabId == tab.id,
              webView.owningTab === tab,
              window.tabManager?.tabCollectionMembershipOwner.tab(
                  for: tab.id
              ) === tab,
              case .window(let trackedOwner) =
                tab.webViewSession.residence(of: webView)
        else {
            return false
        }
        return trackedOwner == TrackedWebViewOwner(
            tabID: tab.id,
            windowID: window.id
        )
    }
}
