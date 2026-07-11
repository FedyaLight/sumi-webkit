import Foundation

@available(macOS 15.5, *)
@MainActor
final class BrowserRequestedTabTargetAdapter: ExtensionTabTargetQuery {
    private let windows: any ExtensionWindowQuery
    private let space: @MainActor (UUID) -> Space?
    private let firstSpace: @MainActor (UUID) -> Space?
    private let auxiliarySessions: AuxiliaryWindowSessionRegistry

    init(
        windows: any ExtensionWindowQuery,
        space: @escaping @MainActor (UUID) -> Space?,
        firstSpace: @escaping @MainActor (UUID) -> Space?,
        auxiliarySessions: AuxiliaryWindowSessionRegistry
    ) {
        self.windows = windows
        self.space = space
        self.firstSpace = firstSpace
        self.auxiliarySessions = auxiliarySessions
    }

    func extensionWindowState(for windowId: UUID) -> BrowserWindowState? {
        windows.extensionWindowState(for: windowId)
    }

    var activeExtensionWindowState: BrowserWindowState? {
        windows.activeExtensionWindowState
    }

    func extensionWindowState(containing tab: Tab) -> BrowserWindowState? {
        windows.extensionWindowState(containing: tab)
    }

    func preferredExtensionWindowState(
        containing tab: Tab
    ) -> BrowserWindowState? {
        windows.preferredExtensionWindowState(containing: tab)
    }

    func extensionTargetSpace(
        for windowState: BrowserWindowState?
    ) -> Space? {
        guard let windowState else { return nil }
        if let spaceID = windowState.currentSpaceId,
           let currentSpace = space(spaceID),
           windowState.currentProfileId
            .map({ currentSpace.profileId == $0 }) ?? true {
            return currentSpace
        }
        return windowState.currentProfileId.flatMap(firstSpace)
    }

    func extensionTargetSpace(for tab: Tab) -> Space? {
        tab.spaceId.flatMap(space)
    }

    func extensionTargetSpace(matchingProfile profileId: UUID) -> Space? {
        firstSpace(profileId)
    }

    func auxiliaryWindowSession(
        for sessionId: UUID
    ) -> AuxiliaryWindowSession? {
        auxiliarySessions.session(for: sessionId)
    }
}
