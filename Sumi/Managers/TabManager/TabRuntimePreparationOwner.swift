import Foundation

@MainActor
final class TabRuntimePreparationOwner {
    enum Result: Equatable {
        case completed
        case superseded
    }

    private let runtimeConnection: TabRuntimePortConnection

    init(runtimeConnection: TabRuntimePortConnection) {
        self.runtimeConnection = runtimeConnection
    }

    @discardableResult
    func prepare(_ tab: Tab) -> Result {
        prepare(tab, using: runtimeConnection.captureLease())
    }

    @discardableResult
    func prepare(_ tab: Tab, using lease: TabRuntimePortLease) -> Result {
        guard runtimeConnection.accepts(lease), let ports = lease.registry else {
            return .superseded
        }
        ports.webViewLifecycle.prepareTab(tab)
        guard runtimeConnection.accepts(lease) else {
            return .superseded
        }

        let settings = ports.settings
        guard runtimeConnection.accepts(lease) else {
            return .superseded
        }
        if tab.sumiSettings == nil {
            tab.sumiSettings = settings
        }
        return .completed
    }
}
