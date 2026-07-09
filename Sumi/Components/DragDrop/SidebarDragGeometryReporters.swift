import SwiftUI

// MARK: - Geometry tracking (deferred)

/// Publishes geometry into `SidebarDragState` on the next main run loop turn so SwiftUI does not emit
/// "Publishing changes from within view updates" during layout/preference application.
@MainActor
enum SidebarDragStateDeferredGeometry {
    static func setPageGeometry(
        dragState: SidebarDragState,
        spaceId: UUID,
        profileId: UUID?,
        renderMode: SidebarPageGeometryRenderMode,
        generation: Int,
        _ frame: CGRect?
    ) {
        dragState.schedulePageGeometry(
            spaceId: spaceId,
            profileId: profileId,
            frame: frame,
            renderMode: renderMode,
            generation: generation
        )
    }

    static func setSectionFrame(
        dragState: SidebarDragState,
        spaceId: UUID,
        section: SidebarSectionPrefix,
        generation: Int,
        _ frame: CGRect?
    ) {
        dragState.scheduleSectionFrame(
            spaceId: spaceId,
            section: section,
            frame: frame,
            generation: generation
        )
    }

    static func updateFolderDropTarget(
        dragState: SidebarDragState,
        update: SidebarFolderDropTargetUpdate,
        generation: Int
    ) {
        dragState.scheduleFolderDropTarget(
            update,
            generation: generation
        )
    }

    static func removeFolderDropTarget(
        dragState: SidebarDragState,
        folderId: UUID,
        region: SidebarFolderDragRegion,
        generation: Int
    ) {
        dragState.scheduleFolderDropTarget(
            SidebarFolderDropTargetUpdate(folderId: folderId, region: region),
            generation: generation
        )
    }

    static func updateTopLevelPinnedItemTarget(
        dragState: SidebarDragState,
        update: SidebarTopLevelPinnedItemTargetUpdate,
        generation: Int
    ) {
        dragState.scheduleTopLevelPinnedItemTarget(
            update,
            generation: generation
        )
    }

    static func removeTopLevelPinnedItemTarget(
        dragState: SidebarDragState,
        itemId: UUID,
        generation: Int
    ) {
        dragState.scheduleTopLevelPinnedItemTarget(
            SidebarTopLevelPinnedItemTargetUpdate(itemId: itemId),
            generation: generation
        )
    }

    static func updateFolderChildDropTarget(
        dragState: SidebarDragState,
        update: SidebarFolderChildDropTargetUpdate,
        generation: Int
    ) {
        dragState.scheduleFolderChildDropTarget(
            update,
            generation: generation
        )
    }

    static func removeFolderChildDropTarget(
        dragState: SidebarDragState,
        childId: UUID,
        generation: Int
    ) {
        dragState.scheduleFolderChildDropTarget(
            SidebarFolderChildDropTargetUpdate(childId: childId),
            generation: generation
        )
    }

    static func updateRegularListHitTarget(
        dragState: SidebarDragState,
        spaceId: UUID,
        frame: CGRect,
        itemCount: Int,
        generation: Int
    ) {
        dragState.scheduleRegularListHitTarget(
            spaceId: spaceId,
            frame: frame,
            itemCount: itemCount,
            generation: generation
        )
    }

    static func removeRegularListHitTarget(
        dragState: SidebarDragState,
        spaceId: UUID,
        generation: Int
    ) {
        dragState.scheduleRegularListHitTarget(
            spaceId: spaceId,
            frame: nil,
            itemCount: 0,
            generation: generation
        )
    }

    static func updateEssentialsLayoutMetrics(
        dragState: SidebarDragState,
        update: SidebarEssentialsLayoutUpdate,
        generation: Int
    ) {
        dragState.scheduleEssentialsLayoutMetrics(
            update,
            generation: generation
        )
    }

    static func removeEssentialsLayoutMetrics(
        dragState: SidebarDragState,
        spaceId: UUID,
        generation: Int
    ) {
        dragState.scheduleEssentialsLayoutMetrics(
            SidebarEssentialsLayoutUpdate(spaceId: spaceId),
            generation: generation
        )
    }
}

// MARK: - Geometry Tracking

/// Shared skeleton for geometry reporters: a background `GeometryReader` that
/// re-reports the global frame when it moves, when any caller-supplied trigger changes,
/// when `SidebarDragState.geometryRevision` bumps, and on appear; `remove` runs on disappear.
private struct SidebarDragGeometryReporting<Trigger: Equatable>: ViewModifier {
    let isEnabled: Bool
    let trigger: Trigger
    var reportsOnDragBegin = false
    let report: (CGRect) -> Void
    let remove: () -> Void
    @EnvironmentObject private var dragState: SidebarDragState

