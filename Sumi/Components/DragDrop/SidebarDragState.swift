import AppKit
import Combine
import SwiftUI

@MainActor
final class SidebarDragState: ObservableObject {
    static let shared = SidebarDragState()

    @Published var isDragging: Bool = false
    @Published var hoveredSlot: DropZoneSlot = .empty
    @Published var folderDropIntent: FolderDropIntent = .none
    @Published var activeHoveredFolderId: UUID? = nil
    @Published var activeSplitTarget: SplitDropSide? = nil
    @Published var activeDragItemId: UUID? = nil
    let locationTracker = SidebarDragLocationTracker()

    var dragLocation: CGPoint? {
        get { locationTracker.location }
        set { locationTracker.location = newValue }
    }
    var previewDragLocation: CGPoint? {
        get { locationTracker.previewLocation }
        set { locationTracker.previewLocation = newValue }
    }
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
        SidebarDragPlaceholderPolicy.shouldHideCommittedCrossContainerPlaceholder(
            isCompletingDrop: isCompletingDrop,
            sourceContainer: projectionDragScope?.sourceContainer,
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

    func scheduleFolderDropTarget(
        folderId: UUID,
        spaceId: UUID,
        parentFolderId: UUID?,
        topLevelIndex: Int,
        childCount: Int,
        isOpen: Bool,
        region: SidebarFolderDragRegion,
        frame: CGRect?,
        isActive: Bool,
        generation: Int
    ) {
        geometryRepository.scheduleFolderDropTarget(
            folderId: folderId,
            spaceId: spaceId,
            parentFolderId: parentFolderId,
            topLevelIndex: topLevelIndex,
            childCount: childCount,
            isOpen: isOpen,
            region: region,
            frame: frame,
            isActive: isActive,
            generation: generation
        )
    }

    func scheduleTopLevelPinnedItemTarget(
        itemId: UUID,
        spaceId: UUID,
        topLevelIndex: Int,
        frame: CGRect?,
        isActive: Bool,
        generation: Int
    ) {
        geometryRepository.scheduleTopLevelPinnedItemTarget(
            itemId: itemId,
            spaceId: spaceId,
            topLevelIndex: topLevelIndex,
            frame: frame,
            isActive: isActive,
            generation: generation
        )
    }

    func scheduleFolderChildDropTarget(
        folderId: UUID,
        childId: UUID,
        index: Int,
        frame: CGRect?,
        isActive: Bool,
        generation: Int
    ) {
        geometryRepository.scheduleFolderChildDropTarget(
            folderId: folderId,
            childId: childId,
            index: index,
            frame: frame,
            isActive: isActive,
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
        geometryRepository.scheduleEssentialsLayoutMetrics(
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

    func applyFolderDropTarget(
        folderId: UUID,
        spaceId: UUID,
        parentFolderId: UUID?,
        topLevelIndex: Int,
        childCount: Int,
        isOpen: Bool,
        region: SidebarFolderDragRegion,
        frame: CGRect?,
        isActive: Bool,
        generation: Int
    ) {
        geometryRepository.applyFolderDropTarget(
            folderId: folderId,
            spaceId: spaceId,
            parentFolderId: parentFolderId,
            topLevelIndex: topLevelIndex,
            childCount: childCount,
            isOpen: isOpen,
            region: region,
            frame: frame,
            isActive: isActive,
            generation: generation
        )
    }

    func applyTopLevelPinnedItemTarget(
        itemId: UUID,
        spaceId: UUID,
        topLevelIndex: Int,
        frame: CGRect?,
        isActive: Bool,
        generation: Int
    ) {
        geometryRepository.applyTopLevelPinnedItemTarget(
            itemId: itemId,
            spaceId: spaceId,
            topLevelIndex: topLevelIndex,
            frame: frame,
            isActive: isActive,
            generation: generation
        )
    }

    func applyFolderChildDropTarget(
        folderId: UUID,
        childId: UUID,
        index: Int,
        frame: CGRect?,
        isActive: Bool,
        generation: Int
    ) {
        geometryRepository.applyFolderChildDropTarget(
            folderId: folderId,
            childId: childId,
            index: index,
            frame: frame,
            isActive: isActive,
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
        geometryRepository.applyEssentialsLayoutMetrics(
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

    func adjustGeometryStoreScrollDelta(deltaY: CGFloat) {
        geometryRepository.adjustGeometryStoreScrollDelta(deltaY: deltaY)
    }
}

@MainActor
final class SidebarDragLocationTracker: ObservableObject {
    @Published var location: CGPoint? = nil
    @Published var previewLocation: CGPoint? = nil
}
