import Foundation

@MainActor
enum BrowserTabResidenceAuthorityFactory {
    static func make(
        regularTabs: RegularTabCollectionOwner,
        liveShortcuts: LiveShortcutTabRegistry,
        structuralLookup: TabStructuralLookupCoordinator,
        persistence: TabStructuralPersistenceService
    ) -> BrowserTabResidenceAuthority {
        BrowserTabResidenceAuthority(
            sessionIdentity: BrowserTabResidenceSessionIdentity(),
            regularTabs: regularTabs,
            liveShortcuts: liveShortcuts,
            structuralLookup: structuralLookup,
            persistence: persistence
        )
    }
}
