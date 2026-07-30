import Foundation
import SumiDomain
import SwiftUI

typealias SpaceSidebarScene = SidebarListScene<
    SpaceSidebarListElementID,
    SpaceSidebarListElementPayload
>
typealias SpaceSidebarSceneElement = SpaceSidebarScene.Element

struct SpaceSidebarSceneOutput {
    let scene: SpaceSidebarScene
    let structuralItemIDs: [UUID]
}

@MainActor
struct SpaceSidebarInventoryTraversal {
    let structuralItemIDs: [UUID]
    let descendantLeafIDsByFolder: [UUID: [UUID]]
    let visibleFolderIDs: [UUID]

    init(
        inventory: SidebarSpaceInventorySnapshot,
        includesVisibleFolders: Bool,
        isLiveFolder: (UUID) -> Bool
    ) {
        var structuralItemIDs: [UUID] = []
        var descendantLeafIDsByFolder: [UUID: [UUID]] = [:]
        var visibleFolderIDs: [UUID] = []
        var visitedFolders = Set<UUID>()

        func visitFolder(_ folderID: UUID, isVisible: Bool) -> [UUID] {
            guard visitedFolders.insert(folderID).inserted else { return [] }
            structuralItemIDs.append(folderID)
            if isVisible {
                visibleFolderIDs.append(folderID)
            }
            let isExpanded = inventory.folderPresentation(id: folderID)?
                .isExpanded ?? false
            let childrenAreVisible = isVisible
                && isExpanded
                && !isLiveFolder(folderID)
            var leafIDs: [UUID] = []
            for item in inventory.folderItems(for: folderID) {
                switch item {
                case .shortcut(let id), .splitGroup(let id):
                    structuralItemIDs.append(id)
                    leafIDs.append(id)
                case .folder(let childID):
                    leafIDs.append(
                        contentsOf: visitFolder(
                            childID,
                            isVisible: childrenAreVisible
                        )
                    )
                }
            }
            descendantLeafIDsByFolder[folderID] = leafIDs
            return leafIDs
        }

        for item in inventory.topLevelItems {
            switch item {
            case .shortcut(let id), .splitGroup(let id):
                structuralItemIDs.append(id)
            case .folder(let folderID):
                _ = visitFolder(
                    folderID,
                    isVisible: includesVisibleFolders
                )
            }
        }

        self.structuralItemIDs = structuralItemIDs
        self.descendantLeafIDsByFolder = descendantLeafIDsByFolder
        self.visibleFolderIDs = visibleFolderIDs
    }
}

@MainActor
struct SpaceSidebarSceneBuilder {
    let space: Space
    let inventory: SidebarSpaceInventorySnapshot
    let launcherRuntime: SidebarLauncherRuntimeSnapshot
    let selection: SidebarWindowSelectionQuery
    let tabs: [Tab]
    let inventoryTraversal: SpaceSidebarInventoryTraversal
    let windowState: BrowserWindowState
    let hasPersistedTabs: Bool
    let showsNewTab: Bool
    let newTabAtTop: Bool
    let selectionSnapshot: SidebarWindowSelectionSnapshot
    let liveSnapshots: [UUID: SidebarLiveFolderSnapshot]
    let dragSnapshots: SpaceSidebarDragSnapshots
    let isInteractive: Bool
    let hasPinnedContent: Bool
    let isPinnedCollapsed: Bool
    let pinnedStickyItemIDs: [UUID]

