#if DEBUG
import Foundation

@MainActor
struct SidebarDebugMetricsSnapshot: Equatable {
    let liveInteractiveItemViewCount: Int
    let liveSidebarAppKitItemBridgeCount: Int
    let liveInteractiveOwnerAttachmentCount: Int
    let interactiveOwnerHostingViewCreatedCount: Int
    let mountedCollapsedSidebarHostCount: Int
    let collapsedHiddenMountedSidebarHostCount: Int
    let hardSidebarInputRehydrateCount: Int
    let hardSidebarInputRehydrateReasons: [String: Int]
    let dragGeometryReporterCountBySection: [String: Int]
    let totalActiveDragGeometryReporterCount: Int
    let isInternalDragGeometryArmed: Bool
    let isDragging: Bool
    let isInternalDragSession: Bool
}

@MainActor
enum SidebarDebugMetrics {
    private static var interactiveItemViews: Set<ObjectIdentifier> = []
    private static var sidebarAppKitItemBridgeViews: Set<ObjectIdentifier> = []
    private static var interactiveOwnerAttachments: Set<ObjectIdentifier> = []
    private static var collapsedSidebarHostModes: [ObjectIdentifier: SidebarPresentationMode] = [:]
    private static var interactiveOwnerHostingViewCreatedCount = 0
    private static var hardSidebarInputRehydrateCount = 0
    private static var hardSidebarInputRehydrateReasons: [String: Int] = [:]

    static func recordInteractiveItemViewInitialized(_ id: ObjectIdentifier) {
        interactiveItemViews.insert(id)
        interactiveOwnerHostingViewCreatedCount += 1
    }

    static func recordInteractiveItemViewDeinitialized(_ id: ObjectIdentifier) {
        interactiveItemViews.remove(id)
        sidebarAppKitItemBridgeViews.remove(id)
        interactiveOwnerAttachments.remove(id)
    }

    static func recordSidebarAppKitItemBridgeAttached(_ id: ObjectIdentifier) {
        sidebarAppKitItemBridgeViews.insert(id)
    }

    static func recordSidebarAppKitItemBridgeDetached(_ id: ObjectIdentifier) {
        sidebarAppKitItemBridgeViews.remove(id)
    }

    static func recordInteractiveOwnerAttached(_ id: ObjectIdentifier) {
        interactiveOwnerAttachments.insert(id)
    }

    static func recordInteractiveOwnerDetached(_ id: ObjectIdentifier) {
        interactiveOwnerAttachments.remove(id)
    }

    static func recordCollapsedHiddenSidebarHost(
        controller: SidebarColumnViewController,
        isMounted: Bool
    ) {
        recordCollapsedSidebarHost(
            controller: controller,
            presentationMode: .collapsedHidden,
            isMounted: isMounted
        )
    }

    static func recordCollapsedSidebarHost(
        controller: SidebarColumnViewController,
        presentationMode: SidebarPresentationMode,
        isMounted: Bool
    ) {
        let id = ObjectIdentifier(controller)
        if isMounted, presentationMode != .docked {
            collapsedSidebarHostModes[id] = presentationMode
        } else {
            collapsedSidebarHostModes.removeValue(forKey: id)
        }
    }

    static func recordHardSidebarInputRehydrate(reason: SidebarInputRecoveryReason) {
        hardSidebarInputRehydrateCount += 1
        hardSidebarInputRehydrateReasons[reason.description, default: 0] += 1
    }

    static func resetForTesting() {
        interactiveItemViews.removeAll()
        sidebarAppKitItemBridgeViews.removeAll()
        interactiveOwnerAttachments.removeAll()
        collapsedSidebarHostModes.removeAll()
        interactiveOwnerHostingViewCreatedCount = 0
        hardSidebarInputRehydrateCount = 0
        hardSidebarInputRehydrateReasons.removeAll()
    }

    static func snapshot(
        dragState: SidebarDragState = .shared
    ) -> SidebarDebugMetricsSnapshot {
        let dragReporterCounts = dragGeometryReporterCounts(from: dragState.geometrySnapshot)
        return SidebarDebugMetricsSnapshot(
            liveInteractiveItemViewCount: interactiveItemViews.count,
            liveSidebarAppKitItemBridgeCount: sidebarAppKitItemBridgeViews.count,
            liveInteractiveOwnerAttachmentCount: interactiveOwnerAttachments.count,
            interactiveOwnerHostingViewCreatedCount: interactiveOwnerHostingViewCreatedCount,
            mountedCollapsedSidebarHostCount: collapsedSidebarHostModes.count,
            collapsedHiddenMountedSidebarHostCount: collapsedSidebarHostModes.values.filter {
                $0 == .collapsedHidden
            }.count,
            hardSidebarInputRehydrateCount: hardSidebarInputRehydrateCount,
            hardSidebarInputRehydrateReasons: hardSidebarInputRehydrateReasons,
            dragGeometryReporterCountBySection: dragReporterCounts,
            totalActiveDragGeometryReporterCount: dragReporterCounts.values.reduce(0, +),
            isInternalDragGeometryArmed: dragState.isInternalDragGeometryArmed,
            isDragging: dragState.isDragging,
            isInternalDragSession: dragState.isInternalDragSession
        )
    }

    private static func dragGeometryReporterCounts(
        from snapshot: SidebarGeometrySnapshot
    ) -> [String: Int] {
        [
            "page": snapshot.pageGeometryByKey.count,
            "section": snapshot.sectionFramesBySpace.count,
            "topLevelPinned": snapshot.topLevelPinnedItemTargets.count,
            "folder": snapshot.folderDropTargets.count,
            "folderChild": snapshot.folderChildDropTargets.count,
            "regular": snapshot.regularListHitTargets.count,
            "essentials": snapshot.essentialsLayoutMetricsBySpace.count,
        ]
    }
}
#endif
