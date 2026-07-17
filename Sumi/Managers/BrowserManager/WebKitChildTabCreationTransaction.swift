import Foundation

struct PreparedWebKitChildTab {
    let tab: Tab
    let residence: WebKitChildTabResidence
}

/// Creates the model residence for a WebKit child Tab. WebView publication and
/// post-publication presentation are settled by a separate transaction.
@MainActor
final class WebKitChildTabCreationTransaction {
    private let spaces: TabSpaceCollectionStateOwner
    private let regularTabs: RegularTabCollectionOwner
    private let regularLifecycle: TabRegularLifecycleOwner
    private let ephemeralLifecycle: TabEphemeralLifecycleOwner

    init(
        spaces: TabSpaceCollectionStateOwner,
        regularTabs: RegularTabCollectionOwner,
        regularLifecycle: TabRegularLifecycleOwner,
        ephemeralLifecycle: TabEphemeralLifecycleOwner
    ) {
        self.spaces = spaces
        self.regularTabs = regularTabs
        self.regularLifecycle = regularLifecycle
        self.ephemeralLifecycle = ephemeralLifecycle
    }

    func prepare(
        from source: PhysicalWebViewSourceReceipt,
        requestURL: URL?,
        selected: Bool
    ) -> PreparedWebKitChildTab? {
        if source.residence == .privateEphemeral {
            guard source.window.isIncognito,
                  source.window.ephemeralProfile === source.executionProfile,
                  let blankURL = URL(string: "about:blank")
            else {
                return nil
            }
            let previousTabID = source.window.currentTabId
            let tab = ephemeralLifecycle.createEphemeralTab(
                url: requestURL ?? blankURL,
                in: source.window,
                profile: source.executionProfile
            )
            tab.isPopupHost = true
            tab.profileId = source.executionProfile.id
            if selected == false {
                source.window.currentTabId = previousTabID
            }
            return PreparedWebKitChildTab(
                tab: tab,
                residence: .ephemeral(previousTabID: previousTabID)
            )
        }

        guard source.window.isIncognito == false,
              source.window.currentSpaceId == source.presentationSpace.id,
              source.window.currentProfileId == source.presentationProfile.id,
              source.presentationSpace.profileId == source.presentationProfile.id,
              spaces.space(with: source.presentationSpace.id)
              === source.presentationSpace
        else {
            return nil
        }
        let insertionIndex = regularTabs.childInsertionIndex(
            openedFrom: source.tab,
            in: source.presentationSpace
        )
        let tab = regularLifecycle.createPopupTab(
            in: source.presentationSpace,
            activate: false,
            executionProfileID: source.executionProfile.id,
            regularInsertionIndex: insertionIndex
        )
        return PreparedWebKitChildTab(
            tab: tab,
            residence: .regular(spaceID: source.presentationSpace.id)
        )
    }
}
