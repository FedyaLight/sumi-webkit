import Combine
import SumiDomain
import SwiftUI

private enum SpaceSidebarListElementID: Hashable {
    case pinnedTop
    case folderHeader(UUID)
    case folderBodyTop(UUID)
    case folderBodyBottom(UUID)
    case shortcut(UUID)
    case liveItem(UUID, String)
    case splitGroup(UUID)
    case boundary
    case regularRunStart
    case regularTab(UUID)
    case regularRunEnd
    case newTabGap
    case newTab

    /// The dragged item behind a row that can move between the pinned and
    /// regular sections, and therefore lend or adopt a presentation identity.
    var transferableItemID: UUID? {
        switch self {
        case .shortcut(let itemID), .regularTab(let itemID):
            return itemID
        default:
            return nil
        }
    }
}

private enum SpaceSidebarListElementPayload {
    struct Boundary {
        let layout: SpaceTabSectionBoundaryLayout
        let hasPersistedTabs: Bool
    }

    struct Folder {
        let model: TabFolder
        let presentation: SidebarFolderPresentationCell
        let parentFolderID: UUID?
        let containerIndex: Int
        let nestingDepth: Int
        let projection: SidebarFolderViewProjection
        let contentProjection: SidebarFolderContentProjection
        let orderedDescendantItemIDs: [UUID]
    }

    struct TopLevelShortcut {
        let pin: ShortcutPin
        let liveTab: Tab?
        let runtimeAffordance: SumiLauncherRuntimeAffordanceState
        let index: Int
    }

    struct FolderShortcut {
        let pin: ShortcutPin
        let folder: TabFolder
        let index: Int
        let nestingDepth: Int
        let projection: SidebarFolderViewProjection
    }

    struct TopLevelSplitGroup {
        let group: SplitGroup
        let items: [SplitGroupSidebarItem]
        let index: Int
    }

    struct FolderSplitGroup {
        let group: SplitGroup
        let items: [SplitGroupSidebarItem]
        let folder: TabFolder
        let index: Int
        let nestingDepth: Int
    }

    struct LiveItem {
        let item: SumiLiveFolderItem
        let folder: TabFolder
        let index: Int
        let nestingDepth: Int
        let isSelected: Bool
    }

    struct RegularSplitGroup {
        let group: SplitGroup
        let tabByID: [UUID: Tab]
    }

    case pinnedTop
    case folderBodyTop
    case folderBodyBottom
    case folder(Folder)
    case topLevelShortcut(TopLevelShortcut)
    case folderShortcut(FolderShortcut)
    case collapsedNestedSticky(UUID)
    case topLevelSplitGroup(TopLevelSplitGroup)
    case folderSplitGroup(FolderSplitGroup)
    case liveItem(LiveItem)
    case boundary(Boundary)
    case regularRunStart
    case regularTab(Tab)
    case regularSplitGroup(RegularSplitGroup)
    case regularRunEnd
    case newTabGap
    case newTab
}

private struct SpaceSidebarDragSnapshots {
    let pinned: SpacePinnedDragSnapshot
    let regular: SpaceRegularDragSnapshot
}

private struct SpaceSidebarDragSnapshotReader<Content: View>: View {
    let spaceID: UUID
    @ObservedObject var listPresentation: SidebarListDragPresentation
    @ViewBuilder let content: (SpaceSidebarDragSnapshots) -> Content

    @EnvironmentObject private var dragGeometry: SidebarDragGeometryModule

    var body: some View {
        let generation = dragGeometry.sidebarGeometryGeneration
        content(
            SpaceSidebarDragSnapshots(
                pinned: SpacePinnedDragSnapshot(
                    frame: listPresentation.frame,
                    geometryGeneration: generation,
                    spaceID: spaceID
                ),
                regular: SpaceRegularDragSnapshot(
                    frame: listPresentation.frame,
                    geometryGeneration: generation
                )
            )
        )
    }
}

/// A single demand-scoped subscription fan-in for the live folders whose
/// headers are currently reachable in the flattened scene.
@MainActor
private final class SpaceSidebarLiveFolderRevision: ObservableObject {
    @Published private(set) var snapshots: [UUID: SidebarLiveFolderSnapshot] = [:]

    private let manager: SumiLiveFolderManager
    private var folderIDs: [UUID] = []
    private var isActive = false
    private var cancellable: AnyCancellable?

    init(manager: SumiLiveFolderManager) {
        self.manager = manager
    }

