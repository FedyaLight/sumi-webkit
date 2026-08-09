import AppKit
import Combine
import SumiDomain
import SwiftUI

@MainActor
final class SidebarDragState: ObservableObject {
    /// Window-scoped registry for tab-list drag autoscroll + swipe forwarding.
    let dragAutoscrollRegistry = SidebarTabListDragAutoscrollRegistry()
    let locationTracker = SidebarDragLocationTracker()
    let geometry = SidebarDragGeometryModule()
    let listPresentation = SidebarListDragPresentation()
    let sessionPresentation = SidebarDragSessionPresentation()
    let favoritePresentation = SidebarFavoriteDragPresentation()
    let floatingPresentation = SidebarFloatingDragPresentation()

    // The AppKit drag pipeline mutates this command owner. SwiftUI observes only
    // the immutable frames above, each of which drops unchanged publications.
    private var storedIsDragging = false
    private var presentedDropIntent = SidebarPresentedDropIntentState()
    private var storedActiveDragItemId: UUID?
    private var storedPreviewKind: SidebarDragPreviewKind?
    private var previewAssets: [SidebarDragPreviewKind: SidebarDragPreviewAsset] = [:]
    private var previewModel: SidebarDragPreviewModel?
    private var floatingPresentationRevision: UInt64 = 0
    private var storedIsInternalDragSession = false
    private var storedActiveDragScope: SidebarDragScope?
    private var storedIsApplyingDropMutation = false
    private var presentationMutationDepth = 0
    private var presentationNeedsPublish = false

    var isDragging: Bool {
        get { storedIsDragging }
        set {
            guard storedIsDragging != newValue else { return }
            storedIsDragging = newValue
            markPresentationChanged()
            interactionState?.setDragActive(newValue, source: .visualItem)
            syncGeometryCollectionContext()
        }
    }

    var hoveredSlot: DropZoneSlot { presentedDropIntent.active.slot }
    var folderDropIntent: FolderDropIntent {
        presentedDropIntent.active.folderIntent
    }
    var activeHoveredFolderId: UUID? {
        presentedDropIntent.active.activeHoveredFolderId
    }

    var activeDragItemId: UUID? {
        get { storedActiveDragItemId }
        set {
            guard storedActiveDragItemId != newValue else { return }
            storedActiveDragItemId = newValue
            markPresentationChanged()
        }
    }

    var isInternalDragSession: Bool {
        get { storedIsInternalDragSession }
        set {
            guard storedIsInternalDragSession != newValue else { return }
            storedIsInternalDragSession = newValue
            markPresentationChanged()
            syncGeometryCollectionContext()
        }
    }

    var activeDragScope: SidebarDragScope? {
        get { storedActiveDragScope }
        set {
            guard storedActiveDragScope != newValue else { return }
            storedActiveDragScope = newValue
            markPresentationChanged()
            syncGeometryCollectionContext()
        }
    }

    var isApplyingDropMutation: Bool {
        storedIsApplyingDropMutation
    }

    var dragLocation: CGPoint? {
        get { locationTracker.location }
        set {
            guard locationTracker.location != newValue else { return }
            locationTracker.location = newValue
        }
    }
    var previewDragLocation: CGPoint? {
        get { locationTracker.previewLocation }
        set {
            guard locationTracker.previewLocation != newValue else { return }
            locationTracker.previewLocation = newValue
        }
    }
    private let delayedActions: MainActorDelayedActionScheduler
    private let dropTargetDwellGate: SidebarDropTargetDwellGate
    private let interactionState: SidebarInteractionState?
    private var dropCompletionGeneration = 0
    private var cancelPendingDropCompletionAction: MainActorDelayedActionScheduler.Cancellation?
    private(set) var isInternalDragGeometryArmed: Bool = false
    private(set) var armedDragScope: SidebarDragScope?

    private var favoritePreviewStateBySpace: [UUID: SidebarFavoritePreviewState] = [:]

    init(
        delayedActions: MainActorDelayedActionScheduler = .live,
        interactionState: SidebarInteractionState? = nil
    ) {
        self.delayedActions = delayedActions
        dropTargetDwellGate = SidebarDropTargetDwellGate(
            delayedActions: delayedActions
        )
        self.interactionState = interactionState
    }

