import AppKit
import Combine
import SwiftUI

/// Mathematical slots for dropping generic items within sections.
enum DropZoneSlot: Equatable {
    case essentials(slot: Int)
    case spacePinned(spaceId: UUID, slot: Int)
    case spaceRegular(spaceId: UUID, slot: Int)
    case folder(folderId: UUID, slot: Int)
    case empty
    
    var asDragContainer: TabDragManager.DragContainer {
        switch self {
        case .essentials: return .essentials
        case .spacePinned(let id, _): return .spacePinned(id)
        case .spaceRegular(let id, _): return .spaceRegular(id)
        case .folder(let id, _): return .folder(id)
        default: return .none
        }
    }
    
    var visualIndex: Int {
        switch self {
        case .essentials(let index): return index
        case .spacePinned(_, let index): return index
        case .spaceRegular(_, let index): return index
        case .folder(_, let index): return index
        default: return 0
        }
    }
}

enum FolderDropIntent: Equatable {
    case none
    case contain(folderId: UUID)
    case insertIntoFolder(folderId: UUID, index: Int)
}

enum SidebarFolderDragRegion {
    case header
    case body
    case after
}

struct SidebarFolderDropTargetMetrics: Equatable {
    let folderId: UUID
    var spaceId: UUID
    var topLevelIndex: Int
    var childCount: Int
    var isOpen: Bool
    var headerFrame: CGRect? = nil
    var bodyFrame: CGRect? = nil
    var afterFrame: CGRect? = nil
}

struct SidebarRegularListHitMetrics: Equatable {
    var frame: CGRect
    var itemCount: Int
}

enum SidebarDragPreviewKind: Hashable {
    case row
    case essentialsTile
    case folderRow
}

struct SidebarDragPreviewAsset {
    let image: NSImage
    let size: CGSize
    let anchorOffset: CGPoint
}

struct SidebarDragPreviewModel {
    let item: SumiDragItem
    let sourceZone: DropZoneID
    let baseKind: SidebarDragPreviewKind
    let previewIcon: Image?
    let chromeTemplateSystemImageName: String?
    let sourceSize: CGSize
    let normalizedTopLeadingAnchor: CGPoint
    let pinnedConfig: PinnedTabsConfiguration
    let shortcutPresentationState: ShortcutPresentationState?
    let folderGlyphPresentation: SumiFolderGlyphPresentationState?
    let folderGlyphPalette: SumiFolderGlyphPalette?

    func anchorOffset(in size: CGSize) -> CGPoint {
        CGPoint(
            x: max(0, min(normalizedTopLeadingAnchor.x, 1)) * size.width,
            y: max(0, min(normalizedTopLeadingAnchor.y, 1)) * size.height
        )
    }

    static func normalizedTopLeadingAnchor(
        fromBottomLeading point: CGPoint,
        in sourceSize: CGSize
    ) -> CGPoint {
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return CGPoint(x: 0.5, y: 0.5)
        }

        return CGPoint(
            x: max(0, min(point.x / sourceSize.width, 1)),
            y: max(0, min((sourceSize.height - point.y) / sourceSize.height, 1))
        )
    }
}

struct SidebarSectionGeometryKey: Hashable {
    let spaceId: UUID
    let section: SidebarSectionPrefix

    static func == (lhs: SidebarSectionGeometryKey, rhs: SidebarSectionGeometryKey) -> Bool {
        lhs.spaceId == rhs.spaceId && lhs.section == rhs.section
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(spaceId)
        hasher.combine(section)
    }
}

enum SidebarPageGeometryRenderMode: Hashable {
    case interactive
    case transitionSnapshot
}

struct SidebarPageGeometryKey: Hashable {
    let spaceId: UUID
    let profileId: UUID?

    static func == (lhs: SidebarPageGeometryKey, rhs: SidebarPageGeometryKey) -> Bool {
        lhs.spaceId == rhs.spaceId && lhs.profileId == rhs.profileId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(spaceId)
        hasher.combine(profileId)
    }
}

struct SidebarPageGeometryMetrics: Equatable {
    let spaceId: UUID
    let profileId: UUID?
    var frame: CGRect
    var renderMode: SidebarPageGeometryRenderMode
}

struct SidebarEssentialsLayoutMetrics: Equatable {
    let profileId: UUID?
    var frame: CGRect
    var dropFrame: CGRect
    var columnCount: Int
    var firstSyntheticRowSlot: Int
    var visibleItemCount: Int
    var visibleRowCount: Int
    var maxDropRowCount: Int
    var itemSize: CGSize
    var gridSpacing: CGFloat
    var canAcceptDrop: Bool
}

struct SidebarEssentialsPreviewState: Equatable {
    var expandedDropRowCount: Int
    var ghostSlot: Int?
}

private struct SidebarRuntimeGeometryStore {
    var pageGeometryByKey: [SidebarPageGeometryKey: SidebarPageGeometryMetrics] = [:]
    var sectionFramesBySpace: [SidebarSectionGeometryKey: CGRect] = [:]
    var folderDropTargets: [UUID: SidebarFolderDropTargetMetrics] = [:]
    var regularListHitTargets: [UUID: SidebarRegularListHitMetrics] = [:]
    var essentialsLayoutMetricsBySpace: [UUID: SidebarEssentialsLayoutMetrics] = [:]
}