    func reconcile(folderIDs: [UUID], isActive: Bool) {
        let normalizedIDs = Array(Set(folderIDs)).sorted {
            $0.uuidString < $1.uuidString
        }
        guard normalizedIDs != self.folderIDs || isActive != self.isActive
        else { return }

        self.folderIDs = normalizedIDs
        self.isActive = isActive
        cancellable?.cancel()
        cancellable = nil

        let nextSnapshots = Dictionary(
            uniqueKeysWithValues: normalizedIDs.map { folderID in
                (folderID, snapshot(for: folderID))
            }
        )
        if nextSnapshots != snapshots {
            snapshots = nextSnapshots
        }

        guard isActive, !normalizedIDs.isEmpty else { return }
        cancellable = Publishers.MergeMany(
            normalizedIDs.map { folderID in
                manager.contentChanges(for: folderID)
                    .map { folderID }
            }
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] folderID in
            self?.refresh(folderID: folderID)
        }
    }

    private func refresh(folderID: UUID) {
        guard snapshots.keys.contains(folderID) else { return }
        let next = snapshot(for: folderID)
        guard snapshots[folderID] != next else { return }
        snapshots[folderID] = next
    }

    private func snapshot(for folderID: UUID) -> SidebarLiveFolderSnapshot {
        let source = manager.source(for: folderID)
        return SidebarLiveFolderSnapshot(
            source: source,
            items: source == nil
                ? []
                : manager.visibleItems(for: folderID)
        )
    }

    isolated deinit {
        cancellable?.cancel()
    }
}

private struct SpaceSidebarLiveFolderReader<Content: View>: View {
    let folderIDs: [UUID]
    let isActive: Bool
    @ViewBuilder let content: ([UUID: SidebarLiveFolderSnapshot]) -> Content

    @StateObject private var revision: SpaceSidebarLiveFolderRevision

    init(
        manager: SumiLiveFolderManager,
        folderIDs: [UUID],
        isActive: Bool,
        @ViewBuilder content: @escaping (
            [UUID: SidebarLiveFolderSnapshot]
        ) -> Content
    ) {
        self.folderIDs = folderIDs
        self.isActive = isActive
        self.content = content
        _revision = StateObject(
            wrappedValue: SpaceSidebarLiveFolderRevision(manager: manager)
        )
    }

    var body: some View {
        content(revision.snapshots)
            .onAppear {
                revision.reconcile(folderIDs: folderIDs, isActive: isActive)
            }
            .onChange(of: folderIDs) { _, folderIDs in
                revision.reconcile(folderIDs: folderIDs, isActive: isActive)
            }
            .onChange(of: isActive) { _, isActive in
                revision.reconcile(folderIDs: folderIDs, isActive: isActive)
            }
            .onDisappear {
                revision.reconcile(folderIDs: [], isActive: false)
            }
    }
}

/// The entire scroll-content Interface for one Space. Pinned content, every
/// recursive folder row, the section boundary, regular tabs, and New Tab all
/// share one lazy presentation surface.
struct SpaceSidebarListView: View {
    let space: Space
    let inventory: SidebarSpaceInventorySnapshot
    let launcherRuntime: SidebarLauncherRuntimeSnapshot
    let selection: SidebarWindowSelectionQuery
    let pinProjection: SidebarPinFolderProjection
    let pinCommands: SidebarPinCommands
    let pinExecution: SidebarPinExecutionCommands
    let folderCommands: SidebarFolderCommands
    let spaceLifecycle: SidebarSpaceLifecycle
    let regularTabCatalog: SidebarRegularTabCatalog
    let regularTabTargets: SidebarRegularTabTargetQuery
    let regularTabLifecycleCommands: SidebarRegularTabLifecycleCommands
    let regularTabShortcutCommands: SidebarRegularTabShortcutCommands
    let regularTabPlacementCommands: SidebarRegularTabPlacementCommands
    let browserContext: SidebarBrowserContext
    let listDragPresentation: SidebarListDragPresentation
    let isInteractive: Bool
    let innerWidth: CGFloat
    let onSetPinnedContentCollapsed: (Bool) -> Void
    @Binding var isSidebarHovered: Bool

    @Environment(BrowserWindowState.self) private var windowState

