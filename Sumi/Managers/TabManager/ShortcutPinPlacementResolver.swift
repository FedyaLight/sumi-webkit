import Foundation
import SumiDomain

@MainActor
final class ShortcutPinPlacementResolver {
    private let destinationValidator: ShortcutPinDestinationValidator
    private let pins: ShortcutPinCollectionStateOwner
    private let spacePinnedStructure: SpacePinnedStructureOwner

    init(
        destinationValidator: ShortcutPinDestinationValidator,
        pins: ShortcutPinCollectionStateOwner,
        spacePinnedStructure: SpacePinnedStructureOwner
    ) {
        self.destinationValidator = destinationValidator
        self.pins = pins
        self.spacePinnedStructure = spacePinnedStructure
    }

    func previewInsert(
        _ pin: ShortcutPin,
        at targetIndex: Int
    ) -> ShortcutPin? {
        guard pins.shortcutPin(by: pin.id) == nil,
              destinationValidator.accepts(
            role: pin.role,
            spaceId: pin.spaceId,
            folderId: pin.folderId
        ) else { return nil }

        let destinationCount: Int
        switch pin.role {
        case .essential:
            guard let profileID = pin.profileId else { return nil }
            destinationCount = pins.essentialPins(for: profileID)
                .filter { $0.id != pin.id }
                .count
            guard destinationCount
                    < EssentialsShortcutPlacementOwner.CapacityPolicy
                        .maxStoredMembers
            else { return nil }
        case .spacePinned:
            guard let spaceID = pin.spaceId else { return nil }
            if let folderID = pin.folderId {
                destinationCount = pins.spacePinnedPins(for: spaceID)
                    .filter { $0.folderId == folderID && $0.id != pin.id }
                    .count
            } else {
                destinationCount = spacePinnedStructure
                    .topLevelSpacePinnedItems(for: spaceID).count
            }
        }
        return pin.refreshed(
            index: max(0, min(targetIndex, destinationCount))
        )
    }

    func previewMove(
        _ pin: ShortcutPin,
        to role: ShortcutPinRole,
        profileId: UUID?,
        spaceId: UUID?,
        folderId: UUID?,
        proposedIndex: Int
    ) -> ShortcutPin? {
        guard let source = canonicalSource(matching: pin),
              acceptsMove(
                  source,
                  to: role,
                  profileId: profileId,
                  spaceId: spaceId,
                  folderId: folderId
              ) else { return nil }
        return clone(
            source,
            role: role,
            profileId: profileId,
            spaceId: spaceId,
            folderId: folderId,
            index: adjustedMoveIndex(
                source,
                to: role,
                profileId: profileId,
                spaceId: spaceId,
                folderId: folderId,
                proposedIndex: proposedIndex
            )
        )
    }

    func canonicalSource(matching pin: ShortcutPin) -> ShortcutPin? {
        guard let stored = pins.shortcutPin(by: pin.id), stored === pin else {
            return nil
        }
        switch pin.role {
        case .essential:
            guard let profileID = pin.profileId,
                  pins.essentialPins(for: profileID).contains(where: {
                      $0 === pin
                  }) else { return nil }
        case .spacePinned:
            guard let spaceID = pin.spaceId,
                  pins.spacePinnedPins(for: spaceID).contains(where: {
                      $0 === pin && $0.folderId == pin.folderId
                  }) else { return nil }
        }
        return pin
    }

    private func acceptsMove(
        _ pin: ShortcutPin,
        to role: ShortcutPinRole,
        profileId: UUID?,
        spaceId: UUID?,
        folderId: UUID?
    ) -> Bool {
        guard destinationValidator.accepts(
            role: role,
            spaceId: spaceId,
            folderId: folderId
        ) else { return false }
        switch role {
        case .essential:
            guard let profileId else { return false }
            return pins.essentialPins(for: profileId)
                .filter { $0.id != pin.id }
                .count < EssentialsShortcutPlacementOwner.CapacityPolicy
                    .maxStoredMembers
        case .spacePinned:
            return spaceId != nil
        }
    }

    private func adjustedMoveIndex(
        _ pin: ShortcutPin,
        to role: ShortcutPinRole,
        profileId: UUID?,
        spaceId: UUID?,
        folderId: UUID?,
        proposedIndex: Int
    ) -> Int {
        guard pin.role == role,
              pin.profileId == profileId,
              pin.spaceId == spaceId,
              pin.folderId == folderId else {
            return proposedIndex
        }

        let currentIndex: Int?
        switch role {
        case .essential:
            guard let profileId else { return proposedIndex }
            currentIndex = pins.essentialPins(for: profileId)
                .firstIndex(where: { $0 === pin })
        case .spacePinned:
            guard let spaceId else { return proposedIndex }
            if folderId == nil {
                currentIndex = spacePinnedStructure
                    .topLevelSpacePinnedItems(for: spaceId).firstIndex {
                        if case .shortcut(let existing) = $0 {
                            return existing === pin
                        }
                        return false
                    }
            } else {
                currentIndex = pins.spacePinnedPins(for: spaceId)
                    .filter { $0.folderId == folderId }
                    .firstIndex(where: { $0 === pin })
            }
        }
        guard let currentIndex else { return proposedIndex }
        return spacePinnedStructure.adjustedSameContainerInsertionIndex(
            currentIndex: currentIndex,
            proposedIndex: proposedIndex
        )
    }

    private func clone(
        _ pin: ShortcutPin,
        role: ShortcutPinRole,
        profileId: UUID?,
        spaceId: UUID?,
        folderId: UUID?,
        index: Int
    ) -> ShortcutPin {
        ShortcutPin(
            id: pin.id,
            role: role,
            profileId: profileId,
            executionProfileId: pin.executionProfileId,
            spaceId: spaceId,
            index: index,
            folderId: folderId,
            launchURL: pin.launchURL,
            title: pin.title,
            iconAsset: pin.iconAsset
        )
    }
}
