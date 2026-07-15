@MainActor
final class ShortcutTabBindingBatchFactory {
    private let runtimeConnection: TabRuntimePortConnection
    private let windowMutations: BrowserWindowShortcutMutationOwner
    private let profiles: TabProfileTransitionService
    private let persistence: ShortcutSplitLauncherWindowPersistence
    private let structuralLookup: TabStructuralLookupCoordinator

    init(
        runtimeConnection: TabRuntimePortConnection,
        windowMutations: BrowserWindowShortcutMutationOwner,
        profiles: TabProfileTransitionService,
        persistence: ShortcutSplitLauncherWindowPersistence,
        structuralLookup: TabStructuralLookupCoordinator
    ) {
        self.runtimeConnection = runtimeConnection
        self.windowMutations = windowMutations
        self.profiles = profiles
        self.persistence = persistence
        self.structuralLookup = structuralLookup
    }

    func make(
        using attachment: TabRuntimeAttachmentWitness? = nil
    ) -> ShortcutTabBindingBatchBuilder {
        ShortcutTabBindingBatchBuilder(
            runtimeConnection: runtimeConnection,
            runtimeAttachment: attachment,
            windowMutations: windowMutations,
            profiles: profiles,
            persistence: persistence,
            structuralLookup: structuralLookup
        )
    }
}
