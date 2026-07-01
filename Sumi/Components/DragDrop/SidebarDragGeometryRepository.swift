import CoreGraphics
import Foundation

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
    private let geometryMutationBuffer = SidebarDragGeometryMutationBuffer()
    private let mainRunLoopOwner = SidebarDragGeometryMainRunLoopOwner()

    private let publishSnapshot: @MainActor (SidebarGeometrySnapshot) -> Void
    private let publishRevision: @MainActor (Int) -> Void
    private let publishGenerations: @MainActor (GenerationState) -> Void

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

    func schedulePageGeometry(
        spaceId: UUID,
        profileId: UUID?,
        frame: CGRect?,
        renderMode: SidebarPageGeometryRenderMode,
        generation: Int
    ) {
        enqueueDeferredGeometryMutation(
            key: .page(SidebarPageGeometryKey(spaceId: spaceId, profileId: profileId))
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

    func scheduleSectionFrame(
        spaceId: UUID,
        section: SidebarSectionPrefix,
        frame: CGRect?,
        generation: Int
    ) {
        enqueueDeferredGeometryMutation(
            key: .section(SidebarSectionGeometryKey(spaceId: spaceId, section: section))
        ) { repository in
            repository.applySectionFrame(
                spaceId: spaceId,
                section: section,
                frame: frame,
                generation: generation
            )
        }
    }

    func scheduleFolderDropTarget(_ update: SidebarFolderDropTargetUpdate, generation: Int) {
        enqueueDeferredGeometryMutation(
            key: .folder(update.folderId, update.region)
        ) { repository in
            repository.applyFolderDropTarget(
                update,
                generation: generation
            )
        }
    }

    func scheduleTopLevelPinnedItemTarget(_ update: SidebarTopLevelPinnedItemTargetUpdate, generation: Int) {
        enqueueDeferredGeometryMutation(
            key: .topLevelPinnedItem(update.itemId)
        ) { repository in
            repository.applyTopLevelPinnedItemTarget(
                update,
                generation: generation
            )
        }
    }

    func scheduleFolderChildDropTarget(_ update: SidebarFolderChildDropTargetUpdate, generation: Int) {
        enqueueDeferredGeometryMutation(
            key: .folderChild(update.childId)
        ) { repository in
            repository.applyFolderChildDropTarget(
                update,
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
            key: .regularList(spaceId)
        ) { repository in
            repository.applyRegularListHitTarget(
                spaceId: spaceId,
                frame: frame,
                itemCount: itemCount,
                generation: generation
            )
        }
    }

    func scheduleEssentialsLayoutMetrics(_ update: SidebarEssentialsLayoutUpdate, generation: Int) {
        enqueueDeferredGeometryMutation(
            key: .essentials(update.spaceId)
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

        guard pendingGeometryStore.sectionFramesBySpace[essentialsKey] != nil,
              pendingGeometryStore.sectionFramesBySpace[pinnedKey] != nil,
              pendingGeometryStore.sectionFramesBySpace[regularKey] != nil,
              pendingGeometryStore.essentialsLayoutMetricsBySpace[spaceId] != nil,
              pendingGeometryStore.regularListHitTargets[spaceId] != nil else {
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

    func applyFolderDropTarget(_ update: SidebarFolderDropTargetUpdate, generation: Int) {
        mutateGeometryStore(for: generation) { store in
            guard let metrics = update.metrics, let frame = update.frame else {
                guard var target = store.folderDropTargets[update.folderId] else { return false }
                switch update.region {
                case .header:
                    target.headerFrame = nil
                case .body:
                    target.bodyFrame = nil
                case .after:
                    target.afterFrame = nil
                }
                if target.headerFrame == nil && target.bodyFrame == nil && target.afterFrame == nil {
                    store.folderDropTargets[update.folderId] = nil
                    return true
                } else {
                    guard store.folderDropTargets[update.folderId] != target else { return false }
                    store.folderDropTargets[update.folderId] = target
                    return true
                }
            }

            var target = store.folderDropTargets[update.folderId] ?? metrics
            target.spaceId = metrics.spaceId
            target.parentFolderId = metrics.parentFolderId
            target.topLevelIndex = metrics.topLevelIndex
            target.childCount = metrics.childCount
            target.isOpen = metrics.isOpen
            switch update.region {
            case .header:
                target.headerFrame = frame
            case .body:
                target.bodyFrame = frame
            case .after:
                target.afterFrame = frame
            }
            guard store.folderDropTargets[update.folderId] != target else { return false }
            store.folderDropTargets[update.folderId] = target
            return true
        }
    }

    func applyTopLevelPinnedItemTarget(_ update: SidebarTopLevelPinnedItemTargetUpdate, generation: Int) {
        mutateGeometryStore(for: generation) { store in
            guard let metrics = update.metrics else {
                guard store.topLevelPinnedItemTargets[update.itemId] != nil else { return false }
                store.topLevelPinnedItemTargets[update.itemId] = nil
                return true
            }

            guard store.topLevelPinnedItemTargets[update.itemId] != metrics else { return false }
            store.topLevelPinnedItemTargets[update.itemId] = metrics
            return true
        }
    }

    func applyFolderChildDropTarget(_ update: SidebarFolderChildDropTargetUpdate, generation: Int) {
        mutateGeometryStore(for: generation) { store in
            guard let metrics = update.metrics else {
                guard store.folderChildDropTargets[update.childId] != nil else { return false }
                store.folderChildDropTargets[update.childId] = nil
                return true
            }

            guard store.folderChildDropTargets[update.childId] != metrics else { return false }
            store.folderChildDropTargets[update.childId] = metrics
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

    func applyEssentialsLayoutMetrics(_ update: SidebarEssentialsLayoutUpdate, generation: Int) {
        mutateGeometryStore(for: generation) { store in
            guard let input = update.input else {
                guard store.essentialsLayoutMetricsBySpace[update.spaceId] != nil else { return false }
                store.essentialsLayoutMetricsBySpace[update.spaceId] = nil
                return true
            }

            let metrics = makeEssentialsLayoutMetrics(input)
            guard store.essentialsLayoutMetricsBySpace[update.spaceId] != metrics else { return false }
            store.essentialsLayoutMetricsBySpace[update.spaceId] = metrics
            return true
        }
    }

    func adjustGeometryStoreScrollDelta(deltaY: CGFloat) {
        guard abs(deltaY) > 0.5 else { return }

        for (id, metrics) in activeGeometryStore.topLevelPinnedItemTargets {
            var updated = metrics
            updated.frame.origin.y -= deltaY
            activeGeometryStore.topLevelPinnedItemTargets[id] = updated
        }

        for (id, metrics) in activeGeometryStore.folderDropTargets {
            var updated = metrics
            if let headerFrame = updated.headerFrame {
                var newHeaderFrame = headerFrame
                newHeaderFrame.origin.y -= deltaY
                updated.headerFrame = newHeaderFrame
            }
            if let bodyFrame = updated.bodyFrame {
                var newBodyFrame = bodyFrame
                newBodyFrame.origin.y -= deltaY
                updated.bodyFrame = newBodyFrame
            }
            if let afterFrame = updated.afterFrame {
                var newAfterFrame = afterFrame
                newAfterFrame.origin.y -= deltaY
                updated.afterFrame = newAfterFrame
            }
            activeGeometryStore.folderDropTargets[id] = updated
        }

        for (id, metrics) in activeGeometryStore.folderChildDropTargets {
            var updated = metrics
            updated.frame.origin.y -= deltaY
            activeGeometryStore.folderChildDropTargets[id] = updated
        }

        for (key, rect) in activeGeometryStore.sectionFramesBySpace {
            var updated = rect
            updated.origin.y -= deltaY
            activeGeometryStore.sectionFramesBySpace[key] = updated
        }

        for (id, metrics) in activeGeometryStore.regularListHitTargets {
            var updated = metrics
            updated.frame.origin.y -= deltaY
            activeGeometryStore.regularListHitTargets[id] = updated
        }

        for (spaceId, metrics) in activeGeometryStore.essentialsLayoutMetricsBySpace {
            var updated = metrics
            updated.frame.origin.y -= deltaY
            updated.dropFrame.origin.y -= deltaY
            updated.dropSlotFrames = updated.dropSlotFrames.map { slot in
                var updatedSlot = slot
                updatedSlot.frame.origin.y -= deltaY
                return updatedSlot
            }
            activeGeometryStore.essentialsLayoutMetricsBySpace[spaceId] = updated
        }

        for (key, metrics) in activeGeometryStore.pageGeometryByKey {
            var updated = metrics
            updated.frame.origin.y -= deltaY
            activeGeometryStore.pageGeometryByKey[key] = updated
        }

        setGeometrySnapshot(Self.snapshot(from: activeGeometryStore))
        setGeometryRevision(geometryRevision &+ 1)
    }

    private func enqueueDeferredGeometryMutation(
        key: SidebarDragGeometryMutationKey,
        apply: @escaping @MainActor (SidebarDragGeometryRepository) -> Void
    ) {
        geometryMutationBuffer.enqueue(key: key, apply: apply)
        scheduleMainRunLoopGeometryDrain()
    }

    private func flushDeferredGeometryMutations() {
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
            : input.dropSlotFrames

        return SidebarEssentialsLayoutMetrics(
            profileId: input.profileId,
            frame: input.frame,
            dropFrame: input.dropFrame,
            dropSlotFrames: resolvedDropSlotFrames,
            firstSyntheticRowSlot: resolvedFirstSyntheticRowSlot,
            visibleItemCount: input.visibleItemCount ?? input.itemCount,
            visibleRowCount: resolvedVisibleRowCount,
            maxDropRowCount: resolvedMaxDropRowCount,
            itemSize: input.itemSize,
            canAcceptDrop: input.canAcceptDrop
        )
    }

    private func publishActiveGeometryStore() {
        pendingGeometrySnapshotPublishRequested = true
        scheduleMainRunLoopGeometryDrain()
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