struct SidebarGeometrySnapshot: Equatable {
    var pageGeometryByKey: [SidebarPageGeometryKey: SidebarPageGeometryMetrics] = [:]
    var sectionFramesBySpace: [SidebarSectionGeometryKey: CGRect] = [:]
    var folderDropTargets: [UUID: SidebarFolderDropTargetMetrics] = [:]
    var regularListHitTargets: [UUID: SidebarRegularListHitMetrics] = [:]
    var essentialsLayoutMetricsBySpace: [UUID: SidebarEssentialsLayoutMetrics] = [:]

    static let empty = SidebarGeometrySnapshot()
}

enum SidebarSectionPrefix: Hashable {
    case essentials
    case spacePinned
    case spaceRegular
}

@MainActor
final class SidebarDragState: ObservableObject {
    static let shared = SidebarDragState()
    
    @Published var isDragging: Bool = false
    @Published var hoveredSlot: DropZoneSlot = .empty
    @Published var folderDropIntent: FolderDropIntent = .none
    @Published var activeHoveredFolderId: UUID? = nil
    @Published var activeSplitTarget: SplitViewManager.Side? = nil
    @Published var activeDragItemId: UUID? = nil
    @Published var dragLocation: CGPoint? = nil
    @Published var previewKind: SidebarDragPreviewKind? = nil
    @Published var previewAssets: [SidebarDragPreviewKind: SidebarDragPreviewAsset] = [:]
    @Published var previewModel: SidebarDragPreviewModel? = nil
    @Published var isInternalDragSession: Bool = false
    
    // For Zen's auto workspace switch
    @Published var isHoveringNearEdge: Bool = false
    
    // Global coordinate mapping
    @Published private(set) var geometrySnapshot: SidebarGeometrySnapshot = .empty
    @Published private(set) var geometryRevision: Int = 0
    @Published var essentialsPreviewStateBySpace: [UUID: SidebarEssentialsPreviewState] = [:]
    @Published var sidebarGeometryGeneration: Int = 0
    @Published private(set) var activeGeometryGeneration: Int = 0
    @Published private(set) var pendingGeometryGeneration: Int? = nil
    
    private var activeGeometryStore = SidebarRuntimeGeometryStore()
    private var pendingGeometryStore: SidebarRuntimeGeometryStore? = nil
    private var pendingInteractivePageKey: SidebarPageGeometryKey? = nil
    private var pendingGeometryRefreshRequested = false
    private var isGeometryRefreshFlushScheduled = false
    private var isGeometrySnapshotPublishScheduled = false
    
    init() {}

    private static func resolvedMetricsRowCount(
        for height: CGFloat,
        itemSize: CGSize,
        gridSpacing: CGFloat,
        fallback: Int
    ) -> Int {
        guard itemSize.height > 0 else { return max(fallback, 1) }
        let stride = max(itemSize.height + gridSpacing, 1)
        let derivedRows = Int(floor(max(height - itemSize.height, 0) / stride)) + 1
        return max(fallback, derivedRows, 1)
    }

    var sectionFramesBySpace: [SidebarSectionGeometryKey: CGRect] {
        geometrySnapshot.sectionFramesBySpace
    }

    var pageGeometryByKey: [SidebarPageGeometryKey: SidebarPageGeometryMetrics] {
        geometrySnapshot.pageGeometryByKey
    }

    var folderDropTargets: [UUID: SidebarFolderDropTargetMetrics] {
        geometrySnapshot.folderDropTargets
    }

    var regularListHitTargets: [UUID: SidebarRegularListHitMetrics] {
        geometrySnapshot.regularListHitTargets
    }

    var essentialsLayoutMetricsBySpace: [UUID: SidebarEssentialsLayoutMetrics] {
        geometrySnapshot.essentialsLayoutMetricsBySpace
    }

    private func snapshot(from store: SidebarRuntimeGeometryStore) -> SidebarGeometrySnapshot {
        SidebarGeometrySnapshot(
            pageGeometryByKey: store.pageGeometryByKey,
            sectionFramesBySpace: store.sectionFramesBySpace,
            folderDropTargets: store.folderDropTargets,
            regularListHitTargets: store.regularListHitTargets,
            essentialsLayoutMetricsBySpace: store.essentialsLayoutMetricsBySpace
        )
    }

    private func setGeometrySnapshot(_ snapshot: SidebarGeometrySnapshot) {
        guard geometrySnapshot != snapshot else { return }
        geometrySnapshot = snapshot
    }

