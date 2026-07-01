import AppKit
import Combine
import SwiftUI

@MainActor
final class SidebarDragState: ObservableObject {
    static let shared = SidebarDragState()

    let interactionStateOwner = SidebarDragInteractionStateOwner()
    private var interactionStateCancellables: Set<AnyCancellable> = []
    let locationTracker = SidebarDragLocationTracker()

    var dragLocation: CGPoint? {
        get { locationTracker.location }
        set { locationTracker.location = newValue }
    }
    var previewDragLocation: CGPoint? {
        get { locationTracker.previewLocation }
        set { locationTracker.previewLocation = newValue }
    }
    @Published private var dropCommitProjection = SidebarDropCommitProjectionState()
    private var dropCommitProjectionGeneration = 0
    private var pendingDropCommitProjectionFinish: DispatchWorkItem?
    private(set) var isInternalDragGeometryArmed: Bool = false
    private(set) var armedDragScope: SidebarDragScope?

    // For Zen's auto workspace switch
    @Published var isHoveringNearEdge: Bool = false

    // Global coordinate mapping
    @Published private(set) var geometrySnapshot: SidebarGeometrySnapshot = .empty
    @Published private(set) var geometryRevision: Int = 0
    @Published var essentialsPreviewStateBySpace: [UUID: SidebarEssentialsPreviewState] = [:]
    @Published var sidebarGeometryGeneration: Int = 0
    @Published private(set) var activeGeometryGeneration: Int = 0
    @Published private(set) var pendingGeometryGeneration: Int? = nil

    private lazy var geometryRepository = SidebarDragGeometryRepository(
        geometrySnapshot: geometrySnapshot,
        geometryRevision: geometryRevision,
        generationState: SidebarDragGeometryRepository.GenerationState(
            sidebarGeometryGeneration: sidebarGeometryGeneration,
            activeGeometryGeneration: activeGeometryGeneration,
            pendingGeometryGeneration: pendingGeometryGeneration
        ),
        publishSnapshot: { [weak self] snapshot in
            self?.setGeometrySnapshot(snapshot)
        },
        publishRevision: { [weak self] revision in
            self?.geometryRevision = revision
        },
        publishGenerations: { [weak self] generationState in
            self?.setGeometryGenerationState(generationState)
        }
    )

