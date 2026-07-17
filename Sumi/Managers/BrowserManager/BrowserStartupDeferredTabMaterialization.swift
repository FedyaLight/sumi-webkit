import Foundation

@MainActor
final class BrowserStartupDeferredTabMaterialization {
    private let membership: TabCollectionMembershipOwner
    private var deferredTabIDs: Set<UUID> = []

    init(membership: TabCollectionMembershipOwner) {
        self.membership = membership
    }

    func deferTab(_ tab: Tab) {
        deferredTabIDs.insert(tab.id)
    }

    func materializeDeferredTabs() {
        let tabIDs = deferredTabIDs
        deferredTabIDs.removeAll()
        for tabID in tabIDs {
            guard let tab = membership.tab(for: tabID),
                  tab.requiresPrimaryWebView else {
                continue
            }
            tab.loadWebViewIfNeeded()
        }
    }
}
