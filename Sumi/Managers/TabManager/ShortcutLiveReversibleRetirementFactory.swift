@MainActor
final class ShortcutLiveReversibleRetirementFactory {
    private let registry: LiveShortcutTabRegistry
    private let runtimeConnection: TabRuntimePortConnection
    private let runtimeTeardown: TabRuntimeTeardownService

    init(
        registry: LiveShortcutTabRegistry,
        runtimeConnection: TabRuntimePortConnection,
        runtimeTeardown: TabRuntimeTeardownService
    ) {
        self.registry = registry
        self.runtimeConnection = runtimeConnection
        self.runtimeTeardown = runtimeTeardown
    }

    func prepare(
        pinID: UUID,
        windowID: UUID
    ) -> ReversibleShortcutLiveTabRetirement? {
        ReversibleShortcutLiveTabRetirement(
            pinID: pinID,
            windowID: windowID,
            registry: registry,
            runtimeConnection: runtimeConnection,
            runtimeTeardown: runtimeTeardown
        )
    }
}