    func body(content: Content) -> some View {
        content
            .background {
                if isEnabled {
                    GeometryReader { geo in
                        Color.clear
                            .onChange(of: geo.frame(in: .global)) { _, newFrame in
                                report(newFrame)
                            }
                            .onChange(of: trigger) { _, _ in
                                report(geo.frame(in: .global))
                            }
                            .onChange(of: dragState.geometryRevision) { _, _ in
                                report(geo.frame(in: .global))
                            }
                            .onChange(of: dragState.isDragging) { _, isDragging in
                                if reportsOnDragBegin, isDragging {
                                    report(geo.frame(in: .global))
                                }
                            }
                            .onAppear {
                                report(geo.frame(in: .global))
                            }
                            .onDisappear {
                                remove()
                            }
                    }
                }
            }
    }
}

/// Parameterized reporter that wires `SidebarDragGeometryReporting` to deferred geometry updates.
private struct SidebarDragGeometryReporter<Trigger: Equatable>: ViewModifier {
    let isEnabled: Bool
    /// When set, the GeometryReader is only mounted while detailed geometry collection is active
    /// for this space — matching the previous per-reporter `isEnabled && shouldCollect…` gate.
    var detailedGeometrySpace: (spaceId: UUID, profileId: UUID?)? = nil
    let trigger: Trigger
    var reportsOnDragBegin = false
    let report: (SidebarDragState, CGRect) -> Void
    let remove: (SidebarDragState) -> Void
    @EnvironmentObject private var dragState: SidebarDragState

    private var resolvedIsEnabled: Bool {
        guard isEnabled else { return false }
        guard let detailedGeometrySpace else { return true }
        return dragState.shouldCollectDetailedGeometry(
            spaceId: detailedGeometrySpace.spaceId,
            profileId: detailedGeometrySpace.profileId
        )
    }

    func body(content: Content) -> some View {
        content.modifier(
            SidebarDragGeometryReporting(
                isEnabled: resolvedIsEnabled,
                trigger: trigger,
                reportsOnDragBegin: reportsOnDragBegin,
                report: { frame in report(dragState, frame) },
                remove: { remove(dragState) }
            )
        )
    }
}

private struct SidebarEssentialsLayoutGeometrySignature: Equatable {
    let itemCount: Int
    let columnCount: Int
    let firstSyntheticRowSlot: Int?
    let rowCount: Int
    let visibleItemCount: Int
    let visibleRowCount: Int
    let maxDropRowCount: Int
    let dropFrame: CGRect
    let dropSlotFrames: [SidebarEssentialsDropSlotMetrics]
    let itemSize: CGSize
    let gridSpacing: CGFloat
    let canAcceptDrop: Bool
    let generation: Int
    let isEnabled: Bool
}

extension View {
    func sidebarPageGeometry(
        spaceId: UUID,
        profileId: UUID?,
        renderMode: SidebarPageGeometryRenderMode,
        generation: Int,
        isEnabled: Bool = true
    ) -> some View {
        modifier(
            SidebarDragGeometryReporter(
                isEnabled: isEnabled && renderMode == .interactive,
                trigger: generation,
                report: { dragState, frame in
                    SidebarDragStateDeferredGeometry.setPageGeometry(
                        dragState: dragState,
                        spaceId: spaceId,
                        profileId: profileId,
                        renderMode: renderMode,
                        generation: generation,
                        frame
                    )
                },
                remove: { dragState in
                    SidebarDragStateDeferredGeometry.setPageGeometry(
                        dragState: dragState,
                        spaceId: spaceId,
                        profileId: profileId,
                        renderMode: renderMode,
                        generation: generation,
                        nil
                    )
                }
            )
        )
    }

    func sidebarSectionGeometry(
        for section: SidebarSectionPrefix,
        spaceId: UUID,
        generation: Int,
        isEnabled: Bool = true
    ) -> some View {
        modifier(
            SidebarDragGeometryReporter(
                isEnabled: isEnabled,
                trigger: generation,
                report: { dragState, frame in
                    SidebarDragStateDeferredGeometry.setSectionFrame(
                        dragState: dragState,
                        spaceId: spaceId,
                        section: section,
                        generation: generation,
                        frame
                    )
                },
                remove: { dragState in
                    SidebarDragStateDeferredGeometry.setSectionFrame(
                        dragState: dragState,
                        spaceId: spaceId,
                        section: section,
                        generation: generation,
                        nil
                    )
                }
            )
        )
    }

