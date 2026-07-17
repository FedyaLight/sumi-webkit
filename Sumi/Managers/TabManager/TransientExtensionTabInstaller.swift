import Foundation
import SumiDomain
import WebKit

@MainActor
final class TransientExtensionTabInstaller {
    private let membership: TabCollectionMembershipOwner
    private let regularTabs: RegularTabCollectionOwner
    private let tabFactory: TabFactory
    private let residence: TransientExtensionTabResidenceQuery

    init(
        membership: TabCollectionMembershipOwner,
        regularTabs: RegularTabCollectionOwner,
        tabFactory: TabFactory,
        residence: TransientExtensionTabResidenceQuery
    ) {
        self.membership = membership
        self.regularTabs = regularTabs
        self.tabFactory = tabFactory
        self.residence = residence
    }

    func install(
        url: URL,
        placement: TabCreationPlacement,
        webExtensionContextOverride: WKWebExtensionContext?
    ) -> Tab {
        let tab = tabFactory.makeTab(
            url: url,
            name: "New Tab",
            favicon: "globe",
            spaceId: placement.space.id,
            index: regularTabs.appendIndex(in: placement.space.id)
        )
        tab.profileId = placement.temporaryProfileOverrideId
        tab.webExtensionContextOverride = webExtensionContextOverride
        membership.attach(tab)
        membership.registerTransientExtensionTab(tab)
        precondition(
            residence.containsExact(tab),
            "Transient extension creation must publish its exact Tab residence"
        )
        return tab
    }

    func makeDetachedFallback(url: URL) -> Tab {
        tabFactory.makeTab(
            url: url,
            name: "New Tab",
            favicon: "globe",
            spaceId: nil,
            index: 0
        )
    }
}
