import Foundation

extension TabManager {
    func activeEssentialTabs(for profileId: UUID?) -> [Tab] {
        guard let profileId else { return [] }
        return activeShortcutTabs(role: .essential).filter { tab in
            guard let shortcutId = tab.shortcutPinId,
                  let pin = shortcutPin(by: shortcutId) else { return false }
            return pin.profileId == profileId
        }
    }

    @discardableResult
    func convertShortcutPinToRegularTab(_ pin: ShortcutPin, in targetSpaceId: UUID, at targetIndex: Int? = nil) -> Bool {
        withStructuralUpdateTransaction {
            _ = insertRegularTabFromShortcut(pin, into: targetSpaceId, at: targetIndex)
            removeShortcutPinFromContainers(pin)
            scheduleStructuralPersistence()
            return true
        }
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
        withStructuralUpdateTransaction {
            let pin = makeShortcutPin(
                from: tab,
                role: role,
                profileId: profileId,
                spaceId: spaceId,
                folderId: folderId,
                index: targetIndex
            )
            guard let insertedPin = insertShortcutPin(
                pin,
                at: targetIndex,
                openTargetFolder: openTargetFolder
            ) else { return nil }

            if !convertDisplayedTabToShortcutLiveInstances(
                tab,
                pin: insertedPin,
                preferredWindowId: preferredWindowId
            ) {
                removeTab(tab.id)
            }
            scheduleStructuralPersistence()
            return insertedPin
        }
    }

    @discardableResult
    func handleShortcutDragOperation(_ pin: ShortcutPin, operation: DragOperation) -> Bool {
        withStructuralUpdateTransaction {
            switch (operation.fromContainer, operation.toContainer) {
            case (.essentials, .essentials):
                return reorderEssential(pin, to: operation.toIndex)

            case (.essentials, .spacePinned(let targetSpaceId)):
                return moveShortcutPin(
                    pin,
                    to: .spacePinned,
                    profileId: nil,
                    spaceId: targetSpaceId,
                    folderId: nil,
                    index: operation.toIndex
                ) != nil

            case (.essentials, .folder(let targetFolderId)):
                guard let targetSpaceId = folderSpaceId(for: targetFolderId) else { return false }
                return moveShortcutPin(
                    pin,
                    to: .spacePinned,
                    profileId: nil,
                    spaceId: targetSpaceId,
                    folderId: targetFolderId,
                    index: operation.toIndex,
                    openTargetFolder: false
                ) != nil

            case (.essentials, .spaceRegular(let targetSpaceId)):
                return convertShortcutPinToRegularTab(pin, in: targetSpaceId, at: operation.toIndex)

            case (.spacePinned, .essentials),
                 (.folder, .essentials):
                guard let currentProfileId = resolvedEssentialsProfileId(for: operation) else { return false }
                return moveShortcutPin(
                    pin,
                    to: .essential,
                    profileId: currentProfileId,
                    spaceId: nil,
                    folderId: nil,
                    index: operation.toIndex
                ) != nil

            case (.spacePinned, .spacePinned(let targetSpaceId)):
                return moveShortcutPin(
                    pin,
                    to: .spacePinned,
                    profileId: nil,
                    spaceId: targetSpaceId,
                    folderId: nil,
                    index: operation.toIndex
                ) != nil

            case (.spacePinned, .folder(let targetFolderId)),
                 (.folder, .folder(let targetFolderId)):
                guard let targetSpaceId = folderSpaceId(for: targetFolderId) else { return false }
                return moveShortcutPin(
                    pin,
                    to: .spacePinned,
                    profileId: nil,
                    spaceId: targetSpaceId,
                    folderId: targetFolderId,
                    index: operation.toIndex,
                    openTargetFolder: false
                ) != nil

            case (.folder, .spacePinned(let targetSpaceId)):
                return moveShortcutPin(
                    pin,
                    to: .spacePinned,
                    profileId: nil,
                    spaceId: targetSpaceId,
                    folderId: nil,
                    index: operation.toIndex
                ) != nil

            case (.spacePinned, .spaceRegular(let targetSpaceId)),
                 (.folder, .spaceRegular(let targetSpaceId)):
                removeShortcutPinFromContainers(pin)
                _ = insertRegularTabFromShortcut(pin, into: targetSpaceId, at: operation.toIndex)
                scheduleStructuralPersistence()
                return true

            case (.spaceRegular, _),
                 (.none, _),
                 (_, .none):
                return false
            }
        }
    }
}
