import CoreGraphics
import Foundation
import SumiDomain

struct SidebarTopLevelPinnedItemMetrics: Equatable {
    let itemId: UUID
    var spaceId: UUID
    var topLevelIndex: Int
    var frame: CGRect
    var splitPairingMemberIDs: [SplitMemberID] = []
}

struct SidebarFolderDropTargetMetrics: Equatable {
    let folderId: UUID
    var spaceId: UUID
    var parentFolderId: UUID?
    var topLevelIndex: Int
    var childCount: Int
    var isOpen: Bool
    var headerFrame: CGRect?
    var bodyFrame: CGRect?
    var afterFrame: CGRect?
}

struct SidebarFolderChildDropTargetMetrics: Equatable {
    let childId: UUID
    var spaceId: UUID
    var folderId: UUID
    var index: Int
    var frame: CGRect
    var splitPairingMemberIDs: [SplitMemberID] = []
}

private enum SidebarUniformRowDropGeometry {
    static func contentHeight(rowCount: Int) -> CGFloat {
        CGFloat(max(rowCount, 0)) * SidebarRowLayout.rowHeight
            + CGFloat(max(rowCount - 1, 0)) * SidebarRowLayout.rowGap
    }

    static func boundaryIndex(localY: CGFloat, rowCount: Int) -> Int {
        guard rowCount > 0 else { return 0 }
        let rowIndex = Int(
            (localY / SidebarRowLayout.rowPitch).rounded(.down)
        )
        let offsetInPitch = localY
            - CGFloat(rowIndex) * SidebarRowLayout.rowPitch
        let rawIndex = offsetInPitch < SidebarRowLayout.rowHeight / 2
            ? rowIndex
            : rowIndex + 1
        return max(0, min(rawIndex, rowCount))
    }

    static func boundaryY(
        minY: CGFloat,
        maxY: CGFloat,
        slot: Int,
        rowCount: Int
    ) -> CGFloat {
        let safeSlot = max(0, min(slot, rowCount))
        if safeSlot == 0 { return minY }
        if safeSlot == rowCount { return maxY }
        return minY
            + CGFloat(safeSlot) * SidebarRowLayout.rowPitch
            - SidebarRowLayout.rowGap / 2
    }
}

struct SidebarRegularListHitMetrics: Equatable {
    let frame: CGRect
    let rowIdentities: [SidebarVisualSceneProjection.RegularRow.Identity]
    let splitPairingMemberIDsByRow: [[SplitMemberID]]
    /// Present only while the rendered track is not uniform (for example,
    /// during insertion, removal, or an interrupted transition). The stable
    /// common path keeps using fixed-pitch arithmetic without a frame array.
    private let presentedRowFrames: [CGRect]?

    /// Number of rendered rows. A split group is one row regardless of its
    /// member count.
    var rowCount: Int { rowIdentities.count }

    init(
        frame: CGRect,
        rowIdentities: [SidebarVisualSceneProjection.RegularRow.Identity],
        splitPairingMemberIDsByRow: [[SplitMemberID]] = [],
        presentedRowFrames: [CGRect]? = nil
    ) {
        precondition(
            presentedRowFrames == nil
                || presentedRowFrames?.count == rowIdentities.count
        )
        self.frame = frame
        self.rowIdentities = rowIdentities
        self.splitPairingMemberIDsByRow = splitPairingMemberIDsByRow
        self.presentedRowFrames = presentedRowFrames
    }

    /// Nearest visual row boundary for a Y offset inside the list frame.
    func rowBoundaryIndex(forLocalY localY: CGFloat) -> Int {
        if let presentedRowFrames {
            let globalY = frame.minY + localY
            for (index, rowFrame) in presentedRowFrames.enumerated() {
                if globalY < rowFrame.midY {
                    return index
                }
                if globalY <= rowFrame.maxY {
                    return index + 1
                }
            }
            return rowCount
        }
        return SidebarUniformRowDropGeometry.boundaryIndex(
            localY: localY,
            rowCount: rowCount
        )
    }