    private func scheduleGeometrySnapshotPublish() {
        guard !isGeometrySnapshotPublishScheduled else { return }
        isGeometrySnapshotPublishScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.flushScheduledGeometrySnapshotPublish()
        }
    }

    private func flushScheduledGeometrySnapshotPublish() {
        isGeometrySnapshotPublishScheduled = false
        setGeometrySnapshot(snapshot(from: activeGeometryStore))
    }

    private func publishActiveGeometryStore() {
        scheduleGeometrySnapshotPublish()
    }

    private func mutateGeometryStore(
        for generation: Int,
        _ mutate: (inout SidebarRuntimeGeometryStore) -> Void
    ) {
        if generation == activeGeometryGeneration {
            mutate(&activeGeometryStore)
            publishActiveGeometryStore()
            return
        }

        guard generation == pendingGeometryGeneration else { return }
        if pendingGeometryStore == nil {
            pendingGeometryStore = SidebarRuntimeGeometryStore()
        }
        mutate(&pendingGeometryStore!)
        promotePendingGeometryIfReady()
    }

    private func upsertPageGeometry(
        spaceId: UUID,
        profileId: UUID?,
        frame: CGRect,
        renderMode: SidebarPageGeometryRenderMode,
        in store: inout SidebarRuntimeGeometryStore
    ) {
        let key = SidebarPageGeometryKey(spaceId: spaceId, profileId: profileId)
        if renderMode == .interactive {
            store.pageGeometryByKey = store.pageGeometryByKey.filter { existingKey, metrics in
                existingKey == key || metrics.renderMode != .interactive
            }
        }
        store.pageGeometryByKey[key] = SidebarPageGeometryMetrics(
            spaceId: spaceId,
            profileId: profileId,
            frame: frame,
            renderMode: renderMode
        )
    }

    private func removePageGeometry(
        spaceId: UUID,
        profileId: UUID?,
        from store: inout SidebarRuntimeGeometryStore
    ) {
        store.pageGeometryByKey[SidebarPageGeometryKey(spaceId: spaceId, profileId: profileId)] = nil
    }

    private func promotePendingGeometryIfReady() {
        guard let pendingGeneration = pendingGeometryGeneration,
              let pendingGeometryStore,
              let pendingInteractivePageKey else {
            return
        }

        guard pendingGeometryStore.pageGeometryByKey[pendingInteractivePageKey]?.renderMode == .interactive else {
            return
        }

        let spaceId = pendingInteractivePageKey.spaceId
        let essentialsKey = SidebarSectionGeometryKey(spaceId: spaceId, section: .essentials)
        let pinnedKey = SidebarSectionGeometryKey(spaceId: spaceId, section: .spacePinned)
        let regularKey = SidebarSectionGeometryKey(spaceId: spaceId, section: .spaceRegular)

        guard pendingGeometryStore.sectionFramesBySpace[essentialsKey] != nil,
              pendingGeometryStore.sectionFramesBySpace[pinnedKey] != nil,
              pendingGeometryStore.sectionFramesBySpace[regularKey] != nil,
              pendingGeometryStore.essentialsLayoutMetricsBySpace[spaceId] != nil,
              pendingGeometryStore.regularListHitTargets[spaceId] != nil else {
            return
        }

        activeGeometryStore = pendingGeometryStore
        activeGeometryGeneration = pendingGeneration
        publishActiveGeometryStore()

        self.pendingGeometryStore = nil
        self.pendingGeometryGeneration = nil
        self.pendingInteractivePageKey = nil
    }

    private func clearEssentialsPreviewState() {
        essentialsPreviewStateBySpace = [:]
    }
    
    func resetInteractionState() {
        isDragging = false
        clearHoverState()
        activeDragItemId = nil
        dragLocation = nil
        previewKind = nil
        previewAssets = [:]
        previewModel = nil
        isInternalDragSession = false
        isHoveringNearEdge = false
        clearEssentialsPreviewState()
    }

    func beginPendingGeometryEpoch(
        expectedSpaceId: UUID?,
        profileId: UUID?
    ) {
        sidebarGeometryGeneration &+= 1
        pendingGeometryGeneration = sidebarGeometryGeneration
        pendingGeometryStore = SidebarRuntimeGeometryStore()
        pendingInteractivePageKey = expectedSpaceId.map {
            SidebarPageGeometryKey(spaceId: $0, profileId: profileId)
        }
        clearHoverState()
        clearEssentialsPreviewState()
        requestGeometryRefresh()
        promotePendingGeometryIfReady()
    }

    func requestGeometryRefresh() {
        pendingGeometryRefreshRequested = true

        guard !isGeometryRefreshFlushScheduled else { return }
        isGeometryRefreshFlushScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.flushPendingGeometryRefresh()
        }
    }

    private func flushPendingGeometryRefresh() {
        isGeometryRefreshFlushScheduled = false
        guard pendingGeometryRefreshRequested else { return }
        pendingGeometryRefreshRequested = false
        geometryRevision &+= 1
    }

    func beginInternalDragSession(
        itemId: UUID,
        location: CGPoint,
        previewKind: SidebarDragPreviewKind,
        previewAssets: [SidebarDragPreviewKind: SidebarDragPreviewAsset],
        previewModel: SidebarDragPreviewModel? = nil
    ) {
        isDragging = true
        activeDragItemId = itemId
        dragLocation = location
        self.previewKind = previewKind
        self.previewAssets = previewAssets
        self.previewModel = previewModel
        isInternalDragSession = true
        clearEssentialsPreviewState()
        requestGeometryRefresh()
    }

    func beginExternalDragSession(itemId: UUID?) {
        isDragging = true
        activeDragItemId = itemId
        isInternalDragSession = false
        clearEssentialsPreviewState()
        requestGeometryRefresh()
    }

    func updateDragLocation(_ location: CGPoint) {
        dragLocation = location
    }

    func clearHoverState() {
        hoveredSlot = .empty
        folderDropIntent = .none
        activeHoveredFolderId = nil
        activeSplitTarget = nil
        clearEssentialsPreviewState()
    }

    func updateEssentialsPreviewState(
        at location: CGPoint,
        resolution: DropZoneSlot
    ) {
        guard isDragging,
              previewAssets[.essentialsTile] != nil,
              let hoveredPage = hoveredInteractivePage(at: location),
              let metrics = essentialsLayoutMetricsBySpace[hoveredPage.spaceId],
              metrics.dropFrame.contains(location),
              metrics.canAcceptDrop,
              metrics.maxDropRowCount > metrics.visibleRowCount else {
            clearEssentialsPreviewState()
            return
        }

        guard case .essentials(let slot) = resolution else {
            clearEssentialsPreviewState()
            return
        }

        let slotAllowsEmptyGridPreview = metrics.visibleItemCount == 0 && slot == 0
        guard slot >= metrics.firstSyntheticRowSlot || slotAllowsEmptyGridPreview else {
            clearEssentialsPreviewState()
            return
        }

        essentialsPreviewStateBySpace = [
            hoveredPage.spaceId: SidebarEssentialsPreviewState(
                expandedDropRowCount: metrics.maxDropRowCount,
                ghostSlot: slot
            )
        ]
    }

    func essentialsPreviewState(for spaceId: UUID) -> SidebarEssentialsPreviewState? {
        essentialsPreviewStateBySpace[spaceId]
    }

    func sectionFrame(
        for section: SidebarSectionPrefix,
        in spaceId: UUID
    ) -> CGRect? {
        sectionFramesBySpace[SidebarSectionGeometryKey(spaceId: spaceId, section: section)]
    }

    func hoveredInteractivePage(at location: CGPoint) -> SidebarPageGeometryMetrics? {
        pageGeometryByKey.values
            .filter { $0.renderMode == .interactive && $0.frame.contains(location) }
            .sorted { lhs, rhs in
                let leftArea = lhs.frame.width * lhs.frame.height
                let rightArea = rhs.frame.width * rhs.frame.height
                if leftArea != rightArea { return leftArea < rightArea }
                return lhs.spaceId.uuidString < rhs.spaceId.uuidString
            }
            .first
    }

    private func makeEssentialsLayoutMetrics(
        profileId: UUID?,
        frame: CGRect,
        dropFrame: CGRect,
        itemCount: Int,
        columnCount: Int,
        firstSyntheticRowSlot: Int? = nil,
        rowCount: Int,
        itemSize: CGSize,
        gridSpacing: CGFloat,
        canAcceptDrop: Bool,
        visibleItemCount: Int? = nil,
        visibleRowCount: Int? = nil,
        maxDropRowCount: Int? = nil
    ) -> SidebarEssentialsLayoutMetrics {
        let resolvedVisibleRowCount = max(
            visibleRowCount ?? Self.resolvedMetricsRowCount(
                for: frame.height,
                itemSize: itemSize,
                gridSpacing: gridSpacing,
                fallback: rowCount
            ),
            1
        )
        let resolvedMaxDropRowCount = max(
            maxDropRowCount ?? Self.resolvedMetricsRowCount(
                for: dropFrame.height,
                itemSize: itemSize,
                gridSpacing: gridSpacing,
                fallback: resolvedVisibleRowCount
            ),
            resolvedVisibleRowCount,
            1
        )
        let resolvedFirstSyntheticRowSlot = firstSyntheticRowSlot
            ?? (max(resolvedVisibleRowCount, 1) * max(columnCount, 1))

        return SidebarEssentialsLayoutMetrics(
            profileId: profileId,
            frame: frame,
            dropFrame: dropFrame,
            columnCount: columnCount,
            firstSyntheticRowSlot: resolvedFirstSyntheticRowSlot,
            visibleItemCount: visibleItemCount ?? itemCount,
            visibleRowCount: resolvedVisibleRowCount,
            maxDropRowCount: resolvedMaxDropRowCount,
            itemSize: itemSize,
            gridSpacing: gridSpacing,
            canAcceptDrop: canAcceptDrop
        )
    }

    func applyPageGeometry(
        spaceId: UUID,
        profileId: UUID?,
        frame: CGRect?,
        renderMode: SidebarPageGeometryRenderMode,
        generation: Int
    ) {
        guard renderMode == .interactive else { return }
        mutateGeometryStore(for: generation) { store in
            if let frame {
                upsertPageGeometry(
                    spaceId: spaceId,
                    profileId: profileId,
                    frame: frame,
                    renderMode: renderMode,
                    in: &store
                )
            } else {
                removePageGeometry(
                    spaceId: spaceId,
                    profileId: profileId,
                    from: &store
                )
            }
        }
    }

    func applySectionFrame(
        spaceId: UUID,
        section: SidebarSectionPrefix,
        frame: CGRect?,
        generation: Int
    ) {
        mutateGeometryStore(for: generation) { store in
            let key = SidebarSectionGeometryKey(spaceId: spaceId, section: section)
            if let frame {
                store.sectionFramesBySpace[key] = frame
            } else {
                store.sectionFramesBySpace[key] = nil
            }
        }
    }

    func applyFolderDropTarget(
        folderId: UUID,
        spaceId: UUID,
        topLevelIndex: Int,
        childCount: Int,
        isOpen: Bool,
        region: SidebarFolderDragRegion,
        frame: CGRect?,
        isActive: Bool,
        generation: Int
    ) {
        mutateGeometryStore(for: generation) { store in
            guard isActive, let frame else {
                guard var target = store.folderDropTargets[folderId] else { return }
                switch region {
                case .header:
                    target.headerFrame = nil
                case .body:
                    target.bodyFrame = nil
                case .after:
                    target.afterFrame = nil
                }
                if target.headerFrame == nil && target.bodyFrame == nil && target.afterFrame == nil {
                    store.folderDropTargets[folderId] = nil
                } else {
                    store.folderDropTargets[folderId] = target
                }
                return
            }

            var target = store.folderDropTargets[folderId] ?? SidebarFolderDropTargetMetrics(
                folderId: folderId,
                spaceId: spaceId,
                topLevelIndex: topLevelIndex,
                childCount: childCount,
                isOpen: isOpen
            )
            target.spaceId = spaceId
            target.topLevelIndex = topLevelIndex
            target.childCount = childCount
            target.isOpen = isOpen
            switch region {
            case .header:
                target.headerFrame = frame
            case .body:
                target.bodyFrame = frame
            case .after:
                target.afterFrame = frame
            }
            store.folderDropTargets[folderId] = target
        }
    }

    func applyRegularListHitTarget(
        spaceId: UUID,
        frame: CGRect?,
        itemCount: Int,
        generation: Int
    ) {
        mutateGeometryStore(for: generation) { store in
            if let frame {
                store.regularListHitTargets[spaceId] = SidebarRegularListHitMetrics(
                    frame: frame,
                    itemCount: itemCount
                )
            } else {
                store.regularListHitTargets[spaceId] = nil
            }
        }
    }

    func applyEssentialsLayoutMetrics(
        spaceId: UUID,
        profileId: UUID?,
        frame: CGRect?,
        dropFrame: CGRect?,
        itemCount: Int,
        columnCount: Int,
        firstSyntheticRowSlot: Int? = nil,
        rowCount: Int,
        itemSize: CGSize,
        gridSpacing: CGFloat,
        canAcceptDrop: Bool,
        visibleItemCount: Int,
        visibleRowCount: Int,
        maxDropRowCount: Int,
        generation: Int
    ) {
        mutateGeometryStore(for: generation) { store in
            guard let frame, let dropFrame else {
                store.essentialsLayoutMetricsBySpace[spaceId] = nil
                return
            }

            store.essentialsLayoutMetricsBySpace[spaceId] = makeEssentialsLayoutMetrics(
                profileId: profileId,
                frame: frame,
                dropFrame: dropFrame,
                itemCount: itemCount,
                columnCount: columnCount,
                firstSyntheticRowSlot: firstSyntheticRowSlot,
                rowCount: rowCount,
                itemSize: itemSize,
                gridSpacing: gridSpacing,
                canAcceptDrop: canAcceptDrop,
                visibleItemCount: visibleItemCount,
                visibleRowCount: visibleRowCount,
                maxDropRowCount: maxDropRowCount
            )
        }
    }
}

