import AppKit
import Combine
import SumiDomain
import SwiftUI

struct SidebarListDragPresentationFrame: Equatable {
    var isDragging = false
    var isCompletingDrop = false
    var isApplyingDropMutation = false
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

    func publish(_ frame: SidebarListDragPresentationFrame) {
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

    func publish(_ frame: SidebarDragSessionPresentationFrame) {
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

    func publish(_ frame: SidebarEssentialsDragPresentationFrame) {
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

    func publish(_ frame: SidebarFloatingDragPresentationFrame) {
        guard self.frame != frame else { return }
        self.frame = frame
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