    func boundaryY(for slot: Int) -> CGFloat {
        if let presentedRowFrames,
           let first = presentedRowFrames.first,
           let last = presentedRowFrames.last {
            let safeSlot = max(0, min(slot, presentedRowFrames.count))
            if safeSlot == 0 { return first.minY }
            if safeSlot == presentedRowFrames.count { return last.maxY }
            return (
                presentedRowFrames[safeSlot - 1].maxY
                    + presentedRowFrames[safeSlot].minY
            ) / 2
        }
        return SidebarUniformRowDropGeometry.boundaryY(
            minY: frame.minY,
            maxY: frame.maxY,
            slot: slot,
            rowCount: rowCount
        )
    }

    func presentedBoundary(
        at index: Int
    ) -> SidebarVisualSceneProjection.RegularBoundary? {
        let safeIndex = max(0, min(index, rowCount))
        return SidebarVisualSceneProjection.RegularBoundary(
            before: safeIndex > 0 ? rowIdentities[safeIndex - 1] : nil,
            after: safeIndex < rowCount ? rowIdentities[safeIndex] : nil
        )
    }

    func rowFrame(at index: Int) -> CGRect? {
        guard rowIdentities.indices.contains(index) else { return nil }
        if let presentedRowFrames {
            return presentedRowFrames[index]
        }
        return CGRect(
            x: frame.minX,
            y: frame.minY + CGFloat(index) * SidebarRowLayout.rowPitch,
            width: frame.width,
            height: SidebarRowLayout.rowHeight
        )
    }

    func rowIndex(containing location: CGPoint) -> Int? {
        guard frame.contains(location) else { return nil }
        if let presentedRowFrames {
            return presentedRowFrames.firstIndex {
                $0.contains(location)
            }
        }
        let index = Int(
            ((location.y - frame.minY) / SidebarRowLayout.rowPitch)
                .rounded(.down)
        )
        guard let rowFrame = rowFrame(at: index),
              rowFrame.contains(location) else {
            return nil
        }
        return index
    }

    func splitPairingCandidate(
        at index: Int
    ) -> SidebarSplitPairingCandidate? {
        guard let frame = rowFrame(at: index),
              splitPairingMemberIDsByRow.indices.contains(index) else {
            return nil
        }
        return SidebarSplitPairingCandidate(
            frame: frame,
            memberIDs: splitPairingMemberIDsByRow[index]
        )
    }
}

/// Compact geometry for the common Pinned layout where every top-level item
/// is one fixed-height row and no folder expands the stack.
struct SidebarPinnedListHitMetrics: Equatable {
    var frame: CGRect
    let rowCount: Int
    let splitPairingMemberIDsByRow: [[SplitMemberID]]
    var leadingInset: CGFloat

    var rowsFrame: CGRect {
        CGRect(
            x: frame.minX,
            y: frame.minY + leadingInset,
            width: frame.width,
            height: SidebarUniformRowDropGeometry.contentHeight(
                rowCount: rowCount
            )
        )
    }

    func rowBoundaryIndex(forGlobalY globalY: CGFloat) -> Int {
        SidebarUniformRowDropGeometry.boundaryIndex(
            localY: globalY - rowsFrame.minY,
            rowCount: rowCount
        )
    }

    func boundaryY(for slot: Int) -> CGFloat {
        SidebarUniformRowDropGeometry.boundaryY(
            minY: rowsFrame.minY,
            maxY: rowsFrame.maxY,
            slot: slot,
            rowCount: rowCount
        )
    }

    func rowIndex(containing location: CGPoint) -> Int? {
        guard rowsFrame.contains(location) else { return nil }
        let index = Int(
            ((location.y - rowsFrame.minY) / SidebarRowLayout.rowPitch)
                .rounded(.down)
        )
        guard let rowFrame = rowFrame(at: index) else { return nil }
        return rowFrame.contains(location) ? index : nil
    }

    func rowFrame(at index: Int) -> CGRect? {
        guard (0..<rowCount).contains(index) else { return nil }
        return CGRect(
            x: rowsFrame.minX,
            y: rowsFrame.minY + CGFloat(index) * SidebarRowLayout.rowPitch,
            width: rowsFrame.width,
            height: SidebarRowLayout.rowHeight
        )
    }