// MARK: - Geometry tracking (deferred)

/// Publishes geometry into `SidebarDragState` on the next main run loop turn so SwiftUI does not emit
/// "Publishing changes from within view updates" during layout/preference application.
private enum SidebarDragStateDeferredGeometry {
    static func setPageGeometry(
        spaceId: UUID,
        profileId: UUID?,
        renderMode: SidebarPageGeometryRenderMode,
        generation: Int,
        _ frame: CGRect?
    ) {
        Task { @MainActor in
            SidebarDragState.shared.applyPageGeometry(
                spaceId: spaceId,
                profileId: profileId,
                frame: frame,
                renderMode: renderMode,
                generation: generation
            )
        }
    }

    static func setSectionFrame(
        spaceId: UUID,
        section: SidebarSectionPrefix,
        generation: Int,
        _ frame: CGRect?
    ) {
        Task { @MainActor in
            SidebarDragState.shared.applySectionFrame(
                spaceId: spaceId,
                section: section,
                frame: frame,
                generation: generation
            )
        }
    }

    static func updateFolderDropTarget(
        isActive: Bool,
        folderId: UUID,
        spaceId: UUID,
        topLevelIndex: Int,
        childCount: Int,
        isOpen: Bool,
        region: SidebarFolderDragRegion,
        frame: CGRect,
        generation: Int
    ) {
        Task { @MainActor in
            SidebarDragState.shared.applyFolderDropTarget(
                folderId: folderId,
                spaceId: spaceId,
                topLevelIndex: topLevelIndex,
                childCount: childCount,
                isOpen: isOpen,
                region: region,
                frame: frame,
                isActive: isActive,
                generation: generation
            )
        }
    }

