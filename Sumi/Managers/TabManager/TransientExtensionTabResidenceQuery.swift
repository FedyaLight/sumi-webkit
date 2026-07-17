import Foundation
import SumiDomain
import WebKit

@MainActor
final class TransientExtensionTabResidenceQuery {
    private let membership: TabCollectionMembershipOwner

    init(membership: TabCollectionMembershipOwner) {
        self.membership = membership
    }

    func containsExact(_ tab: Tab) -> Bool {
        membership.isTransientExtensionTab(tab)
            && membership.tab(for: tab.id) === tab
    }
}
