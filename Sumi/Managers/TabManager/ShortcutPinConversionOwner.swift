import Foundation

@MainActor
final class ShortcutPinConversionOwner {
    private let insertRegularTabFromShortcut: @MainActor (ShortcutPin, UUID, Int?) -> Tab
    private let removeShortcutPinFromContainers: @MainActor (ShortcutPin) -> Void
    private let scheduleStructuralPersistence: @MainActor () -> Void
    private let makeShortcutPin: @MainActor (Tab, ShortcutPinRole, UUID?, UUID?, UUID?, Int) -> ShortcutPin
    private let insertShortcutPin: @MainActor (ShortcutPin, Int, Bool) -> ShortcutPin?
    private let convertDisplayedTabToShortcutLiveInstances: @MainActor (Tab, ShortcutPin, UUID?) -> Bool
    private let removeTab: @MainActor (UUID) -> Void

    init(
        insertRegularTabFromShortcut: @escaping @MainActor (ShortcutPin, UUID, Int?) -> Tab,
        removeShortcutPinFromContainers: @escaping @MainActor (ShortcutPin) -> Void,
        scheduleStructuralPersistence: @escaping @MainActor () -> Void,
        makeShortcutPin: @escaping @MainActor (Tab, ShortcutPinRole, UUID?, UUID?, UUID?, Int) -> ShortcutPin,
        insertShortcutPin: @escaping @MainActor (ShortcutPin, Int, Bool) -> ShortcutPin?,
        convertDisplayedTabToShortcutLiveInstances: @escaping @MainActor (Tab, ShortcutPin, UUID?) -> Bool,
        removeTab: @escaping @MainActor (UUID) -> Void
    ) {
        self.insertRegularTabFromShortcut = insertRegularTabFromShortcut
        self.removeShortcutPinFromContainers = removeShortcutPinFromContainers
        self.scheduleStructuralPersistence = scheduleStructuralPersistence
        self.makeShortcutPin = makeShortcutPin
        self.insertShortcutPin = insertShortcutPin
        self.convertDisplayedTabToShortcutLiveInstances = convertDisplayedTabToShortcutLiveInstances
        self.removeTab = removeTab
    }

    convenience init(tabManager: TabManager) {
        self.init(
            insertRegularTabFromShortcut: { [weak tabManager] pin, spaceId, targetIndex in
                guard let tabManager else { preconditionFailure("TabManager dependency used after deallocation") }
                return tabManager.shortcutLiveTabOwner.insertRegularTabFromShortcut(pin, into: spaceId, at: targetIndex)
            },
            removeShortcutPinFromContainers: { [weak tabManager] pin in
                tabManager?.shortcutPinStoreOwner.removeFromContainers(pin)
            },
            scheduleStructuralPersistence: { [weak tabManager] in
                tabManager?.scheduleStructuralPersistence()
            },
            makeShortcutPin: { [weak tabManager] tab, role, profileId, spaceId, folderId, index in
                guard let tabManager else { preconditionFailure("TabManager dependency used after deallocation") }
                return tabManager.shortcutPinRuntimeResolutionOwner.makeShortcutPin(
                    from: tab,
                    role: role,
                    profileId: profileId,
                    spaceId: spaceId,
                    folderId: folderId,
                    index: index
                )
            },
            insertShortcutPin: { [weak tabManager] pin, targetIndex, openTargetFolder in
                tabManager?.shortcutPinStoreOwner.insert(
                    pin,
                    at: targetIndex,
                    openTargetFolder: openTargetFolder
                )
            },
            convertDisplayedTabToShortcutLiveInstances: { [weak tabManager] tab, pin, preferredWindowId in
                tabManager?.shortcutLiveTabOwner.convertDisplayedTabToShortcutLiveInstances(
                    tab,
                    pin: pin,
                    preferredWindowId: preferredWindowId
                ) ?? false
            },
            removeTab: { [weak tabManager] tabId in
                tabManager?.tabRemovalOwner.removeTab(tabId)
            }
        )
    }

    @discardableResult
    func convertShortcutPinToRegularTab(
        _ pin: ShortcutPin,
        in targetSpaceId: UUID,
        at targetIndex: Int? = nil
    ) -> Bool {
        _ = insertRegularTabFromShortcut(pin, targetSpaceId, targetIndex)
        removeShortcutPinFromContainers(pin)
        scheduleStructuralPersistence()
        return true
    }

    @discardableResult
    func convertTabToShortcutPin(
        _ tab: Tab,
        role: ShortcutPinRole,
        profileId: UUID?,
        spaceId: UUID?,
        folderId: UUID?,
        at targetIndex: Int,
        openTargetFolder: Bool = true,
        preferredWindowId: UUID? = nil
    ) -> ShortcutPin? {
        let pin = makeShortcutPin(
            tab,
            role,
            profileId,
            spaceId,
            folderId,
            targetIndex
        )
        guard let insertedPin = insertShortcutPin(
            pin,
            targetIndex,
            openTargetFolder
        ) else { return nil }

        if !convertDisplayedTabToShortcutLiveInstances(
            tab,
            insertedPin,
            preferredWindowId
        ) {
            removeTab(tab.id)
        }
        scheduleStructuralPersistence()
        return insertedPin
    }
}