    func build() -> SpaceSidebarSceneOutput {
        var elements: [SpaceSidebarSceneElement] = []

        appendPinnedElements(
            descendantLeafIDsByFolder:
                inventoryTraversal.descendantLeafIDsByFolder,
            to: &elements
        )

        let splitGroups = RegularSplitSegmentResolver(
            space: space,
            isInteractive: isInteractive
        ).visibleSplitGroups(
            currentTabs: tabs,
            splitGroup: { inventory.splitGroup(containing: $0) }
        )
        let tabByID = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
        let groupsByID = Dictionary(
            uniqueKeysWithValues: splitGroups.map { ($0.id, $0) }
        )
        let regularRun = SidebarVisualSceneProjection.regularRun(
            tabIDs: tabs.map(\.id),
            groups: splitGroups
        )
        appendBoundary(to: &elements)
        if showsNewTab, newTabAtTop {
            elements.append(newTabElement)
            let gap = regularRun.rows.isEmpty ? 0 : SidebarRowLayout.rowGap
            elements.append(newTabGapElement(extent: gap))
        }

        elements.append(
            .init(
                id: .regularRunStart,
                payload: .regularRunStart,
                targetExtent: 0,
                placement: .regularRunStart
            )
        )
        appendRegularRows(
            regularRun,
            tabByID: tabByID,
            groupsByID: groupsByID,
            to: &elements
        )
        elements.append(
            .init(
                id: .regularRunEnd,
                payload: .regularRunEnd,
                targetExtent: 0,
                placement: .regularRunEnd
            )
        )

        if showsNewTab, !newTabAtTop {
            elements.append(
                newTabGapElement(
                    extent: regularRun.rows.isEmpty
                        ? 0
                        : SidebarRowLayout.rowGap
                )
            )
            elements.append(newTabElement)
        }

        return SpaceSidebarSceneOutput(
            scene: SidebarListScene(elements: elements),
            structuralItemIDs: inventoryTraversal.structuralItemIDs
        )
    }

    private func appendPinnedElements(
        descendantLeafIDsByFolder: [UUID: [UUID]],
        to elements: inout [SpaceSidebarSceneElement]
    ) {
        guard hasPinnedContent else {
            elements.append(
                .init(
                    id: .pinnedTop,
                    payload: .pinnedTop,
                    targetExtent: 0
                )
            )
            return
        }

        let stickyIDs = isPinnedCollapsed ? pinnedStickyItemIDs : []
        let topPadding: CGFloat =
            isPinnedCollapsed && stickyIDs.isEmpty
            ? 6
            : SidebarInsertionGuide.visualCenterY
        elements.append(
            .init(
                id: .pinnedTop,
                payload: .pinnedTop,
                targetExtent: topPadding
            )
        )

        if isPinnedCollapsed {
            appendCollapsedSpaceItems(
                stickyIDs,
                descendantLeafIDsByFolder: descendantLeafIDsByFolder,
                to: &elements
            )
            return
        }

        for (index, item) in inventory.topLevelItems.enumerated() {
            let firstElementIndex = elements.count
            appendTopLevelItem(
                item,
                index: index,
                descendantLeafIDsByFolder: descendantLeafIDsByFolder,
                to: &elements
            )
            if index < inventory.topLevelItems.count - 1,
               elements.count > firstElementIndex {
                let lastIndex = elements.index(before: elements.endIndex)
                elements[lastIndex] = elements[lastIndex]
                    .addingTrailingExtent(SidebarRowLayout.rowGap)
            }
        }
    }

    private func appendCollapsedSpaceItems(
        _ stickyIDs: [UUID],
        descendantLeafIDsByFolder: [UUID: [UUID]],
        to elements: inout [SpaceSidebarSceneElement]
    ) {
        for (position, itemID) in stickyIDs.enumerated() {
            let firstElementIndex = elements.count
            if let topLevelIndex = inventory.topLevelItems.firstIndex(
                where: { $0.id == itemID }
            ) {
                appendTopLevelItem(
                    inventory.topLevelItems[topLevelIndex],
                    index: topLevelIndex,
                    descendantLeafIDsByFolder: descendantLeafIDsByFolder,
                    to: &elements
                )
            } else {
                let id: SpaceSidebarListElementID =
                    inventory.pin(id: itemID) != nil
                    ? .shortcut(itemID)
                    : .splitGroup(itemID)
                elements.append(
                    .init(
                        id: id,
                        payload: .collapsedNestedSticky(itemID),
                        targetExtent: SidebarRowLayout.rowHeight,
                        overflowBleed: SidebarRowLayout.selectionShadowBleed
                    )
                )
            }
            if position < stickyIDs.count - 1,
               elements.count > firstElementIndex {
                let lastIndex = elements.index(before: elements.endIndex)
                elements[lastIndex] = elements[lastIndex]
                    .addingTrailingExtent(SidebarRowLayout.rowGap)
            }
        }
    }