    static func removeFolderDropTarget(folderId: UUID, region: SidebarFolderDragRegion, generation: Int) {
        Task { @MainActor in
            SidebarDragState.shared.applyFolderDropTarget(
                folderId: folderId,
                spaceId: UUID(),
                topLevelIndex: 0,
                childCount: 0,
                isOpen: false,
                region: region,
                frame: nil,
                isActive: false,
                generation: generation
            )
        }
    }

    static func updateRegularListHitTarget(spaceId: UUID, frame: CGRect, itemCount: Int, generation: Int) {
        Task { @MainActor in
            SidebarDragState.shared.applyRegularListHitTarget(
                spaceId: spaceId,
                frame: frame,
                itemCount: itemCount,
                generation: generation
            )
        }
    }

    static func removeRegularListHitTarget(spaceId: UUID, generation: Int) {
        Task { @MainActor in
            SidebarDragState.shared.applyRegularListHitTarget(
                spaceId: spaceId,
                frame: nil,
                itemCount: 0,
                generation: generation
            )
        }
    }

    static func updateEssentialsLayoutMetrics(
        spaceId: UUID,
        profileId: UUID?,
        frame: CGRect,
        dropFrame: CGRect,
        itemCount: Int,
        columnCount: Int,
        firstSyntheticRowSlot: Int? = nil,
        rowCount: Int,
        itemSize: CGSize,
        gridSpacing: CGFloat,
        canAcceptDrop: Bool,
        visibleItemCount: Int,
        visibleRowCount: Int,
        maxDropRowCount: Int,
        generation: Int
    ) {
        Task { @MainActor in
            SidebarDragState.shared.applyEssentialsLayoutMetrics(
                spaceId: spaceId,
                profileId: profileId,
                frame: frame,
                dropFrame: dropFrame,
                itemCount: itemCount,
                columnCount: columnCount,
                firstSyntheticRowSlot: firstSyntheticRowSlot,
                rowCount: rowCount,
                itemSize: itemSize,
                gridSpacing: gridSpacing,
                canAcceptDrop: canAcceptDrop,
                visibleItemCount: visibleItemCount,
                visibleRowCount: visibleRowCount,
                maxDropRowCount: maxDropRowCount,
                generation: generation
            )
        }
    }

