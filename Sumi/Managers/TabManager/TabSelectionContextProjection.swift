import Foundation

@MainActor
final class TabSelectionContextProjection {
    private let runtimeConnection: TabRuntimePortConnection
    private let spaces: TabSpaceCollectionStateOwner
    private let regularTabs: RegularTabCollectionOwner
    private let shortcutPresentation: TabShortcutPresentationOwner

    init(
        runtimeConnection: TabRuntimePortConnection,
        spaces: TabSpaceCollectionStateOwner,
        regularTabs: RegularTabCollectionOwner,
        shortcutPresentation: TabShortcutPresentationOwner
    ) {
        self.runtimeConnection = runtimeConnection
        self.spaces = spaces
        self.regularTabs = regularTabs
        self.shortcutPresentation = shortcutPresentation
    }

    func tabs(in windowID: UUID? = nil) -> [Tab] {
        let windowState = windowID.flatMap {
            runtimeConnection.current?.windowState(for: $0)
        }
        let spaceID = windowState?.currentSpaceId ?? spaces.currentSpaceId
        let profileID = windowState?.currentProfileId
            ?? spaceID.flatMap { spaces.profileId(for: $0) }
            ?? runtimeConnection.current?.currentProfileId
        let regular = spaceID.map { regularTabs.tabs(in: $0) } ?? []
        let launcher = windowID
            .flatMap { shortcutPresentation.activeShortcutTab(for: $0) }
            .flatMap { tab -> Tab? in
                guard tab.shortcutPinRole != .essential else { return nil }
                guard tab.spaceId == nil || tab.spaceId == spaceID else {
                    return nil
                }
                return tab
            }

        return shortcutPresentation.activeEssentialTabs(for: profileID)
            + (launcher.map { [$0] } ?? [])
            + regular
    }
}
