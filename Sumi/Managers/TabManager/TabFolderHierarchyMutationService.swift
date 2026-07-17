import AppKit
import Foundation

@MainActor
final class TabFolderHierarchyMutationService {
    private let folders: TabFolderCollectionStateOwner
    private let pins: ShortcutPinCollectionStateOwner
    private let structuralMutations: TabStructuralCollectionMutationOwner
    private let spacePinnedStructure: SpacePinnedStructureOwner
    private let shortcutBindings: ShortcutTabBindingSynchronizer

    init(
        folders: TabFolderCollectionStateOwner,
        pins: ShortcutPinCollectionStateOwner,
        structuralMutations: TabStructuralCollectionMutationOwner,
        spacePinnedStructure: SpacePinnedStructureOwner,
        shortcutBindings: ShortcutTabBindingSynchronizer
    ) {
        self.folders = folders
        self.pins = pins
        self.structuralMutations = structuralMutations
        self.spacePinnedStructure = spacePinnedStructure
        self.shortcutBindings = shortcutBindings
    }

    func childItems(
        in parentFolderID: UUID?,
        spaceID: UUID
    ) -> [TabFolderContainerItem] {
        let childFolders = folders.childFolders(
            of: parentFolderID,
            in: spaceID
        ).map { ($0.index, 0, TabFolderContainerItem.folder($0.id)) }
        let childPins = pins.spacePinnedPins(for: spaceID)
            .filter { $0.folderId == parentFolderID }
            .map { ($0.index, 1, TabFolderContainerItem.shortcut($0.id)) }

        return (childFolders + childPins)
            .sorted { lhs, rhs in
                if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                return lhs.2.id.uuidString < rhs.2.id.uuidString
            }
            .map(\.2)
    }

    func applyChildItems(
        _ items: [TabFolderContainerItem],
        in parentFolderID: UUID?,
        spaceID: UUID
    ) {
        let currentFolders = folders.folders(for: spaceID)
        let folderByID = Dictionary(
            uniqueKeysWithValues: currentFolders.map { ($0.id, $0) }
        )
        let currentPins = pins.spacePinnedPins(for: spaceID)
        let pinByID = Dictionary(
            uniqueKeysWithValues: currentPins.map { ($0.id, $0) }
        )

        var folderPlacements: [UUID: TabFolderPlacement] = [:]
        var touchedPinIDs: Set<UUID> = []
        var rebuiltPins = currentPins
        for (index, item) in items.enumerated() {
            switch item {
            case .folder(let folderID):
                guard let folder = folderByID[folderID] else { continue }
                folderPlacements[folder.id] = TabFolderPlacement(
                    spaceID: spaceID,
                    parentFolderID: parentFolderID,
                    index: index
                )

            case .shortcut(let pinID):
                guard let pin = pinByID[pinID] else { continue }
                touchedPinIDs.insert(pin.id)
                let updated = pin
                    .refreshed(index: index)
                    .moved(toFolderId: parentFolderID)
                if let existingIndex = rebuiltPins.firstIndex(where: {
                    $0 === pin
                }) {
                    rebuiltPins[existingIndex] = updated
                } else {
                    rebuiltPins.append(updated)
                }
            }
        }

        structuralMutations.setFolderPlacements(
            folderPlacements,
            in: currentFolders,
            for: spaceID
        )
        let normalizedPins = spacePinnedStructure
            .normalizedSpacePinnedShortcuts(rebuiltPins)
        structuralMutations.setSpacePinnedShortcuts(
            normalizedPins,
            for: spaceID
        )
        for pinID in touchedPinIDs {
            if let updatedPin = normalizedPins.first(where: {
                $0.id == pinID
            }) {
                shortcutBindings.refreshInstances(for: updatedPin)
            }
        }
    }

    func replaceFolders(_ items: [TabFolder], in spaceID: UUID) {
        structuralMutations.setFolders(items, for: spaceID)
    }

    func appendFolder(_ folder: TabFolder, in spaceID: UUID) {
        var currentFolders = folders.folders(for: spaceID)
        currentFolders.append(folder)
        structuralMutations.setFolders(currentFolders, for: spaceID)
    }

    func replaceSpacePinnedShortcuts(
        _ items: [ShortcutPin],
        in spaceID: UUID
    ) {
        structuralMutations.setSpacePinnedShortcuts(
            spacePinnedStructure.normalizedSpacePinnedShortcuts(items),
            for: spaceID
        )
    }

    func alphabetizePins(in folderID: UUID, spaceID: UUID) -> Bool {
        let folderPins = pins.spacePinnedPins(for: spaceID)
            .filter { $0.folderId == folderID }
            .sorted { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                    == .orderedAscending
            }
        guard folderPins.isEmpty == false else { return false }
        spacePinnedStructure.withSpacePinnedShortcutGroup(
            for: spaceID,
            folderId: folderID
        ) { pins in
            pins = folderPins
        }
        return true
    }

    func isFolder(
        _ folderID: UUID?,
        descendantOf ancestorID: UUID,
        in spaceID: UUID
    ) -> Bool {
        guard let folderID else { return false }
        var currentID: UUID? = folderID
        var seen: Set<UUID> = []
        let currentFolders = folders.folders(for: spaceID)
        while let id = currentID {
            guard seen.insert(id).inserted else { return true }
            guard let folder = currentFolders.first(where: {
                $0.id == id
            }) else {
                return false
            }
            if folder.parentFolderId == ancestorID { return true }
            currentID = folder.parentFolderId
        }
        return false
    }

    func descendantFolderIDs(
        including rootFolderID: UUID,
        in spaceID: UUID
    ) -> Set<UUID> {
        let childrenByParentID = Dictionary(
            grouping: folders.folders(for: spaceID),
            by: \.parentFolderId
        )
        var result: Set<UUID> = []
        var stack = [rootFolderID]
        while let folderID = stack.popLast() {
            guard result.insert(folderID).inserted else { continue }
            stack.append(contentsOf: (childrenByParentID[folderID] ?? []).map(\.id))
        }
        return result
    }
}
