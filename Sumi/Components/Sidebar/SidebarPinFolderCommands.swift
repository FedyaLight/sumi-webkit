import AppKit
import Foundation

/// Semantic mutation boundary for saved shortcuts and folders. Destination
/// indices and target ownership are re-read from canonical stores at command
/// time; callers never commit from rendered sidebar arrays.
@MainActor
final class SidebarPinFolderCommands {
    private let runtimeIsAlive: @MainActor () -> Bool
    private let windows: SidebarWindowIdentityQuery
    private let pins: ShortcutPinCollectionStateOwner
    private let folders: TabFolderCollectionStateOwner
    private let structure: SpacePinnedStructureOwner
    private let shortcutCommands: ShortcutPinCommandOwner
    private let folderCommands: TabFolderMutationOwner
    private let folderOpenState: TabFolderOpenStateService
    private let materializer: ShortcutTabMaterializer
    private let profileAssignments: ShortcutExecutionProfileAssignmentService

    init(
        runtimeIsAlive: @escaping @MainActor () -> Bool,
        windows: SidebarWindowIdentityQuery,
        pins: ShortcutPinCollectionStateOwner,
        folders: TabFolderCollectionStateOwner,
        structure: SpacePinnedStructureOwner,
        shortcutCommands: ShortcutPinCommandOwner,
        folderCommands: TabFolderMutationOwner,
        folderOpenState: TabFolderOpenStateService,
        materializer: ShortcutTabMaterializer,
        profileAssignments: ShortcutExecutionProfileAssignmentService
    ) {
        self.runtimeIsAlive = runtimeIsAlive
        self.windows = windows
        self.pins = pins
        self.folders = folders
        self.structure = structure
        self.shortcutCommands = shortcutCommands
        self.folderCommands = folderCommands
        self.folderOpenState = folderOpenState
        self.materializer = materializer
        self.profileAssignments = profileAssignments
    }

    @discardableResult
    func resetToLaunchURL(
        _ pin: ShortcutPin,
        in windowState: BrowserWindowState,
        preserveCurrentPage: Bool
    ) -> Bool {
        guard let current = currentPin(pin), windows.contains(windowState) else {
            return false
        }
        return shortcutCommands.resetShortcutPinToLaunchURL(
            current,
            in: windowState,
            preserveCurrentPage: preserveCurrentPage
        ) != nil
    }

    @discardableResult
    func replaceSavedURLWithCurrent(
        _ pin: ShortcutPin,
        in windowState: BrowserWindowState
    ) -> Bool {
        guard let current = currentPin(pin), windows.contains(windowState) else {
            return false
        }
        return shortcutCommands.replaceShortcutPinURLWithCurrent(
            current,
            in: windowState
        ) != nil
    }

    @discardableResult
    func remove(_ pin: ShortcutPin) -> Bool {
        guard let current = currentPin(pin) else { return false }
        shortcutCommands.removeShortcutPin(current)
        return pins.shortcutPin(by: current.id) == nil
    }

    @discardableResult
    func move(
        _ pin: ShortcutPin,
        toFolder folderID: UUID
    ) -> Bool {
        guard let current = currentPin(pin),
              let targetFolder = folders.folder(by: folderID) else {
            return false
        }
        let targetIndex = pins.folderPinnedPins(
            for: folderID,
            in: targetFolder.spaceId
        ).count
        return shortcutCommands.moveShortcutPin(
            current,
            to: .spacePinned,
            profileId: nil,
            spaceId: targetFolder.spaceId,
            folderId: folderID,
            index: targetIndex
        ) != nil
    }

    @discardableResult
    func move(
        _ pin: ShortcutPin,
        toSpace spaceID: UUID
    ) -> Bool {
        guard let current = currentPin(pin) else { return false }
        let targetIndex = structure.topLevelSpacePinnedItems(for: spaceID).count
        return shortcutCommands.moveShortcutPin(
            current,
            to: .spacePinned,
            profileId: nil,
            spaceId: spaceID,
            folderId: nil,
            index: targetIndex
        ) != nil
    }

    @discardableResult
    func assignExecutionProfile(
        _ pin: ShortcutPin,
        profileID: UUID
    ) -> Bool {
        guard let current = currentPin(pin) else { return false }
        return profileAssignments.assign(
            current,
            toExecutionProfile: profileID
        ) != nil
    }

    func recursiveChildCount(
        for folderID: UUID,
        in spaceID: UUID
    ) -> Int? {
        guard runtimeIsAlive(),
              folders.folder(by: folderID)?.spaceId == spaceID else {
            return nil
        }
        return structure.folderRecursiveChildCount(
            for: folderID,
            in: spaceID
        )
    }

    @discardableResult
    func toggleFolder(_ folderID: UUID) -> Bool {
        guard runtimeIsAlive(), folders.folder(by: folderID) != nil else {
            return false
        }
        folderOpenState.toggleFolderOpenState(folderID)
        return true
    }

    @discardableResult
    func deleteFolder(_ folderID: UUID) -> Bool {
        guard runtimeIsAlive(), folders.folder(by: folderID) != nil else {
            return false
        }
        folderCommands.deleteFolder(folderID)
        return true
    }

    @discardableResult
    func ungroupFolder(_ folderID: UUID) -> Bool {
        guard runtimeIsAlive(), folders.folder(by: folderID) != nil else {
            return false
        }
        folderCommands.ungroupFolder(folderID)
        return true
    }

    @discardableResult
    func alphabetizeFolder(_ folderID: UUID, in spaceID: UUID) -> Bool {
        guard runtimeIsAlive(),
              folders.folder(by: folderID)?.spaceId == spaceID else {
            return false
        }
        folderCommands.alphabetizeFolderPins(folderID, in: spaceID)
        return true
    }

    func materialize(
        _ pin: ShortcutPin,
        in windowState: BrowserWindowState,
        currentSpaceID: UUID?
    ) -> Tab? {
        guard let current = currentPin(pin), windows.contains(windowState) else {
            return nil
        }
        return materializer.materialize(
            current,
            in: windowState.id,
            currentSpaceId: currentSpaceID
        )
    }

    private func currentPin(_ pin: ShortcutPin) -> ShortcutPin? {
        guard runtimeIsAlive() else { return nil }
        return pins.shortcutPin(by: pin.id)
    }
}
