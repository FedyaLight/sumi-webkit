import Foundation
import SumiDomain

/// Canonical visual scene consumed by sidebar rendering, hit testing and DnD.
/// A Split Group is always one row; launcher groups are live only as a whole.
@MainActor
struct SidebarVisualSceneProjection {
    struct LauncherItem: Identifiable, Equatable {
        let source: SidebarPinnedInventoryItem
        let isLive: Bool
        let isSelected: Bool

        var id: UUID { source.id }
    }

    struct RegularRow: Identifiable, Equatable {
        enum Identity: Hashable {
            case tab(UUID)
            case splitGroup(UUID)
        }

        let identity: Identity
        let tabIDs: [UUID]

        var id: Identity { identity }
    }

    struct RegularBoundary: Equatable {
        let before: RegularRow.Identity?
        let after: RegularRow.Identity?
    }

    struct RegularRun: Equatable {
        let rows: [RegularRow]

        func boundary(at proposedIndex: Int) -> RegularBoundary {
            let index = max(0, min(proposedIndex, rows.count))
            return RegularBoundary(
                before: index > 0 ? rows[index - 1].identity : nil,
                after: index < rows.count ? rows[index].identity : nil
            )
        }

        func visualIndex(for boundary: RegularBoundary) -> Int? {
            switch (boundary.before, boundary.after) {
            case (nil, let after?):
                return rows.first?.identity == after ? 0 : nil
            case (let before?, nil):
                return rows.last?.identity == before ? rows.count : nil
            case (let before?, let after?):
                guard let afterIndex = rows.firstIndex(where: {
                    $0.identity == after
                }), afterIndex > 0,
                      rows[afterIndex - 1].identity == before else {
                    return nil
                }
                return afterIndex
            case (nil, nil):
                return rows.isEmpty ? 0 : nil
            }
        }

        func rawInsertionIndex(atVisualBoundary proposedIndex: Int) -> Int {
            let safeIndex = max(0, min(proposedIndex, rows.count))
            return rows.prefix(safeIndex).reduce(0) {
                $0 + $1.tabIDs.count
            }
        }
    }

    let inventory: SidebarSpaceInventorySnapshot
    let launcherRuntime: SidebarLauncherRuntimeSnapshot
    let selection: SidebarWindowSelectionQuery
    let selectionSnapshot: SidebarWindowSelectionSnapshot
    let windowState: BrowserWindowState

    var selectedItemRevealPath: SidebarSelectedItemRevealPath? {
        if let splitSelection = selectionSnapshot.splitSelection,
           contains(splitSelection.activeMemberID),
           let group = inventory.splitGroup(containing: splitSelection.activeMemberID),
           group.id == splitSelection.groupID {
            return revealPath(
                to: .splitGroup(group.id),
                parentFolderID: group.container.shortcutSidebarFolderId
            )
        }

        if let pin = selectedPin {
            if let group = inventory.splitGroup(containing: .shortcutPin(pin.id)) {
                return revealPath(
                    to: .splitGroup(group.id),
                    parentFolderID: group.container.shortcutSidebarFolderId
                )
            }
            return revealPath(to: .launcher(pin.id), parentFolderID: pin.folderId)
        }

        guard let tabID = selectionSnapshot.currentTabID,
              inventory.tab(id: tabID) != nil else { return nil }
        if let group = inventory.splitGroup(containing: .regularTab(tabID)) {
            return SidebarSelectedItemRevealPath([.splitGroup(group.id)])
        }
        return SidebarSelectedItemRevealPath([.regularTab(tabID)])
    }

    private func revealPath(
        to targetID: SidebarScrollTargetID,
        parentFolderID: UUID?
    ) -> SidebarSelectedItemRevealPath {
        guard !windowState.sidebarSpacePinnedCollapse.isCollapsed(inventory.spaceID),
              let parentFolderID else {
            return SidebarSelectedItemRevealPath([targetID])
        }

        var folders: [TabFolder] = []
        var visited = Set<UUID>()
        var currentID: UUID? = parentFolderID
        while let folderID = currentID,
              visited.insert(folderID).inserted,
              let folder = inventory.folder(id: folderID) {
            folders.append(folder)
            currentID = folder.parentFolderId
        }

        var targets: [SidebarScrollTargetID] = []
        for folder in folders.reversed() {
            targets.append(.folder(folder.id))
            let isExpanded = inventory.folderPresentation(id: folder.id)?.isExpanded
                ?? folder.isOpen
            if !isExpanded {
                break
            }
        }
        targets.append(targetID)
        return SidebarSelectedItemRevealPath(targets)
    }

