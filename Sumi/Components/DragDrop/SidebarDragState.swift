import AppKit
import Combine
import SwiftUI

private enum SidebarDragGeometryMutationKey: Hashable {
    case page(SidebarPageGeometryKey)
    case section(SidebarSectionGeometryKey)
    case folder(UUID, SidebarFolderDragRegion)
    case topLevelPinnedItem(UUID)
    case folderChild(UUID)
    case regularList(UUID)
    case essentials(UUID)
}

private struct SidebarDragGeometryMutation {
    let apply: @MainActor (SidebarDragState) -> Void
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
    @Published var previewDragLocation: CGPoint? = nil
    @Published var previewKind: SidebarDragPreviewKind? = nil
    @Published var previewAssets: [SidebarDragPreviewKind: SidebarDragPreviewAsset] = [:]
    @Published var previewModel: SidebarDragPreviewModel? = nil
    @Published var isInternalDragSession: Bool = false
    @Published var activeDragScope: SidebarDragScope? = nil
    @Published private(set) var isCompletingDrop: Bool = false
    private var completingDropItemId: UUID?
    private var completingDropScope: SidebarDragScope?
    private var completingDropSlot: DropZoneSlot = .empty
    private var completingDropFolderIntent: FolderDropIntent = .none
    private(set) var isInternalDragGeometryArmed: Bool = false
    private(set) var armedDragScope: SidebarDragScope? = nil
    
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
    private var deferredGeometryMutations: [SidebarDragGeometryMutationKey: SidebarDragGeometryMutation] = [:]
    private var isDeferredGeometryMutationFlushScheduled = false
    
    init() {}

    var shouldAnimateDropLayout: Bool {
        isDragging && !isCompletingDrop
    }

    var isDropProjectionActive: Bool {
        isDragging || isCompletingDrop
    }

    var projectionDragItemId: UUID? {
        activeDragItemId ?? completingDropItemId
    }

    var projectionDragScope: SidebarDragScope? {
        activeDragScope ?? completingDropScope
    }

    var projectionHoveredSlot: DropZoneSlot {
        hoveredSlot != .empty ? hoveredSlot : completingDropSlot
    }

    var projectionFolderDropIntent: FolderDropIntent {
        folderDropIntent != .none ? folderDropIntent : completingDropFolderIntent
    }

    func shouldHideCommittedCrossContainerPlaceholder(
        into targetContainer: TabDragManager.DragContainer,
        targetAlreadyContainsDraggedItem: Bool
    ) -> Bool {
        guard isCompletingDrop,
              targetAlreadyContainsDraggedItem,
              let sourceContainer = projectionDragScope?.sourceContainer else {
            return false
        }
        return sourceContainer != targetContainer
    }

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

    private func snapshot(from store: SidebarRuntimeGeometryStore) -> SidebarGeometrySnapshot {
        SidebarGeometrySnapshot(
            pageGeometryByKey: store.pageGeometryByKey,
            sectionFramesBySpace: store.sectionFramesBySpace,
            topLevelPinnedItemTargets: store.topLevelPinnedItemTargets,
            folderDropTargets: store.folderDropTargets,
            folderChildDropTargets: store.folderChildDropTargets,
            regularListHitTargets: store.regularListHitTargets,
            essentialsLayoutMetricsBySpace: store.essentialsLayoutMetricsBySpace
        )
    }

    private func setGeometrySnapshot(_ snapshot: SidebarGeometrySnapshot) {
        guard geometrySnapshot != snapshot else {
            return
        }
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

    private func enqueueDeferredGeometryMutation(
        key: SidebarDragGeometryMutationKey,
        reporterSection: String,
        apply: @escaping @MainActor (SidebarDragState) -> Void
    ) {
        _ = reporterSection

        deferredGeometryMutations[key] = SidebarDragGeometryMutation(apply: apply)

        guard !isDeferredGeometryMutationFlushScheduled else { return }
        isDeferredGeometryMutationFlushScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.flushDeferredGeometryMutations()
        }
    }

