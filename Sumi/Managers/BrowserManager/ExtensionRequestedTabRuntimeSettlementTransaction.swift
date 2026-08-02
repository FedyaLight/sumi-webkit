import Foundation

@available(macOS 15.5, *)
@MainActor
final class ExtensionRequestedTabRuntimeSettlementTransaction {
    private let runtimeConnection: TabRuntimePortConnection
    private let membership: TabCollectionMembershipOwner
    private let persistence: TabStructuralPersistenceService

    init(
        runtimeConnection: TabRuntimePortConnection,
        membership: TabCollectionMembershipOwner,
        persistence: TabStructuralPersistenceService
    ) {
        self.runtimeConnection = runtimeConnection
        self.membership = membership
        self.persistence = persistence
    }

    func settle(
        _ removal: ExtensionRequestedTabRemoval,
        notifyingExtensionClose: Bool,
        restoreSelection: () -> Void
    ) {
        let runtime = runtimeConnection.requireLease()
        switch removal {
        case .transient:
            restoreSelection()
        case .regular(let tab):
            let splitSettlement = runtime.stageTabClosures([tab.id])
            if notifyingExtensionClose {
                runtime.notifyTabClosedIfLoaded(tab)
            }
            runtime.forEachWindowState { windowState in
                windowState.selectionHistory
                    .removeFromRegularTabHistory(tab.id)
            }
            runtime.webViewLifecycle.unloadTab(tab)
            runtime.webViewLifecycle.requireRemoveAllWebViews(for: tab)
            membership.detach(tab)
            restoreSelection()
            NotificationCenter.default.post(
                name: .sumiTabLifecycleDidChange,
                object: tab
            )
            splitSettlement?.publish()
        }
        persistence.scheduleStructuralPersistence()
        _ = runtime.validateWindowStates()
    }
}
