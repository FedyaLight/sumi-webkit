//
//  SpacePinnedListView.swift
//  Sumi
//

import SumiDomain
import SwiftUI

typealias SpacePinnedListItem = SplitGroupVisualListItem

enum SpacePinnedDisclosureItem: Hashable {
    case pinned(SpacePinnedListItem)
    case nestedSticky(UUID)
}

private struct SpacePinnedContentDisplayEntry: Identifiable {
    let item: SpacePinnedDisclosureItem
    let dropIndex: Int
    var id: SpacePinnedDisclosureItem { item }
}

struct SpacePinnedDisclosureProjection {
    static func items(
        isCollapsed: Bool,
        pinnedItems: [SpacePinnedListItem],
        stickyItemIDs: [UUID],
        knownNestedItemIDs: Set<UUID>
    ) -> [SpacePinnedDisclosureItem] {
        guard isCollapsed else {
            return pinnedItems.map(SpacePinnedDisclosureItem.pinned)
        }

        return stickyItemIDs.compactMap { itemID in
            if let item = pinnedItems.first(where: { $0.id == itemID }) {
                return .pinned(item)
            }
            return knownNestedItemIDs.contains(itemID)
                ? .nestedSticky(itemID)
                : nil
        }
    }
}

/// Renders and reorders the top-level saved folders, shortcuts, and split groups.
struct SpacePinnedListView: View {
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
    let isCollapsed: Bool
    let pinnedItems: [SpacePinnedListItem]
    let stickyItemIDs: [UUID]
    let dragSnapshot: SpacePinnedDragSnapshot
    let disclosureAnimation: Animation?
    let contentMutationAnimation: Animation?
    let actionOwner: SpacePinnedActionOwner

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sidebarWindowSelectionSnapshot) private var sidebarSelection

    private var topLevelPins: [ShortcutPin] {
        windowState.isIncognito ? [] : inventory.topLevelPins
    }

    private var topLevelFolders: [TabFolder] {
        windowState.isIncognito ? [] : inventory.topLevelFolders
    }

    private var knownNestedItemIDs: Set<UUID> {
        Set(stickyItemIDs.filter { itemID in
            inventory.pin(id: itemID) != nil
                || inventory.splitGroup(id: itemID) != nil
        })
    }

    private var disclosureItems: [SpacePinnedDisclosureItem] {
        SpacePinnedDisclosureProjection.items(
            isCollapsed: isCollapsed,
            pinnedItems: pinnedItems,
            stickyItemIDs: stickyItemIDs,
            knownNestedItemIDs: knownNestedItemIDs
        )
    }

    private var splitPairingMemberIDsByDisclosureRow: [[SplitMemberID]] {
        disclosureItems.map { item in
            switch item {
            case .pinned(.shortcut(let pinID)):
                return [.shortcutPin(pinID)]
            case .pinned(.splitGroup(let groupID)):
                return inventory.splitGroup(id: groupID)?.memberIDs ?? []
            case .pinned(.folder), .nestedSticky:
                return []
            }
        }
    }

    private var disclosureTarget: SidebarDisclosureTarget<SpacePinnedDisclosureItem> {
        SidebarDisclosureTarget(
            isRevealed: !isCollapsed,
            items: disclosureItems,
            topPadding: isCollapsed && disclosureItems.isEmpty
                ? collapsedEmptyTargetHeight
                : SidebarInsertionGuide.visualCenterY
        )
    }

    private var collapsedEmptyTargetHeight: CGFloat {
        isInteractive && dragSnapshot.isHoveringEmptySection
            ? SidebarRowLayout.rowHeight
            : 6
    }

    /// Shortcut and split rows are a gapless fixed-height stack. Folders and
    /// collapsed sticky projections keep the exact per-item measured path.
    private var usesUniformDropGeometry: Bool {
        !isCollapsed && !pinnedItems.contains { item in
            if case .folder = item { return true }
            return false
        }
    }

    private func elevatedFolderIDs(
        selectionSnapshot: SidebarWindowSelectionSnapshot
    ) -> Set<UUID> {
        SpaceElevatedFolderOwner(
            inventory: inventory,
            selection: selection,
            windowState: windowState,
            selectionSnapshot: selectionSnapshot
        ).elevatedFolderIds
    }

    private func contentDisplayEntries(
        from items: [SpacePinnedDisclosureItem]
    ) -> [SpacePinnedContentDisplayEntry] {
        items.map { item in
            let dropIndex: Int
            switch item {
            case .pinned(let pinnedItem):
                dropIndex = pinnedItems.firstIndex(of: pinnedItem) ?? 0
            case .nestedSticky:
                dropIndex = 0
            }
            return SpacePinnedContentDisplayEntry(
                item: item,
                dropIndex: dropIndex
            )
        }
    }

    var body: some View {
        let selectionSnapshot = sidebarSelection
        let elevatedFolderIDs = elevatedFolderIDs(
            selectionSnapshot: selectionSnapshot
        )
        let foldersByID = Dictionary(uniqueKeysWithValues: topLevelFolders.map { ($0.id, $0) })
        let pinsByID = Dictionary(uniqueKeysWithValues: topLevelPins.map { ($0.id, $0) })

        SidebarDisclosureHost(
            target: disclosureTarget,
            disclosureAnimation: disclosureAnimation,
            layoutAnimation: contentMutationAnimation
        ) { disclosurePresentation, reportsGeometry in
            let displayEntries = contentDisplayEntries(
                from: disclosurePresentation.items
            )
            // Disclosure layout owns drop-geometry readiness, not pointer
            // eligibility. Existing rows remain interactive while their
            // presentation changes, matching a stable browser tab element.
            let rowIsInteractive = isInteractive
            let reportsDropGeometry = isInteractive && reportsGeometry

            SidebarDisclosureTrackLayout(
                progress: disclosurePresentation.progress,
                sourceOrder: disclosurePresentation.sourceOrder,
                destinationOrder: disclosurePresentation.destinationOrder,
                sourceTopPadding: disclosurePresentation.sourceTopPadding,
                sourceBottomPadding: disclosurePresentation.sourceBottomPadding,
                destinationTopPadding: disclosurePresentation.destinationTopPadding,
                destinationBottomPadding: disclosurePresentation.destinationBottomPadding,
                itemSpacing: SidebarRowLayout.rowGap
            ) {
                ForEach(displayEntries) { entry in
                    VStack(spacing: 0) {
                        switch entry.item {
                        case .pinned(let item):
                            switch item {
                            case .folder(let folderID):
                                if let folder = foldersByID[folderID],
                                   let presentation = inventory.folderPresentation(id: folderID) {
                                    SpacePinnedFolderEntryView(
                                        folder: folder,
                                        presentation: presentation,
                                        space: space,
                                        inventory: inventory,
                                        selection: selection,
                                        pinProjection: pinProjection,
                                        pinCommands: pinCommands,
                                        pinExecution: pinExecution,
                                        folderCommands: folderCommands,
                                        spaceLifecycle: spaceLifecycle,
                                        browserContext: browserContext,
                                        elevatedFolderIDs: elevatedFolderIDs,
                                        topLevelIndex: entry.dropIndex,
                                        geometryGeneration: dragSnapshot.geometryGeneration,
                                        dragSnapshot: dragSnapshot.folderSnapshot,
                                        isInteractive: rowIsInteractive,
                                        reportsDropGeometry: reportsDropGeometry
                                            && !usesUniformDropGeometry
                                    )
                                    .opacity(itemOpacity(folderID))
                                }
                            case .shortcut(let pinID):
                                if let pin = pinsByID[pinID] {
                                    shortcutEntry(
                                        pin,
                                        topLevelIndex: entry.dropIndex,
                                        selectionSnapshot: selectionSnapshot,
                                        isInteractive: rowIsInteractive
                                    )
                                }
                            case .splitGroup(let groupID):
                                if let group = inventory.splitGroup(id: groupID) {
                                    SpacePinnedSplitGroupEntryView(
                                        group: group,
                                        items: SplitGroupSidebarModel.items(
                                            for: group,
                                            inventory: inventory,
                                            selection: selection,
                                            windowState: windowState
                                        ),
                                        space: space,
                                        browserContext: browserContext,
                                        isInteractive: rowIsInteractive,
                                        topLevelIndex: entry.dropIndex,
                                        geometryGeneration: dragSnapshot.geometryGeneration,
                                        dragSnapshot: dragSnapshot.folderSnapshot,
                                        reportsDropGeometry: reportsDropGeometry
                                            && !usesUniformDropGeometry
                                    )
                                    .opacity(itemOpacity(groupID))
                                }
                            }
                        case .nestedSticky(let itemID):
                            SpaceNestedPinnedStickyEntryView(
                                space: space,
                                inventory: inventory,
                                selection: selection,
                                pinProjection: pinProjection,
                                pinCommands: pinCommands,
                                pinExecution: pinExecution,
                                folderCommands: folderCommands,
                                spaceLifecycle: spaceLifecycle,
                                browserContext: browserContext,
                                isInteractive: rowIsInteractive,
                                itemID: itemID,
                                dragSnapshot: dragSnapshot,
                                contentMutationAnimation: contentMutationAnimation
                            )
                        }
                    }
                    .opacity(
                        disclosurePresentation.crossfadeOpacity(
                            for: entry.item
                        )
                    )
                    .zIndex(
                        displayEntryZIndex(
                            entry,
                            selectionSnapshot: selectionSnapshot,
                            elevatedFolderIDs: elevatedFolderIDs
                        )
                    )
                    .sidebarScrollTarget(scrollTargetID(for: entry.item))
                }
            }
            .clipped()
            .frame(maxWidth: .infinity, alignment: .leading)
            .sidebarPinnedListHitGeometry(
                for: space.id,
                rowCount: disclosureItems.count,
                splitPairingMemberIDsByRow:
                    splitPairingMemberIDsByDisclosureRow,
                leadingInset: disclosureTarget.topPadding,
                generation: dragSnapshot.geometryGeneration,
                isEnabled: reportsDropGeometry && usesUniformDropGeometry
            )
            .sidebarSectionGeometry(
                for: .spacePinned,
                spaceId: space.id,
                generation: dragSnapshot.geometryGeneration,
                isEnabled: reportsDropGeometry
            )
        }
    }

    private func scrollTargetID(
        for item: SpacePinnedDisclosureItem
    ) -> SidebarScrollTargetID {
        switch item {
        case .pinned(.folder(let folderID)):
            return .folder(folderID)
        case .pinned(.shortcut(let pinID)):
            return .launcher(pinID)
        case .pinned(.splitGroup(let groupID)):
            return .splitGroup(groupID)
        case .nestedSticky(let itemID):
            return inventory.pin(id: itemID) != nil
                ? .launcher(itemID)
                : .splitGroup(itemID)
        }
    }

    private func shortcutEntry(
        _ pin: ShortcutPin,
        topLevelIndex: Int,
        selectionSnapshot: SidebarWindowSelectionSnapshot,
        isInteractive: Bool
    ) -> SpacePinnedShortcutEntryView {
        return SpacePinnedShortcutEntryView(
            pin: pin,
            liveTab: selection.liveTab(for: pin.id, in: windowState),
            faviconPartition: pinProjection.faviconPartition(
                for: pin,
                currentSpaceID: windowState.currentSpaceId
            ),
            faviconImageReader: browserContext.faviconImageReader,
            runtimeAffordance: selection.runtimeAffordance(
                for: pin,
                in: windowState,
                selection: selectionSnapshot
            ),
            spaceID: space.id,
            isInteractive: isInteractive,
            opacity: itemOpacity(pin.id),
            topLevelIndex: topLevelIndex,
            geometryGeneration: dragSnapshot.geometryGeneration,
            reportsDropGeometry: isInteractive && !usesUniformDropGeometry,
            projectedSplitTarget: dragSnapshot.splitPairingTarget?
                .projectedTarget(for: .shortcutPin(pin.id)),
            actionOwner: actionOwner
        )
    }

    private func displayEntryZIndex(
        _ entry: SpacePinnedContentDisplayEntry,
        selectionSnapshot: SidebarWindowSelectionSnapshot,
        elevatedFolderIDs: Set<UUID>
    ) -> Double {
        guard case .pinned(let item) = entry.item else { return 0 }
        return SidebarSelectionElevation.zIndex(
            isElevated: itemIsElevated(
                item,
                selectionSnapshot: selectionSnapshot,
                elevatedFolderIDs: elevatedFolderIDs
            )
        )
    }

    private func itemIsElevated(
        _ item: SpacePinnedListItem,
        selectionSnapshot: SidebarWindowSelectionSnapshot,
        elevatedFolderIDs: Set<UUID>
    ) -> Bool {
        switch item {
        case .folder(let folderID):
            return elevatedFolderIDs.contains(folderID)
        case .shortcut(let pinID):
            guard let pin = topLevelPins.first(where: { $0.id == pinID }) else { return false }
            return selection.isShortcutSelected(
                pin,
                in: windowState,
                selection: selectionSnapshot
            )
        case .splitGroup(let groupID):
            guard let group = inventory.splitGroup(id: groupID) else { return false }
            return selection.isSplitGroupSelected(
                group,
                in: windowState,
                selection: selectionSnapshot
            )
        }
    }

    private func itemOpacity(_ itemID: UUID) -> Double {
        dragSnapshot.isDragging && dragSnapshot.activeDragItemID == itemID
            ? SidebarDragSourceDim.opacity
            : 1
    }

}
