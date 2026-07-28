import AppKit
import Combine
import SumiDomain
import SwiftUI

struct SidebarListDragPresentationFrame: Equatable {
    var isDragging = false
    var isCompletingDrop = false
    var activeDragItemID: UUID?
    var activeHoveredFolderID: UUID?
    var folderDropIntent: FolderDropIntent = .none
    var hoveredPinnedSpaceID: UUID?
    var splitPairingTarget: SidebarSplitPairingTarget?
}

/// Atomic read model for the flattened sidebar list. The broader drag coordinator can
/// mutate several internal fields per command; rendering receives one frame.
@MainActor
final class SidebarListDragPresentation: ObservableObject {
    @Published private(set) var frame = SidebarListDragPresentationFrame()

    fileprivate func publish(_ frame: SidebarListDragPresentationFrame) {
        guard self.frame != frame else { return }
        self.frame = frame
    }
}

@MainActor
final class SidebarDragState: ObservableObject {
    /// Window-scoped registry for tab-list drag autoscroll + swipe forwarding.
    let dragAutoscrollRegistry = SidebarTabListDragAutoscrollRegistry()
    let locationTracker = SidebarDragLocationTracker()
    /// Narrow observable for per-row chrome (hover sensors etc.) that only
    /// cares whether a drag session is active — subscribing rows to the full
    /// drag state would re-render all of them on every hover-slot change.
    let activityState = SidebarDragActivityState()
    let geometry = SidebarDragGeometryModule()
    let listPresentation = SidebarListDragPresentation()

    // Every setter below drops writes that don't change the value. The AppKit drag
    // pipeline re-resolves state on each pointer sample (and on periodic dragging
    // updates while the pointer is idle); without this guard each sample publishes
    // `objectWillChange` to every observing sidebar view even when nothing moved.
    @Published private var storedIsDragging = false
    @Published private var presentedDropIntent = SidebarPresentedDropIntentState()
    @Published private var storedActiveSplitTarget: SplitDropSide?
    @Published private var storedActiveDragItemId: UUID?
    @Published private var storedPreviewKind: SidebarDragPreviewKind?
    @Published var previewAssets: [SidebarDragPreviewKind: SidebarDragPreviewAsset] = [:]
    @Published var previewModel: SidebarDragPreviewModel?
    @Published private var storedIsInternalDragSession = false
    @Published private var storedActiveDragScope: SidebarDragScope?
    private var listPresentationMutationDepth = 0
    private var listPresentationNeedsPublish = false

