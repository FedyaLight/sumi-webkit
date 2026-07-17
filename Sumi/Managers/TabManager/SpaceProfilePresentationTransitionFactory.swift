import Foundation

@MainActor
final class SpaceProfilePresentationTransitionFactory {
    private let pins: ShortcutPinCollectionStateOwner
    private let registry: LiveShortcutTabRegistry
    private let runtimeConnection: TabRuntimePortConnection
    private let runtimeTeardown: TabRuntimeTeardownService
    private let terminalPublisher: SpaceProfilePresentationTerminalEffectPublisher

    init(
        pins: ShortcutPinCollectionStateOwner,
        registry: LiveShortcutTabRegistry,
        runtimeConnection: TabRuntimePortConnection,
        runtimeTeardown: TabRuntimeTeardownService,
        terminalPublisher: SpaceProfilePresentationTerminalEffectPublisher
    ) {
        self.pins = pins
        self.registry = registry
        self.runtimeConnection = runtimeConnection
        self.runtimeTeardown = runtimeTeardown
        self.terminalPublisher = terminalPublisher
    }

    func make(
        spaceID: UUID,
        expectedProfileID: UUID?,
        targetProfileID: UUID?,
        using runtimeLease: TabRuntimePortLease
    ) -> SpaceProfilePresentationTransition? {
        guard runtimeConnection.accepts(runtimeLease) else { return nil }
        var relocations: [SpaceProfilePresentationTransition.Relocation] = []
        var retirements: [SpaceProfilePresentationTransition.Retirement] = []
        for entry in registry.entries(presentedInSpace: spaceID) {
            let expectedPage = LiveShortcutPresentationPageReceipt(
                windowID: entry.windowId,
                spaceID: spaceID,
                profileID: expectedProfileID
            )
            guard entry.presentationPage == expectedPage,
                  entry.tab.shortcutPinId == entry.pinId,
                  let pin = pins.shortcutPin(by: entry.pinId),
                  pin.role == entry.tab.shortcutPinRole else { return nil }
            switch pin.role {
            case .spacePinned:
                guard pin.spaceId == spaceID,
                      entry.tab.spaceId == spaceID else { return nil }
                relocations.append(.init(
                    entry: entry,
                    targetPage: LiveShortcutPresentationPageReceipt(
                        windowID: entry.windowId,
                        spaceID: spaceID,
                        profileID: targetProfileID
                    )
                ))
            case .essential:
                guard let profileID = pin.profileId,
                      profileID == expectedProfileID,
                      entry.tab.spaceId == nil,
                      let runtime = runtimeLease.registry,
                      let window = runtime.windowState(for: entry.windowId),
                      runtimeConnection.accepts(runtimeLease)
                else { return nil }
                retirements.append(.init(entry: entry, window: window))
            }
        }
        guard runtimeConnection.accepts(runtimeLease) else { return nil }
        return SpaceProfilePresentationTransition(
            relocations: relocations,
            retirements: retirements,
            registry: registry,
            runtimeConnection: runtimeConnection,
            runtimeLease: runtimeLease,
            runtimeTeardown: runtimeTeardown,
            terminalPublisher: terminalPublisher
        )
    }
}