    var body: some View {
        let traversal = SpaceSidebarInventoryTraversal(
            inventory: inventory,
            includesVisibleFolders:
                !windowState.isIncognito
                    && !windowState.sidebarSpacePinnedCollapse
                        .isCollapsed(space.id),
            isLiveFolder: browserContext.liveFolderManager.isLiveFolder
        )
        SpaceSidebarDragSnapshotReader(
            spaceID: space.id,
            listPresentation: listDragPresentation
        ) { dragSnapshots in
            SpaceSidebarLiveFolderReader(
                manager: browserContext.liveFolderManager,
                folderIDs: traversal.visibleFolderIDs,
                isActive: isInteractive
            ) { liveSnapshots in
                SpaceSidebarListContentView(
                    space: space,
                    inventory: inventory,
                    launcherRuntime: launcherRuntime,
                    selection: selection,
                    pinProjection: pinProjection,
                    pinCommands: pinCommands,
                    pinExecution: pinExecution,
                    folderCommands: folderCommands,
                    spaceLifecycle: spaceLifecycle,
                    regularTabCatalog: regularTabCatalog,
                    regularTabTargets: regularTabTargets,
                    regularTabLifecycleCommands: regularTabLifecycleCommands,
                    regularTabShortcutCommands: regularTabShortcutCommands,
                    regularTabPlacementCommands: regularTabPlacementCommands,
                    browserContext: browserContext,
                    isInteractive: isInteractive,
                    innerWidth: innerWidth,
                    // Both halves of the scene must come from the same
                    // snapshot: a live regular read would land one run loop
                    // ahead of the deferred inventory publish and split one
                    // container transfer into two structural transitions.
                    tabs: inventory.regularTabs,
                    inventoryTraversal: traversal,
                    liveSnapshots: liveSnapshots,
                    dragSnapshots: dragSnapshots,
                    onSetPinnedContentCollapsed:
                        onSetPinnedContentCollapsed,
                    isSidebarHovered: $isSidebarHovered
                )
            }
        }
    }
}

private struct SpaceSidebarSceneOutput {
    let scene: SidebarListScene<
        SpaceSidebarListElementID,
        SpaceSidebarListElementPayload
    >
    let structuralItemIDs: [UUID]
}

@MainActor
private struct SpaceSidebarInventoryTraversal {
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

private struct SpaceSidebarListContentView: View {
    private static let folderIndent: CGFloat = 14

    let space: Space
    let inventory: SidebarSpaceInventorySnapshot
    let launcherRuntime: SidebarLauncherRuntimeSnapshot
    let selection: SidebarWindowSelectionQuery
    let pinProjection: SidebarPinFolderProjection
    let pinCommands: SidebarPinCommands
    let pinExecution: SidebarPinExecutionCommands
    let folderCommands: SidebarFolderCommands
    let spaceLifecycle: SidebarSpaceLifecycle
    let regularTabCatalog: SidebarRegularTabCatalog
    let regularTabTargets: SidebarRegularTabTargetQuery
    let regularTabLifecycleCommands: SidebarRegularTabLifecycleCommands
    let regularTabShortcutCommands: SidebarRegularTabShortcutCommands
    let regularTabPlacementCommands: SidebarRegularTabPlacementCommands
    let browserContext: SidebarBrowserContext
    let isInteractive: Bool
    let innerWidth: CGFloat
    let tabs: [Tab]
    let inventoryTraversal: SpaceSidebarInventoryTraversal
    let liveSnapshots: [UUID: SidebarLiveFolderSnapshot]
    let dragSnapshots: SpaceSidebarDragSnapshots
    let onSetPinnedContentCollapsed: (Bool) -> Void
    @Binding var isSidebarHovered: Bool

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(WindowRegistry.self) private var windowRegistry
    @Environment(\.sumiSettings) private var sumiSettings
    @Environment(\.resolvedThemeContext) private var themeContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sidebarWindowSelectionSnapshot) private var sidebarSelection

    private var hasPinnedContent: Bool {
        !windowState.isIncognito && !inventory.topLevelItems.isEmpty
    }

    private var isPinnedCollapsed: Bool {
        hasPinnedContent
            && windowState.sidebarSpacePinnedCollapse.isCollapsed(space.id)
    }

    private var hasStalePinnedCollapseState: Bool {
        !hasPinnedContent
            && windowState.sidebarSpacePinnedCollapse.isCollapsed(space.id)
    }

    private var elevatedFolderIDs: Set<UUID> {
        SpaceElevatedFolderOwner(
            inventory: inventory,
            launcherRuntime: launcherRuntime,
            selection: selection,
            windowState: windowState,
            selectionSnapshot: sidebarSelection
        ).elevatedFolderIds
    }

    private var spaceStickyOwner: SidebarSpacePinnedStickyProjectionOwner {
        SidebarSpacePinnedStickyProjectionOwner(
            space: space,
            inventory: inventory,
            launcherRuntime: launcherRuntime,
            selection: selection,
            selectionSnapshot: sidebarSelection,
            windowState: windowState
        )
    }

