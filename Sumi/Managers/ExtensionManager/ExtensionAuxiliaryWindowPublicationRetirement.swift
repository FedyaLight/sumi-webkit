import Foundation

@available(macOS 15.5, *)
@MainActor
enum ExtensionAuxiliaryWindowRetirementMode {
    case terminal(restoreNormalFocus: Bool)
    case rejected
    case runtimeSuspension

    var removesPublishedAdapters: Bool {
        switch self {
        case .terminal, .rejected: true
        case .runtimeSuspension: false
        }
    }

    var restoresNormalFocus: Bool {
        if case .terminal(let restore) = self { return restore }
        return false
    }
}

@available(macOS 15.5, *)
@MainActor
struct ExtensionAuxiliaryWindowRetirementOutcome {
    let closedTab: Bool
}

/// Balances an already-tombstoned auxiliary Tab+Window publication. The
/// ledger claim is deliberately owned by the caller so nested callbacks
/// cannot start another transaction for the same session identity.
@available(macOS 15.5, *)
@MainActor
final class ExtensionAuxiliaryWindowPublicationRetirement {
    private let ledger: ExtensionAuxiliaryWindowPublicationLedger
    private let adapterStore: ExtensionBrowserAdapterStore
    private let publicationResolver: ExtensionAuxiliaryWindowPublicationResolver
    private let normalWindows: ExtensionNormalWindowLifecycle
    #if DEBUG
        private let debugEvent:
            @MainActor (ExtensionAuxiliaryPublicationDebugEvent) -> Void
    #endif

    #if DEBUG
    init(
        ledger: ExtensionAuxiliaryWindowPublicationLedger,
        adapterStore: ExtensionBrowserAdapterStore,
        publicationResolver: ExtensionAuxiliaryWindowPublicationResolver,
        normalWindows: ExtensionNormalWindowLifecycle,
        debugEvent: @escaping @MainActor (
            ExtensionAuxiliaryPublicationDebugEvent
        ) -> Void
    ) {
        self.ledger = ledger
        self.adapterStore = adapterStore
        self.publicationResolver = publicationResolver
        self.normalWindows = normalWindows
        self.debugEvent = debugEvent
    }
    #else
        init(
            ledger: ExtensionAuxiliaryWindowPublicationLedger,
            adapterStore: ExtensionBrowserAdapterStore,
            publicationResolver: ExtensionAuxiliaryWindowPublicationResolver,
            normalWindows: ExtensionNormalWindowLifecycle
        ) {
            self.ledger = ledger
            self.adapterStore = adapterStore
            self.publicationResolver = publicationResolver
            self.normalWindows = normalWindows
        }
    #endif

    func retire(
        _ publication: ExtensionAuxiliaryWindowPublication,
        session: AuxiliaryWindowSession,
        windowQuery: (any ExtensionWindowQuery)?,
        control: (any ExtensionAuxiliaryWindowControl)?,
        mode: ExtensionAuxiliaryWindowRetirementMode
    ) -> ExtensionAuxiliaryWindowRetirementOutcome? {
        guard ledger.claimForRetirement(
            publication,
            session: session
        ) else {
            return nil
        }
        defer {
            ledger.finishRetirement(
                publication,
                sessionID: session.id
            )
        }

        let closedTab: Bool
        let removesAdapters = mode.removesPublishedAdapters
            || control?.auxiliaryWindowSession(for: session.id) !== session
        let removesPreparedAdaptersBeforeWindowClose =
            publication.tabReceipt.isPrepared && removesAdapters
        if publication.tabReceipt.isPrepared {
            _ = publication.tabReceipt.cancelForWindowRetirement()
            closedTab = false
        } else {
            closedTab = publication.tabReceipt
                .closePublishedTabForWindowRetirement()
            #if DEBUG
                if closedTab {
                    debugEvent(.didCloseTab(
                        sessionID: session.id,
                        tabID: session.tab.id
                    ))
            }
            #endif
        }

        // Retire didOpenWindow's implicit Tab projection before balancing a
        // rejected Window callback.
        if removesPreparedAdaptersBeforeWindowClose {
            removeAdapters(for: publication, session: session)
        }

        publication.context.didCloseWindow(publication.adapter)
        #if DEBUG
            debugEvent(.didCloseWindow(sessionID: session.id))
        #endif

        if mode.restoresNormalFocus {
            restoreNormalWindowFocus(
                for: publication,
                windowQuery: windowQuery
            )
        }

        if removesAdapters && removesPreparedAdaptersBeforeWindowClose == false {
            removeAdapters(for: publication, session: session)
        }
        return ExtensionAuxiliaryWindowRetirementOutcome(closedTab: closedTab)
    }

    func removeUnpublishedWindowAdapter(for session: AuxiliaryWindowSession) {
        guard ledger.isClosing(session) == false,
              let adapter = session.miniWindowAdapter else {
            return
        }
        _ = adapterStore.removeMiniWindowAdapter(
            for: session.id,
            ifIdenticalTo: adapter
        )
    }

    private func removeAdapters(
        for publication: ExtensionAuxiliaryWindowPublication, session: AuxiliaryWindowSession
    ) {
        _ = adapterStore.removeTabAdapter(
            for: session.tab.id,
            ifIdenticalTo: publication.tabReceipt.adapter
        )
        _ = adapterStore.removeMiniWindowAdapter(
            for: session.id,
            ifIdenticalTo: publication.adapter
        )
    }

    private func restoreNormalWindowFocus(
        for publication: ExtensionAuxiliaryWindowPublication,
        windowQuery: (any ExtensionWindowQuery)?
    ) {
        guard let windowQuery,
              let activeWindow = windowQuery.activeExtensionWindowState,
              windowQuery.extensionWindowState(for: activeWindow.id)
                === activeWindow,
              publicationResolver.windowMatchesProfile(
                  activeWindow,
                  publication: publication
              ),
              let adapter = normalWindows.publishedAdapter(
                  for: activeWindow,
                  profileID: publication.profileID
              )
        else {
            publication.context.didFocusWindow(nil)
            return
        }
        publication.context.didFocusWindow(adapter)
    }
}