    func splitPairingCandidate(
        at index: Int
    ) -> SidebarSplitPairingCandidate? {
        guard let frame = rowFrame(at: index),
              splitPairingMemberIDsByRow.indices.contains(index) else {
            return nil
        }
        return SidebarSplitPairingCandidate(
            frame: frame,
            memberIDs: splitPairingMemberIDsByRow[index]
        )
    }
}

struct SidebarSectionGeometryKey: Hashable {
    let spaceId: UUID
    let section: SidebarSectionPrefix

    static func == (lhs: SidebarSectionGeometryKey, rhs: SidebarSectionGeometryKey) -> Bool {
        lhs.spaceId == rhs.spaceId && lhs.section == rhs.section
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(spaceId)
        hasher.combine(section)
    }
}

enum SidebarPageGeometryRenderMode: Hashable {
    case interactive
    case transitionSnapshot
}

struct SidebarPageGeometryKey: Hashable {
    let spaceId: UUID
    let profileId: UUID?

    static func == (lhs: SidebarPageGeometryKey, rhs: SidebarPageGeometryKey) -> Bool {
        lhs.spaceId == rhs.spaceId && lhs.profileId == rhs.profileId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(spaceId)
        hasher.combine(profileId)
    }
}

struct SidebarPageGeometryMetrics: Equatable {
    let spaceId: UUID
    let profileId: UUID?
    var frame: CGRect
    var renderMode: SidebarPageGeometryRenderMode
}

struct SidebarEssentialsLayoutMetrics: Equatable {
    let profileId: UUID?
    let frame: CGRect
    let dropFrame: CGRect
    let dropSlotFrames: [SidebarEssentialsDropSlotMetrics]
    let firstSyntheticRowSlot: Int
    let visibleItemCount: Int
    let visibleRowCount: Int
    let maxDropRowCount: Int
    let itemSize: CGSize
    let canAcceptDrop: Bool

    /// Pre-resolved by `SidebarEssentialsDropHitPolicy` when the metrics are
    /// built, so `containsDropLocation` stays a single rect test on every
    /// `draggingUpdated`.
    let dropHitFrame: CGRect

    func containsDropLocation(_ location: CGPoint) -> Bool {
        dropHitFrame.contains(location)
    }
}

struct SidebarEssentialsLayoutMetricsInput: Equatable {
    var profileId: UUID?
    var frame: CGRect
    var dropFrame: CGRect
    var dropSlotFrames: [SidebarEssentialsDropSlotMetrics] = []
    var itemCount: Int
    var columnCount: Int
    var firstSyntheticRowSlot: Int?
    var rowCount: Int
    var itemSize: CGSize
    var gridSpacing: CGFloat
    var canAcceptDrop: Bool
    var visibleItemCount: Int?
    var visibleRowCount: Int?
    var maxDropRowCount: Int?
}

struct SidebarEssentialsLayoutUpdate: Equatable {
    let spaceId: UUID
    var input: SidebarEssentialsLayoutMetricsInput?

    init(spaceId: UUID, input: SidebarEssentialsLayoutMetricsInput) {
        self.spaceId = spaceId
        self.input = input
    }

    init(spaceId: UUID) {
        self.spaceId = spaceId
        input = nil
    }
}

struct SidebarEssentialsDropSlotMetrics: Equatable {
    var slot: Int
    var frame: CGRect
}

struct SidebarEssentialsPreviewState: Equatable {
    var expandedDropRowCount: Int
    var gapSlot: Int?
}

struct SidebarGeometryHitTestIndex: Equatable {
    var topLevelPinnedItemsBySpace: [UUID: [SidebarTopLevelPinnedItemMetrics]]
    var folderTargetsBySpace: [UUID: [SidebarFolderDropTargetMetrics]]
    var folderChildrenByFolder: [UUID: [SidebarFolderChildDropTargetMetrics]]

    static let empty = SidebarGeometryHitTestIndex(
        topLevelPinnedItemsBySpace: [:],
        folderTargetsBySpace: [:],
        folderChildrenByFolder: [:]
    )