    private var contentMutationAnimation: Animation? {
        guard isInteractive,
              !reduceMotion,
              !sumiSettings.shouldReduceChromeMotion
        else { return nil }
        let mode = SidebarMotionPolicy.currentMode(
            reduceMotion: reduceMotion || sumiSettings.shouldReduceChromeMotion
        )
        return SidebarMotionPolicy.contentLayoutAnimation(for: mode)
    }

    private var isCompletingDrop: Bool {
        dragSnapshots.pinned.isCompletingDrop
            || dragSnapshots.regular.isCompletingDrop
    }

    /// A committed drop moves the dragged row between the pinned and regular
    /// sections. Naming the retired row keeps an unrelated coincident change
    /// from being mistaken for that move.
    private var identityTransfer:
        SidebarListIdentityTransfer<SpaceSidebarListElementID>? {
        guard isCompletingDrop,
              let draggedItemID = dragSnapshots.pinned.activeDragItemID
                  ?? dragSnapshots.regular.activeDragItemID
        else { return nil }

        return SidebarListIdentityTransfer(
            isSource: { $0.transferableItemID == draggedItemID },
            isTransferable: { $0.transferableItemID != nil }
        )
    }

    private var topLevelActionOwner: SpacePinnedActionOwner {
        SpacePinnedActionOwner(
            space: space,
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
            contentMutationAnimation: contentMutationAnimation
        )
    }

    private var regularTabActionOwner: SpaceRegularTabActionOwner {
        SpaceRegularTabActionOwner(
            space: space,
            catalog: regularTabCatalog,
            targets: regularTabTargets,
            lifecycleCommands: regularTabLifecycleCommands,
            shortcutCommands: regularTabShortcutCommands,
            placementCommands: regularTabPlacementCommands,
            browserContext: browserContext,
            windowState: windowState,
            firstTabID: tabs.first?.id,
            lastTabID: tabs.last?.id
        )
    }

    var body: some View {
        let output = SpaceSidebarSceneBuilder(
            space: space,
            inventory: inventory,
            launcherRuntime: launcherRuntime,
            selection: selection,
            regularTabTargets: regularTabTargets,
            tabs: tabs,
            inventoryTraversal: inventoryTraversal,
            windowState: windowState,
            hasPersistedTabs: regularTabCatalog.hasPersistedTabs(in: space),
            showsNewTab: sumiSettings.showNewTabButtonInTabList,
            newTabAtTop:
                sumiSettings.tabListNewTabButtonPosition == .top,
            selectionSnapshot: sidebarSelection,
            liveSnapshots: liveSnapshots,
            dragSnapshots: dragSnapshots,
            isInteractive: isInteractive,
            hasPinnedContent: hasPinnedContent,
            isPinnedCollapsed: isPinnedCollapsed,
            pinnedStickyItemIDs: spaceStickyOwner.visibleStickyItemIDs
        ).build()
        SidebarListSurface(
            scene: output.scene,
            animation: contentMutationAnimation,
            identityTransfer: identityTransfer,
            presentedSpaceID: space.id,
            geometryGeneration: dragSnapshots.pinned.geometryGeneration
        ) { payload, _ in
            elementView(payload)
        }
        .frame(minWidth: 0, maxWidth: innerWidth, alignment: .leading)
        .contentShape(Rectangle())
        .onAppear {
            spaceStickyOwner.reconcileOnAppear()
            if hasStalePinnedCollapseState {
                onSetPinnedContentCollapsed(false)
            }
        }
        .onChange(of: sidebarSelection) { _, _ in
            spaceStickyOwner.handleSelectionChange()
        }
        .onChange(of: output.structuralItemIDs) { oldIDs, newIDs in
            spaceStickyOwner.handleMembershipChange()
            guard isPinnedCollapsed else { return }
            if newIDs.isEmpty || !Set(newIDs).subtracting(oldIDs).isEmpty {
                onSetPinnedContentCollapsed(false)
            }
        }
        .onChange(of: dragSnapshots.pinned.isCompletingDrop) {
            _, isCompletingDrop in
            if isCompletingDrop,
               isPinnedCollapsed,
               dragSnapshots.pinned.isHoveringEmptySection {
                onSetPinnedContentCollapsed(false)
            }
        }
    }
}

