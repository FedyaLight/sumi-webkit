import Foundation

@MainActor
final class SidebarPinCommands {
    private let runtime: TabRuntimePortConnection
    private let placement: SidebarPinPlacementCommands
    private let lifecycle: SidebarPinLifecycleCommands
    private let favoriteCopy: ShortcutPinFavoriteCopyTransaction
    private let favoritePinning: RegularTabFavoritePinningService

    init(
        runtime: TabRuntimePortConnection,
        windows: SidebarWindowIdentityQuery,
        pins: ShortcutPinCollectionStateOwner,
        folders: TabFolderCollectionStateOwner,
        structure: SpacePinnedStructureOwner,
        placement: ShortcutPinPlacementCommandService,
        favoriteCopy: ShortcutPinFavoriteCopyTransaction,
        favoritePinning: RegularTabFavoritePinningService,
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
        self.favoriteCopy = favoriteCopy
        self.favoritePinning = favoritePinning
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

    func remove(
        _ pins: [ShortcutPin],
        presentNotification: Bool = true
    ) -> Bool {
        guard runtime.current != nil else { return false }
        return lifecycle.remove(
            pins,
            presentNotification: presentNotification
        )
    }

    func move(_ pin: ShortcutPin, toFolder folderID: UUID) -> Bool {
        guard runtime.current != nil else { return false }
        return placement.move(pin, toFolder: folderID)
    }

    func move(_ pin: ShortcutPin, toSpace spaceID: UUID) -> Bool {
        guard runtime.current != nil else { return false }
        return placement.move(pin, toSpace: spaceID)
    }

    func copyToFavorite(
        _ pin: ShortcutPin,
        title: String,
        context: FavoriteShortcutPlacementOwner.TargetContext?
    ) -> ShortcutPin? {
        guard runtime.current != nil else { return nil }
        return favoriteCopy.copy(pin, title: title, context: context)
    }

    func pinTab(
        _ tab: Tab,
        context: FavoriteShortcutPlacementOwner.TargetContext?
    ) {
        guard runtime.current != nil else { return }
        favoritePinning.pin(tab, context: context)
    }

    func update(
        _ pin: ShortcutPin,
        title: String,
        launchURL: URL,
        iconAsset: String?
    ) -> ShortcutPin? {
        update(
            pin,
            title: title,
            launchURL: launchURL,
            iconAsset: iconAsset,
            titleIsCustom: title == pin.title ? pin.titleIsCustom : true
        )
    }

    func update(
        _ pin: ShortcutPin,
        title: String,
        launchURL: URL,
        iconAsset: String?,
        titleIsCustom: Bool
    ) -> ShortcutPin? {
        guard runtime.current != nil else { return nil }
        return lifecycle.update(
            pin,
            title: title,
            launchURL: launchURL,
            iconAsset: iconAsset,
            titleIsCustom: titleIsCustom
        )
    }
}