    private func flushDeferredGeometryMutations() {
        isDeferredGeometryMutationFlushScheduled = false
        guard !deferredGeometryMutations.isEmpty else { return }

        let mutations = Array(deferredGeometryMutations.values)
        deferredGeometryMutations = [:]

        for mutation in mutations {
            mutation.apply(self)
        }
    }

    func flushDeferredGeometryForDragStart() {
        flushDeferredGeometryMutations()
        flushScheduledGeometrySnapshotPublish()
    }

    func schedulePageGeometry(
        spaceId: UUID,
        profileId: UUID?,
        frame: CGRect?,
        renderMode: SidebarPageGeometryRenderMode,
        generation: Int
    ) {
        enqueueDeferredGeometryMutation(
            key: .page(SidebarPageGeometryKey(spaceId: spaceId, profileId: profileId)),
            reporterSection: "page"
        ) { state in
            state.applyPageGeometry(
                spaceId: spaceId,
                profileId: profileId,
                frame: frame,
                renderMode: renderMode,
                generation: generation
            )
        }
    }

    func scheduleSectionFrame(
        spaceId: UUID,
        section: SidebarSectionPrefix,
        frame: CGRect?,
        generation: Int
    ) {
        enqueueDeferredGeometryMutation(
            key: .section(SidebarSectionGeometryKey(spaceId: spaceId, section: section)),
            reporterSection: "section"
        ) { state in
            state.applySectionFrame(
                spaceId: spaceId,
                section: section,
                frame: frame,
                generation: generation
            )
        }
    }

