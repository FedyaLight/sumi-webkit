import CoreGraphics
import Foundation
import SumiDomain

enum PresentedSidebarElementPlacement: Equatable {
    case inert
    case pinnedRow(
        itemID: UUID,
        topLevelIndex: Int,
        splitPairingMemberIDs: [SplitMemberID]
    )
    case folderHeader(
        folderID: UUID,
        parentFolderID: UUID?,
        containerIndex: Int,
        childCount: Int,
        nestingDepth: Int,
        isOpen: Bool,
        acceptsDrop: Bool,
        afterRegionHeight: CGFloat
    )
    case folderBodyTop(folderID: UUID)
    case folderBodyBottom(folderID: UUID)
    case folderChild(
        folderID: UUID,
        childID: UUID,
        index: Int,
        nestingDepth: Int,
        splitPairingMemberIDs: [SplitMemberID]
    )
    case boundary
    case regularRunStart
    case regularRow(
        identity: SidebarVisualSceneProjection.RegularRow.Identity,
        splitPairingMemberIDs: [SplitMemberID]
    )
    case regularRunEnd
}

/// Atomic DnD projection of the same transient track that SwiftUI presents.
///
/// Callers provide semantic placements and current animated extents. This
/// module owns every frame reconstruction rule, so rendering, hit testing, and
/// the visible insertion line cannot drift into separate coordinate systems.
struct PresentedSidebarLayout: Equatable {
    struct Item: Equatable {
        let extent: CGFloat
        let phase: SidebarListElementPhase
        let placement: PresentedSidebarElementPlacement
    }

    let spaceID: UUID
    let sectionFrames: [SidebarSectionPrefix: CGRect]
    let topLevelPinnedItemTargets: [UUID: SidebarTopLevelPinnedItemMetrics]
    let folderDropTargets: [UUID: SidebarFolderDropTargetMetrics]
    let folderChildDropTargets: [UUID: SidebarFolderChildDropTargetMetrics]
    let pinnedListHitTarget: SidebarPinnedListHitMetrics?
    let regularListHitTarget: SidebarRegularListHitMetrics

