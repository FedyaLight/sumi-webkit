import Foundation
import SumiDomain

@MainActor
final class ShortcutPinStoreOwner {
    private let placements: ShortcutPinPlacementResolver
    private let mutations: ShortcutPinCatalogMutationTransaction
    private let folderOpenState: TabFolderOpenStateService

    init(
        placements: ShortcutPinPlacementResolver,
        mutations: ShortcutPinCatalogMutationTransaction,
        folderOpenState: TabFolderOpenStateService
    ) {
        self.placements = placements
        self.mutations = mutations
        self.folderOpenState = folderOpenState
    }

    @discardableResult
    func insert(
        _ pin: ShortcutPin,
        at targetIndex: Int,
        openTargetFolder: Bool = true
    ) -> ShortcutPin? {
        guard placements.previewInsert(pin, at: targetIndex) != nil,
              let inserted = mutations.insert(pin, at: targetIndex) else {
            return nil
        }
        openFolderIfNeeded(for: inserted, enabled: openTargetFolder)
        return inserted
    }

    func previewInsert(
        _ pin: ShortcutPin,
        at targetIndex: Int
    ) -> ShortcutPin? {
        placements.previewInsert(pin, at: targetIndex)
    }

    @discardableResult
    func move(
        _ pin: ShortcutPin,
        to role: ShortcutPinRole,
        profileId: UUID?,
        spaceId: UUID?,
        folderId: UUID?,
        index: Int,
        openTargetFolder: Bool = true
    ) -> ShortcutPin? {
        moveResolved(
            pin,
            to: role,
            profileId: profileId,
            spaceId: spaceId,
            folderId: folderId,
            index: index,
            openTargetFolder: openTargetFolder,
            applying: nil
        )
    }

    @discardableResult
    func move(
        _ pin: ShortcutPin,
        to role: ShortcutPinRole,
        profileId: UUID?,
        spaceId: UUID?,
        folderId: UUID?,
        index: Int,
        openTargetFolder: Bool = true,
        applying: @escaping (ShortcutPin) -> Bool
    ) -> ShortcutPin? {
        moveResolved(
            pin,
            to: role,
            profileId: profileId,
            spaceId: spaceId,
            folderId: folderId,
            index: index,
            openTargetFolder: openTargetFolder,
            applying: applying
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
        placements.previewMove(
            pin,
            to: role,
            profileId: profileId,
            spaceId: spaceId,
            folderId: folderId,
            proposedIndex: proposedIndex
        )
    }

    func canMove(
        _ pin: ShortcutPin,
        to role: ShortcutPinRole,
        profileId: UUID?,
        spaceId: UUID?,
        folderId: UUID?
    ) -> Bool {
        previewMove(
            pin,
            to: role,
            profileId: profileId,
            spaceId: spaceId,
            folderId: folderId,
            proposedIndex: pin.index
        ) != nil
    }

    func removeFromContainers(_ pin: ShortcutPin) {
        mutations.removeFromContainers(pin)
    }

    private func moveResolved(
        _ pin: ShortcutPin,
        to role: ShortcutPinRole,
        profileId: UUID?,
        spaceId: UUID?,
        folderId: UUID?,
        index: Int,
        openTargetFolder: Bool,
        applying: ((ShortcutPin) -> Bool)?
    ) -> ShortcutPin? {
        guard let source = placements.canonicalSource(matching: pin),
              let target = placements.previewMove(
                  source,
                  to: role,
                  profileId: profileId,
                  spaceId: spaceId,
                  folderId: folderId,
                  proposedIndex: index
              ), let inserted = mutations.move(
                  source: source,
                  target: target,
                  applying: applying
              ) else { return nil }
        openFolderIfNeeded(for: inserted, enabled: openTargetFolder)
        return inserted
    }

    private func openFolderIfNeeded(
        for pin: ShortcutPin,
        enabled: Bool
    ) {
        guard enabled, let folderID = pin.folderId else { return }
        folderOpenState.openFolderIfNeeded(folderID)
    }
}

extension ProfileReferenceAdmissionLedger {
    func admitShortcutPinReferences(
        for pins: [ShortcutPin]
    ) -> [ProfileReferenceAdmissionReceipt]? {
        let profileIDs = Set(pins.flatMap { pin in
            [pin.profileId, pin.executionProfileId].compactMap { $0 }
        })
        let receipts = profileIDs.compactMap(admitReference(to:))
        return receipts.count == profileIDs.count ? receipts : nil
    }

    func validate(_ receipts: [ProfileReferenceAdmissionReceipt]) -> Bool {
        receipts.allSatisfy(validate(_:))
    }
}
