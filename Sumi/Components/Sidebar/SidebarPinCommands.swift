import Foundation

@MainActor
final class SidebarPinCommands {
    private let placement: SidebarPinPlacementCommands
    private let lifecycle: SidebarPinLifecycleCommands
    private let essentialCopy: ShortcutPinEssentialCopyTransaction
    private let essentialPinning: RegularTabEssentialPinningService

    init(
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
        lifecycle.resetToLaunchURL(
            pin,
            in: windowState,
            preserveCurrentPage: preserveCurrentPage
        )
    }

    func replaceSavedURLWithCurrent(
        _ pin: ShortcutPin,
        in windowState: BrowserWindowState
    ) -> Bool {
        lifecycle.replaceSavedURLWithCurrent(pin, in: windowState)
    }

    func remove(_ pin: ShortcutPin) -> Bool {
        lifecycle.remove(pin)
    }

    func move(_ pin: ShortcutPin, toFolder folderID: UUID) -> Bool {
        placement.move(pin, toFolder: folderID)
    }

    func move(_ pin: ShortcutPin, toSpace spaceID: UUID) -> Bool {
        placement.move(pin, toSpace: spaceID)
    }

    func copyToEssentials(
        _ pin: ShortcutPin,
        title: String,
        context: EssentialsShortcutPlacementOwner.TargetContext?
    ) -> ShortcutPin? {
        essentialCopy.copy(pin, title: title, context: context)
    }

    func pinTab(
        _ tab: Tab,
        context: EssentialsShortcutPlacementOwner.TargetContext?
    ) {
        essentialPinning.pin(tab, context: context)
    }

    func update(
        _ pin: ShortcutPin,
        title: String,
        launchURL: URL,
        iconAsset: String?
    ) -> ShortcutPin? {
        lifecycle.update(
            pin,
            title: title,
            launchURL: launchURL,
            iconAsset: iconAsset
        )
    }
}
