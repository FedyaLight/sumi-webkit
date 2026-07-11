import Foundation

/// Retires one exact inactive Tab whose WebExtension creation transaction did
/// not commit. This is not a user close: no recently-closed entry or closure
/// notification is produced, while a didOpenTab that crossed WebKit is still
/// balanced before model/WebView teardown.
@available(macOS 15.5, *)
@MainActor
final class ExtensionRequestedTabDiscardService {
    private let transactions: TabStructuralLookupCoordinator
    private let persistence: TabStructuralPersistenceService
    private let membership: TabCollectionMembershipOwner
    private let transientTabs: TabTransientWebKitTabLifecycleOwner
    private let regularTabs: RegularTabCollectionOwner
    private let spaces: TabSpaceCollectionStateOwner
    private let selection: TabSelectionStateOwner
    private let runtimePorts: @MainActor () -> RuntimePortRegistry

    init(
        transactions: TabStructuralLookupCoordinator,
        persistence: TabStructuralPersistenceService,
        membership: TabCollectionMembershipOwner,
        transientTabs: TabTransientWebKitTabLifecycleOwner,
        regularTabs: RegularTabCollectionOwner,
        spaces: TabSpaceCollectionStateOwner,
        selection: TabSelectionStateOwner,
        runtimePorts: @escaping @MainActor () -> RuntimePortRegistry
    ) {
        self.transactions = transactions
        self.persistence = persistence
        self.membership = membership
        self.transientTabs = transientTabs
        self.regularTabs = regularTabs
        self.spaces = spaces
        self.selection = selection
        self.runtimePorts = runtimePorts
    }

    @discardableResult
    func discard(
        _ tab: Tab,
        restoringSelectionTo tabID: UUID?
    ) -> Bool {
        transactions.withTransaction {
            guard membership.tab(for: tab.id) === tab else {
                return false
            }

            let wasCurrent = selection.currentTab === tab
            let needsExtensionClose = tab.extensionPageRuntimeOwner
                .hasAnyDidOpenTabNotification()
            persistence.cancelRuntimeStatePersistence(for: tab.id)
            let removedTransient = needsExtensionClose
                ? transientTabs.removeTransientExtensionTab(id: tab.id)
                : transientTabs
                    .discardTransientExtensionTabWithoutPublishedOpen(
                        id: tab.id
                    )
            if removedTransient {
                restoreSelectionIfNeeded(
                    wasCurrent: wasCurrent,
                    tabID: tabID
                )
                persistence.scheduleStructuralPersistence()
                _ = runtimePorts().validateWindowStates()
                return true
            }

            let removals = regularTabs.remove(
                [tab.id],
                in: spaces.spaces,
                currentSpaceId: spaces.currentSpaceId
            )
            guard removals.count == 1,
                  removals[0].tab === tab
            else {
                return false
            }

            let runtime = runtimePorts()
            runtime.handleTabClosures([tab.id])
            if needsExtensionClose {
                runtime.notifyTabClosedIfLoaded(tab)
            }
            runtime.forEachWindowState { windowState in
                windowState.selectionHistory
                    .removeFromRegularTabHistory(tab.id)
            }
            runtime.webViewLifecycle.unloadTab(tab)
            runtime.webViewLifecycle.requireRemoveAllWebViews(
                for: tab,
                closeActiveFullscreenMedia: true
            )
            membership.detach(tab)
            restoreSelectionIfNeeded(
                wasCurrent: wasCurrent,
                tabID: tabID
            )
            NotificationCenter.default.post(
                name: .sumiTabLifecycleDidChange,
                object: tab
            )
            persistence.scheduleStructuralPersistence()
            _ = runtime.validateWindowStates()
            return true
        }
    }

    private func restoreSelectionIfNeeded(
        wasCurrent: Bool,
        tabID: UUID?
    ) {
        guard wasCurrent else { return }
        selection.replaceCurrentTab(
            tabID.flatMap { membership.tab(for: $0) }
        )
    }
}