    isolated deinit {
        cancelPendingDropCompletionAction?()
        dropTargetDwellGate.leaveDeferredTargets()
        interactionState?.setDragActive(false, source: .visualItem)
    }

    var shouldAnimateDropLayout: Bool {
        isDragging && !isCompletingDrop
    }

    var deferredDropTargetRevision: UInt64 {
        dropTargetDwellGate.revision
    }

    func admitsDeferredDropTarget(
        _ target: SidebarDeferredDropTarget
    ) -> Bool {
        dropTargetDwellGate.admits(target)
    }

    func leaveDeferredDropTargets() {
        dropTargetDwellGate.leaveDeferredTargets()
    }

    var isCompletingDrop: Bool {
        presentedDropIntent.isCompletingDrop
    }

    var isDropProjectionActive: Bool {
        presentedDropIntent.isDropProjectionActive(isDragging: isDragging)
    }

    var projectionDragItemId: UUID? {
        presentedDropIntent.dragItemId(activeDragItemId: activeDragItemId)
    }

    var projectionDragScope: SidebarDragScope? {
        presentedDropIntent.dragScope(activeDragScope: activeDragScope)
    }

    var projectionHoveredSlot: DropZoneSlot {
        presentedDropIntent.projected.slot
    }

    var projectionSplitPairingTarget: SidebarSplitPairingTarget? {
        presentedDropIntent.projected.splitPairingTarget
    }

    var projectionFolderDropIntent: FolderDropIntent {
        presentedDropIntent.projected.folderIntent
    }

    func shouldHideCommittedCrossContainerPlaceholder(
        into targetContainer: TabDragManager.DragContainer,
        targetAlreadyContainsDraggedItem: Bool
    ) -> Bool {
        presentedDropIntent.shouldHideCommittedCrossContainerPlaceholder(
            activeDragScope: activeDragScope,
            targetContainer: targetContainer,
            targetAlreadyContainsDraggedItem: targetAlreadyContainsDraggedItem
        )
    }

    private func clearFavoritePreviewState() {
        guard !favoritePreviewStateBySpace.isEmpty else { return }
        favoritePreviewStateBySpace = [:]
        markPresentationChanged()
    }

    @discardableResult
    func beginDropCommit(
        refreshingIfEmpty refresh: () -> SidebarDropResolution? = { nil }
    ) -> SidebarDropResolution? {
        withPresentationMutation {
            let resolution = hoveredSlot == .empty
                ? refresh()
                : presentedDropIntent.active
            guard let resolution, resolution.slot != .empty else {
                return nil
            }
            cancelPendingDropCompletion()
            dropCompletionGeneration += 1
            var projection = presentedDropIntent
            projection.begin(
                itemId: activeDragItemId,
                scope: activeDragScope,
                resolution: resolution
            )
            setPresentedDropIntent(projection)
            setApplyingDropMutation(true)
            return resolution
        }
    }

    func resetInteractionState() {
        withPresentationMutation {
            isDragging = false
            clearHoverState()
            activeDragItemId = nil
            dragLocation = nil
            previewDragLocation = nil
            clearPreviewPresentation()
            isInternalDragSession = false
            activeDragScope = nil
            if isCompletingDrop {
                let expectedGeneration = dropCompletionGeneration
                setApplyingDropMutation(false)
                scheduleDropCompletionFinish(expectedGeneration: expectedGeneration)
            } else {
                finishDropCompletion()
            }
            isInternalDragGeometryArmed = false
            armedDragScope = nil
            markPresentationChanged()
            syncGeometryCollectionContext()
            clearFavoritePreviewState()
            requestGeometryRefresh()
        }
    }

    private func scheduleDropCompletionFinish(expectedGeneration: Int) {
        cancelPendingDropCompletion()
        cancelPendingDropCompletionAction = delayedActions.schedule(
            after: SidebarMotionPolicy.dropSettleDuration
        ) { [weak self] in
            self?.finishDropCompletion(expectedGeneration: expectedGeneration)
        }
    }

    private func cancelPendingDropCompletion() {
        cancelPendingDropCompletionAction?()
        cancelPendingDropCompletionAction = nil
    }

