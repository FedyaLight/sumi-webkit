import Foundation

@MainActor
final class BrowserNativeSurfaceResidenceOwner {
    private let ephemeralLifecycle: TabEphemeralLifecycleOwner
    private let spaces: TabSpaceCollectionStateOwner
    private let regularTabs: RegularTabCollectionOwner
    private let persistence: TabStructuralPersistenceService

    init(
        ephemeralLifecycle: TabEphemeralLifecycleOwner,
        spaces: TabSpaceCollectionStateOwner,
        regularTabs: RegularTabCollectionOwner,
        persistence: TabStructuralPersistenceService
    ) {
        self.ephemeralLifecycle = ephemeralLifecycle
        self.spaces = spaces
        self.regularTabs = regularTabs
        self.persistence = persistence
    }

    func existingRegularTab(
        matching kind: SumiNativeBrowserSurfaceKind,
        in space: Space?
    ) -> Tab? {
        guard let space else { return nil }
        return regularTabs.tabs(in: space.id).first(where: kind.matches)
    }

    func makeEphemeralTab(
        url: URL,
        in windowState: BrowserWindowState,
        profile: Profile
    ) -> Tab {
        ephemeralLifecycle.createEphemeralTab(
            url: url,
            in: windowState,
            profile: profile
        )
    }

    func targetSpace(
        for windowState: BrowserWindowState,
        preferredSpaceID: UUID?
    ) -> Space? {
        if let preferredSpaceID,
           let preferred = spaces.spaces.first(where: { $0.id == preferredSpaceID }) {
            return preferred
        }
        if let currentSpaceID = windowState.currentSpaceId,
           let current = spaces.spaces.first(where: { $0.id == currentSpaceID }) {
            return current
        }
        if let currentProfileID = windowState.currentProfileId,
           let profileSpace = spaces.spaces.first(where: { $0.profileId == currentProfileID }) {
            return profileSpace
        }
        return spaces.spaces.first
    }

    func persistRuntimeState(of tab: Tab) {
        persistence.scheduleRuntimeStatePersistence(for: tab)
    }
}