    static func resolve(
        spaceID: UUID,
        rootFrame: CGRect,
        items: [Item]
    ) -> Self {
        let records = presentedRecords(items)
        let trackMaxY = rootFrame.minY + records.reduce(0) {
            $0 + $1.item.extent
        }
        let boundaryMinY = rootFrame.minY + (records.first {
            $0.item.placement == .boundary
        }?.minY ?? (trackMaxY - rootFrame.minY))
        let regularStartY = rootFrame.minY + (records.first {
            $0.item.placement == .regularRunStart
        }?.minY ?? (boundaryMinY - rootFrame.minY))
        let regularEndY = rootFrame.minY + (records.first {
            $0.item.placement == .regularRunEnd
        }?.minY ?? (trackMaxY - rootFrame.minY))

        var topLevelTargets: [UUID: SidebarTopLevelPinnedItemMetrics] = [:]
        var folderTargets: [UUID: SidebarFolderDropTargetMetrics] = [:]
        var folderChildTargets: [UUID: SidebarFolderChildDropTargetMetrics] = [:]
        var regularIdentities: [
            SidebarVisualSceneProjection.RegularRow.Identity
        ] = []
        var regularMembers: [[SplitMemberID]] = []
        var regularFrames: [CGRect] = []

        let bodyTopYByFolder: [UUID: CGFloat] = Dictionary(
            uniqueKeysWithValues: records.compactMap { record in
                guard case .folderBodyTop(let folderID) =
                    record.item.placement else {
                    return nil
                }
                return (folderID, rootFrame.minY + record.minY)
            }
        )
        let bodyBottomYByFolder: [UUID: CGFloat] = Dictionary(
            uniqueKeysWithValues: records.compactMap { record in
                guard case .folderBodyBottom(let folderID) =
                    record.item.placement else {
                    return nil
                }
                return (
                    folderID,
                    rootFrame.minY + record.minY
                        + min(
                            record.item.extent,
                            SidebarRowLayout.folderBodyPadding
                        )
                )
            }
        )

        for record in records {
            guard record.item.phase != .leaving else { continue }

            switch record.item.placement {
            case .inert, .folderBodyTop, .folderBodyBottom, .boundary,
                    .regularRunStart, .regularRunEnd:
                continue

            case .pinnedRow(
                let itemID,
                let topLevelIndex,
                let splitPairingMemberIDs
            ):
                topLevelTargets[itemID] = SidebarTopLevelPinnedItemMetrics(
                    itemId: itemID,
                    spaceId: spaceID,
                    topLevelIndex: topLevelIndex,
                    frame: rowFrame(
                        rootFrame: rootFrame,
                        minY: record.minY,
                        extent: record.item.extent,
                        nestingDepth: 0
                    ),
                    splitPairingMemberIDs: splitPairingMemberIDs
                )

            case .folderChild(
                let folderID,
                let childID,
                let index,
                let nestingDepth,
                let splitPairingMemberIDs
            ):
                folderChildTargets[childID] =
                    SidebarFolderChildDropTargetMetrics(
                        childId: childID,
                        spaceId: spaceID,
                        folderId: folderID,
                        index: index,
                        frame: rowFrame(
                            rootFrame: rootFrame,
                            minY: record.minY,
                            extent: record.item.extent,
                            nestingDepth: nestingDepth
                        ),
                        splitPairingMemberIDs: splitPairingMemberIDs
                    )

            case .folderHeader(
                let folderID,
                let parentFolderID,
                let containerIndex,
                let childCount,
                let nestingDepth,
                let isOpen,
                let acceptsDrop,
                let afterRegionHeight
            ):
                let headerFrame = rowFrame(
                    rootFrame: rootFrame,
                    minY: record.minY,
                    extent: record.item.extent,
                    nestingDepth: nestingDepth
                )
                let compositeMaxY = bodyBottomYByFolder[folderID]
                    ?? headerFrame.maxY
                let compositeFrame = CGRect(
                    x: headerFrame.minX,
                    y: headerFrame.minY,
                    width: headerFrame.width,
                    height: max(compositeMaxY - headerFrame.minY, 0)
                )

                if let parentFolderID {
                    folderChildTargets[folderID] =
                        SidebarFolderChildDropTargetMetrics(
                            childId: folderID,
                            spaceId: spaceID,
                            folderId: parentFolderID,
                            index: containerIndex,
                            frame: compositeFrame
                        )
                } else {
                    topLevelTargets[folderID] =
                        SidebarTopLevelPinnedItemMetrics(
                            itemId: folderID,
                            spaceId: spaceID,
                            topLevelIndex: containerIndex,
                            frame: compositeFrame
                        )
                }

                guard acceptsDrop else { continue }
                let bodyFrame = bodyTopYByFolder[folderID].map { bodyMinY in
                    CGRect(
                        x: headerFrame.minX,
                        y: bodyMinY,
                        width: headerFrame.width,
                        height: max(compositeMaxY - bodyMinY, 0)
                    )
                }
                let afterFrame = afterRegionHeight > 0
                    ? CGRect(
                        x: headerFrame.minX,
                        y: compositeFrame.maxY - afterRegionHeight / 2,
                        width: headerFrame.width,
                        height: afterRegionHeight
                    )
                    : nil
                folderTargets[folderID] = SidebarFolderDropTargetMetrics(
                    folderId: folderID,
                    spaceId: spaceID,
                    parentFolderId: parentFolderID,
                    topLevelIndex: containerIndex,
                    childCount: childCount,
                    isOpen: isOpen,
                    headerFrame: headerFrame,
                    bodyFrame: bodyFrame,
                    afterFrame: afterFrame
                )

            case .regularRow(let identity, let splitPairingMemberIDs):
                regularIdentities.append(identity)
                regularMembers.append(splitPairingMemberIDs)
                regularFrames.append(
                    rowFrame(
                        rootFrame: rootFrame,
                        minY: record.minY,
                        extent: record.item.extent,
                        nestingDepth: 0
                    )
                )
            }
        }

        let regularFrame = CGRect(
            x: rootFrame.minX,
            y: regularStartY,
            width: rootFrame.width,
            height: max(regularEndY - regularStartY, 0)
        )
        let usesUniformRegularGeometry = regularFrames.enumerated().allSatisfy {
            index, frame in
            abs(frame.height - SidebarRowLayout.rowHeight) < 0.001
                && (
                    index == 0
                    || abs(
                        frame.minY
                            - regularFrames[index - 1].minY
                            - SidebarRowLayout.rowPitch
                    ) < 0.001
                )
        }
        let regularTarget = SidebarRegularListHitMetrics(
            frame: regularFrame,
            rowIdentities: regularIdentities,
            splitPairingMemberIDsByRow: regularMembers,
            presentedRowFrames:
                usesUniformRegularGeometry ? nil : regularFrames
        )

        return Self(
            spaceID: spaceID,
            sectionFrames: [
                .spacePinned: CGRect(
                    x: rootFrame.minX,
                    y: rootFrame.minY,
                    width: rootFrame.width,
                    height: max(boundaryMinY - rootFrame.minY, 0)
                ),
                .spaceRegular: CGRect(
                    x: rootFrame.minX,
                    y: boundaryMinY,
                    width: rootFrame.width,
                    height: max(trackMaxY - boundaryMinY, 0)
                ),
            ],
            topLevelPinnedItemTargets: topLevelTargets,
            folderDropTargets: folderTargets,
            folderChildDropTargets: folderChildTargets,
            pinnedListHitTarget: uniformPinnedTarget(
                records: records,
                topLevelTargets: topLevelTargets
            ),
            regularListHitTarget: regularTarget
        )
    }

