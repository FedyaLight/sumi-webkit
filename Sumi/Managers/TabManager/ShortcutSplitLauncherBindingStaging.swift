import Foundation

/// Creates batch-scoped launcher binding staging. Capturing the runtime lease
/// once prevents a multi-move batch from mixing attachment generations.
@MainActor
final class ShortcutSplitLauncherBindingStaging {
    private let refreshes: LiveShortcutPresentationRefreshService
    private let resolution: ShortcutPinRuntimeResolutionOwner
    private let runtimeConnection: TabRuntimePortConnection
    private let windowMutations: BrowserWindowShortcutMutationOwner
    private let profiles: TabProfileTransitionService
    private let persistence: ShortcutSplitLauncherWindowPersistence
    private let structuralLookup: TabStructuralLookupCoordinator

    init(
        refreshes: LiveShortcutPresentationRefreshService,
        resolution: ShortcutPinRuntimeResolutionOwner,
        runtimeConnection: TabRuntimePortConnection,
        windowMutations: BrowserWindowShortcutMutationOwner,
        profiles: TabProfileTransitionService,
        persistence: ShortcutSplitLauncherWindowPersistence,
        structuralLookup: TabStructuralLookupCoordinator
    ) {
        self.refreshes = refreshes
        self.resolution = resolution
        self.runtimeConnection = runtimeConnection
        self.windowMutations = windowMutations
        self.profiles = profiles
        self.persistence = persistence
        self.structuralLookup = structuralLookup
    }

    convenience init(tabManager: TabManager) {
        let structuralLookup = tabManager.structuralLookupCoordinator
        self.init(
            refreshes: tabManager.liveShortcutPresentationRefreshes,
            resolution: tabManager.shortcutPinRuntimeResolutionOwner,
            runtimeConnection: tabManager.runtimePortConnection,
            windowMutations: tabManager.shortcutWindowMutationOwner,
            profiles: tabManager.profileAssignments.tabs,
            persistence: ShortcutSplitLauncherWindowPersistence(
                structuralLookup: structuralLookup
            ),
            structuralLookup: structuralLookup
        )
    }

    func beginBatch() -> ShortcutSplitLauncherBindingBatchStaging {
        ShortcutSplitLauncherBindingBatchStaging(
            refreshes: refreshes,
            resolution: resolution,
            runtimeConnection: runtimeConnection,
            windowMutations: windowMutations,
            profiles: profiles,
            persistence: persistence,
            structuralLookup: structuralLookup
        )
    }

    func admission(
        for pin: ShortcutPin
    ) -> LiveShortcutPresentationRefreshAdmission? {
        refreshes.admission(for: pin)
    }
}
