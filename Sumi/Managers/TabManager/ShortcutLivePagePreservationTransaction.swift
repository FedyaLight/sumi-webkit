import Foundation
import SumiDomain

@MainActor
final class ShortcutLivePagePreservationTransaction {
    private let tabFactory: TabFactory
    private let membership: TabCollectionMembershipOwner
    private let regularTabs: RegularTabCollectionOwner
    private let structuralMutations: TabStructuralCollectionMutationOwner

    init(
        tabFactory: TabFactory,
        membership: TabCollectionMembershipOwner,
        regularTabs: RegularTabCollectionOwner,
        structuralMutations: TabStructuralCollectionMutationOwner
    ) {
        self.tabFactory = tabFactory
        self.membership = membership
        self.regularTabs = regularTabs
        self.structuralMutations = structuralMutations
    }

    func preserveCurrentPage(
        from liveTab: Tab,
        for pin: ShortcutPin,
        in windowState: BrowserWindowState
    ) -> Bool {
        guard liveTab.url.absoluteString != pin.launchURL.absoluteString,
              let spaceID = pin.spaceId ?? windowState.currentSpaceId
        else { return false }
        let duplicate = tabFactory.makeTab(
            url: liveTab.url,
            name: liveTab.name,
            favicon: SumiPersistentGlyph.launcherSystemImageFallback,
            spaceId: spaceID,
            index: 0
        )
        duplicate.faviconPresentation = liveTab.faviconPresentation
        duplicate.faviconIsTemplateGlobePlaceholder = liveTab
            .faviconIsTemplateGlobePlaceholder
        duplicate.profileId = liveTab.profileId
        membership.attach(duplicate)
        var tabs = regularTabs.tabs(in: spaceID)
        tabs.append(duplicate)
        structuralMutations.setTabs(tabs, for: spaceID)
        structuralMutations.schedulePersistence()
        return true
    }
}
