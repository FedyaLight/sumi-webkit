import AppKit
import Foundation

@MainActor
final class TabFolderTabPlacementTransaction {
    private let structuralLookup: TabStructuralLookupCoordinator
    private let targets: TabFolderShortcutPlacementTargetQuery
    private let folderOpenState: TabFolderOpenStateService
    private let shortcutPlacement: ShortcutPinPlacementCommandService
    private let shortcutConversion: RegularTabShortcutConversionCommand

    init(
        structuralLookup: TabStructuralLookupCoordinator,
        targets: TabFolderShortcutPlacementTargetQuery,
        folderOpenState: TabFolderOpenStateService,
        shortcutPlacement: ShortcutPinPlacementCommandService,
        shortcutConversion: RegularTabShortcutConversionCommand
    ) {
        self.structuralLookup = structuralLookup
        self.targets = targets
        self.folderOpenState = folderOpenState
        self.shortcutPlacement = shortcutPlacement
        self.shortcutConversion = shortcutConversion
    }

    func moveTabToFolder(_ tab: Tab, folderID: UUID) {
        structuralLookup.withTransaction {
            guard let target = targets.target(for: folderID, moving: tab) else {
                return
            }
            folderOpenState.openFolderIfNeeded(target.folderID)
            if let pin = target.sourcePin {
                _ = shortcutPlacement.move(
                    pin,
                    to: .spacePinned,
                    profileId: nil,
                    spaceId: target.spaceID,
                    folderId: target.folderID,
                    index: target.insertionIndex,
                    openTargetFolder: true
                )
                return
            }
            _ = shortcutConversion.convert(
                tab,
                destination: TabShortcutPinDestination(
                    role: .spacePinned,
                    profileId: nil,
                    spaceId: target.spaceID,
                    folderId: target.folderID,
                    index: target.insertionIndex,
                    opensFolder: true
                ),
                preferredWindowId: nil
            )
        }
    }
}
