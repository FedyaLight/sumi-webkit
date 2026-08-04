import Foundation

/// Opens a normal link Tab in the receipt's presentation Space while preserving
/// an explicit execution-profile override before any WebView is materialized.
@MainActor
final class PhysicalSourceTabOpeningService {
    private let spaces: TabSpaceCollectionStateOwner
    private let regularTabs: RegularTabCollectionOwner
    private let regularLifecycle: TabRegularLifecycleOwner
    private weak var opening: BrowserTabOpeningOwner?
    private weak var notifications: (any BackgroundTabOpenedNotifying)?
    private let select: @MainActor (
        Tab,
        BrowserWindowState,
        TabSelectionLoadPolicy
    ) -> Void

    init(
        spaces: TabSpaceCollectionStateOwner,
        regularTabs: RegularTabCollectionOwner,
        regularLifecycle: TabRegularLifecycleOwner,
        opening: BrowserTabOpeningOwner,
        notifications: any BackgroundTabOpenedNotifying,
        select: @escaping @MainActor (
            Tab,
            BrowserWindowState,
            TabSelectionLoadPolicy
        ) -> Void
    ) {
        self.spaces = spaces
        self.regularTabs = regularTabs
        self.regularLifecycle = regularLifecycle
        self.opening = opening
        self.notifications = notifications
        self.select = select
    }

    func open(
        _ url: URL,
        from source: PhysicalWebViewSourceReceipt,
        selected: Bool,
        foregroundLoadPolicy: TabSelectionLoadPolicy = .deferred
    ) -> Tab? {
        guard let opening else { return nil }

        if source.residence == .privateEphemeral {
            guard source.window.ephemeralProfile === source.executionProfile,
                  source.presentationProfile === source.executionProfile
            else {
                return nil
            }
            let context: BrowserTabOpenContext = selected
                ? .foreground(
                    windowState: source.window,
                    sourceTab: source.tab,
                    preferredSpaceId: source.presentationSpace.id,
                    loadPolicy: foregroundLoadPolicy
                )
                : .background(
                    windowState: source.window,
                    sourceTab: source.tab,
                    preferredSpaceId: source.presentationSpace.id
                )
            return opening.openNewTab(
                url: url.absoluteString,
                context: context
            )
        }

        guard source.window.isIncognito == false,
              source.window.currentSpaceId == source.presentationSpace.id,
              source.window.currentProfileId
                == source.presentationProfile.id,
              source.presentationSpace.profileId
                == source.presentationProfile.id,
              spaces.space(
                  with: source.presentationSpace.id
              ) === source.presentationSpace
        else {
            return nil
        }

        let insertionIndex = regularTabs.childInsertionIndex(
            openedFrom: source.tab,
            in: source.presentationSpace
        )
        let child = regularLifecycle.createNewTab(
            url: url.absoluteString,
            in: source.presentationSpace,
            activate: false,
            executionProfileID: source.descendantProfileID,
            regularInsertionIndex: insertionIndex
        )
        source.window.markWebKitChildWindowAdopted(by: child.id)

        if selected {
            select(child, source.window, foregroundLoadPolicy)
        } else {
            opening.prepareBackgroundTabIfNeeded(child, in: source.window)
            notifications?.presentBackgroundTabOpenedNotification(
                tabId: child.id,
                in: source.window
            )
        }
        return child
    }
}