    private func appendTopLevelItem(
        _ item: SidebarPinnedInventoryItem,
        index: Int,
        descendantLeafIDsByFolder: [UUID: [UUID]],
        to elements: inout [SpaceSidebarSceneElement]
    ) {
        switch item {
        case .folder(let folderID):
            guard let folder = inventory.folder(id: folderID) else { return }
            elements.append(
                contentsOf: folderElements(
                    folder,
                    parentFolderID: nil,
                    containerIndex: index,
                    nestingDepth: 0,
                    descendantLeafIDsByFolder: descendantLeafIDsByFolder
                )
            )
        case .shortcut(let pinID):
            guard let pin = inventory.pin(id: pinID) else { return }
            let liveTab = launcherRuntime.liveTab(for: pin.id)
            elements.append(
                .init(
                    id: .shortcut(pin.id),
                    payload: .topLevelShortcut(.init(
                        pin: pin,
                        liveTab: liveTab,
                        runtimeAffordance: selection.runtimeAffordance(
                            for: pin,
                            liveTab: liveTab,
                            in: windowState,
                            selection: selectionSnapshot
                        ),
                        index: index
                    )),
                    targetExtent: SidebarRowLayout.rowHeight,
                    overflowBleed: SidebarRowLayout.selectionShadowBleed,
                    placement: .pinnedRow(
                        itemID: pin.id,
                        topLevelIndex: index,
                        splitPairingMemberIDs: [.shortcutPin(pin.id)]
                    )
                )
            )
        case .splitGroup(let groupID):
            guard let group = inventory.splitGroup(id: groupID) else { return }
            let items = SplitGroupSidebarModel.items(
                for: group,
                inventory: inventory,
                launcherRuntime: launcherRuntime
            )
            elements.append(
                .init(
                    id: .splitGroup(group.id),
                    payload: .topLevelSplitGroup(
                        .init(
                            group: group,
                            items: items,
                            index: index
                        )
                    ),
                    targetExtent: SidebarRowLayout.rowHeight,
                    overflowBleed: SidebarRowLayout.selectionShadowBleed,
                    placement: .pinnedRow(
                        itemID: group.id,
                        topLevelIndex: index,
                        splitPairingMemberIDs: group.memberIDs
                    )
                )
            )
        }
    }