    func scheduleFolderDropTarget(
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
        enqueueDeferredGeometryMutation(
            key: .folder(folderId, region),
            reporterSection: "folder"
        ) { state in
            state.applyFolderDropTarget(
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

    func scheduleTopLevelPinnedItemTarget(
        itemId: UUID,
        spaceId: UUID,
        topLevelIndex: Int,
        frame: CGRect?,
        isActive: Bool,
        generation: Int
    ) {
        enqueueDeferredGeometryMutation(
            key: .topLevelPinnedItem(itemId),
            reporterSection: "topLevelPinned"
        ) { state in
            state.applyTopLevelPinnedItemTarget(
                itemId: itemId,
                spaceId: spaceId,
                topLevelIndex: topLevelIndex,
                frame: frame,
                isActive: isActive,
                generation: generation
            )
        }
    }

    func scheduleFolderChildDropTarget(
        folderId: UUID,
        childId: UUID,
        index: Int,
        frame: CGRect?,
        isActive: Bool,
        generation: Int
    ) {
        enqueueDeferredGeometryMutation(
            key: .folderChild(childId),
            reporterSection: "folderChild"
        ) { state in
            state.applyFolderChildDropTarget(
                folderId: folderId,
                childId: childId,
                index: index,
                frame: frame,
                isActive: isActive,
                generation: generation
            )
        }
    }

    func scheduleRegularListHitTarget(
        spaceId: UUID,
        frame: CGRect?,
        itemCount: Int,
        generation: Int
    ) {
        enqueueDeferredGeometryMutation(
            key: .regularList(spaceId),
            reporterSection: "regular"
        ) { state in
            state.applyRegularListHitTarget(
                spaceId: spaceId,
                frame: frame,
                itemCount: itemCount,
                generation: generation
            )
        }
    }

    func scheduleEssentialsLayoutMetrics(
        spaceId: UUID,
        profileId: UUID?,
        frame: CGRect?,
        dropFrame: CGRect?,
        dropSlotFrames: [SidebarEssentialsDropSlotMetrics] = [],
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
        enqueueDeferredGeometryMutation(
            key: .essentials(spaceId),
            reporterSection: "essentials"
        ) { state in
            state.applyEssentialsLayoutMetrics(
                spaceId: spaceId,
                profileId: profileId,
                frame: frame,
                dropFrame: dropFrame,
                dropSlotFrames: dropSlotFrames,
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

    private func mutateGeometryStore(
        for generation: Int,
        _ mutate: (inout SidebarRuntimeGeometryStore) -> Bool
    ) {
        if generation == activeGeometryGeneration {
            if mutate(&activeGeometryStore) {
                publishActiveGeometryStore()
            }
            return
        }

        guard generation == pendingGeometryGeneration else { return }
        if pendingGeometryStore == nil {
            pendingGeometryStore = SidebarRuntimeGeometryStore()
        }
        if mutate(&pendingGeometryStore!) {
            promotePendingGeometryIfReady()
        }
    }

    @discardableResult
    private func upsertPageGeometry(
        spaceId: UUID,
        profileId: UUID?,
        frame: CGRect,
        renderMode: SidebarPageGeometryRenderMode,
        in store: inout SidebarRuntimeGeometryStore
    ) -> Bool {
        let key = SidebarPageGeometryKey(spaceId: spaceId, profileId: profileId)
        let metrics = SidebarPageGeometryMetrics(
            spaceId: spaceId,
            profileId: profileId,
            frame: frame,
            renderMode: renderMode
        )
        var updatedGeometry = store.pageGeometryByKey
        if renderMode == .interactive {
            updatedGeometry = updatedGeometry.filter { existingKey, metrics in
                existingKey == key || metrics.renderMode != .interactive
            }
        }
        updatedGeometry[key] = metrics

        guard store.pageGeometryByKey != updatedGeometry else { return false }
        store.pageGeometryByKey = updatedGeometry
        return true
    }

    @discardableResult
    private func removePageGeometry(
        spaceId: UUID,
        profileId: UUID?,
        from store: inout SidebarRuntimeGeometryStore
    ) -> Bool {
        let key = SidebarPageGeometryKey(spaceId: spaceId, profileId: profileId)
        guard store.pageGeometryByKey[key] != nil else { return false }
        store.pageGeometryByKey[key] = nil
        return true
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

    func beginDropCommit() {
        completingDropItemId = activeDragItemId
        completingDropScope = activeDragScope
        completingDropSlot = hoveredSlot
        completingDropFolderIntent = folderDropIntent
        isCompletingDrop = true
    }
    
    func resetInteractionState() {
        isDragging = false
        clearHoverState()
        activeDragItemId = nil
        dragLocation = nil
        previewDragLocation = nil
        previewKind = nil
        previewAssets = [:]
        previewModel = nil
        isInternalDragSession = false
        activeDragScope = nil
        if isCompletingDrop {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.finishDropCommitProjection()
            }
        } else {
            finishDropCommitProjection()
        }
        isInternalDragGeometryArmed = false
        armedDragScope = nil
        isHoveringNearEdge = false
        clearEssentialsPreviewState()
        requestGeometryRefresh()
    }

    private func finishDropCommitProjection() {
        isCompletingDrop = false
        completingDropItemId = nil
        completingDropScope = nil
        completingDropSlot = .empty
        completingDropFolderIntent = .none
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
        previewLocation: CGPoint? = nil,
        previewKind: SidebarDragPreviewKind,
        previewAssets: [SidebarDragPreviewKind: SidebarDragPreviewAsset],
        previewModel: SidebarDragPreviewModel? = nil,
        scope: SidebarDragScope? = nil
    ) {
        let resolvedScope = scope ?? armedDragScope
        isDragging = true
        activeDragItemId = itemId
        dragLocation = location
        previewDragLocation = previewLocation ?? location
        self.previewKind = previewKind
        self.previewAssets = previewAssets
        self.previewModel = previewModel
        isInternalDragSession = true
        activeDragScope = resolvedScope
        isInternalDragGeometryArmed = false
        armedDragScope = nil
        clearEssentialsPreviewState()
        requestGeometryRefresh()
        flushDeferredGeometryForDragStart()
    }

    func beginExternalDragSession(itemId: UUID?) {
        isDragging = true
        activeDragItemId = itemId
        previewDragLocation = nil
        isInternalDragSession = false
        activeDragScope = nil
        isInternalDragGeometryArmed = false
        armedDragScope = nil
        clearEssentialsPreviewState()
        requestGeometryRefresh()
    }

    func armInternalDragGeometry(scope: SidebarDragScope?) {
        guard !isDragging else { return }
        guard !isInternalDragGeometryArmed || armedDragScope != scope else { return }

        isInternalDragGeometryArmed = true
        armedDragScope = scope
        requestGeometryRefresh()
    }

    func cancelArmedDragGeometry() {
        guard !isDragging,
              isInternalDragGeometryArmed || armedDragScope != nil else {
            return
        }

        isInternalDragGeometryArmed = false
        armedDragScope = nil
        requestGeometryRefresh()
    }

    func shouldCollectDetailedGeometry(
        spaceId: UUID,
        profileId: UUID?
    ) -> Bool {
        if let activeDragScope {
            return activeDragScope.spaceId == spaceId
                && activeDragScope.matches(profileId: profileId)
        }

        if isInternalDragGeometryArmed {
            guard let armedDragScope else { return true }
            return armedDragScope.spaceId == spaceId
                && armedDragScope.matches(profileId: profileId)
        }

        if isDragging {
            return !isInternalDragSession
        }

        return true
    }

    func updateDragLocation(
        _ location: CGPoint,
        previewLocation: CGPoint? = nil
    ) {
        dragLocation = location
        if isInternalDragSession {
            previewDragLocation = previewLocation ?? location
        }
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
              let hoveredPage = hoveredInteractivePage(at: location, matching: activeDragScope),
              let metrics = essentialsLayoutMetricsBySpace[hoveredPage.spaceId],
              activeDragScope?.matches(profileId: metrics.profileId) != false,
              metrics.containsDropLocation(location),
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
                gapSlot: slot
            )
        ]
    }

    func essentialsPreviewState(for spaceId: UUID) -> SidebarEssentialsPreviewState? {
        essentialsPreviewStateBySpace[spaceId]
    }

    private func makeEssentialsLayoutMetrics(
        profileId: UUID?,
        frame: CGRect,
        dropFrame: CGRect,
        dropSlotFrames: [SidebarEssentialsDropSlotMetrics] = [],
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
        let resolvedDropSlotFrames = dropSlotFrames.isEmpty
            ? Self.defaultEssentialsDropSlotFrames(
                dropFrame: dropFrame,
                visibleItemCount: visibleItemCount ?? itemCount,
                columnCount: columnCount,
                itemSize: itemSize,
                gridSpacing: gridSpacing,
                maxDropRowCount: resolvedMaxDropRowCount
            )
            : dropSlotFrames

        return SidebarEssentialsLayoutMetrics(
            profileId: profileId,
            frame: frame,
            dropFrame: dropFrame,
            dropSlotFrames: resolvedDropSlotFrames,
            firstSyntheticRowSlot: resolvedFirstSyntheticRowSlot,
            visibleItemCount: visibleItemCount ?? itemCount,
            visibleRowCount: resolvedVisibleRowCount,
            maxDropRowCount: resolvedMaxDropRowCount,
            itemSize: itemSize,
            canAcceptDrop: canAcceptDrop
        )
    }

    private static func defaultEssentialsDropSlotFrames(
        dropFrame: CGRect,
        visibleItemCount: Int,
        columnCount: Int,
        itemSize: CGSize,
        gridSpacing: CGFloat,
        maxDropRowCount: Int
    ) -> [SidebarEssentialsDropSlotMetrics] {
        let safeColumnCount = max(columnCount, 1)
        let safeVisibleItemCount = max(visibleItemCount, 0)
        let maxSlot = min(safeVisibleItemCount, safeColumnCount * max(maxDropRowCount, 1))
        guard itemSize.width > 0, itemSize.height > 0 else {
            return [SidebarEssentialsDropSlotMetrics(slot: 0, frame: dropFrame)]
        }

        return (0...maxSlot).map { slot in
            let row = max(0, slot / safeColumnCount)
            let column = max(0, min(slot % safeColumnCount, safeColumnCount - 1))
            return SidebarEssentialsDropSlotMetrics(
                slot: slot,
                frame: CGRect(
                    x: dropFrame.minX + CGFloat(column) * (itemSize.width + gridSpacing),
                    y: dropFrame.minY + CGFloat(row) * (itemSize.height + gridSpacing),
                    width: itemSize.width,
                    height: itemSize.height
                )
            )
        }
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
                return upsertPageGeometry(
                    spaceId: spaceId,
                    profileId: profileId,
                    frame: frame,
                    renderMode: renderMode,
                    in: &store
                )
            } else {
                return removePageGeometry(
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
                guard store.sectionFramesBySpace[key] != frame else { return false }
                store.sectionFramesBySpace[key] = frame
                return true
            } else {
                guard store.sectionFramesBySpace[key] != nil else { return false }
                store.sectionFramesBySpace[key] = nil
                return true
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
                guard var target = store.folderDropTargets[folderId] else { return false }
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
                    return true
                } else {
                    guard store.folderDropTargets[folderId] != target else { return false }
                    store.folderDropTargets[folderId] = target
                    return true
                }
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
            guard store.folderDropTargets[folderId] != target else { return false }
            store.folderDropTargets[folderId] = target
            return true
        }
    }

    func applyTopLevelPinnedItemTarget(
        itemId: UUID,
        spaceId: UUID,
        topLevelIndex: Int,
        frame: CGRect?,
        isActive: Bool,
        generation: Int
    ) {
        mutateGeometryStore(for: generation) { store in
            guard isActive, let frame else {
                guard store.topLevelPinnedItemTargets[itemId] != nil else { return false }
                store.topLevelPinnedItemTargets[itemId] = nil
                return true
            }

            let target = SidebarTopLevelPinnedItemMetrics(
                itemId: itemId,
                spaceId: spaceId,
                topLevelIndex: topLevelIndex,
                frame: frame
            )
            guard store.topLevelPinnedItemTargets[itemId] != target else { return false }
            store.topLevelPinnedItemTargets[itemId] = target
            return true
        }
    }

    func applyFolderChildDropTarget(
        folderId: UUID,
        childId: UUID,
        index: Int,
        frame: CGRect?,
        isActive: Bool,
        generation: Int
    ) {
        mutateGeometryStore(for: generation) { store in
            guard isActive, let frame else {
                guard store.folderChildDropTargets[childId] != nil else { return false }
                store.folderChildDropTargets[childId] = nil
                return true
            }

            let target = SidebarFolderChildDropTargetMetrics(
                childId: childId,
                folderId: folderId,
                index: index,
                frame: frame
            )
            guard store.folderChildDropTargets[childId] != target else { return false }
            store.folderChildDropTargets[childId] = target
            return true
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
                let target = SidebarRegularListHitMetrics(
                    frame: frame,
                    itemCount: itemCount
                )
                guard store.regularListHitTargets[spaceId] != target else { return false }
                store.regularListHitTargets[spaceId] = target
                return true
            } else {
                guard store.regularListHitTargets[spaceId] != nil else { return false }
                store.regularListHitTargets[spaceId] = nil
                return true
            }
        }
    }

    func applyEssentialsLayoutMetrics(
        spaceId: UUID,
        profileId: UUID?,
        frame: CGRect?,
        dropFrame: CGRect?,
        dropSlotFrames: [SidebarEssentialsDropSlotMetrics] = [],
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
                guard store.essentialsLayoutMetricsBySpace[spaceId] != nil else { return false }
                store.essentialsLayoutMetricsBySpace[spaceId] = nil
                return true
            }

            let metrics = makeEssentialsLayoutMetrics(
                profileId: profileId,
                frame: frame,
                dropFrame: dropFrame,
                dropSlotFrames: dropSlotFrames,
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
            guard store.essentialsLayoutMetricsBySpace[spaceId] != metrics else { return false }
            store.essentialsLayoutMetricsBySpace[spaceId] = metrics
            return true
        }
    }
}