    private func finishDropCompletion(expectedGeneration: Int? = nil) {
        if let expectedGeneration, expectedGeneration != dropCompletionGeneration {
            return
        }
        cancelPendingDropCompletion()
        setApplyingDropMutation(false)
        var projection = presentedDropIntent
        projection.finish()
        setPresentedDropIntent(projection)
    }

    func beginPendingGeometryEpoch(
        expectedSpaceId: UUID?,
        profileId: UUID?
    ) {
        geometry.beginPendingGeometryEpoch(
            expectedSpaceId: expectedSpaceId,
            profileId: profileId
        )
        clearHoverState()
        clearFavoritePreviewState()
        requestGeometryRefresh()
        geometry.promotePendingGeometryIfReady()
    }

    func requestGeometryRefresh() {
        geometry.requestGeometryRefresh()
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
        withPresentationMutation {
            let resolvedScope = scope ?? armedDragScope
            isDragging = true
            activeDragItemId = itemId
            dragLocation = location
            previewDragLocation = previewLocation ?? location
            setPreviewPresentation(
                kind: previewKind,
                assets: previewAssets,
                model: previewModel
            )
            isInternalDragSession = true
            activeDragScope = resolvedScope
            isInternalDragGeometryArmed = false
            armedDragScope = nil
            markPresentationChanged()
            syncGeometryCollectionContext()
            clearFavoritePreviewState()
            requestGeometryRefresh()
            geometry.flushDeferredGeometryForDragStart()
        }
    }

    func beginExternalDragSession(itemId: UUID?) {
        withPresentationMutation {
            isDragging = true
            activeDragItemId = itemId
            previewDragLocation = nil
            isInternalDragSession = false
            activeDragScope = nil
            isInternalDragGeometryArmed = false
            armedDragScope = nil
            markPresentationChanged()
            syncGeometryCollectionContext()
            clearFavoritePreviewState()
            requestGeometryRefresh()
            geometry.flushDeferredGeometryForDragStart()
        }
    }

    func armInternalDragGeometry(scope: SidebarDragScope?) {
        guard !isDragging else { return }
        guard !isInternalDragGeometryArmed || armedDragScope != scope else { return }

        isInternalDragGeometryArmed = true
        armedDragScope = scope
        markPresentationChanged()
        syncGeometryCollectionContext()
        requestGeometryRefresh()
    }

    func cancelArmedDragGeometry() {
        guard !isDragging,
              isInternalDragGeometryArmed || armedDragScope != nil else {
            return
        }

        isInternalDragGeometryArmed = false
        armedDragScope = nil
        markPresentationChanged()
        syncGeometryCollectionContext()
        requestGeometryRefresh()
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
        leaveDeferredDropTargets()
        var intent = presentedDropIntent
        intent.clearPresentation()
        setPresentedDropIntent(intent)
        clearFavoritePreviewState()
    }

    func presentDropResolution(_ resolution: SidebarDropResolution) {
        guard presentedDropIntent.active != resolution else { return }
        var intent = presentedDropIntent
        intent.present(resolution)
        setPresentedDropIntent(intent)
    }

    func updateFavoritePreviewState(
        at location: CGPoint,
        resolution: DropZoneSlot
    ) {
        let baseLocation = baseGeometryLocation(from: location)
        guard isDragging,
              let hoveredPage = hoveredInteractivePage(at: location, matching: activeDragScope),
              let metrics = favoriteLayoutMetricsBySpace[hoveredPage.spaceId],
              activeDragScope?.matches(profileId: metrics.profileId) != false,
              metrics.containsDropLocation(baseLocation),
              metrics.canAcceptDrop,
              metrics.maxDropRowCount > metrics.visibleRowCount else {
            clearFavoritePreviewState()
            return
        }

        guard case .favorite(let slot) = resolution else {
            clearFavoritePreviewState()
            return
        }

        let slotAllowsEmptyGridPreview = metrics.visibleItemCount == 0 && slot == 0
        guard slot >= metrics.firstSyntheticRowSlot || slotAllowsEmptyGridPreview else {
            clearFavoritePreviewState()
            return
        }

        let nextPreviewState = [
            hoveredPage.spaceId: SidebarFavoritePreviewState(
                expandedDropRowCount: metrics.maxDropRowCount,
                gapSlot: slot
            ),
        ]
        guard favoritePreviewStateBySpace != nextPreviewState else { return }
        favoritePreviewStateBySpace = nextPreviewState
        markPresentationChanged()
    }

