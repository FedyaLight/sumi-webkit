import Foundation
import SumiDomain
import WebKit

@MainActor
final class TransientExtensionTabRetirementTransaction {
    private let runtimeConnection: TabRuntimePortConnection
    private let membership: TabCollectionMembershipOwner

    init(
        runtimeConnection: TabRuntimePortConnection,
        membership: TabCollectionMembershipOwner
    ) {
        self.runtimeConnection = runtimeConnection
        self.membership = membership
    }

    @discardableResult
    func remove(id: UUID, notifyingExtensionClose: Bool) -> Bool {
        guard let expectedTab = membership.tab(for: id),
              membership.isTransientExtensionTab(expectedTab) else {
            return false
        }
        let runtimePorts = runtimeConnection.requireLease()
        guard let tab = membership.removeTransientExtensionTab(id: id) else {
            preconditionFailure("Transient Tab disappeared during retirement")
        }
        precondition(tab === expectedTab, "Transient Tab identity changed during retirement")
        if notifyingExtensionClose {
            runtimePorts.notifyTabClosedIfLoaded(tab)
        }
        runtimePorts.webViewLifecycle.unloadTab(tab)
        runtimePorts.webViewLifecycle.requireRemoveAllWebViews(for: tab)
        membership.detach(tab)
        NotificationCenter.default.post(
            name: .sumiTabLifecycleDidChange,
            object: tab
        )
        return true
    }
}