    static func removeEssentialsLayoutMetrics(spaceId: UUID, generation: Int) {
        Task { @MainActor in
            SidebarDragState.shared.applyEssentialsLayoutMetrics(
                spaceId: spaceId,
                profileId: nil,
                frame: nil,
                dropFrame: nil,
                itemCount: 0,
                columnCount: 1,
                rowCount: 1,
                itemSize: .zero,
                gridSpacing: 0,
                canAcceptDrop: false,
                visibleItemCount: 0,
                visibleRowCount: 0,
                maxDropRowCount: 0,
                generation: generation
            )
        }
    }
}

// MARK: - Geometry Tracking

struct SidebarPageGeometryReporter: ViewModifier {
    let spaceId: UUID
    let profileId: UUID?
    let renderMode: SidebarPageGeometryRenderMode
    let generation: Int
    let isEnabled: Bool
    @ObservedObject private var dragState = SidebarDragState.shared

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onChange(of: geo.frame(in: .global)) { _, newFrame in
                            SidebarDragStateDeferredGeometry.setPageGeometry(
                                spaceId: spaceId,
                                profileId: profileId,
                                renderMode: renderMode,
                                generation: generation,
                                isEnabled ? newFrame : nil
                            )
                        }
                        .onChange(of: renderMode) { _, newRenderMode in
                            SidebarDragStateDeferredGeometry.setPageGeometry(
                                spaceId: spaceId,
                                profileId: profileId,
                                renderMode: newRenderMode,
                                generation: generation,
                                isEnabled ? geo.frame(in: .global) : nil
                            )
                        }
                        .onChange(of: generation) { _, newGeneration in
                            SidebarDragStateDeferredGeometry.setPageGeometry(
                                spaceId: spaceId,
                                profileId: profileId,
                                renderMode: renderMode,
                                generation: newGeneration,
                                isEnabled ? geo.frame(in: .global) : nil
                            )
                        }
                        .onChange(of: isEnabled) { _, enabled in
                            SidebarDragStateDeferredGeometry.setPageGeometry(
                                spaceId: spaceId,
                                profileId: profileId,
                                renderMode: renderMode,
                                generation: generation,
                                enabled ? geo.frame(in: .global) : nil
                            )
                        }
                        .onChange(of: dragState.geometryRevision) { _, _ in
                            SidebarDragStateDeferredGeometry.setPageGeometry(
                                spaceId: spaceId,
                                profileId: profileId,
                                renderMode: renderMode,
                                generation: generation,
                                isEnabled ? geo.frame(in: .global) : nil
                            )
                        }
                        .onAppear {
                            SidebarDragStateDeferredGeometry.setPageGeometry(
                                spaceId: spaceId,
                                profileId: profileId,
                                renderMode: renderMode,
                                generation: generation,
                                isEnabled ? geo.frame(in: .global) : nil
                            )
                        }
                        .onDisappear {
                            SidebarDragStateDeferredGeometry.setPageGeometry(
                                spaceId: spaceId,
                                profileId: profileId,
                                renderMode: renderMode,
                                generation: generation,
                                nil
                            )
                        }
                }
            }
    }
}

struct SidebarSectionGeometryReporter: ViewModifier {
    let spaceId: UUID
    let section: SidebarSectionPrefix
    let generation: Int
    let isEnabled: Bool
    @ObservedObject private var dragState = SidebarDragState.shared
    
    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onChange(of: geo.frame(in: .global)) { _, newFrame in
                            SidebarDragStateDeferredGeometry.setSectionFrame(
                                spaceId: spaceId,
                                section: section,
                                generation: generation,
                                isEnabled ? newFrame : nil
                            )
                        }
                        .onChange(of: generation) { _, newGeneration in
                            SidebarDragStateDeferredGeometry.setSectionFrame(
                                spaceId: spaceId,
                                section: section,
                                generation: newGeneration,
                                isEnabled ? geo.frame(in: .global) : nil
                            )
                        }
                        .onChange(of: isEnabled) { _, enabled in
                            SidebarDragStateDeferredGeometry.setSectionFrame(
                                spaceId: spaceId,
                                section: section,
                                generation: generation,
                                enabled ? geo.frame(in: .global) : nil
                            )
                        }
                        .onChange(of: dragState.geometryRevision) { _, _ in
                            SidebarDragStateDeferredGeometry.setSectionFrame(
                                spaceId: spaceId,
                                section: section,
                                generation: generation,
                                isEnabled ? geo.frame(in: .global) : nil
                            )
                        }
                        .onAppear {
                            SidebarDragStateDeferredGeometry.setSectionFrame(
                                spaceId: spaceId,
                                section: section,
                                generation: generation,
                                isEnabled ? geo.frame(in: .global) : nil
                            )
                        }
                        .onDisappear {
                            SidebarDragStateDeferredGeometry.setSectionFrame(
                                spaceId: spaceId,
                                section: section,
                                generation: generation,
                                nil
                            )
                        }
                }
            }
    }
}

