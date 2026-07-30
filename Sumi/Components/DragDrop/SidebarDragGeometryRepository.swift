import CoreGraphics
import Foundation
import SumiDomain

@MainActor
final class SidebarDragGeometryRepository {
    struct GenerationState: Equatable {
        var sidebarGeometryGeneration: Int = 0
        var activeGeometryGeneration: Int = 0
        var pendingGeometryGeneration: Int?
    }

    private(set) var geometrySnapshot: SidebarGeometrySnapshot
    private(set) var geometryRevision: Int
    private(set) var generationState: GenerationState

    var activeGeometryGeneration: Int {
        generationState.activeGeometryGeneration
    }

    var pendingGeometryGeneration: Int? {
        generationState.pendingGeometryGeneration
    }

    private var activeGeometryStore = SidebarRuntimeGeometryStore()
    private var pendingGeometryStore: SidebarRuntimeGeometryStore?
    private var pendingInteractivePageKey: SidebarPageGeometryKey?
    private var pendingGeometryRefreshRequested = false
    private var pendingGeometrySnapshotPublishRequested = false
    private var isDrainingMainRunLoopGeometry = false
    private var isApplyingDeferredGeometryBatch = false
    private let geometryMutationBuffer = SidebarDragGeometryMutationBuffer()
    private let mainRunLoopOwner = MainRunLoopOwner()

    private let publishSnapshot: @MainActor (SidebarGeometrySnapshot) -> Void
    private let publishRevision: @MainActor (Int) -> Void
    private let publishGenerations: @MainActor (GenerationState) -> Void

    @MainActor
    private final class MainRunLoopOwner {
        private var scheduledDrainToken = 0
        private var isDrainScheduled = false

        func scheduleDrain(_ drain: @escaping @MainActor () -> Void) {
            guard !isDrainScheduled else { return }
            isDrainScheduled = true
            let token = scheduledDrainToken

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      isDrainScheduled,
                      scheduledDrainToken == token else {
                    return
                }
                isDrainScheduled = false
                drain()
            }
        }

