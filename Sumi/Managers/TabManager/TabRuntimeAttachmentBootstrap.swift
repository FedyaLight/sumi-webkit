import Foundation

@MainActor
final class TabRuntimeAttachmentBootstrap {
    enum Result {
        case completed
        case superseded
    }

    private let connection: TabRuntimePortConnection
    private let membership: TabCollectionMembershipOwner
    private let runtimePreparation: TabRuntimePreparationOwner
    private let selection: TabSelectionStateOwner

    init(
        connection: TabRuntimePortConnection,
        membership: TabCollectionMembershipOwner,
        runtimePreparation: TabRuntimePreparationOwner,
        selection: TabSelectionStateOwner
    ) {
        self.connection = connection
        self.membership = membership
        self.runtimePreparation = runtimePreparation
        self.selection = selection
    }

    func run(using lease: TabRuntimePortLease) -> Result {
        guard connection.accepts(lease), let runtime = lease.registry else {
            return .superseded
        }
        var preparedTabs: Set<ObjectIdentifier> = []
        while let tab = membership.allTabs().first(where: {
            preparedTabs.contains(ObjectIdentifier($0)) == false
        }) {
            guard connection.accepts(lease) else { return .superseded }
            preparedTabs.insert(ObjectIdentifier(tab))
            guard runtimePreparation.prepare(tab, using: lease) == .completed else {
                return .superseded
            }
            if membership.allTabs().contains(where: { $0 === tab }) == false {
                runtime.webViewLifecycle.unloadTab(tab)
                guard connection.accepts(lease) else { return .superseded }
            }
        }

        if let current = selection.currentTab,
           let canonical = membership.tab(for: current.id) {
            selection.replaceCurrentTab(canonical)
        }
        return connection.accepts(lease) ? .completed : .superseded
    }
}