extension View {
    func sidebarPageGeometry(
        spaceId: UUID,
        profileId: UUID?,
        renderMode: SidebarPageGeometryRenderMode,
        generation: Int,
        isEnabled: Bool = true
    ) -> some View {
        modifier(
            SidebarPageGeometryReporter(
                spaceId: spaceId,
                profileId: profileId,
                renderMode: renderMode,
                generation: generation,
                isEnabled: isEnabled
            )
        )
    }

    func sidebarSectionGeometry(
        for section: SidebarSectionPrefix,
        spaceId: UUID,
        generation: Int,
        isEnabled: Bool = true
    ) -> some View {
        modifier(
            SidebarSectionGeometryReporter(
                spaceId: spaceId,
                section: section,
                generation: generation,
                isEnabled: isEnabled
            )
        )
    }

    func sidebarFolderDropGeometry(
        folderId: UUID,
        spaceId: UUID,
        topLevelIndex: Int,
        childCount: Int,
        isOpen: Bool,
        region: SidebarFolderDragRegion,
        generation: Int,
        isActive: Bool = true
    ) -> some View {
        modifier(
            SidebarFolderDropGeometryReporter(
                folderId: folderId,
                spaceId: spaceId,
                topLevelIndex: topLevelIndex,
                childCount: childCount,
                isOpen: isOpen,
                region: region,
                isActive: isActive,
                generation: generation
            )
        )
    }

    func sidebarRegularListHitGeometry(
        for spaceId: UUID,
        itemCount: Int,
        generation: Int,
        isEnabled: Bool = true
    ) -> some View {
        modifier(
            SidebarRegularListHitGeometryReporter(
                spaceId: spaceId,
                itemCount: itemCount,
                generation: generation,
                isEnabled: isEnabled
            )
        )
    }

    func sidebarEssentialsLayoutGeometry(
        spaceId: UUID,
        profileId: UUID?,
        itemCount: Int,
        columnCount: Int,
        firstSyntheticRowSlot: Int? = nil,
        rowCount: Int,
        visibleItemCount: Int,
        visibleRowCount: Int,
        maxDropRowCount: Int,
        dropFrame: CGRect,
        itemSize: CGSize,
        gridSpacing: CGFloat,
        canAcceptDrop: Bool,
        generation: Int,
        isEnabled: Bool = true
    ) -> some View {
        modifier(
            SidebarEssentialsLayoutGeometryReporter(
                spaceId: spaceId,
                profileId: profileId,
                itemCount: itemCount,
                columnCount: columnCount,
                firstSyntheticRowSlot: firstSyntheticRowSlot,
                rowCount: rowCount,
                visibleItemCount: visibleItemCount,
                visibleRowCount: visibleRowCount,
                maxDropRowCount: maxDropRowCount,
                dropFrame: dropFrame,
                itemSize: itemSize,
                gridSpacing: gridSpacing,
                canAcceptDrop: canAcceptDrop,
                generation: generation,
                isEnabled: isEnabled
            )
        )
    }
}

struct SidebarFolderDropGeometryReporter: ViewModifier {
    let folderId: UUID
    let spaceId: UUID
    let topLevelIndex: Int
    let childCount: Int
    let isOpen: Bool
    let region: SidebarFolderDragRegion
    let isActive: Bool
    let generation: Int
    @ObservedObject private var dragState = SidebarDragState.shared

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onChange(of: geo.frame(in: .global)) { _, newFrame in
                            update(frame: newFrame)
                        }
                        .onChange(of: topLevelIndex) { _, _ in
                            update(frame: geo.frame(in: .global))
                        }
                        .onChange(of: childCount) { _, _ in
                            update(frame: geo.frame(in: .global))
                        }
                        .onChange(of: isOpen) { _, _ in
                            update(frame: geo.frame(in: .global))
                        }
                        .onChange(of: isActive) { _, _ in
                            update(frame: geo.frame(in: .global))
                        }
                        .onChange(of: generation) { _, _ in
                            update(frame: geo.frame(in: .global))
                        }
                        .onChange(of: dragState.isDragging) { _, isDragging in
                            if isDragging {
                                update(frame: geo.frame(in: .global))
                            }
                        }
                        .onChange(of: dragState.geometryRevision) { _, _ in
                            update(frame: geo.frame(in: .global))
                        }
                        .onAppear {
                            update(frame: geo.frame(in: .global))
                        }
                        .onDisappear {
                            SidebarDragStateDeferredGeometry.removeFolderDropTarget(
                                folderId: folderId,
                                region: region,
                                generation: generation
                            )
                        }
                }
            }
    }

    private func update(frame: CGRect) {
        SidebarDragStateDeferredGeometry.updateFolderDropTarget(
            isActive: isActive,
            folderId: folderId,
            spaceId: spaceId,
            topLevelIndex: topLevelIndex,
            childCount: childCount,
            isOpen: isOpen,
            region: region,
            frame: frame,
            generation: generation
        )
    }
}

