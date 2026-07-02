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
