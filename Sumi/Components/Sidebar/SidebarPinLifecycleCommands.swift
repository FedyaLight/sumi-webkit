import Foundation

@MainActor
final class SidebarPinLifecycleCommands {
    private let windows: SidebarWindowIdentityQuery
    private let pins: ShortcutPinCollectionStateOwner
    private let retirement: ShortcutPinRetirementTransaction
    private let livePages: ShortcutPinLivePageMutationService
    private let metadata: ShortcutPinMetadataMutationService

    init(
        windows: SidebarWindowIdentityQuery,
        pins: ShortcutPinCollectionStateOwner,
        retirement: ShortcutPinRetirementTransaction,
        livePages: ShortcutPinLivePageMutationService,
        metadata: ShortcutPinMetadataMutationService
    ) {
        self.windows = windows
        self.pins = pins
        self.retirement = retirement
        self.livePages = livePages
        self.metadata = metadata
    }

    func resetToLaunchURL(
        _ pin: ShortcutPin,
        in windowState: BrowserWindowState,
        preserveCurrentPage: Bool
    ) -> Bool {
        guard let pin = current(pin), windows.contains(windowState) else { return false }
        return livePages.reset(
            pin,
            in: windowState,
            preserveCurrentPage: preserveCurrentPage
        ) != nil
    }

    func replaceSavedURLWithCurrent(
        _ pin: ShortcutPin,
        in windowState: BrowserWindowState
    ) -> Bool {
        guard let pin = current(pin), windows.contains(windowState),
              let liveTab = livePages.liveTab(for: pin, in: windowState)
        else { return false }
        let liveTitle = liveTab.name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return metadata.update(
            pin,
            title: liveTitle.isEmpty ? pin.title : liveTitle,
            launchURL: liveTab.url
        ) != nil
    }

    func remove(_ pin: ShortcutPin) -> Bool {
        guard let pin = current(pin) else { return false }
        retirement.remove(pin)
        return pins.shortcutPin(by: pin.id) == nil
    }

    func update(
        _ pin: ShortcutPin,
        title: String,
        launchURL: URL,
        iconAsset: String?
    ) -> ShortcutPin? {
        guard let pin = current(pin) else { return nil }
        return metadata.update(
            pin,
            title: title,
            launchURL: launchURL,
            iconAsset: .some(iconAsset)
        )
    }

    private func current(_ pin: ShortcutPin) -> ShortcutPin? {
        guard let current = pins.shortcutPin(by: pin.id), current === pin else {
            return nil
        }
        return current
    }
}