        func drainSynchronously(_ drain: @MainActor () -> Void) {
            if isDrainScheduled {
                scheduledDrainToken &+= 1
                isDrainScheduled = false
            }
            drain()
        }
    }

    init(
        geometrySnapshot: SidebarGeometrySnapshot = .empty,
        geometryRevision: Int = 0,
        generationState: GenerationState = GenerationState(),
        publishSnapshot: @escaping @MainActor (SidebarGeometrySnapshot) -> Void = { _ in /* No-op. */ },
        publishRevision: @escaping @MainActor (Int) -> Void = { _ in /* No-op. */ },
        publishGenerations: @escaping @MainActor (GenerationState) -> Void = { _ in /* No-op. */ }
    ) {
        self.geometrySnapshot = geometrySnapshot
        self.geometryRevision = geometryRevision
        self.generationState = generationState
        self.publishSnapshot = publishSnapshot
        self.publishRevision = publishRevision
        self.publishGenerations = publishGenerations
    }

    func flushDeferredGeometryForDragStart() {
        mainRunLoopOwner.drainSynchronously { [self] in
            drainPendingMainRunLoopGeometry()
        }
    }

    func schedulePresentedSpaceList(
        _ layout: PresentedSidebarLayout,
        generation: Int
    ) {
        enqueueDeferredGeometryMutation(
            key: .presentedSpaceList(
                spaceID: layout.spaceID,
                generation: generation
            )
        ) { repository in
            repository.applyPresentedSpaceList(
                layout,
                generation: generation
            )
        }
    }

    func schedulePresentedSpaceListRemoval(
        spaceID: UUID,
        generation: Int
    ) {
        enqueueDeferredGeometryMutation(
            key: .presentedSpaceList(
                spaceID: spaceID,
                generation: generation
            )
        ) { repository in
            repository.applyPresentedSpaceListRemoval(
                spaceID: spaceID,
                generation: generation
            )
        }
    }

    func schedulePageGeometry(
        spaceId: UUID,
        profileId: UUID?,
        frame: CGRect?,
        renderMode: SidebarPageGeometryRenderMode,
        generation: Int
    ) {
        enqueueDeferredGeometryMutation(
            key: .page(
                SidebarPageGeometryKey(
                    spaceId: spaceId,
                    profileId: profileId
                ),
                generation: generation
            )
        ) { repository in
            repository.applyPageGeometry(
                spaceId: spaceId,
                profileId: profileId,
                frame: frame,
                renderMode: renderMode,
                generation: generation
            )
        }
    }

    func scheduleEssentialsLayoutMetrics(_ update: SidebarEssentialsLayoutUpdate, generation: Int) {
        enqueueDeferredGeometryMutation(
            key: .essentials(
                spaceID: update.spaceId,
                generation: generation
            )
        ) { repository in
            repository.applyEssentialsLayoutMetrics(
                update,
                generation: generation
            )
        }
    }

    func beginPendingGeometryEpoch(
        expectedSpaceId: UUID?,
        profileId: UUID?
    ) {
        var nextGenerationState = generationState
        nextGenerationState.sidebarGeometryGeneration &+= 1
        nextGenerationState.pendingGeometryGeneration = nextGenerationState.sidebarGeometryGeneration
        setGenerationState(nextGenerationState)

        pendingGeometryStore = SidebarRuntimeGeometryStore()
        pendingInteractivePageKey = expectedSpaceId.map {
            SidebarPageGeometryKey(spaceId: $0, profileId: profileId)
        }
    }

    func requestGeometryRefresh() {
        pendingGeometryRefreshRequested = true
        scheduleMainRunLoopGeometryDrain()
    }

    func promotePendingGeometryIfReady() {
        guard let pendingGeneration = generationState.pendingGeometryGeneration,
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
        let listLayout = pendingGeometryStore.spaceListLayoutsBySpace[spaceId]

        guard pendingGeometryStore.sectionFramesBySpace[essentialsKey] != nil,
              listLayout?.sectionFrames[pinnedKey.section] != nil,
              listLayout?.sectionFrames[regularKey.section] != nil,
              pendingGeometryStore.essentialsLayoutMetricsBySpace[spaceId] != nil,
              listLayout != nil else {
            return
        }

        activeGeometryStore = pendingGeometryStore

        var nextGenerationState = generationState
        nextGenerationState.activeGeometryGeneration = pendingGeneration
        nextGenerationState.pendingGeometryGeneration = nil
        setGenerationState(nextGenerationState)
        publishActiveGeometryStore()

        self.pendingGeometryStore = nil
        self.pendingInteractivePageKey = nil
    }

    func applyPageGeometry(
        spaceId: UUID,
        profileId: UUID?,
        frame: CGRect?,
        renderMode: SidebarPageGeometryRenderMode,
        generation: Int
    ) {
        guard renderMode == .interactive else { return }
        let frame = frame.map { normalizedFrame($0, for: generation) }
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

    func applyPresentedSpaceList(
        _ layout: PresentedSidebarLayout,
        generation: Int
    ) {
        let normalizedLayout = layout.offsettingY(
            by: generation == activeGeometryGeneration
                ? activeGeometryStore.cumulativeScrollDeltaY
                : 0
        )
        mutateGeometryStore(for: generation) { store in
            Self.replacePresentedSpaceList(
                normalizedLayout,
                spaceID: normalizedLayout.spaceID,
                in: &store
            )
        }
    }

    func applyPresentedSpaceListRemoval(
        spaceID: UUID,
        generation: Int
    ) {
        mutateGeometryStore(for: generation) { store in
            Self.replacePresentedSpaceList(
                nil,
                spaceID: spaceID,
                in: &store
            )
        }
    }

    private static func replacePresentedSpaceList(
        _ layout: PresentedSidebarLayout?,
        spaceID: UUID,
        in store: inout SidebarRuntimeGeometryStore
    ) -> Bool {
        if let layout {
            precondition(layout.spaceID == spaceID)
            guard store.spaceListLayoutsBySpace[spaceID] != layout else {
                return false
            }
            store.spaceListLayoutsBySpace[spaceID] = layout
            return true
        }

        guard store.spaceListLayoutsBySpace[spaceID] != nil else {
            return false
        }
        store.spaceListLayoutsBySpace[spaceID] = nil
        return true
    }

    func applyEssentialsLayoutMetrics(_ update: SidebarEssentialsLayoutUpdate, generation: Int) {
        var update = update
        if var input = update.input {
            input.frame = normalizedFrame(input.frame, for: generation)
            input.dropFrame = normalizedFrame(input.dropFrame, for: generation)
            input.dropSlotFrames = input.dropSlotFrames.map { slot in
                var slot = slot
                slot.frame = normalizedFrame(slot.frame, for: generation)
                return slot
            }
            update.input = input
        }
        mutateGeometryStore(for: generation) { store in
            let sectionKey = SidebarSectionGeometryKey(
                spaceId: update.spaceId,
                section: .essentials
            )
            guard let input = update.input else {
                let hadMetrics =
                    store.essentialsLayoutMetricsBySpace[update.spaceId] != nil
                let hadSection = store.sectionFramesBySpace[sectionKey] != nil
                guard hadMetrics || hadSection else { return false }
                store.essentialsLayoutMetricsBySpace[update.spaceId] = nil
                store.sectionFramesBySpace[sectionKey] = nil
                return true
            }

            let metrics = makeEssentialsLayoutMetrics(input)
            guard store.essentialsLayoutMetricsBySpace[update.spaceId]
                    != metrics
                    || store.sectionFramesBySpace[sectionKey] != input.frame
            else { return false }
            store.essentialsLayoutMetricsBySpace[update.spaceId] = metrics
            store.sectionFramesBySpace[sectionKey] = input.frame
            return true
        }
    }

    func adjustGeometryStoreScrollDelta(deltaY: CGFloat) {
        guard abs(deltaY) > 0.5 else { return }
        activeGeometryStore.cumulativeScrollDeltaY += deltaY
        activeGeometryStore.scrollRevision &+= 1
        setGeometrySnapshot(Self.snapshot(from: activeGeometryStore))
        setGeometryRevision(geometryRevision &+ 1)
    }

    private func normalizedFrame(_ frame: CGRect, for generation: Int) -> CGRect {
        guard generation == activeGeometryGeneration else { return frame }
        var normalized = frame
        normalized.origin.y += activeGeometryStore.cumulativeScrollDeltaY
        return normalized
    }

    private func enqueueDeferredGeometryMutation(
        key: SidebarDragGeometryMutationKey,
        apply: @escaping @MainActor (SidebarDragGeometryRepository) -> Void
    ) {
        geometryMutationBuffer.enqueue(key: key, apply: apply)
        scheduleMainRunLoopGeometryDrain()
    }

    private func flushDeferredGeometryMutations() {
        guard !isApplyingDeferredGeometryBatch else { return }
        isApplyingDeferredGeometryBatch = true
        defer {
            isApplyingDeferredGeometryBatch = false
            if pendingGeometrySnapshotPublishRequested {
                rebuildIndices(in: &activeGeometryStore)
            }
        }
        geometryMutationBuffer.flush(into: self)
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
        guard var pendingGeometryStore else { return }
        let shouldPromotePendingGeometry = mutate(&pendingGeometryStore)
        self.pendingGeometryStore = pendingGeometryStore
        if shouldPromotePendingGeometry {
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

    private func makeEssentialsLayoutMetrics(
        _ input: SidebarEssentialsLayoutMetricsInput
    ) -> SidebarEssentialsLayoutMetrics {
        let resolvedVisibleRowCount = max(
            input.visibleRowCount ?? Self.resolvedMetricsRowCount(
                for: input.frame.height,
                itemSize: input.itemSize,
                gridSpacing: input.gridSpacing,
                fallback: input.rowCount
            ),
            1
        )
        let resolvedMaxDropRowCount = max(
            input.maxDropRowCount ?? Self.resolvedMetricsRowCount(
                for: input.dropFrame.height,
                itemSize: input.itemSize,
                gridSpacing: input.gridSpacing,
                fallback: resolvedVisibleRowCount
            ),
            resolvedVisibleRowCount,
            1
        )
        let resolvedFirstSyntheticRowSlot = input.firstSyntheticRowSlot
            ?? (max(resolvedVisibleRowCount, 1) * max(input.columnCount, 1))
        let resolvedDropSlotFrames = input.dropSlotFrames.isEmpty
            ? Self.defaultEssentialsDropSlotFrames(
                dropFrame: input.dropFrame,
                visibleItemCount: input.visibleItemCount ?? input.itemCount,
                columnCount: input.columnCount,
                itemSize: input.itemSize,
                gridSpacing: input.gridSpacing,
                maxDropRowCount: resolvedMaxDropRowCount
            )
            : input.dropSlotFrames.sorted { lhs, rhs in
                if lhs.slot != rhs.slot { return lhs.slot < rhs.slot }
                if lhs.frame.minY != rhs.frame.minY { return lhs.frame.minY < rhs.frame.minY }
                return lhs.frame.minX < rhs.frame.minX
            }

        let resolvedVisibleItemCount = input.visibleItemCount ?? input.itemCount

        return SidebarEssentialsLayoutMetrics(
            profileId: input.profileId,
            frame: input.frame,
            dropFrame: input.dropFrame,
            dropSlotFrames: resolvedDropSlotFrames,
            firstSyntheticRowSlot: resolvedFirstSyntheticRowSlot,
            visibleItemCount: resolvedVisibleItemCount,
            visibleRowCount: resolvedVisibleRowCount,
            maxDropRowCount: resolvedMaxDropRowCount,
            itemSize: input.itemSize,
            canAcceptDrop: input.canAcceptDrop,
            dropHitFrame: SidebarEssentialsDropHitPolicy.resolvedDropHitFrame(
                frame: input.frame,
                dropFrame: input.dropFrame,
                dropSlotFrames: resolvedDropSlotFrames,
                visibleItemCount: resolvedVisibleItemCount,
                itemSize: input.itemSize,
                canAcceptDrop: input.canAcceptDrop
            )
        )
    }

    private func publishActiveGeometryStore() {
        activeGeometryStore.structuralRevision &+= 1
        if !isApplyingDeferredGeometryBatch {
            rebuildIndices(in: &activeGeometryStore)
        }
        pendingGeometrySnapshotPublishRequested = true
        scheduleMainRunLoopGeometryDrain()
    }

    private func rebuildIndices(in store: inout SidebarRuntimeGeometryStore) {
        store.hitTestIndex = SidebarGeometryHitTestIndex(
            spaceListLayoutsBySpace: store.spaceListLayoutsBySpace
        )
    }

    private func scheduleMainRunLoopGeometryDrain() {
        guard !isDrainingMainRunLoopGeometry else { return }
        mainRunLoopOwner.scheduleDrain { [weak self] in
            self?.drainPendingMainRunLoopGeometry()
        }
    }

    private func drainPendingMainRunLoopGeometry() {
        guard !isDrainingMainRunLoopGeometry else { return }
        isDrainingMainRunLoopGeometry = true
        defer { isDrainingMainRunLoopGeometry = false }

        flushDeferredGeometryMutations()
        promotePendingGeometryIfReady()
        flushPendingGeometrySnapshotPublish()
        flushPendingGeometryRefresh()
    }

    private func flushPendingGeometrySnapshotPublish() {
        guard pendingGeometrySnapshotPublishRequested else { return }
        pendingGeometrySnapshotPublishRequested = false
        setGeometrySnapshot(Self.snapshot(from: activeGeometryStore))
    }

    private func flushPendingGeometryRefresh() {
        guard pendingGeometryRefreshRequested else { return }
        pendingGeometryRefreshRequested = false
        setGeometryRevision(geometryRevision &+ 1)
    }

    private func setGeometrySnapshot(_ snapshot: SidebarGeometrySnapshot) {
        guard geometrySnapshot != snapshot else {
            return
        }
        geometrySnapshot = snapshot
        publishSnapshot(snapshot)
    }

    private func setGeometryRevision(_ revision: Int) {
        guard geometryRevision != revision else {
            return
        }
        geometryRevision = revision
        publishRevision(revision)
    }

    private func setGenerationState(_ generationState: GenerationState) {
        guard self.generationState != generationState else {
            return
        }
        self.generationState = generationState
        publishGenerations(generationState)
    }

    private static func snapshot(from store: SidebarRuntimeGeometryStore) -> SidebarGeometrySnapshot {
        var sectionFrames = store.sectionFramesBySpace
        var folderTargets: [UUID: SidebarFolderDropTargetMetrics] = [:]
        var pinnedTargets: [UUID: SidebarPinnedListHitMetrics] = [:]
        var regularTargets: [UUID: SidebarRegularListHitMetrics] = [:]

        for (spaceID, layout) in store.spaceListLayoutsBySpace {
            for (section, frame) in layout.sectionFrames {
                sectionFrames[
                    SidebarSectionGeometryKey(
                        spaceId: spaceID,
                        section: section
                    )
                ] = frame
            }
            folderTargets.merge(layout.folderDropTargets) { _, new in new }
            pinnedTargets[spaceID] = layout.pinnedListHitTarget
            regularTargets[spaceID] = layout.regularListHitTarget
        }

        return SidebarGeometrySnapshot(
            cumulativeScrollDeltaY: store.cumulativeScrollDeltaY,
            structuralRevision: store.structuralRevision,
            scrollRevision: store.scrollRevision,
            pageGeometryByKey: store.pageGeometryByKey,
            sectionFramesBySpace: sectionFrames,
            folderDropTargets: folderTargets,
            pinnedListHitTargets: pinnedTargets,
            regularListHitTargets: regularTargets,
            essentialsLayoutMetricsBySpace: store.essentialsLayoutMetricsBySpace,
            hitTestIndex: store.hitTestIndex
        )
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
}