@MainActor
private struct SpaceSidebarSceneBuilder {
    let space: Space
    let inventory: SidebarSpaceInventorySnapshot
    let launcherRuntime: SidebarLauncherRuntimeSnapshot
    let selection: SidebarWindowSelectionQuery
    let regularTabTargets: SidebarRegularTabTargetQuery
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
        var elements: [
            SidebarListScene<
                SpaceSidebarListElementID,
                SpaceSidebarListElementPayload
            >.Element
        ] = []

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
            splitGroup: { regularTabTargets.splitGroup(containing: $0) }
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
        to elements: inout [
            SidebarListScene<
                SpaceSidebarListElementID,
                SpaceSidebarListElementPayload
            >.Element
        ]
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
        to elements: inout [
            SidebarListScene<
                SpaceSidebarListElementID,
                SpaceSidebarListElementPayload
            >.Element
        ]
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
        to elements: inout [
            SidebarListScene<
                SpaceSidebarListElementID,
                SpaceSidebarListElementPayload
            >.Element
        ]
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
    ) -> [
        SidebarListScene<
            SpaceSidebarListElementID,
            SpaceSidebarListElementPayload
        >.Element
    ] {
        guard let presentation = inventory.folderPresentation(id: folder.id)
        else { return [] }

        let live = liveSnapshots[folder.id]
            ?? SidebarLiveFolderSnapshot(source: nil, items: [])
        let projection = SidebarFolderViewProjection(
            folder: folder,
            space: space,
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

        var body: [
            SidebarListScene<
                SpaceSidebarListElementID,
                SpaceSidebarListElementPayload
            >.Element
        ] = []
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
                                isSelected:
                                    projection.currentTabURLString
                                        == item.urlString
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
        let header = SidebarListScene<
            SpaceSidebarListElementID,
            SpaceSidebarListElementPayload
        >.Element(
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
        to elements: inout [
            SidebarListScene<
                SpaceSidebarListElementID,
                SpaceSidebarListElementPayload
            >.Element
        ]
    ) {
        let layout = SpaceTabSectionBoundaryLayout(
            hasPinnedContent: hasPinnedContent,
            regularTabCount: tabs.count
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
        to elements: inout [
            SidebarListScene<
                SpaceSidebarListElementID,
                SpaceSidebarListElementPayload
            >.Element
        ]
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

    private var newTabElement: SidebarListScene<
        SpaceSidebarListElementID,
        SpaceSidebarListElementPayload
    >.Element {
        .init(
            id: .newTab,
            payload: .newTab,
            targetExtent: SidebarRowLayout.rowHeight
        )
    }

    private func newTabGapElement(
        extent: CGFloat
    ) -> SidebarListScene<
        SpaceSidebarListElementID,
        SpaceSidebarListElementPayload
    >.Element {
        .init(
            id: .newTabGap,
            payload: .newTabGap,
            targetExtent: extent
        )
    }
}

private extension SpaceSidebarListContentView {
    @ViewBuilder
    private func elementView(
        _ payload: SpaceSidebarListElementPayload
    ) -> some View {
        switch payload {
        case .pinnedTop, .folderBodyTop, .folderBodyBottom,
                .regularRunStart, .regularRunEnd, .newTabGap:
            Color.clear
        case .folder(let folder):
            folderHeader(folder)
        case .topLevelShortcut(let row):
            topLevelShortcut(row)
        case .folderShortcut(let row):
            folderShortcut(row)
        case .collapsedNestedSticky(let itemID):
            SpaceNestedPinnedStickyEntryView(
                space: space,
                inventory: inventory,
                selection: selection,
                launcherRuntime: launcherRuntime,
                pinProjection: pinProjection,
                pinCommands: pinCommands,
                pinExecution: pinExecution,
                folderCommands: folderCommands,
                spaceLifecycle: spaceLifecycle,
                browserContext: browserContext,
                isInteractive: isInteractive,
                itemID: itemID,
                dragSnapshot: dragSnapshots.pinned,
                contentMutationAnimation: contentMutationAnimation
            )
            .sidebarScrollTarget(
                inventory.pin(id: itemID) != nil
                    ? .launcher(itemID)
                    : .splitGroup(itemID)
            )
        case .topLevelSplitGroup(let row):
            topLevelSplitGroup(row)
        case .folderSplitGroup(let row):
            folderSplitGroup(row)
        case .liveItem(let row):
            liveFolderItem(row)
        case .boundary(let boundary):
            SpaceSidebarBoundaryView(
                boundary: boundary,
                space: space,
                regularTabLifecycleCommands: regularTabLifecycleCommands,
                isSidebarHovered: $isSidebarHovered
            )
        case .regularTab(let tab):
            regularTab(tab)
        case .regularSplitGroup(let row):
            regularSplitGroup(row)
        case .newTab:
            SpaceRegularNewTabRow(
                space: space,
                browserContext: browserContext,
                isInteractive: isInteractive
            )
        }
    }

    private func folderHeader(
        _ row: SpaceSidebarListElementPayload.Folder
    ) -> some View {
        let projectionState = windowState.sidebarFolderProjections
            .pendingOrCurrentProjection(for: row.model.id)
        let hasLiveSelection =
            row.projection.isLiveFolder
            && row.projection.liveFolderItems.contains {
                $0.urlString == row.projection.currentTabURLString
            }
        let mutationActions = folderMutationActions
        let contextOwner = folderContextOwner(
            row.model,
            mutationActions: mutationActions
        )
        return SpaceFlatFolderHeaderView(
            folder: row,
            space: space,
            inventory: inventory,
            selection: selection,
            launcherRuntime: launcherRuntime,
            pinProjection: pinProjection,
            browserContext: browserContext,
            isInteractive: isInteractive,
            elevatedFolderIDs: elevatedFolderIDs,
            hasLiveSelection: hasLiveSelection,
            hasActiveProjection: projectionState.hasActiveProjection,
            dragSnapshot: dragSnapshots.pinned.folderSnapshot,
            mutationActions: mutationActions,
            contextOwner: contextOwner
        )
        .padding(.leading, CGFloat(row.nestingDepth) * Self.folderIndent)
        .sidebarDropContainmentBackdrop(
            isVisible: dragSnapshots.pinned.folderSnapshot
                .isContainTargeted(folderID: row.model.id)
        )
        .opacity(itemOpacity(row.model.id))
        .zIndex(
            SidebarSelectionElevation.zIndex(
                isElevated: elevatedFolderIDs.contains(row.model.id)
            )
        )
        .sidebarScrollTarget(.folder(row.model.id))
    }

    private func topLevelShortcut(
        _ row: SpaceSidebarListElementPayload.TopLevelShortcut
    ) -> some View {
        let pin = row.pin
        return SpacePinnedShortcutEntryView(
            pin: pin,
            liveTab: row.liveTab,
            faviconPartition: pinProjection.faviconPartition(
                for: pin,
                currentSpaceID: windowState.currentSpaceId
            ),
            faviconImageReader: browserContext.faviconImageReader,
            runtimeAffordance: row.runtimeAffordance,
            spaceID: space.id,
            isInteractive: isInteractive,
            opacity: itemOpacity(pin.id),
            projectedSplitTarget: dragSnapshots.pinned.splitPairingTarget?
                .projectedTarget(for: .shortcutPin(pin.id)),
            actionOwner: topLevelActionOwner
        )
        .zIndex(
            SidebarSelectionElevation.zIndex(
                isElevated: selection.isShortcutSelected(
                    pin,
                    in: windowState,
                    selection: sidebarSelection
                )
            )
        )
        .sidebarScrollTarget(.launcher(pin.id))
    }

    private func folderShortcut(
        _ row: SpaceSidebarListElementPayload.FolderShortcut
    ) -> some View {
        let mutationActions = folderMutationActions
        let contextOwner = folderContextOwner(
            row.folder,
            mutationActions: mutationActions
        )
        let presentationOwner = TabFolderShortcutPresentationOwner(
            pinProjection: pinProjection,
            selection: selection,
            launcherRuntime: launcherRuntime,
            windowState: windowState,
            selectionSnapshot: sidebarSelection
        )
        return TabFolderShortcutEntryView(
            pin: row.pin,
            liveTab: row.projection.liveTab(for: row.pin.id),
            faviconPartition: presentationOwner.faviconPartition(for: row.pin),
            faviconImageReader: browserContext.faviconImageReader,
            runtimeAffordance: presentationOwner.runtimeAffordance(for: row.pin),
            folderID: row.folder.id,
            isInteractive: isInteractive,
            opacity: dragSnapshots.pinned.folderSnapshot.childOpacity(
                itemID: row.pin.id
            ),
            projectedSplitTarget:
                dragSnapshots.pinned.splitPairingTarget?
                    .projectedTarget(for: .shortcutPin(row.pin.id)),
            contextMenuActionOwner: contextOwner,
            mutationActions: mutationActions
        )
        .padding(.leading, CGFloat(row.nestingDepth) * Self.folderIndent)
        .zIndex(
            SidebarSelectionElevation.zIndex(
                isElevated: row.projection.isShortcutSelected(row.pin)
            )
        )
        .sidebarScrollTarget(.launcher(row.pin.id))
    }

    private func topLevelSplitGroup(
        _ row: SpaceSidebarListElementPayload.TopLevelSplitGroup
    ) -> some View {
        SpacePinnedSplitGroupEntryView(
            group: row.group,
            items: row.items,
            space: space,
            browserContext: browserContext,
            pinProjection: pinProjection,
            isInteractive: isInteractive,
            dragSnapshot: dragSnapshots.pinned.folderSnapshot
        )
        .opacity(itemOpacity(row.group.id))
        .zIndex(
            SidebarSelectionElevation.zIndex(
                isElevated: selection.isSplitGroupSelected(
                    row.group,
                    in: windowState,
                    selection: sidebarSelection
                )
            )
        )
        .sidebarScrollTarget(.splitGroup(row.group.id))
    }

    private func folderSplitGroup(
        _ row: SpaceSidebarListElementPayload.FolderSplitGroup
    ) -> some View {
        TabFolderSplitGroupEntryView(
            group: row.group,
            items: row.items,
            space: space,
            browserContext: browserContext,
            pinProjection: pinProjection,
            isInteractive: isInteractive
        )
        .padding(.leading, CGFloat(row.nestingDepth) * Self.folderIndent)
        .sidebarDropContainmentBackdrop(
            isVisible: dragSnapshots.pinned.folderSnapshot
                .isExistingSplitGroupTargeted(
                    memberIDs: row.group.memberIDs
                )
        )
        .zIndex(
            SidebarSelectionElevation.zIndex(
                isElevated: selection.isSplitGroupSelected(
                    row.group,
                    in: windowState,
                    selection: sidebarSelection
                )
            )
        )
        .sidebarScrollTarget(.splitGroup(row.group.id))
    }

    private func liveFolderItem(
        _ row: SpaceSidebarListElementPayload.LiveItem
    ) -> some View {
        let mutationActions = folderMutationActions
        return TabFolderLiveItemEntryView(
            item: row.item,
            folderID: row.folder.id,
            isSelected: row.isSelected,
            isInteractive: isInteractive,
            actionOwner: folderContextOwner(
                row.folder,
                mutationActions: mutationActions
            )
        )
        .padding(.leading, CGFloat(row.nestingDepth) * Self.folderIndent)
        .zIndex(
            SidebarSelectionElevation.zIndex(isElevated: row.isSelected)
        )
        .sidebarScrollTarget(
            .liveFolderItem(
                folderID: row.folder.id,
                itemID: row.item.id
            )
        )
    }

    private func regularTab(_ tab: Tab) -> some View {
        let isCurrent = sidebarSelection.currentTabID == tab.id
        return SpaceRegularTabEntryView(
            tab: tab,
            spaceID: space.id,
            isCurrentTab: isCurrent,
            opacity:
                dragSnapshots.regular.isDragging
                    && dragSnapshots.regular.activeDragItemID == tab.id
                ? SidebarDragSourceDim.opacity
                : 1,
            isInteractive: isInteractive,
            projectedSplitTarget:
                dragSnapshots.regular.splitPairingTarget?
                    .projectedTarget(for: .regularTab(tab.id)),
            actionOwner: regularTabActionOwner,
            onClose: { regularTabActionOwner.close(tab) }
        )
        .zIndex(
            SidebarSelectionElevation.zIndex(isElevated: isCurrent)
        )
        .sidebarScrollTarget(.regularTab(tab.id))
    }

    private func regularSplitGroup(
        _ row: SpaceSidebarListElementPayload.RegularSplitGroup
    ) -> some View {
        let isDropTarget: Bool
        if let target = dragSnapshots.regular.splitPairingTarget,
           target.presentation == .existingGroupRow {
            isDropTarget = row.group.memberIDs.contains(target.memberID)
        } else {
            isDropTarget = false
        }
        return SpaceRegularSplitGroupEntryView(
            group: row.group,
            space: space,
            tabByID: row.tabByID,
            selection: selection,
            launcherRuntime: launcherRuntime,
            regularTabCatalog: regularTabCatalog,
            regularTabTargets: regularTabTargets,
            browserContext: browserContext,
            isInteractive: isInteractive,
            isDropHighlighted: isDropTarget,
            tabActionOwner: regularTabActionOwner
        )
        .opacity(
            dragSnapshots.regular.isDragging
                && dragSnapshots.regular.activeDragItemID == row.group.id
                ? SidebarDragSourceDim.opacity
                : 1
        )
        .sidebarScrollTarget(.splitGroup(row.group.id))
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
        _ folder: TabFolder,
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
        dragSnapshots.pinned.isDragging
            && dragSnapshots.pinned.activeDragItemID == itemID
            ? SidebarDragSourceDim.opacity
            : 1
    }
}

private struct SpaceFlatFolderHeaderView: View {
    let folder: SpaceSidebarListElementPayload.Folder
    let space: Space
    let inventory: SidebarSpaceInventorySnapshot
    let selection: SidebarWindowSelectionQuery
    let launcherRuntime: SidebarLauncherRuntimeSnapshot
    let pinProjection: SidebarPinFolderProjection
    let browserContext: SidebarBrowserContext
    let isInteractive: Bool
    let elevatedFolderIDs: Set<UUID>
    let hasLiveSelection: Bool
    let hasActiveProjection: Bool
    let dragSnapshot: SidebarFolderDragSnapshot
    let mutationActions: TabFolderMutationActions
    let contextOwner: TabFolderContextMenuActionOwner

    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.sidebarWindowSelectionSnapshot) private var sidebarSelection

    private var stickyOwner: SidebarFolderStickyProjectionOwner {
        SidebarFolderStickyProjectionOwner(
            folder: folder.model,
            presentation: folder.presentation,
            inventory: inventory,
            launcherRuntime: launcherRuntime,
            selection: selection,
            selectionSnapshot: sidebarSelection,
            windowState: windowState
        )
    }

    var body: some View {
        TabFolderHeaderView(
            folder: folder.model,
            presentation: folder.presentation,
            space: space,
            browserContext: browserContext,
            inventory: inventory,
            selection: selection,
            pinProjection: pinProjection,
            parentFolderId: folder.parentFolderID,
            contentProjection: folder.contentProjection,
            isInteractive: isInteractive,
            folderPreviewIsOpen: dragSnapshot.isFolderPreviewOpen(
                folderID: folder.model.id,
                isOpen: folder.presentation.isExpanded
            ),
            hasActiveSelection:
                hasLiveSelection
                || elevatedFolderIDs.contains(folder.model.id),
            hasActiveProjection: hasActiveProjection,
            isDragging: dragSnapshot.isDragging,
            contextMenuEntries: {
                contextOwner.folderHeaderContextMenuEntries()
            },
            onToggle: {
                mutationActions.toggleFolderOpenState(folder.model.id)
            },
            onActivateShortcutPin: mutationActions.activateShortcutPin,
            onResetProjection:
                !folder.presentation.isExpanded
                    && !folder.contentProjection
                        .visibleCollapsedProjectionIDs.isEmpty
                ? {
                    mutationActions.resetCollapsedProjection(
                        folder.model,
                        inventory: inventory
                    )
                }
                : nil
        )
        .onAppear {
            stickyOwner.reconcileOnAppear()
            refreshLiveFolderIfNeeded()
        }
        .onChange(of: folder.presentation.expansionRevision) { _, _ in
            if folder.presentation.isExpanded {
                stickyOwner.handleExpand()
            } else {
                stickyOwner.handleCollapse()
            }
            stickyOwner.prunePublish()
            refreshLiveFolderIfNeeded()
        }
        .onChange(of: sidebarSelection) { _, _ in
            stickyOwner.handleSelectionChange()
        }
        .onChange(of: folder.orderedDescendantItemIDs) { _, _ in
            stickyOwner.handleMembershipChange()
        }
        .onChange(
            of: folder.contentProjection.targetCollapsedProjectionIDs
        ) { _, _ in
            stickyOwner.prunePublish()
        }
    }

    private func refreshLiveFolderIfNeeded() {
        guard folder.presentation.isExpanded else { return }
        browserContext.liveFolderManager.refreshIfStale(
            folderId: folder.model.id
        )
    }
}

private struct SpaceSidebarBoundaryView: View {
    let boundary: SpaceSidebarListElementPayload.Boundary
    let space: Space
    let regularTabLifecycleCommands: SidebarRegularTabLifecycleCommands
    @Binding var isSidebarHovered: Bool

    var body: some View {
        SpaceTabSectionBoundary(layout: boundary.layout) {
            SpaceSeparator(
                hasTabs: boundary.hasPersistedTabs,
                isHovering: $isSidebarHovered
            ) {
                regularTabLifecycleCommands.clearRegularTabs(for: space.id)
            }
            .padding(.horizontal, 8)
        }
    }
}
