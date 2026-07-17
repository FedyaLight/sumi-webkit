import Foundation

@MainActor
final class ShortcutHostedSplitFallbackQuery {
    private let spaces: TabSpaceCollectionStateOwner
    private let regularTabs: RegularTabCollectionOwner

    init(
        spaces: TabSpaceCollectionStateOwner,
        regularTabs: RegularTabCollectionOwner
    ) {
        self.spaces = spaces
        self.regularTabs = regularTabs
    }

    func visibleRegularTab(in windowState: BrowserWindowState) -> Tab? {
        guard let spaceID = windowState.currentSpaceId,
              let space = spaces.space(with: spaceID) else {
            return nil
        }
        return regularTabs.tabs(in: space).first
    }
}