    init(
        topLevelPinnedItemTargets: [UUID: SidebarTopLevelPinnedItemMetrics],
        folderDropTargets: [UUID: SidebarFolderDropTargetMetrics],
        folderChildDropTargets: [UUID: SidebarFolderChildDropTargetMetrics]
    ) {
        topLevelPinnedItemsBySpace = Dictionary(
            grouping: topLevelPinnedItemTargets.values,
            by: \.spaceId
        ).mapValues { items in
            items.sorted {
                if $0.topLevelIndex != $1.topLevelIndex {
                    return $0.topLevelIndex < $1.topLevelIndex
                }
                return $0.itemId.uuidString < $1.itemId.uuidString
            }
        }
        folderTargetsBySpace = Dictionary(
            grouping: folderDropTargets.values,
            by: \.spaceId
        )
        folderChildrenByFolder = Dictionary(
            grouping: folderChildDropTargets.values,
            by: \.folderId
        ).mapValues { children in
            children.sorted {
                if $0.index != $1.index { return $0.index < $1.index }
                return $0.childId.uuidString < $1.childId.uuidString
            }
        }
    }

    init(spaceListLayoutsBySpace: [UUID: PresentedSidebarLayout]) {
        topLevelPinnedItemsBySpace = spaceListLayoutsBySpace.mapValues {
            $0.topLevelPinnedItemTargets.values.sorted {
                if $0.topLevelIndex != $1.topLevelIndex {
                    return $0.topLevelIndex < $1.topLevelIndex
                }
                return $0.itemId.uuidString < $1.itemId.uuidString
            }
        }
        folderTargetsBySpace = spaceListLayoutsBySpace.mapValues {
            Array($0.folderDropTargets.values)
        }
        folderChildrenByFolder = [:]
        for layout in spaceListLayoutsBySpace.values {
            for child in layout.folderChildDropTargets.values {
                folderChildrenByFolder[child.folderId, default: []]
                    .append(child)
            }
        }
        for folderID in Array(folderChildrenByFolder.keys) {
            folderChildrenByFolder[folderID]?.sort {
                if $0.index != $1.index { return $0.index < $1.index }
                return $0.childId.uuidString < $1.childId.uuidString
            }
        }
    }

    private init(
        topLevelPinnedItemsBySpace: [UUID: [SidebarTopLevelPinnedItemMetrics]],
        folderTargetsBySpace: [UUID: [SidebarFolderDropTargetMetrics]],
        folderChildrenByFolder: [UUID: [SidebarFolderChildDropTargetMetrics]]
    ) {
        self.topLevelPinnedItemsBySpace = topLevelPinnedItemsBySpace
        self.folderTargetsBySpace = folderTargetsBySpace
        self.folderChildrenByFolder = folderChildrenByFolder
    }
}

struct SidebarRuntimeGeometryStore {
    var cumulativeScrollDeltaY: CGFloat = 0
    var structuralRevision: UInt64 = 0
    var scrollRevision: UInt64 = 0
    var pageGeometryByKey: [SidebarPageGeometryKey: SidebarPageGeometryMetrics] = [:]
    var spaceListLayoutsBySpace: [UUID: PresentedSidebarLayout] = [:]
    var sectionFramesBySpace: [SidebarSectionGeometryKey: CGRect] = [:]
    var essentialsLayoutMetricsBySpace: [UUID: SidebarEssentialsLayoutMetrics] = [:]
    var hitTestIndex: SidebarGeometryHitTestIndex = .empty
}

enum SidebarDragGeometryMutationKey: Hashable {
    case presentedSpaceList(spaceID: UUID, generation: Int)
    case page(SidebarPageGeometryKey, generation: Int)
    case essentials(spaceID: UUID, generation: Int)
}

private struct SidebarDragGeometryMutation {
    let apply: @MainActor (SidebarDragGeometryRepository) -> Void
}

@MainActor
final class SidebarDragGeometryMutationBuffer {
    private var mutations: [SidebarDragGeometryMutationKey: SidebarDragGeometryMutation] = [:]

    func enqueue(
        key: SidebarDragGeometryMutationKey,
        apply: @escaping @MainActor (SidebarDragGeometryRepository) -> Void
    ) {
        mutations[key] = SidebarDragGeometryMutation(apply: apply)
    }

    func flush(into repository: SidebarDragGeometryRepository) {
        guard !mutations.isEmpty else { return }

        let pendingMutations = Array(mutations.values)
        mutations = [:]

        for mutation in pendingMutations {
            mutation.apply(repository)
        }
    }
}

