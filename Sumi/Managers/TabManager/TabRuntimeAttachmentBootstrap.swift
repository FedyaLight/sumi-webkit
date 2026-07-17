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
        let trace = PerformanceTrace.beginInterval("Startup.tabRuntimeAttachment")
        defer { PerformanceTrace.endInterval("Startup.tabRuntimeAttachment", trace) }
        guard connection.accepts(lease), let runtime = lease.registry else {
            return .superseded
        }
        let tabs = membership.allTabs()
        for tab in tabs {
            guard connection.accepts(lease) else { return .superseded }
            guard runtimePreparation.prepare(tab, using: lease) == .completed else {
                return .superseded
            }
            if membership.tab(for: tab.id) !== tab {
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
