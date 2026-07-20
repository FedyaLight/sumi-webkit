import Foundation

@MainActor
final class SidebarPinCommands {
    private let runtime: TabRuntimePortConnection
    private let placement: SidebarPinPlacementCommands
    private let lifecycle: SidebarPinLifecycleCommands
    private let essentialCopy: ShortcutPinEssentialCopyTransaction
    private let essentialPinning: RegularTabEssentialPinningService

    init(
        runtime: TabRuntimePortConnection,
        windows: SidebarWindowIdentityQuery,
        pins: ShortcutPinCollectionStateOwner,
        folders: TabFolderCollectionStateOwner,
        structure: SpacePinnedStructureOwner,
        placement: ShortcutPinPlacementCommandService,
        essentialCopy: ShortcutPinEssentialCopyTransaction,
        essentialPinning: RegularTabEssentialPinningService,
        retirement: ShortcutPinRetirementTransaction,
        livePages: ShortcutPinLivePageMutationService,
        metadata: ShortcutPinMetadataMutationService
    ) {
        self.runtime = runtime
        self.placement = SidebarPinPlacementCommands(
            pins: pins,
            folders: folders,
            structure: structure,
            placement: placement
        )
        self.lifecycle = SidebarPinLifecycleCommands(
            windows: windows,
            pins: pins,
            retirement: retirement,
            livePages: livePages,
            metadata: metadata
        )
        self.essentialCopy = essentialCopy
        self.essentialPinning = essentialPinning
    }

    func resetToLaunchURL(
        _ pin: ShortcutPin,
        in windowState: BrowserWindowState,
        preserveCurrentPage: Bool
    ) -> Bool {
        guard runtime.current != nil else { return false }
        return lifecycle.resetToLaunchURL(
            pin,
            in: windowState,
            preserveCurrentPage: preserveCurrentPage
        )
    }

    func replaceSavedURLWithCurrent(
        _ pin: ShortcutPin,
        in windowState: BrowserWindowState
    ) -> Bool {
        guard runtime.current != nil else { return false }
        return lifecycle.replaceSavedURLWithCurrent(pin, in: windowState)
    }

    func remove(_ pin: ShortcutPin) -> Bool {
        guard runtime.current != nil else { return false }
        return lifecycle.remove(pin)
    }

    func remove(_ pins: [ShortcutPin]) -> Bool {
        guard runtime.current != nil else { return false }
        return lifecycle.remove(pins)
    }

    func move(_ pin: ShortcutPin, toFolder folderID: UUID) -> Bool {
        guard runtime.current != nil else { return false }
        return placement.move(pin, toFolder: folderID)
    }

    func move(_ pin: ShortcutPin, toSpace spaceID: UUID) -> Bool {
        guard runtime.current != nil else { return false }
        return placement.move(pin, toSpace: spaceID)
    }

    func copyToEssentials(
        _ pin: ShortcutPin,
        title: String,
        context: EssentialsShortcutPlacementOwner.TargetContext?
    ) -> ShortcutPin? {
        guard runtime.current != nil else { return nil }
        return essentialCopy.copy(pin, title: title, context: context)
    }

    func pinTab(
        _ tab: Tab,
        context: EssentialsShortcutPlacementOwner.TargetContext?
    ) {
        guard runtime.current != nil else { return }
        essentialPinning.pin(tab, context: context)
    }

    func update(
        _ pin: ShortcutPin,
        title: String,
        launchURL: URL,
        iconAsset: String?
    ) -> ShortcutPin? {
        guard runtime.current != nil else { return nil }
        return lifecycle.update(
            pin,
            title: title,
            launchURL: launchURL,
            iconAsset: iconAsset
        )
    }
}