    private var selectedPin: ShortcutPin? {
        if let pinID = selectionSnapshot.currentShortcutPinID,
           let pin = inventory.pin(id: pinID) {
            return pin
        }
        return inventory.pinsByID.values.first {
            selection.isShortcutSelected(
                $0,
                in: windowState,
                selection: selectionSnapshot
            )
        }
    }

    private func contains(_ memberID: SplitMemberID) -> Bool {
        switch memberID {
        case .regularTab(let tabID):
            inventory.tab(id: tabID) != nil
        case .shortcutPin(let pinID):
            inventory.pin(id: pinID) != nil
        }
    }

    static func regularRun(
        tabIDs: [UUID],
        groups: [SplitGroup]
    ) -> RegularRun {
        let availableTabIDs = Set(tabIDs)
        let validGroups = groups.filter { group in
            guard case .regularTabs = group.container else { return false }
            let memberTabIDs = group.memberIDs.compactMap { memberID -> UUID? in
                guard case .regularTab(let tabID) = memberID else { return nil }
                return tabID
            }
            return memberTabIDs.count == group.memberIDs.count
                && memberTabIDs.allSatisfy(availableTabIDs.contains)
        }
        let groupByMemberID = validGroups.reduce(into: [UUID: SplitGroup]()) {
            result, group in
            for memberID in group.memberIDs {
                guard case .regularTab(let tabID) = memberID else { continue }
                result[tabID] = group
            }
        }
        let tabIDsByGroupID = tabIDs.reduce(into: [UUID: [UUID]]()) {
            result, tabID in
            guard let groupID = groupByMemberID[tabID]?.id else { return }
            result[groupID, default: []].append(tabID)
        }
        var emittedGroupIDs = Set<UUID>()

        let rows = tabIDs.compactMap { tabID -> RegularRow? in
            guard let group = groupByMemberID[tabID] else {
                return RegularRow(identity: .tab(tabID), tabIDs: [tabID])
            }
            guard emittedGroupIDs.insert(group.id).inserted else { return nil }
            return RegularRow(
                identity: .splitGroup(group.id),
                tabIDs: tabIDsByGroupID[group.id] ?? []
            )
        }
        return RegularRun(rows: rows)
    }

    static func regularRawInsertionIndex(
        movingGroupID: UUID,
        atModelBoundary proposedIndex: Int,
        rows: [RegularRow]
    ) -> Int? {
        guard let currentRowIndex = rows.firstIndex(where: {
            $0.identity == .splitGroup(movingGroupID)
        }) else { return nil }
        let groupStartIndex = rows.prefix(currentRowIndex).reduce(0) {
            $0 + $1.tabIDs.count
        }
        let groupItemCount = rows[currentRowIndex].tabIDs.count
        let groupEndIndex = groupStartIndex + groupItemCount
        let modelItemCount = rows.reduce(0) { $0 + $1.tabIDs.count }
        let safeProposedIndex = max(0, min(proposedIndex, modelItemCount))

        if safeProposedIndex <= groupStartIndex {
            return safeProposedIndex
        }
        if safeProposedIndex >= groupEndIndex {
            return safeProposedIndex - groupItemCount
        }
        return groupStartIndex
    }

    func launcherItems(
        _ sourceItems: [SidebarPinnedInventoryItem]
    ) -> [LauncherItem] {
        sourceItems.compactMap { source in
            switch source {
            case .folder:
                return nil

            case .shortcut(let pinID):
                guard let pin = inventory.pin(id: pinID) else { return nil }
                let liveTab = launcherRuntime.liveTab(for: pinID)
                return LauncherItem(
                    source: source,
                    isLive: liveTab != nil,
                    isSelected: isPinSelected(pin, liveTab: liveTab)
                )

            case .splitGroup(let groupID):
                guard let group = inventory.splitGroup(id: groupID) else {
                    return nil
                }
                let items = SplitGroupSidebarModel.items(
                    for: group,
                    inventory: inventory,
                    launcherRuntime: launcherRuntime
                )
                return LauncherItem(
                    source: source,
                    isLive: Self.isWholeSplitGroupLive(group, items: items),
                    isSelected: selection.isSplitGroupSelected(
                        group,
                        in: windowState,
                        selection: selectionSnapshot
                    )
                )
            }
        }
    }

    static func isWholeSplitGroupLive(
        _ group: SplitGroup,
        items: [SplitGroupSidebarItem]
    ) -> Bool {
        !items.isEmpty
            && items.count == group.memberIDs.count
            && items.allSatisfy { $0.tab != nil }
    }

    private func isPinSelected(_ pin: ShortcutPin, liveTab: Tab?) -> Bool {
        if selection.isShortcutSelected(
            pin,
            in: windowState,
            selection: selectionSnapshot
        ) {
            return true
        }
        guard let liveTab, let currentTabID = selectionSnapshot.currentTabID else {
            return false
        }
        return liveTab.id == currentTabID
    }
}
