import SumiDomain
import SwiftUI

// MARK: - Geometry Tracking

/// Shared skeleton for geometry reporters: a background `GeometryReader` that
/// re-reports the global frame when it moves, when any caller-supplied trigger changes,
/// when the geometry module revision bumps, and on appear; `remove` runs on disappear.
private struct SidebarDragGeometryReporting<Trigger: Equatable>: ViewModifier {
    let isEnabled: Bool
    let trigger: Trigger
    var reportsOnDragBegin = false
    let report: (CGRect) -> Void
    let remove: () -> Void
    @EnvironmentObject private var geometry: SidebarDragGeometryModule
    @EnvironmentObject private var refreshSignal: SidebarDragGeometryRefreshSignal

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
                            .onChange(of: refreshSignal.revision) { _, _ in
                                report(geo.frame(in: .global))
                            }
                            .onChange(of: geometry.isDragging) { _, isDragging in
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
    var detailedGeometrySpace: (spaceId: UUID, profileId: UUID?)?
    let trigger: Trigger
    var reportsOnDragBegin = false
    let report: (SidebarDragGeometryModule, CGRect) -> Void
    let remove: (SidebarDragGeometryModule) -> Void
    @EnvironmentObject private var geometry: SidebarDragGeometryModule

    private var resolvedIsEnabled: Bool {
        guard isEnabled else { return false }
        guard let detailedGeometrySpace else { return true }
        return geometry.shouldCollectDetailedGeometry(
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
                report: { frame in report(geometry, frame) },
                remove: { remove(geometry) }
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
                report: { geometry, frame in
                    geometry.report(
                        .page(
                            spaceId: spaceId,
                            profileId: profileId,
                            frame: frame,
                            renderMode: renderMode
                        ),
                        generation: generation
                    )
                },
                remove: { geometry in
                    geometry.report(
                        .page(
                            spaceId: spaceId,
                            profileId: profileId,
                            frame: nil,
                            renderMode: renderMode
                        ),
                        generation: generation
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
                report: { geometry, frame in
                    geometry.report(
                        .section(spaceId: spaceId, section: section, frame: frame),
                        generation: generation
                    )
                },
                remove: { geometry in
                    geometry.report(
                        .section(spaceId: spaceId, section: section, frame: nil),
                        generation: generation
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
                report: { geometry, frame in
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
                    geometry.report(
                        .folder(update),
                        generation: generation
                    )
                },
                remove: { geometry in
                    geometry.report(
                        .folder(SidebarFolderDropTargetUpdate(
                            folderId: folderId,
                            region: region
                        )),
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
        splitPairingMemberIDs: [SplitMemberID] = [],
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
                report: { geometry, frame in
                    let update = isActive
                        ? SidebarTopLevelPinnedItemTargetUpdate(
                            metrics: SidebarTopLevelPinnedItemMetrics(
                                itemId: itemId,
                                spaceId: spaceId,
                                topLevelIndex: topLevelIndex,
                                frame: frame,
                                splitPairingMemberIDs: splitPairingMemberIDs
                            )
                        )
                        : SidebarTopLevelPinnedItemTargetUpdate(itemId: itemId)
                    geometry.report(
                        .topLevelPinnedItem(update),
                        generation: generation
                    )
                },
                remove: { geometry in
                    geometry.report(
                        .topLevelPinnedItem(
                            SidebarTopLevelPinnedItemTargetUpdate(itemId: itemId)
                        ),
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
        splitPairingMemberIDs: [SplitMemberID] = [],
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
                report: { geometry, frame in
                    let update = isActive
                        ? SidebarFolderChildDropTargetUpdate(
                            metrics: SidebarFolderChildDropTargetMetrics(
                                childId: childId,
                                folderId: folderId,
                                index: index,
                                frame: frame,
                                splitPairingMemberIDs: splitPairingMemberIDs
                            )
                        )
                        : SidebarFolderChildDropTargetUpdate(childId: childId)
                    geometry.report(
                        .folderChild(update),
                        generation: generation
                    )
                },
                remove: { geometry in
                    geometry.report(
                        .folderChild(
                            SidebarFolderChildDropTargetUpdate(childId: childId)
                        ),
                        generation: generation
                    )
                }
            )
        )
    }

    func sidebarRegularListHitGeometry(
        for spaceId: UUID,
        rowIdentities: [SidebarVisualSceneProjection.RegularRow.Identity],
        splitPairingMemberIDsByRow: [[SplitMemberID]],
        generation: Int,
        isEnabled: Bool = true
    ) -> some View {
        modifier(
            SidebarDragGeometryReporter(
                isEnabled: isEnabled,
                detailedGeometrySpace: (spaceId, nil),
                trigger: [
                    AnyHashable(rowIdentities),
                    AnyHashable(splitPairingMemberIDsByRow),
                    AnyHashable(generation),
                ],
                report: { geometry, frame in
                    if isEnabled {
                        geometry.report(
                            .regularList(
                                spaceId: spaceId,
                                frame: frame,
                                rowIdentities: rowIdentities,
                                splitPairingMemberIDsByRow: splitPairingMemberIDsByRow
                            ),
                            generation: generation
                        )
                    } else {
                        geometry.report(
                            .regularList(
                                spaceId: spaceId,
                                frame: nil,
                                rowIdentities: [],
                                splitPairingMemberIDsByRow: []
                            ),
                            generation: generation
                        )
                    }
                },
                remove: { geometry in
                    geometry.report(
                        .regularList(
                            spaceId: spaceId,
                            frame: nil,
                            rowIdentities: [],
                            splitPairingMemberIDsByRow: []
                        ),
                        generation: generation
                    )
                }
            )
        )
    }

    func sidebarPinnedListHitGeometry(
        for spaceId: UUID,
        rowCount: Int,
        splitPairingMemberIDsByRow: [[SplitMemberID]],
        leadingInset: CGFloat,
        generation: Int,
        isEnabled: Bool
    ) -> some View {
        modifier(
            SidebarDragGeometryReporter(
                isEnabled: isEnabled,
                detailedGeometrySpace: (spaceId, nil),
                trigger: [
                    AnyHashable(splitPairingMemberIDsByRow),
                    AnyHashable(rowCount),
                    AnyHashable(leadingInset),
                    AnyHashable(generation),
                ],
                report: { geometry, frame in
                    geometry.report(
                            .pinnedList(
                                spaceId: spaceId,
                                frame: frame,
                                rowCount: rowCount,
                                splitPairingMemberIDsByRow:
                                    splitPairingMemberIDsByRow,
                                leadingInset: leadingInset
                            ),
                        generation: generation
                    )
                },
                remove: { geometry in
                    geometry.report(
                            .pinnedList(
                                spaceId: spaceId,
                                frame: nil,
                                rowCount: 0,
                                splitPairingMemberIDsByRow: [],
                                leadingInset: 0
                            ),
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
                report: { geometry, frame in
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
                        geometry.report(
                            .essentials(update),
                            generation: generation
                        )
                    } else {
                        geometry.report(
                            .essentials(SidebarEssentialsLayoutUpdate(spaceId: spaceId)),
                            generation: generation
                        )
                    }
                },
                remove: { geometry in
                    geometry.report(
                        .essentials(SidebarEssentialsLayoutUpdate(spaceId: spaceId)),
                        generation: generation
                    )
                }
            )
        )
    }
}