    private func folderElements(
        _ folder: TabFolder,
        parentFolderID: UUID?,
        containerIndex: Int,
        nestingDepth: Int,
        descendantLeafIDsByFolder: [UUID: [UUID]]
    ) -> [SpaceSidebarSceneElement] {
        guard let presentation = inventory.folderPresentation(id: folder.id)
        else { return [] }

        let live = liveSnapshots[folder.id]
            ?? SidebarLiveFolderSnapshot(source: nil, items: [])
        let projection = SidebarFolderViewProjection(
            folder: folder,
            shortcutPins: inventory.folderPinsByFolderID[folder.id] ?? [],
            inventory: inventory,
            selection: selection,
            launcherRuntime: launcherRuntime,
            liveFolderSource: live.source,
            liveFolderItems: live.items,
            currentTab: selection.currentTab(in: windowState),
            windowState: windowState,
            selectionSnapshot: selectionSnapshot,
            includesCollapsedDescendants: !presentation.isExpanded
        )
        let orderedDescendantIDs = descendantLeafIDsByFolder[folder.id] ?? []
        let folderState = windowState.sidebarFolderProjections
            .pendingOrCurrentProjection(for: folder.id)
        let disclosureStickyIDs =
            SidebarFolderDisplayProjection.disclosureTargetStickyItemIDs(
                currentStickyItemIDs: folderState.stickyItemIDs,
                selectedDescendantItemID:
                    projection.selectedCollapsedProjectionItemID
            )
        let targetCollapsedIDs = presentation.isExpanded
            ? []
            : SidebarFolderDisplayProjection.targetCollapsedProjectionIDs(
                stickyItemIDs: disclosureStickyIDs,
                orderedDescendantItemIDs: orderedDescendantIDs,
                projection: projection
            )
        let contentProjection = SidebarFolderContentProjection(
            baseItems: projection.baseItems,
            isFolderOpen: presentation.isExpanded,
            displayedCollapsedProjectionIDs: targetCollapsedIDs,
            stickyItemIDs: disclosureStickyIDs,
            orderedDescendantItemIDs: orderedDescendantIDs,
            projection: projection
        )
        let bodyItems = presentation.isExpanded
            ? projection.baseItems
            : targetCollapsedIDs.compactMap(
                projection.collapsedProjectionItem
            )

        var body: [SpaceSidebarSceneElement] = []
        for entry in SidebarFolderDisplayProjection.displayEntries(
            from: bodyItems
        ) {
            switch entry.item {
            case .folder(let childID):
                guard let child = inventory.folder(id: childID) else { continue }
                body.append(
                    contentsOf: folderElements(
                        child,
                        parentFolderID: folder.id,
                        containerIndex: entry.dropIndex,
                        nestingDepth: nestingDepth + 1,
                        descendantLeafIDsByFolder: descendantLeafIDsByFolder
                    )
                )
            case .shortcut(let pinID):
                guard let pin = projection.shortcutPin(with: pinID) else {
                    continue
                }
                body.append(
                    .init(
                        id: .shortcut(pin.id),
                        payload: .folderShortcut(
                            .init(
                                pin: pin,
                                folder: folder,
                                index: entry.dropIndex,
                                nestingDepth: nestingDepth + 1,
                                projection: projection
                            )
                        ),
                        targetExtent: SidebarRowLayout.rowHeight,
                        overflowBleed: SidebarRowLayout.selectionShadowBleed,
                        placement: .folderChild(
                            folderID: folder.id,
                            childID: pin.id,
                            index: entry.dropIndex,
                            nestingDepth: nestingDepth + 1,
                            splitPairingMemberIDs: [
                                .shortcutPin(pin.id),
                            ]
                        )
                    )
                )
            case .liveItem(let itemID):
                guard let item = projection.liveFolderItem(with: itemID) else {
                    continue
                }
                body.append(
                    .init(
                        id: .liveItem(folder.id, item.id),
                        payload: .liveItem(
                            .init(
                                item: item,
                                folder: folder,
                                index: entry.dropIndex,
                                nestingDepth: nestingDepth + 1,
                                isSelected: projection
                                    .isLiveFolderItemSelected(item)
                            )
                        ),
                        targetExtent: SidebarRowLayout.rowHeight,
                        overflowBleed: SidebarRowLayout.selectionShadowBleed
                    )
                )
            case .splitGroup(let groupID):
                guard let group = projection.splitGroup(with: groupID) else {
                    continue
                }
                let items = projection.splitGroupItems(for: group.id)
                body.append(
                    .init(
                        id: .splitGroup(group.id),
                        payload: .folderSplitGroup(
                            .init(
                                group: group,
                                items: items,
                                folder: folder,
                                index: entry.dropIndex,
                                nestingDepth: nestingDepth + 1
                            )
                        ),
                        targetExtent: SidebarRowLayout.rowHeight,
                        overflowBleed: SidebarRowLayout.selectionShadowBleed,
                        placement: .folderChild(
                            folderID: folder.id,
                            childID: group.id,
                            index: entry.dropIndex,
                            nestingDepth: nestingDepth + 1,
                            splitPairingMemberIDs: group.memberIDs
                        )
                    )
                )
            }
        }

        let rendersBody =
            presentation.isExpanded || !targetCollapsedIDs.isEmpty
        let header = SpaceSidebarSceneElement(
            id: .folderHeader(folder.id),
            payload: .folder(
                .init(
                    model: folder,
                    presentation: presentation,
                    parentFolderID: parentFolderID,
                    containerIndex: containerIndex,
                    nestingDepth: nestingDepth,
                    projection: projection,
                    contentProjection: contentProjection,
                    orderedDescendantItemIDs: orderedDescendantIDs
                )
            ),
            targetExtent: SidebarRowLayout.rowHeight,
            overflowBleed: SidebarRowLayout.selectionShadowBleed,
            contentRevision: AnyHashable(
                [
                    presentation.expansionRevision,
                    UInt64(targetCollapsedIDs.count),
                ]
            ),
            placement: .folderHeader(
                folderID: folder.id,
                parentFolderID: parentFolderID,
                containerIndex: containerIndex,
                childCount: contentProjection.childCount,
                nestingDepth: nestingDepth,
                isOpen: presentation.isExpanded,
                acceptsDrop: !projection.isLiveFolder,
                afterRegionHeight: dragSnapshots.pinned.folderSnapshot
                    .afterDropTargetHeight(
                        rowHeight: SidebarRowLayout.rowHeight
                    )
            )
        )
        guard rendersBody else { return [header] }

        return [
            header,
            .init(
                id: .folderBodyTop(folder.id),
                payload: .folderBodyTop,
                targetExtent: SidebarRowLayout.folderBodyPadding,
                placement: .folderBodyTop(folderID: folder.id)
            ),
        ] + body + [
            .init(
                id: .folderBodyBottom(folder.id),
                payload: .folderBodyBottom,
                targetExtent: SidebarRowLayout.folderBodyPadding,
                placement: .folderBodyBottom(folderID: folder.id)
            ),
        ]
    }

