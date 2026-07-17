import Foundation

@MainActor
final class BrowserTabOpenDestinationResolver {
    private let spaces: TabSpaceCollectionStateOwner
    private let regularTabs: RegularTabCollectionOwner
    private let windows: WindowRegistry
    private let windowTabs: BrowserWindowTabContext

    init(
        spaces: TabSpaceCollectionStateOwner,
        regularTabs: RegularTabCollectionOwner,
        windows: WindowRegistry,
        windowTabs: BrowserWindowTabContext
    ) {
        self.spaces = spaces
        self.regularTabs = regularTabs
        self.windows = windows
        self.windowTabs = windowTabs
    }

    var firstSpace: Space? {
        spaces.spaces.first
    }

    func window(for context: BrowserTabOpenContext) -> BrowserWindowState? {
        if let windowState = context.windowState {
            return windowState
        }
        if let sourceTab = context.sourceTab,
           let windowState = windowTabs.windowState(containing: sourceTab) {
            return windowState
        }
        return windows.activeWindow
    }

    func space(for context: BrowserTabOpenContext) -> Space? {
        let windowState = window(for: context)
        if let preferredSpaceID = context.preferredSpaceId,
           let preferredSpace = space(id: preferredSpaceID) {
            return preferredSpace
        }
        if let windowSpaceID = windowState?.currentSpaceId,
           let windowSpace = space(id: windowSpaceID) {
            return windowSpace
        }
        if let sourceSpaceID = context.sourceTab?.spaceId,
           let sourceSpace = space(id: sourceSpaceID) {
            return sourceSpace
        }
        if let profileID = windowState?.currentProfileId,
           let profileSpace = spaces.firstSpace(forProfile: profileID) {
            return profileSpace
        }
        if let profileID = context.sourceTab?.profileId,
           let profileSpace = spaces.firstSpace(forProfile: profileID) {
            return profileSpace
        }
        return firstSpace
    }

    func insertionIndex(
        openedFrom sourceTab: Tab?,
        in space: Space?
    ) -> Int? {
        regularTabs.childInsertionIndex(openedFrom: sourceTab, in: space)
    }

    private func space(id: UUID) -> Space? {
        spaces.spaces.first { $0.id == id }
    }
}
