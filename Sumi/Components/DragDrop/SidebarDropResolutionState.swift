import CoreGraphics
import Foundation
import SumiDomain

@MainActor
enum SidebarDropResolver {
    static func resolve(
        location: CGPoint,
        state: SidebarDragState,
        draggedItem: SumiDragItem?,
        scope: SidebarDragScope? = nil,
        allowsDeferredTargets: Bool = true
    ) -> SidebarDropResolution {
        let activeScope = scope ?? state.activeDragScope
        let hoveredPage = state.hoveredInteractivePage(
            at: location,
            matching: activeScope
        )
        let baseLocation = state.baseGeometryLocation(from: location)
        return resolve(
            location: baseLocation,
            state: state,
            draggedItem: draggedItem,
            hoveredPage: hoveredPage,
            scope: activeScope,
            allowsDeferredTargets: allowsDeferredTargets
        ).anchored(in: state.geometry.geometrySnapshot)
    }

    private static func resolveEssentials(
        location: CGPoint,
        state: SidebarDragState,
        draggedItem: SumiDragItem?,
        hoveredPage: SidebarPageGeometryMetrics?,
        scope: SidebarDragScope?
    ) -> SidebarDropResolution? {
        guard let hoveredPage,
              let metrics = state.essentialsLayoutMetricsBySpace[
                  hoveredPage.spaceId
              ],
              scope?.matches(profileId: metrics.profileId) != false,
              metrics.containsDropLocation(location),
              metrics.canAcceptDrop || metrics.visibleItemCount > 0,
              location.y < metrics.dropHitFrame.maxY else {
            _ = draggedItem
            return nil
        }
        return SidebarEssentialsDropPolicy.resolve(
            location: location,
            metrics: metrics
        )
    }

    private static func resolveRegularTarget(
        location: CGPoint,
        state: SidebarDragState,
        hoveredPage: SidebarPageGeometryMetrics?
    ) -> SidebarDropResolution? {
        guard let hoveredPage else { return nil }
        let spaceID = hoveredPage.spaceId
        return SidebarRegularDropPolicy.resolve(
            location: location,
            context: SidebarRegularDropContext(
                spaceID: spaceID,
                outerFrame: state.sectionFrame(
                    for: .spaceRegular,
                    in: spaceID
                ) ?? state.regularListHitTargets[spaceID]?.frame,
                listMetrics: state.regularListHitTargets[spaceID]
            )
        )
    }

    private static func resolve(
        location: CGPoint,
        state: SidebarDragState,
        draggedItem: SumiDragItem?,
        hoveredPage: SidebarPageGeometryMetrics?,
        scope: SidebarDragScope?,
        allowsDeferredTargets: Bool
    ) -> SidebarDropResolution {
        if let essentialsResolution = resolveEssentials(
            location: location,
            state: state,
            draggedItem: draggedItem,
            hoveredPage: hoveredPage,
            scope: scope
        ) {
            return essentialsResolution
        }

        if allowsDeferredTargets,
           let pairingResolution = resolveSplitPairingTarget(
            location: location,
            state: state,
            draggedItem: draggedItem,
            hoveredPage: hoveredPage
        ) {
            return pairingResolution
        }

        if let folderResolution = resolveFolderTarget(
            location: location,
            state: state,
            draggedItem: draggedItem,
            hoveredPage: hoveredPage
        ) {
            return folderResolution
        }

        if let pinnedResolution = resolveSpacePinnedTarget(
            location: location,
            state: state,
            draggedItem: draggedItem,
            hoveredPage: hoveredPage
        ) {
            return pinnedResolution
        }

        if let regularResolution = resolveRegularTarget(
            location: location,
            state: state,
            hoveredPage: hoveredPage
        ) {
            return regularResolution
        }

        return SidebarDropResolution(
            slot: .empty,
            folderIntent: .none,
            activeHoveredFolderId: nil
        )
    }

    private static func resolveSplitPairingTarget(
        location: CGPoint,
        state: SidebarDragState,
        draggedItem: SumiDragItem?,
        hoveredPage: SidebarPageGeometryMetrics?
    ) -> SidebarDropResolution? {
        guard let hoveredPage,
              let hit = SidebarSplitPairingHitTest.hit(
                  at: location,
                  state: state,
                  hoveredPage: hoveredPage
              ),
              let target = SidebarSplitPairingPolicy.target(
                  at: location,
                  draggedItem: draggedItem,
                  candidate: hit.candidate
              ) else {
            return nil
        }
        return hit.resolution(target: target)
    }

    @discardableResult
    static func updateState(
        location: CGPoint,
        previewLocation: CGPoint? = nil,
        state: SidebarDragState,
        draggedItem: SumiDragItem?,
        scope: SidebarDragScope? = nil
    ) -> SidebarDropResolution {
        state.updateDragLocation(
            location,
            previewLocation: previewLocation
        )
        let resolution = resolve(
            location: location,
            state: state,
            draggedItem: draggedItem,
            scope: scope
        )
        let presentedResolution: SidebarDropResolution
        if let deferredTarget = resolution.deferredTarget {
            if state.admitsDeferredDropTarget(deferredTarget) {
                presentedResolution = resolution
            } else {
                presentedResolution = resolve(
                    location: location,
                    state: state,
                    draggedItem: draggedItem,
                    scope: scope,
                    allowsDeferredTargets: false
                )
            }
        } else {
            state.leaveDeferredDropTargets()
            presentedResolution = resolution
        }
        state.presentDropResolution(presentedResolution)
        state.updateEssentialsPreviewState(
            at: location,
            resolution: presentedResolution.slot
        )
        return presentedResolution
    }

    private static func resolveSpacePinnedTarget(
        location: CGPoint,
        state: SidebarDragState,
        draggedItem: SumiDragItem?,
        hoveredPage: SidebarPageGeometryMetrics?
    ) -> SidebarDropResolution? {
        guard let hoveredPage,
              let sectionFrame = state.sectionFrame(
                  for: .spacePinned,
                  in: hoveredPage.spaceId
              ) else { return nil }
        let spaceID = hoveredPage.spaceId
        return SidebarPinnedDropPolicy.resolve(
            location: location,
            context: SidebarPinnedDropContext(
                page: hoveredPage,
                sectionFrame: sectionFrame,
                essentialsBoundaryY: state.essentialsLayoutMetricsBySpace[
                    spaceID
                ]?.dropHitFrame.maxY ?? hoveredPage.frame.minY + 26,
                topLevelItems: state.topLevelPinnedItemsBySpace[spaceID] ?? [],
                listMetrics: state.pinnedListHitTargets[spaceID],
                hasFolderTargets: state.folderDropTargets.values.contains {
                    $0.spaceId == spaceID
                },
                draggedItem: draggedItem
            )
        )
    }

    private static func resolveFolderTarget(
        location: CGPoint,
        state: SidebarDragState,
        draggedItem: SumiDragItem?,
        hoveredPage: SidebarPageGeometryMetrics?
    ) -> SidebarDropResolution? {
        guard let hoveredPage else { return nil }
        return SidebarFolderDropPolicy.resolve(
            location: location,
            context: SidebarFolderDropContext(
                targets: state.folderTargetsBySpace[hoveredPage.spaceId] ?? [],
                childrenByFolder: state.folderChildrenByFolder,
                draggedItem: draggedItem
            )
        )
    }
}
