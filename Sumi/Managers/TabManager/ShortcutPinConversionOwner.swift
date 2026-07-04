import Foundation

@MainActor
final class ShortcutPinConversionOwner {
    struct Dependencies {
        let insertRegularTabFromShortcut: @MainActor (ShortcutPin, UUID, Int?) -> Tab
        let removeShortcutPinFromContainers: @MainActor (ShortcutPin) -> Void
        let scheduleStructuralPersistence: @MainActor () -> Void
        let makeShortcutPin: @MainActor (Tab, ShortcutPinRole, UUID?, UUID?, UUID?, Int) -> ShortcutPin
        let insertShortcutPin: @MainActor (ShortcutPin, Int, Bool) -> ShortcutPin?
        let convertDisplayedTabToShortcutLiveInstances: @MainActor (Tab, ShortcutPin, UUID?) -> Bool
        let removeTab: @MainActor (UUID) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    @discardableResult
    func convertShortcutPinToRegularTab(
        _ pin: ShortcutPin,
        in targetSpaceId: UUID,
        at targetIndex: Int? = nil
    ) -> Bool {
        _ = dependencies.insertRegularTabFromShortcut(pin, targetSpaceId, targetIndex)
        dependencies.removeShortcutPinFromContainers(pin)
        dependencies.scheduleStructuralPersistence()
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
        let pin = dependencies.makeShortcutPin(
            tab,
            role,
            profileId,
            spaceId,
            folderId,
            targetIndex
        )
        guard let insertedPin = dependencies.insertShortcutPin(
            pin,
            targetIndex,
            openTargetFolder
        ) else { return nil }

        if !dependencies.convertDisplayedTabToShortcutLiveInstances(
            tab,
            insertedPin,
            preferredWindowId
        ) {
            dependencies.removeTab(tab.id)
        }
        dependencies.scheduleStructuralPersistence()
        return insertedPin
    }
}

extension ShortcutPinConversionOwner.Dependencies {
    @MainActor
    static func live(tabManager: TabManager) -> Self {
        Self(
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
}