struct SidebarGeometrySnapshot: Equatable {
    var cumulativeScrollDeltaY: CGFloat = 0
    var structuralRevision: UInt64 = 0
    var scrollRevision: UInt64 = 0
    var pageGeometryByKey: [SidebarPageGeometryKey: SidebarPageGeometryMetrics] = [:]
    var sectionFramesBySpace: [SidebarSectionGeometryKey: CGRect] = [:]
    var folderDropTargets: [UUID: SidebarFolderDropTargetMetrics] = [:]
    var pinnedListHitTargets: [UUID: SidebarPinnedListHitMetrics] = [:]
    var regularListHitTargets: [UUID: SidebarRegularListHitMetrics] = [:]
    var essentialsLayoutMetricsBySpace: [UUID: SidebarEssentialsLayoutMetrics] = [:]
    var hitTestIndex: SidebarGeometryHitTestIndex = .empty

    static let empty = SidebarGeometrySnapshot()
}

enum SidebarSectionPrefix: Hashable {
    case essentials
    case spacePinned
    case spaceRegular
}

@MainActor
extension SidebarDragState {
    func baseGeometryLocation(from visibleLocation: CGPoint) -> CGPoint {
        CGPoint(
            x: visibleLocation.x,
            y: visibleLocation.y + geometry.geometrySnapshot.cumulativeScrollDeltaY
        )
    }

    var sectionFramesBySpace: [SidebarSectionGeometryKey: CGRect] {
        geometry.geometrySnapshot.sectionFramesBySpace
    }

    var pageGeometryByKey: [SidebarPageGeometryKey: SidebarPageGeometryMetrics] {
        geometry.geometrySnapshot.pageGeometryByKey
    }

    var folderDropTargets: [UUID: SidebarFolderDropTargetMetrics] {
        geometry.geometrySnapshot.folderDropTargets
    }

    var regularListHitTargets: [UUID: SidebarRegularListHitMetrics] {
        geometry.geometrySnapshot.regularListHitTargets
    }

    var pinnedListHitTargets: [UUID: SidebarPinnedListHitMetrics] {
        geometry.geometrySnapshot.pinnedListHitTargets
    }

    var essentialsLayoutMetricsBySpace: [UUID: SidebarEssentialsLayoutMetrics] {
        geometry.geometrySnapshot.essentialsLayoutMetricsBySpace
    }

    var topLevelPinnedItemsBySpace: [UUID: [SidebarTopLevelPinnedItemMetrics]] {
        geometry.geometrySnapshot.hitTestIndex.topLevelPinnedItemsBySpace
    }

    var folderTargetsBySpace: [UUID: [SidebarFolderDropTargetMetrics]] {
        geometry.geometrySnapshot.hitTestIndex.folderTargetsBySpace
    }

    var folderChildrenByFolder: [UUID: [SidebarFolderChildDropTargetMetrics]] {
        geometry.geometrySnapshot.hitTestIndex.folderChildrenByFolder
    }

    func sectionFrame(
        for section: SidebarSectionPrefix,
        in spaceId: UUID
    ) -> CGRect? {
        sectionFramesBySpace[SidebarSectionGeometryKey(spaceId: spaceId, section: section)]
    }

    func hoveredInteractivePage(
        at location: CGPoint,
        matching scope: SidebarDragScope? = nil
    ) -> SidebarPageGeometryMetrics? {
        let location = baseGeometryLocation(from: location)
        return pageGeometryByKey.values
            .filter { metrics in
                guard metrics.renderMode == .interactive,
                      metrics.frame.contains(location) else {
                    return false
                }
                guard let scope else {
                    return true
                }
                return metrics.spaceId == scope.spaceId
                    && scope.matches(profileId: metrics.profileId)
            }
            .sorted { lhs, rhs in
                let leftArea = lhs.frame.width * lhs.frame.height
                let rightArea = rhs.frame.width * rhs.frame.height
                if leftArea != rightArea { return leftArea < rightArea }
                return lhs.spaceId.uuidString < rhs.spaceId.uuidString
            }
            .first
    }
}
