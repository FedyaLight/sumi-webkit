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

struct SidebarDragSessionPresentationFrame: Equatable {
    var isDragging = false
    var isInternalDragSession = false
    var isInternalDragGeometryArmed = false
}

@MainActor
final class SidebarDragSessionPresentation: ObservableObject {
    @Published private(set) var frame = SidebarDragSessionPresentationFrame()

    fileprivate func publish(_ frame: SidebarDragSessionPresentationFrame) {
        guard self.frame != frame else { return }
        self.frame = frame
    }
}

struct SidebarEssentialsDragPresentationFrame: Equatable {
    var isDragging = false
    var isCompletingDrop = false
    var projectionDragItemID: UUID?
    var projectionDragScope: SidebarDragScope?
    var projectionHoveredSlot: DropZoneSlot = .empty
    var previewStateBySpace: [UUID: SidebarEssentialsPreviewState] = [:]

    var isDropProjectionActive: Bool {
        isDragging || isCompletingDrop
    }

    var shouldAnimateDropLayout: Bool {
        isDragging && !isCompletingDrop
    }

    func previewState(for spaceID: UUID) -> SidebarEssentialsPreviewState? {
        previewStateBySpace[spaceID]
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
}

@MainActor
final class SidebarEssentialsDragPresentation: ObservableObject {
    @Published private(set) var frame = SidebarEssentialsDragPresentationFrame()

    fileprivate func publish(_ frame: SidebarEssentialsDragPresentationFrame) {
        guard self.frame != frame else { return }
        self.frame = frame
    }
}

struct SidebarFloatingDragPresentationFrame: Equatable {
    let revision: UInt64
    let hoveredSlot: DropZoneSlot
    let previewKind: SidebarDragPreviewKind?
    let previewAssets: [SidebarDragPreviewKind: SidebarDragPreviewAsset]
    let previewModel: SidebarDragPreviewModel?

    static func == (
        lhs: SidebarFloatingDragPresentationFrame,
        rhs: SidebarFloatingDragPresentationFrame
    ) -> Bool {
        lhs.revision == rhs.revision && lhs.hoveredSlot == rhs.hoveredSlot
    }
}

@MainActor
final class SidebarFloatingDragPresentation: ObservableObject {
    @Published private(set) var frame = SidebarFloatingDragPresentationFrame(
        revision: 0,
        hoveredSlot: .empty,
        previewKind: nil,
        previewAssets: [:],
        previewModel: nil
    )

    fileprivate func publish(_ frame: SidebarFloatingDragPresentationFrame) {
        guard self.frame != frame else { return }
        self.frame = frame
    }
}

@MainActor
final class SidebarDragState: ObservableObject {
    /// Window-scoped registry for tab-list drag autoscroll + swipe forwarding.
    let dragAutoscrollRegistry = SidebarTabListDragAutoscrollRegistry()
    let locationTracker = SidebarDragLocationTracker()
    let geometry = SidebarDragGeometryModule()
    let listPresentation = SidebarListDragPresentation()
    let sessionPresentation = SidebarDragSessionPresentation()
    let essentialsPresentation = SidebarEssentialsDragPresentation()
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

    private var essentialsPreviewStateBySpace: [UUID: SidebarEssentialsPreviewState] = [:]

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
                scheduleDropCompletionFinish(expectedGeneration: expectedGeneration)
            } else {
                finishDropCompletion()
            }
            isInternalDragGeometryArmed = false
            armedDragScope = nil
            markPresentationChanged()
            syncGeometryCollectionContext()
            clearEssentialsPreviewState()
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
            clearEssentialsPreviewState()
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
        essentialsPresentation.publish(
            SidebarEssentialsDragPresentationFrame(
                isDragging: isDragging,
                isCompletingDrop: isCompletingDrop,
                projectionDragItemID: projectionDragItemId,
                projectionDragScope: projectionDragScope,
                projectionHoveredSlot: projectionHoveredSlot,
                previewStateBySpace: essentialsPreviewStateBySpace
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