    func offsettingY(by deltaY: CGFloat) -> Self {
        guard deltaY != 0 else { return self }
        return Self(
            spaceID: spaceID,
            sectionFrames: sectionFrames.mapValues {
                $0.offsettingY(by: deltaY)
            },
            topLevelPinnedItemTargets: topLevelPinnedItemTargets.mapValues {
                var metrics = $0
                metrics.frame = metrics.frame.offsettingY(by: deltaY)
                return metrics
            },
            folderDropTargets: folderDropTargets.mapValues {
                var metrics = $0
                metrics.headerFrame = metrics.headerFrame?.offsettingY(
                    by: deltaY
                )
                metrics.bodyFrame = metrics.bodyFrame?.offsettingY(by: deltaY)
                metrics.afterFrame = metrics.afterFrame?.offsettingY(by: deltaY)
                return metrics
            },
            folderChildDropTargets: folderChildDropTargets.mapValues {
                var metrics = $0
                metrics.frame = metrics.frame.offsettingY(by: deltaY)
                return metrics
            },
            pinnedListHitTarget: pinnedListHitTarget.map {
                var metrics = $0
                metrics.frame = metrics.frame.offsettingY(by: deltaY)
                return metrics
            },
            regularListHitTarget: regularListHitTarget.offsettingY(by: deltaY)
        )
    }

    private struct Record {
        let item: Item
        let minY: CGFloat

        var maxY: CGFloat { minY + item.extent }
    }

    private static func presentedRecords(_ items: [Item]) -> [Record] {
        var y: CGFloat = 0
        return items.map { item in
            let normalized = Item(
                extent: max(item.extent, 0),
                phase: item.phase,
                placement: item.placement
            )
            defer { y += normalized.extent }
            return Record(item: normalized, minY: y)
        }
    }

    private static func rowFrame(
        rootFrame: CGRect,
        minY: CGFloat,
        extent: CGFloat,
        nestingDepth: Int
    ) -> CGRect {
        let inset = CGFloat(max(nestingDepth, 0)) * 14
        return CGRect(
            x: rootFrame.minX + inset,
            y: rootFrame.minY + minY,
            width: max(rootFrame.width - inset, 0),
            height: min(max(extent, 0), SidebarRowLayout.rowHeight)
        )
    }

    private static func uniformPinnedTarget(
        records: [Record],
        topLevelTargets: [UUID: SidebarTopLevelPinnedItemMetrics]
    ) -> SidebarPinnedListHitMetrics? {
        let rows = topLevelTargets.values.sorted {
            $0.topLevelIndex < $1.topLevelIndex
        }
        guard !rows.isEmpty,
              rows.enumerated().allSatisfy({ index, row in
                  row.topLevelIndex == index
                      && abs(row.frame.height - SidebarRowLayout.rowHeight)
                          < 0.001
                      && (
                          index == 0
                          || abs(
                              row.frame.minY
                                  - rows[index - 1].frame.minY
                                  - SidebarRowLayout.rowPitch
                          ) < 0.001
                      )
              }),
              !records.contains(where: {
                  if case .folderHeader = $0.item.placement { return true }
                  return false
              }),
              let first = rows.first,
              let last = rows.last else {
            return nil
        }

        return SidebarPinnedListHitMetrics(
            frame: CGRect(
                x: first.frame.minX,
                y: first.frame.minY,
                width: first.frame.width,
                height: last.frame.maxY - first.frame.minY
            ),
            rowCount: rows.count,
            splitPairingMemberIDsByRow: rows.map(
                \.splitPairingMemberIDs
            ),
            leadingInset: 0
        )
    }
}

private extension CGRect {
    func offsettingY(by deltaY: CGFloat) -> CGRect {
        offsetBy(dx: 0, dy: deltaY)
    }
}

private extension SidebarRegularListHitMetrics {
    func offsettingY(by deltaY: CGFloat) -> Self {
        let frames = (0..<rowCount).compactMap {
            rowFrame(at: $0)?.offsettingY(by: deltaY)
        }
        let originalWasUniform = frames.enumerated().allSatisfy {
            index, frame in
            abs(frame.height - SidebarRowLayout.rowHeight) < 0.001
                && (
                    index == 0
                    || abs(
                        frame.minY
                            - frames[index - 1].minY
                            - SidebarRowLayout.rowPitch
                    ) < 0.001
                )
        }
        return Self(
            frame: frame.offsettingY(by: deltaY),
            rowIdentities: rowIdentities,
            splitPairingMemberIDsByRow: splitPairingMemberIDsByRow,
            presentedRowFrames: originalWasUniform ? nil : frames
        )
    }
}
