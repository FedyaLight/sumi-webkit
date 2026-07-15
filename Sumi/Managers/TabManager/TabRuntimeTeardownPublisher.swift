import Foundation

/// Owns post-WebKit publication after a Tab generation is irreversibly gone.
@MainActor
final class TabRuntimeTeardownPublisher {
    private let membership: TabCollectionMembershipOwner
    private let terminalModel: TabTerminalModelPublisher

    init(
        membership: TabCollectionMembershipOwner,
        terminalModel: TabTerminalModelPublisher
    ) {
        self.membership = membership
        self.terminalModel = terminalModel
    }

    func prepareTerminalModelRetirement(
        _ tabs: [Tab],
        sourceModelIsExact: @escaping @MainActor () -> Bool
    ) -> PreparedTabTerminalModelRetirement? {
        terminalModel.prepareRetirement(
            tabs, sourceModelIsExact: sourceModelIsExact
        )
    }

    func prepareTerminalLifecyclePublication(
        afterDetaching tabs: [Tab],
        modelIsExact: @escaping @MainActor () -> Bool
    ) -> PreparedTabTerminalLifecyclePublication? {
        terminalModel.prepareLifecyclePublication(
            afterDetaching: tabs,
            modelIsExact: modelIsExact
        )
    }

    @discardableResult
    func publish(
        _ tabs: [Tab],
        runtime: RuntimePortRegistry
    ) -> Set<UUID> {
        let tabIDs = publishRuntime(tabs, runtime: runtime)
        guard tabIDs.isEmpty == false else { return [] }
        precondition(terminalModel.publish(tabs) == tabIDs)
        return tabIDs
    }

    @discardableResult
    func publishRuntime(
        _ tabs: [Tab],
        runtime: RuntimePortRegistry
    ) -> Set<UUID> {
        let tabIDs = Set(tabs.map(\.id))
        guard tabIDs.isEmpty == false else { return [] }
        let splitSettlement = runtime.stageTabClosures(tabIDs)

        for tab in tabs {
            removeAuxiliaryResidence(of: tab, runtime: runtime)
            runtime.notifyTabClosedIfLoaded(tab)
            runtime.webViewLifecycle.unloadTab(tab)
        }
        splitSettlement?.publish()
        return tabIDs
    }

    func prepareScopedRuntimePublication(
        _ tabs: [Tab],
        runtime: RuntimePortRegistry
    ) -> PreparedScopedTabRuntimePublication? {
        PreparedScopedTabRuntimePublication(tabs: tabs, runtime: runtime)
    }

    private func removeAuxiliaryResidence(
        of tab: Tab,
        runtime: RuntimePortRegistry
    ) {
        if membership.isAuxiliaryMiniWindowTab(tab) {
            runtime.closeAuxiliaryMiniWindow(for: tab, reason: .bulkCleanup)
            if membership.isAuxiliaryMiniWindowTab(tab) {
                membership.removeAuxiliaryMiniWindowTab(tab)
            }
        } else if membership.isTransientExtensionTab(tab) {
            _ = membership.removeTransientExtensionTab(id: tab.id)
        }
    }
}