    func adjustGeometryStoreScrollDelta(deltaY: CGFloat) {
        geometry.adjustScroll(deltaY: deltaY)
    }

    private func syncGeometryCollectionContext() {
        geometry.updateCollectionContext(
            isDragging: storedIsDragging,
            isInternalDragSession: storedIsInternalDragSession,
            activeScope: storedActiveDragScope,
            isArmed: isInternalDragGeometryArmed,
            armedScope: armedDragScope
        )
    }

    private func setPresentedDropIntent(
        _ intent: SidebarPresentedDropIntentState
    ) {
        presentedDropIntent = intent
        markPresentationChanged()
    }

    private func setApplyingDropMutation(_ isApplying: Bool) {
        guard storedIsApplyingDropMutation != isApplying else {
            return
        }
        storedIsApplyingDropMutation = isApplying
        markPresentationChanged()
    }

    private func setPreviewPresentation(
        kind: SidebarDragPreviewKind,
        assets: [SidebarDragPreviewKind: SidebarDragPreviewAsset],
        model: SidebarDragPreviewModel?
    ) {
        storedPreviewKind = kind
        previewAssets = assets
        previewModel = model
        floatingPresentationRevision &+= 1
        markPresentationChanged()
    }

    private func clearPreviewPresentation() {
        guard storedPreviewKind != nil
                || !previewAssets.isEmpty
                || previewModel != nil else { return }
        storedPreviewKind = nil
        previewAssets = [:]
        previewModel = nil
        floatingPresentationRevision &+= 1
        markPresentationChanged()
    }

    private func withPresentationMutation<T>(
        _ update: () throws -> T
    ) rethrows -> T {
        presentationMutationDepth += 1
        defer {
            presentationMutationDepth -= 1
            if presentationMutationDepth == 0,
               presentationNeedsPublish {
                presentationNeedsPublish = false
                publishPresentations()
            }
        }
        return try update()
    }

    private func markPresentationChanged() {
        guard presentationMutationDepth > 0 else {
            publishPresentations()
            return
        }
        presentationNeedsPublish = true
    }

    private func publishPresentations() {
        let hoveredPinnedSpaceID: UUID?
        if case .spacePinned(let spaceID, _) = projectionHoveredSlot {
            hoveredPinnedSpaceID = spaceID
        } else {
            hoveredPinnedSpaceID = nil
        }
        listPresentation.publish(
            SidebarListDragPresentationFrame(
                isDragging: isDragging,
                isCompletingDrop: isCompletingDrop,
                isApplyingDropMutation: isApplyingDropMutation,
                // Retained past the pointer session: the list surface needs to
                // know which row the committed drop retired in order to hand
                // its presentation identity to the row replacing it. Source
                // dimming is unaffected — it is gated on `isDragging`.
                activeDragItemID: projectionDragItemId,
                activeHoveredFolderID: activeHoveredFolderId,
                folderDropIntent: folderDropIntent,
                hoveredPinnedSpaceID: hoveredPinnedSpaceID,
                splitPairingTarget: projectionSplitPairingTarget
            )
        )
        sessionPresentation.publish(
            SidebarDragSessionPresentationFrame(
                isDragging: isDragging,
                isInternalDragSession: isInternalDragSession,
                isInternalDragGeometryArmed: isInternalDragGeometryArmed
            )
        )
        favoritePresentation.publish(
            SidebarFavoriteDragPresentationFrame(
                isDragging: isDragging,
                isCompletingDrop: isCompletingDrop,
                projectionDragItemID: projectionDragItemId,
                projectionDragScope: projectionDragScope,
                projectionHoveredSlot: projectionHoveredSlot,
                previewStateBySpace: favoritePreviewStateBySpace
            )
        )
        floatingPresentation.publish(
            SidebarFloatingDragPresentationFrame(
                revision: floatingPresentationRevision,
                hoveredSlot: hoveredSlot,
                previewKind: storedPreviewKind,
                previewAssets: previewAssets,
                previewModel: previewModel
            )
        )
    }
}