    func sidebarFolderDropGeometry(
        folderId: UUID,
        spaceId: UUID,
        parentFolderId: UUID?,
        topLevelIndex: Int,
        childCount: Int,
        isOpen: Bool,
        region: SidebarFolderDragRegion,
        generation: Int,
        isActive: Bool = true
    ) -> some View {
        modifier(
            SidebarDragGeometryReporter(
                isEnabled: isActive,
                detailedGeometrySpace: (spaceId, nil),
                trigger: [
                    AnyHashable(topLevelIndex),
                    AnyHashable(parentFolderId),
                    AnyHashable(childCount),
                    AnyHashable(isOpen),
                    AnyHashable(generation),
                ],
                reportsOnDragBegin: true,
                report: { dragState, frame in
                    let update = isActive
                        ? SidebarFolderDropTargetUpdate(
                            metrics: SidebarFolderDropTargetMetrics(
                                folderId: folderId,
                                spaceId: spaceId,
                                parentFolderId: parentFolderId,
                                topLevelIndex: topLevelIndex,
                                childCount: childCount,
                                isOpen: isOpen
                            ),
                            region: region,
                            frame: frame
                        )
                        : SidebarFolderDropTargetUpdate(folderId: folderId, region: region)
                    SidebarDragStateDeferredGeometry.updateFolderDropTarget(
                        dragState: dragState,
                        update: update,
                        generation: generation
                    )
                },
                remove: { dragState in
                    SidebarDragStateDeferredGeometry.removeFolderDropTarget(
                        dragState: dragState,
                        folderId: folderId,
                        region: region,
                        generation: generation
                    )
                }
            )
        )
    }

    func sidebarTopLevelPinnedItemGeometry(
        itemId: UUID,
        spaceId: UUID,
        topLevelIndex: Int,
        generation: Int,
        isActive: Bool = true
    ) -> some View {
        modifier(
            SidebarDragGeometryReporter(
                isEnabled: isActive,
                detailedGeometrySpace: (spaceId, nil),
                trigger: [
                    AnyHashable(topLevelIndex),
                    AnyHashable(generation),
                ],
                report: { dragState, frame in
                    let update = isActive
                        ? SidebarTopLevelPinnedItemTargetUpdate(
                            metrics: SidebarTopLevelPinnedItemMetrics(
                                itemId: itemId,
                                spaceId: spaceId,
                                topLevelIndex: topLevelIndex,
                                frame: frame
                            )
                        )
                        : SidebarTopLevelPinnedItemTargetUpdate(itemId: itemId)
                    SidebarDragStateDeferredGeometry.updateTopLevelPinnedItemTarget(
                        dragState: dragState,
                        update: update,
                        generation: generation
                    )
                },
                remove: { dragState in
                    SidebarDragStateDeferredGeometry.removeTopLevelPinnedItemTarget(
                        dragState: dragState,
                        itemId: itemId,
                        generation: generation
                    )
                }
            )
        )
    }

    func sidebarFolderChildDropGeometry(
        spaceId: UUID,
        folderId: UUID,
        childId: UUID,
        index: Int,
        generation: Int,
        isActive: Bool = true
    ) -> some View {
        modifier(
            SidebarDragGeometryReporter(
                isEnabled: isActive,
                detailedGeometrySpace: (spaceId, nil),
                trigger: [
                    AnyHashable(index),
                    AnyHashable(generation),
                ],
                report: { dragState, frame in
                    let update = isActive
                        ? SidebarFolderChildDropTargetUpdate(
                            metrics: SidebarFolderChildDropTargetMetrics(
                                childId: childId,
                                folderId: folderId,
                                index: index,
                                frame: frame
                            )
                        )
                        : SidebarFolderChildDropTargetUpdate(childId: childId)
                    SidebarDragStateDeferredGeometry.updateFolderChildDropTarget(
                        dragState: dragState,
                        update: update,
                        generation: generation
                    )
                },
                remove: { dragState in
                    SidebarDragStateDeferredGeometry.removeFolderChildDropTarget(
                        dragState: dragState,
                        childId: childId,
                        generation: generation
                    )
                }
            )
        )
    }