    init() {
        interactionStateOwner.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &interactionStateCancellables)
    }

    var shouldAnimateDropLayout: Bool {
        isDragging && !isCompletingDrop
    }

    var isCompletingDrop: Bool {
        dropCommitProjection.isCompletingDrop
    }

    var isDropProjectionActive: Bool {
        dropCommitProjection.isDropProjectionActive(isDragging: isDragging)
    }

    var projectionDragItemId: UUID? {
        dropCommitProjection.dragItemId(activeDragItemId: activeDragItemId)
    }

    var projectionDragScope: SidebarDragScope? {
        dropCommitProjection.dragScope(activeDragScope: activeDragScope)
    }

    var projectionHoveredSlot: DropZoneSlot {
        dropCommitProjection.hoveredSlot(activeHoveredSlot: hoveredSlot)
    }

    var projectionFolderDropIntent: FolderDropIntent {
        dropCommitProjection.folderDropIntent(activeFolderDropIntent: folderDropIntent)
    }

    func shouldHideCommittedCrossContainerPlaceholder(
        into targetContainer: TabDragManager.DragContainer,
        targetAlreadyContainsDraggedItem: Bool
    ) -> Bool {
        dropCommitProjection.shouldHideCommittedCrossContainerPlaceholder(
            activeDragScope: activeDragScope,
            targetContainer: targetContainer,
            targetAlreadyContainsDraggedItem: targetAlreadyContainsDraggedItem
        )
    }

    private func setGeometrySnapshot(_ snapshot: SidebarGeometrySnapshot) {
        guard geometrySnapshot != snapshot else {
            return
        }
        geometrySnapshot = snapshot
    }

    private func setGeometryGenerationState(_ generationState: SidebarDragGeometryRepository.GenerationState) {
        sidebarGeometryGeneration = generationState.sidebarGeometryGeneration
        activeGeometryGeneration = generationState.activeGeometryGeneration
        pendingGeometryGeneration = generationState.pendingGeometryGeneration
    }

    func flushDeferredGeometryForDragStart() {
        geometryRepository.flushDeferredGeometryForDragStart()
    }

    func schedulePageGeometry(
        spaceId: UUID,
        profileId: UUID?,
        frame: CGRect?,
        renderMode: SidebarPageGeometryRenderMode,
        generation: Int
    ) {
        geometryRepository.schedulePageGeometry(
            spaceId: spaceId,
            profileId: profileId,
            frame: frame,
            renderMode: renderMode,
            generation: generation
        )
    }

    func scheduleSectionFrame(
        spaceId: UUID,
        section: SidebarSectionPrefix,
        frame: CGRect?,
        generation: Int
    ) {
        geometryRepository.scheduleSectionFrame(
            spaceId: spaceId,
            section: section,
            frame: frame,
            generation: generation
        )
    }

    func scheduleFolderDropTarget(_ update: SidebarFolderDropTargetUpdate, generation: Int) {
        geometryRepository.scheduleFolderDropTarget(
            update,
            generation: generation
        )
    }

    func scheduleTopLevelPinnedItemTarget(_ update: SidebarTopLevelPinnedItemTargetUpdate, generation: Int) {
        geometryRepository.scheduleTopLevelPinnedItemTarget(
            update,
            generation: generation
        )
    }

    func scheduleFolderChildDropTarget(_ update: SidebarFolderChildDropTargetUpdate, generation: Int) {
        geometryRepository.scheduleFolderChildDropTarget(
            update,
            generation: generation
        )
    }

    func scheduleRegularListHitTarget(
        spaceId: UUID,
        frame: CGRect?,
        itemCount: Int,
        generation: Int
    ) {
        geometryRepository.scheduleRegularListHitTarget(
            spaceId: spaceId,
            frame: frame,
            itemCount: itemCount,
            generation: generation
        )
    }

    func scheduleEssentialsLayoutMetrics(_ update: SidebarEssentialsLayoutUpdate, generation: Int) {
        geometryRepository.scheduleEssentialsLayoutMetrics(
            update,
            generation: generation
        )
    }

    private func clearEssentialsPreviewState() {
        essentialsPreviewStateBySpace = [:]
    }

    func beginDropCommit() {
        cancelPendingDropCommitProjectionFinish()
        dropCommitProjectionGeneration += 1
        var projection = dropCommitProjection
        projection.begin(
            itemId: activeDragItemId,
            scope: activeDragScope,
            slot: hoveredSlot,
            folderIntent: folderDropIntent
        )
        dropCommitProjection = projection
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
            let expectedProjectionGeneration = dropCommitProjectionGeneration
            scheduleDropCommitProjectionFinish(expectedGeneration: expectedProjectionGeneration)
        } else {
            finishDropCommitProjection()
        }
        isInternalDragGeometryArmed = false
        armedDragScope = nil
        isHoveringNearEdge = false
        clearEssentialsPreviewState()
        requestGeometryRefresh()
    }

    private func scheduleDropCommitProjectionFinish(expectedGeneration: Int) {
        cancelPendingDropCommitProjectionFinish()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.finishDropCommitProjection(expectedGeneration: expectedGeneration)
            }
        }
        pendingDropCommitProjectionFinish = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
    }

    private func cancelPendingDropCommitProjectionFinish() {
        pendingDropCommitProjectionFinish?.cancel()
        pendingDropCommitProjectionFinish = nil
    }

    private func finishDropCommitProjection(expectedGeneration: Int? = nil) {
        if let expectedGeneration, expectedGeneration != dropCommitProjectionGeneration {
            return
        }
        cancelPendingDropCommitProjectionFinish()
        var projection = dropCommitProjection
        projection.finish()
        dropCommitProjection = projection
    }

    func beginPendingGeometryEpoch(
        expectedSpaceId: UUID?,
        profileId: UUID?
    ) {
        geometryRepository.beginPendingGeometryEpoch(
            expectedSpaceId: expectedSpaceId,
            profileId: profileId
        )
        clearHoverState()
        clearEssentialsPreviewState()
        requestGeometryRefresh()
        geometryRepository.promotePendingGeometryIfReady()
    }

    func requestGeometryRefresh() {
        geometryRepository.requestGeometryRefresh()
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
        flushDeferredGeometryForDragStart()
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

        return false
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
            ),
        ]
    }

    func essentialsPreviewState(for spaceId: UUID) -> SidebarEssentialsPreviewState? {
        essentialsPreviewStateBySpace[spaceId]
    }

    func applyPageGeometry(
        spaceId: UUID,
        profileId: UUID?,
        frame: CGRect?,
        renderMode: SidebarPageGeometryRenderMode,
        generation: Int
    ) {
        geometryRepository.applyPageGeometry(
            spaceId: spaceId,
            profileId: profileId,
            frame: frame,
            renderMode: renderMode,
            generation: generation
        )
    }

    func applySectionFrame(
        spaceId: UUID,
        section: SidebarSectionPrefix,
        frame: CGRect?,
        generation: Int
    ) {
        geometryRepository.applySectionFrame(
            spaceId: spaceId,
            section: section,
            frame: frame,
            generation: generation
        )
    }

    func applyFolderDropTarget(_ update: SidebarFolderDropTargetUpdate, generation: Int) {
        geometryRepository.applyFolderDropTarget(
            update,
            generation: generation
        )
    }

    func applyTopLevelPinnedItemTarget(_ update: SidebarTopLevelPinnedItemTargetUpdate, generation: Int) {
        geometryRepository.applyTopLevelPinnedItemTarget(
            update,
            generation: generation
        )
    }

    func applyFolderChildDropTarget(_ update: SidebarFolderChildDropTargetUpdate, generation: Int) {
        geometryRepository.applyFolderChildDropTarget(
            update,
            generation: generation
        )
    }

    func applyRegularListHitTarget(
        spaceId: UUID,
        frame: CGRect?,
        itemCount: Int,
        generation: Int
    ) {
        geometryRepository.applyRegularListHitTarget(
            spaceId: spaceId,
            frame: frame,
            itemCount: itemCount,
            generation: generation
        )
    }

    func applyEssentialsLayoutMetrics(_ update: SidebarEssentialsLayoutUpdate, generation: Int) {
        geometryRepository.applyEssentialsLayoutMetrics(
            update,
            generation: generation
        )
    }

    func adjustGeometryStoreScrollDelta(deltaY: CGFloat) {
        geometryRepository.adjustGeometryStoreScrollDelta(deltaY: deltaY)
    }
}

@MainActor
final class SidebarDragLocationTracker: ObservableObject {
    @Published var location: CGPoint? = nil
    @Published var previewLocation: CGPoint? = nil
}