    var isDragging: Bool {
        get { storedIsDragging }
        set {
            guard storedIsDragging != newValue else { return }
            storedIsDragging = newValue
            markListPresentationChanged()
            activityState.isDragging = newValue
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

    var activeSplitTarget: SplitDropSide? {
        get { storedActiveSplitTarget }
        set {
            guard storedActiveSplitTarget != newValue else { return }
            storedActiveSplitTarget = newValue
        }
    }

    var activeDragItemId: UUID? {
        get { storedActiveDragItemId }
        set {
            guard storedActiveDragItemId != newValue else { return }
            storedActiveDragItemId = newValue
            markListPresentationChanged()
        }
    }

    var previewKind: SidebarDragPreviewKind? {
        get { storedPreviewKind }
        set {
            guard storedPreviewKind != newValue else { return }
            storedPreviewKind = newValue
        }
    }

    var isInternalDragSession: Bool {
        get { storedIsInternalDragSession }
        set {
            guard storedIsInternalDragSession != newValue else { return }
            storedIsInternalDragSession = newValue
            syncGeometryCollectionContext()
        }
    }

    var activeDragScope: SidebarDragScope? {
        get { storedActiveDragScope }
        set {
            guard storedActiveDragScope != newValue else { return }
            storedActiveDragScope = newValue
            syncGeometryCollectionContext()
        }
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

    // For Zen's auto workspace switch
    @Published var isHoveringNearEdge: Bool = false

    @Published var essentialsPreviewStateBySpace: [UUID: SidebarEssentialsPreviewState] = [:]

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

    private func clearEssentialsPreviewState() {
        guard !essentialsPreviewStateBySpace.isEmpty else { return }
        essentialsPreviewStateBySpace = [:]
    }

    @discardableResult
    func beginDropCommit(
        refreshingIfEmpty refresh: () -> SidebarDropResolution? = { nil }
    ) -> SidebarDropResolution? {
        withListPresentationMutation {
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
            return resolution
        }
    }

    func resetInteractionState() {
        withListPresentationMutation {
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
                let expectedGeneration = dropCompletionGeneration
                scheduleDropCompletionFinish(expectedGeneration: expectedGeneration)
            } else {
                finishDropCompletion()
            }
            isInternalDragGeometryArmed = false
            armedDragScope = nil
            syncGeometryCollectionContext()
            isHoveringNearEdge = false
            clearEssentialsPreviewState()
            requestGeometryRefresh()
        }
    }

    private func scheduleDropCompletionFinish(expectedGeneration: Int) {
        cancelPendingDropCompletion()
        cancelPendingDropCompletionAction = delayedActions.schedule(after: 0.05) { [weak self] in
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
        clearEssentialsPreviewState()
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
        withListPresentationMutation {
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
            syncGeometryCollectionContext()
            clearEssentialsPreviewState()
            requestGeometryRefresh()
            geometry.flushDeferredGeometryForDragStart()
        }
    }

    func beginExternalDragSession(itemId: UUID?) {
        withListPresentationMutation {
            isDragging = true
            activeDragItemId = itemId
            previewDragLocation = nil
            isInternalDragSession = false
            activeDragScope = nil
            isInternalDragGeometryArmed = false
            armedDragScope = nil
            syncGeometryCollectionContext()
            clearEssentialsPreviewState()
            requestGeometryRefresh()
            geometry.flushDeferredGeometryForDragStart()
        }
    }

    func armInternalDragGeometry(scope: SidebarDragScope?) {
        guard !isDragging else { return }
        guard !isInternalDragGeometryArmed || armedDragScope != scope else { return }

        isInternalDragGeometryArmed = true
        armedDragScope = scope
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
        activeSplitTarget = nil
        clearEssentialsPreviewState()
    }

    func presentDropResolution(_ resolution: SidebarDropResolution) {
        guard presentedDropIntent.active != resolution else { return }
        var intent = presentedDropIntent
        intent.present(resolution)
        setPresentedDropIntent(intent)
    }

    func updateEssentialsPreviewState(
        at location: CGPoint,
        resolution: DropZoneSlot
    ) {
        let baseLocation = baseGeometryLocation(from: location)
        guard isDragging,
              let hoveredPage = hoveredInteractivePage(at: location, matching: activeDragScope),
              let metrics = essentialsLayoutMetricsBySpace[hoveredPage.spaceId],
              activeDragScope?.matches(profileId: metrics.profileId) != false,
              metrics.containsDropLocation(baseLocation),
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

        let nextPreviewState = [
            hoveredPage.spaceId: SidebarEssentialsPreviewState(
                expandedDropRowCount: metrics.maxDropRowCount,
                gapSlot: slot
            ),
        ]
        guard essentialsPreviewStateBySpace != nextPreviewState else { return }
        essentialsPreviewStateBySpace = nextPreviewState
    }

    func essentialsPreviewState(for spaceId: UUID) -> SidebarEssentialsPreviewState? {
        essentialsPreviewStateBySpace[spaceId]
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
        markListPresentationChanged()
    }

    private func withListPresentationMutation<T>(
        _ update: () throws -> T
    ) rethrows -> T {
        listPresentationMutationDepth += 1
        defer {
            listPresentationMutationDepth -= 1
            if listPresentationMutationDepth == 0,
               listPresentationNeedsPublish {
                listPresentationNeedsPublish = false
                publishListPresentation()
            }
        }
        return try update()
    }

    private func markListPresentationChanged() {
        guard listPresentationMutationDepth > 0 else {
            publishListPresentation()
            return
        }
        listPresentationNeedsPublish = true
    }

    private func publishListPresentation() {
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
                activeDragItemID: activeDragItemId,
                activeHoveredFolderID: activeHoveredFolderId,
                folderDropIntent: folderDropIntent,
                hoveredPinnedSpaceID: hoveredPinnedSpaceID,
                splitPairingTarget: projectionSplitPairingTarget
            )
        )
    }
}

@MainActor
final class SidebarDropTargetDwellGate {
    static let duration: TimeInterval = 0.16

    private let delayedActions: MainActorDelayedActionScheduler
    private var pendingTarget: SidebarDeferredDropTarget?
    private var admittedTarget: SidebarDeferredDropTarget?
    private var cancelPendingAdmission: MainActorDelayedActionScheduler.Cancellation?
    private(set) var revision: UInt64 = 0

    init(delayedActions: MainActorDelayedActionScheduler = .live) {
        self.delayedActions = delayedActions
    }

    isolated deinit {
        cancelPendingAdmission?()
    }

    func admits(_ target: SidebarDeferredDropTarget) -> Bool {
        if admittedTarget == target {
            return true
        }
        guard pendingTarget != target else { return false }

        cancelPendingAdmission?()
        admittedTarget = nil
        pendingTarget = target
        cancelPendingAdmission = delayedActions.schedule(
            after: Self.duration
        ) { [weak self] in
            guard let self, self.pendingTarget == target else { return }
            self.pendingTarget = nil
            self.admittedTarget = target
            self.cancelPendingAdmission = nil
            self.revision &+= 1
        }
        return false
    }

    func leaveDeferredTargets() {
        guard pendingTarget != nil || admittedTarget != nil else { return }
        cancelPendingAdmission?()
        cancelPendingAdmission = nil
        pendingTarget = nil
        admittedTarget = nil
    }
}

@MainActor
final class SidebarDragLocationTracker: ObservableObject {
    @Published var location: CGPoint? = nil
    @Published var previewLocation: CGPoint? = nil
}

/// Minimal drag-session flag for chrome that must disable itself while any
/// drag is in flight. Publishes exactly twice per drag (begin/end).
@MainActor
final class SidebarDragActivityState: ObservableObject {
    @Published var isDragging: Bool = false
}