    private func appendBoundary(
        to elements: inout [SpaceSidebarSceneElement]
    ) {
        let layout = SpaceTabSectionBoundaryLayout(
            hasPinnedContent: hasPinnedContent,
            regularTabCount: tabs.count,
            supportsPinnedContent: !windowState.isIncognito
        )
        let extent =
            layout.topPadding + layout.separatorHeight + layout.bottomPadding
        elements.append(
            .init(
                id: .boundary,
                payload: .boundary(
                    .init(
                        layout: layout,
                        hasPersistedTabs: hasPersistedTabs
                    )
                ),
                targetExtent: extent,
                // The hairline renders inside a 2pt row that is centered on a
                // 1pt slot, so it always overhangs its own extent by half a
                // point. Bleeding by the hairline keeps the line whole no
                // matter how small the surrounding padding gets.
                overflowBleed: SpaceTabSectionBoundaryLayout.hairlineHeight,
                contentRevision: AnyHashable(
                    [
                        hasPinnedContent,
                        hasPersistedTabs,
                        layout.showsSeparator,
                    ]
                ),
                placement: .boundary
            )
        )
    }

    private func appendRegularRows(
        _ run: SidebarVisualSceneProjection.RegularRun,
        tabByID: [UUID: Tab],
        groupsByID: [UUID: SplitGroup],
        to elements: inout [SpaceSidebarSceneElement]
    ) {
        for (index, row) in run.rows.enumerated() {
            let trailingGap = index == run.rows.count - 1
                ? 0
                : SidebarRowLayout.rowGap
            switch row.identity {
            case .tab(let tabID):
                guard let tab = tabByID[tabID] else { continue }
                elements.append(
                    .init(
                        id: .regularTab(tabID),
                        payload: .regularTab(tab),
                        targetExtent:
                            SidebarRowLayout.rowHeight + trailingGap,
                        overflowBleed: SidebarRowLayout.selectionShadowBleed,
                        contentRevision: AnyHashable(row.tabIDs),
                        placement: .regularRow(
                            identity: row.identity,
                            splitPairingMemberIDs: row.tabIDs.map(
                                SplitMemberID.regularTab
                            )
                        )
                    )
                )
            case .splitGroup(let groupID):
                guard let group = groupsByID[groupID] else { continue }
                elements.append(
                    .init(
                        id: .splitGroup(groupID),
                        payload: .regularSplitGroup(
                            .init(group: group, tabByID: tabByID)
                        ),
                        targetExtent:
                            SidebarRowLayout.rowHeight + trailingGap,
                        overflowBleed: SidebarRowLayout.selectionShadowBleed,
                        contentRevision: AnyHashable(row.tabIDs),
                        placement: .regularRow(
                            identity: row.identity,
                            splitPairingMemberIDs: row.tabIDs.map(
                                SplitMemberID.regularTab
                            )
                        )
                    )
                )
            }
        }
    }

    private var newTabElement: SpaceSidebarSceneElement {
        .init(
            id: .newTab,
            payload: .newTab,
            targetExtent: SidebarRowLayout.rowHeight
        )
    }

    private func newTabGapElement(
        extent: CGFloat
    ) -> SpaceSidebarSceneElement {
        .init(
            id: .newTabGap,
            payload: .newTabGap,
            targetExtent: extent
        )
    }
}
