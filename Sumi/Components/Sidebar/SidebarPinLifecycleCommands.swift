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
        guard let pin = pins.shortcutPin(by: pin.id),
              windows.contains(windowState)
        else { return false }
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
            title: pin.titleIsCustom || liveTitle.isEmpty
                ? pin.title
                : liveTitle,
            launchURL: liveTab.url
        ) != nil
    }

    func remove(_ pin: ShortcutPin) -> Bool {
        guard let pin = current(pin) else { return false }
        retirement.remove(pin)
        return pins.shortcutPin(by: pin.id) == nil
    }

    func remove(
        _ candidates: [ShortcutPin],
        presentNotification: Bool = true
    ) -> Bool {
        let currentPins = candidates.compactMap(current)
        guard currentPins.count == candidates.count,
              retirement.remove(
                  currentPins,
                  presentNotification: presentNotification
              )
        else { return false }
        return currentPins.allSatisfy {
            pins.shortcutPin(by: $0.id) == nil
        }
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
        guard let pin = current(pin) else { return nil }
        return metadata.update(
            pin,
            title: title,
            launchURL: launchURL,
            iconAsset: .some(iconAsset),
            titleIsCustom: titleIsCustom
        )
    }

    private func current(_ pin: ShortcutPin) -> ShortcutPin? {
        guard let current = pins.shortcutPin(by: pin.id), current === pin else {
            return nil
        }
        return current
    }
}