    func sidebarRegularListHitGeometry(
        for spaceId: UUID,
        itemCount: Int,
        generation: Int,
        isEnabled: Bool = true
    ) -> some View {
        modifier(
            SidebarDragGeometryReporter(
                isEnabled: isEnabled,
                detailedGeometrySpace: (spaceId, nil),
                trigger: [
                    AnyHashable(itemCount),
                    AnyHashable(generation),
                ],
                report: { dragState, frame in
                    if isEnabled {
                        SidebarDragStateDeferredGeometry.updateRegularListHitTarget(
                            dragState: dragState,
                            spaceId: spaceId,
                            frame: frame,
                            itemCount: itemCount,
                            generation: generation
                        )
                    } else {
                        SidebarDragStateDeferredGeometry.removeRegularListHitTarget(
                            dragState: dragState,
                            spaceId: spaceId,
                            generation: generation
                        )
                    }
                },
                remove: { dragState in
                    SidebarDragStateDeferredGeometry.removeRegularListHitTarget(
                        dragState: dragState,
                        spaceId: spaceId,
                        generation: generation
                    )
                }
            )
        )
    }

    func sidebarEssentialsLayoutGeometry(
        spaceId: UUID,
        profileId: UUID?,
        itemCount: Int,
        columnCount: Int,
        firstSyntheticRowSlot: Int? = nil,
        rowCount: Int,
        visibleItemCount: Int,
        visibleRowCount: Int,
        maxDropRowCount: Int,
        dropFrame: CGRect,
        dropSlotFrames: [SidebarEssentialsDropSlotMetrics] = [],
        itemSize: CGSize,
        gridSpacing: CGFloat,
        canAcceptDrop: Bool,
        generation: Int,
        isEnabled: Bool = true
    ) -> some View {
        let signature = SidebarEssentialsLayoutGeometrySignature(
            itemCount: itemCount,
            columnCount: columnCount,
            firstSyntheticRowSlot: firstSyntheticRowSlot,
            rowCount: rowCount,
            visibleItemCount: visibleItemCount,
            visibleRowCount: visibleRowCount,
            maxDropRowCount: maxDropRowCount,
            dropFrame: dropFrame,
            dropSlotFrames: dropSlotFrames,
            itemSize: itemSize,
            gridSpacing: gridSpacing,
            canAcceptDrop: canAcceptDrop,
            generation: generation,
            isEnabled: isEnabled
        )
        return modifier(
            SidebarDragGeometryReporter(
                isEnabled: isEnabled,
                detailedGeometrySpace: (spaceId, profileId),
                trigger: signature,
                report: { dragState, frame in
                    if isEnabled {
                        let resolvedDropFrame = CGRect(
                            x: frame.minX + dropFrame.minX,
                            y: frame.minY + dropFrame.minY,
                            width: dropFrame.width,
                            height: dropFrame.height
                        )
                        let resolvedDropSlotFrames = dropSlotFrames.map { slotFrame in
                            SidebarEssentialsDropSlotMetrics(
                                slot: slotFrame.slot,
                                frame: CGRect(
                                    x: frame.minX + slotFrame.frame.minX,
                                    y: frame.minY + slotFrame.frame.minY,
                                    width: slotFrame.frame.width,
                                    height: slotFrame.frame.height
                                )
                            )
                        }
                        let update = SidebarEssentialsLayoutUpdate(
                            spaceId: spaceId,
                            input: SidebarEssentialsLayoutMetricsInput(
                                profileId: profileId,
                                frame: frame,
                                dropFrame: resolvedDropFrame,
                                dropSlotFrames: resolvedDropSlotFrames,
                                itemCount: itemCount,
                                columnCount: columnCount,
                                firstSyntheticRowSlot: firstSyntheticRowSlot,
                                rowCount: rowCount,
                                itemSize: itemSize,
                                gridSpacing: gridSpacing,
                                canAcceptDrop: canAcceptDrop,
                                visibleItemCount: visibleItemCount,
                                visibleRowCount: visibleRowCount,
                                maxDropRowCount: maxDropRowCount
                            )
                        )
                        SidebarDragStateDeferredGeometry.updateEssentialsLayoutMetrics(
                            dragState: dragState,
                            update: update,
                            generation: generation
                        )
                    } else {
                        SidebarDragStateDeferredGeometry.removeEssentialsLayoutMetrics(
                            dragState: dragState,
                            spaceId: spaceId,
                            generation: generation
                        )
                    }
                },
                remove: { dragState in
                    SidebarDragStateDeferredGeometry.removeEssentialsLayoutMetrics(
                        dragState: dragState,
                        spaceId: spaceId,
                        generation: generation
                    )
                }
            )
        )
    }
}