struct SidebarRegularListHitGeometryReporter: ViewModifier {
    let spaceId: UUID
    let itemCount: Int
    let generation: Int
    let isEnabled: Bool
    @ObservedObject private var dragState = SidebarDragState.shared

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onChange(of: geo.frame(in: .global)) { _, newFrame in
                            update(frame: newFrame)
                        }
                        .onChange(of: itemCount) { _, _ in
                            update(frame: geo.frame(in: .global))
                        }
                        .onChange(of: isEnabled) { _, _ in
                            update(frame: geo.frame(in: .global))
                        }
                        .onChange(of: generation) { _, _ in
                            update(frame: geo.frame(in: .global))
                        }
                        .onChange(of: dragState.geometryRevision) { _, _ in
                            update(frame: geo.frame(in: .global))
                        }
                        .onAppear {
                            update(frame: geo.frame(in: .global))
                        }
                        .onDisappear {
                            SidebarDragStateDeferredGeometry.removeRegularListHitTarget(
                                spaceId: spaceId,
                                generation: generation
                            )
                        }
                }
            }
    }

    private func update(frame: CGRect) {
        if isEnabled {
            SidebarDragStateDeferredGeometry.updateRegularListHitTarget(
                spaceId: spaceId,
                frame: frame,
                itemCount: itemCount,
                generation: generation
            )
        } else {
            SidebarDragStateDeferredGeometry.removeRegularListHitTarget(
                spaceId: spaceId,
                generation: generation
            )
        }
    }
}

struct SidebarEssentialsLayoutGeometryReporter: ViewModifier {
    let spaceId: UUID
    let profileId: UUID?
    let itemCount: Int
    let columnCount: Int
    let firstSyntheticRowSlot: Int?
    let rowCount: Int
    let visibleItemCount: Int
    let visibleRowCount: Int
    let maxDropRowCount: Int
    let dropFrame: CGRect
    let itemSize: CGSize
    let gridSpacing: CGFloat
    let canAcceptDrop: Bool
    let generation: Int
    let isEnabled: Bool
    @ObservedObject private var dragState = SidebarDragState.shared

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geo in
                    Color.clear
                        .onChange(of: geo.frame(in: .global)) { _, _ in
                            update(frame: geo.frame(in: .global))
                        }
                        .onChange(of: itemCount) { _, _ in
                            update(frame: geo.frame(in: .global))
                        }
                        .onChange(of: columnCount) { _, _ in
                            update(frame: geo.frame(in: .global))
                        }
                        .onChange(of: rowCount) { _, _ in
                            update(frame: geo.frame(in: .global))
                        }
                        .onChange(of: dropFrame) { _, _ in
                            update(frame: geo.frame(in: .global))
                        }
                        .onChange(of: itemSize) { _, _ in
                            update(frame: geo.frame(in: .global))
                        }
                        .onChange(of: gridSpacing) { _, _ in
                            update(frame: geo.frame(in: .global))
                        }
                        .onChange(of: canAcceptDrop) { _, _ in
                            update(frame: geo.frame(in: .global))
                        }
                        .onChange(of: visibleItemCount) { _, _ in
                            update(frame: geo.frame(in: .global))
                        }
                        .onChange(of: visibleRowCount) { _, _ in
                            update(frame: geo.frame(in: .global))
                        }
                        .onChange(of: maxDropRowCount) { _, _ in
                            update(frame: geo.frame(in: .global))
                        }
                        .onChange(of: generation) { _, _ in
                            update(frame: geo.frame(in: .global))
                        }
                        .onChange(of: isEnabled) { _, _ in
                            update(frame: geo.frame(in: .global))
                        }
                        .onChange(of: dragState.geometryRevision) { _, _ in
                            update(frame: geo.frame(in: .global))
                        }
                        .onAppear {
                            update(frame: geo.frame(in: .global))
                        }
                        .onDisappear {
                            SidebarDragStateDeferredGeometry.removeEssentialsLayoutMetrics(
                                spaceId: spaceId,
                                generation: generation
                            )
                        }
                }
            }
    }

    private func update(frame: CGRect) {
        if isEnabled {
            let resolvedDropFrame = CGRect(
                x: frame.minX + dropFrame.minX,
                y: frame.minY + dropFrame.minY,
                width: dropFrame.width,
                height: dropFrame.height
            )
            SidebarDragStateDeferredGeometry.updateEssentialsLayoutMetrics(
                spaceId: spaceId,
                profileId: profileId,
                frame: frame,
                dropFrame: resolvedDropFrame,
                itemCount: itemCount,
                columnCount: columnCount,
                firstSyntheticRowSlot: firstSyntheticRowSlot,
                rowCount: rowCount,
                itemSize: itemSize,
                gridSpacing: gridSpacing,
                canAcceptDrop: canAcceptDrop,
                visibleItemCount: visibleItemCount,
                visibleRowCount: visibleRowCount,
                maxDropRowCount: maxDropRowCount,
                generation: generation
            )
        } else {
            SidebarDragStateDeferredGeometry.removeEssentialsLayoutMetrics(
                spaceId: spaceId,
                generation: generation
            )
        }
    }
}
