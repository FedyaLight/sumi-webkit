import SumiDomain
import SwiftUI

/// Renders one sticky saved row that originated inside a folder while the Space
/// root is collapsed. The root list owns its stable identity and layout slot.
struct SpaceNestedPinnedStickyEntryView: View {
    private static let nestingIndent: CGFloat = 14

    let space: Space
    let inventory: SidebarSpaceInventorySnapshot
    let selection: SidebarWindowSelectionQuery
    let pinProjection: SidebarPinFolderProjection
    let pinCommands: SidebarPinCommands
    let pinExecution: SidebarPinExecutionCommands
    let folderCommands: SidebarFolderCommands
    let spaceLifecycle: SidebarSpaceLifecycle
    let browserContext: SidebarBrowserContext
    let isInteractive: Bool
    let itemID: UUID
    let dragSnapshot: SpacePinnedDragSnapshot
    let contentMutationAnimation: Animation?

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(WindowRegistry.self) private var windowRegistry
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.sidebarWindowSelectionSnapshot) private var sidebarSelection

    @ViewBuilder
    var body: some View {
        if let pin = inventory.pin(id: itemID),
           let folderID = pin.folderId,
           let folder = inventory.folder(id: folderID) {
            nestedShortcutEntry(pin, folder: folder)
                .padding(.leading, indentation(for: folder))
        } else if let group = inventory.splitGroup(id: itemID),
                  let folderID = owningFolderID(of: group),
                  let folder = inventory.folder(id: folderID) {
            nestedSplitEntry(group)
                .padding(.leading, indentation(for: folder))
                .sidebarDropContainmentBackdrop(
                    isVisible: dragSnapshot.folderSnapshot
                        .isExistingSplitGroupTargeted(
                            memberIDs: group.memberIDs
                        )
                )
        }
    }

    private func nestedShortcutEntry(
        _ pin: ShortcutPin,
        folder: TabFolder
    ) -> TabFolderShortcutEntryView {
        let mutationActions = folderMutationActions
        let contextOwner = folderContextOwner(
            folder: folder,
            mutationActions: mutationActions
        )
        let presentationOwner = shortcutPresentationOwner
        return TabFolderShortcutEntryView(
            pin: pin,
            liveTab: selection.liveTab(for: pin.id, in: windowState),
            faviconPartition: presentationOwner.faviconPartition(for: pin),
            faviconImageReader: browserContext.faviconImageReader,
            runtimeAffordance: presentationOwner.runtimeAffordance(for: pin),
            folderID: folder.id,
            isInteractive: isInteractive,
            opacity: itemOpacity(pin.id),
            projectedSplitTarget:
                dragSnapshot.splitPairingTarget?
                    .projectedTarget(for: .shortcutPin(pin.id)),
            contextMenuActionOwner: contextOwner,
            mutationActions: mutationActions
        )
    }

    private func nestedSplitEntry(_ group: SplitGroup) -> TabFolderSplitGroupEntryView {
        TabFolderSplitGroupEntryView(
            group: group,
            items: SplitGroupSidebarModel.items(
                for: group,
                inventory: inventory,
                selection: selection,
                windowState: windowState
            ),
            space: space,
            browserContext: browserContext,
            isInteractive: isInteractive
        )
    }

    private var shortcutPresentationOwner: TabFolderShortcutPresentationOwner {
        TabFolderShortcutPresentationOwner(
            pinProjection: pinProjection,
            selection: selection,
            windowState: windowState,
            selectionSnapshot: sidebarSelection
        )
    }

    private var folderMutationActions: TabFolderMutationActions {
        TabFolderMutationActions(
            browserContext: browserContext,
            pinExecution: pinExecution,
            folderCommands: folderCommands,
            windowState: windowState,
            windowRegistry: windowRegistry,
            themeContext: themeContext,
            space: space,
            folderLayoutAnimation: contentMutationAnimation
        )
    }

    private func folderContextOwner(
        folder: TabFolder,
        mutationActions: TabFolderMutationActions
    ) -> TabFolderContextMenuActionOwner {
        TabFolderContextMenuActionOwner(
            folder: folder,
            space: space,
            childFoldersByParentId: inventory.childFoldersByParentID,
            folderPinsByFolderId: inventory.folderPinsByFolderID,
            browserContext: browserContext,
            inventory: inventory,
            selection: selection,
            pinProjection: pinProjection,
            pinCommands: pinCommands,
            pinExecution: pinExecution,
            folderCommands: folderCommands,
            spaceLifecycle: spaceLifecycle,
            windowState: windowState,
            themeContext: themeContext,
            folderLayoutAnimation: contentMutationAnimation,
            mutationActions: mutationActions
        )
    }

    private func itemOpacity(_ itemID: UUID) -> Double {
        dragSnapshot.isDragging && dragSnapshot.activeDragItemID == itemID
            ? SidebarDragSourceDim.opacity
            : 1
    }

    private func owningFolderID(of group: SplitGroup) -> UUID? {
        guard case .shortcutSidebar(_, _, let folderID, _) = group.container else {
            return nil
        }
        return folderID
    }

    private func indentation(for folder: TabFolder) -> CGFloat {
        var depth = 1
        var currentID = folder.parentFolderId
        var visited = Set<UUID>()
        while let folderID = currentID, visited.insert(folderID).inserted {
            depth += 1
            currentID = inventory.folder(id: folderID)?.parentFolderId
        }
        return CGFloat(depth) * Self.nestingIndent
    }
}
