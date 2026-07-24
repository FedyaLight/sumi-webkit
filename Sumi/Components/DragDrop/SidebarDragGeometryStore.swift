import CoreGraphics
import Foundation

enum SidebarFolderDragRegion: Hashable {
    case header
    case body
    case after
}

struct SidebarTopLevelPinnedItemMetrics: Equatable {
    let itemId: UUID
    var spaceId: UUID
    var topLevelIndex: Int
    var frame: CGRect
}

struct SidebarTopLevelPinnedItemTargetUpdate: Equatable {
    let itemId: UUID
    var metrics: SidebarTopLevelPinnedItemMetrics?

    init(metrics: SidebarTopLevelPinnedItemMetrics) {
        itemId = metrics.itemId
        self.metrics = metrics
    }

    init(itemId: UUID) {
        self.itemId = itemId
        metrics = nil
    }
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

struct SidebarFolderDropTargetUpdate: Equatable {
    let folderId: UUID
    var region: SidebarFolderDragRegion
    var metrics: SidebarFolderDropTargetMetrics?
    var frame: CGRect?

    init(
        metrics: SidebarFolderDropTargetMetrics,
        region: SidebarFolderDragRegion,
        frame: CGRect
    ) {
        folderId = metrics.folderId
        self.region = region
        self.metrics = metrics
        self.frame = frame
    }

    init(folderId: UUID, region: SidebarFolderDragRegion) {
        self.folderId = folderId
        self.region = region
        metrics = nil
        frame = nil
    }
}

struct SidebarFolderChildDropTargetMetrics: Equatable {
    let childId: UUID
    var folderId: UUID
    var index: Int
    var frame: CGRect
}

struct SidebarFolderChildDropTargetUpdate: Equatable {
    let childId: UUID
    var metrics: SidebarFolderChildDropTargetMetrics?

    init(metrics: SidebarFolderChildDropTargetMetrics) {
        childId = metrics.childId
        self.metrics = metrics
    }

    init(childId: UUID) {
        self.childId = childId
        metrics = nil
    }
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

    /// Number of rendered rows. A split group is one row regardless of its
    /// member count.
    var rowCount: Int { rowIdentities.count }

    init(
        frame: CGRect,
        rowIdentities: [SidebarVisualSceneProjection.RegularRow.Identity]
    ) {
        self.frame = frame
        self.rowIdentities = rowIdentities
    }

    /// Nearest visual row boundary for a Y offset inside the list frame.
    func rowBoundaryIndex(forLocalY localY: CGFloat) -> Int {
        SidebarUniformRowDropGeometry.boundaryIndex(
            localY: localY,
            rowCount: rowCount
        )
    }

    func boundaryY(for slot: Int) -> CGFloat {
        SidebarUniformRowDropGeometry.boundaryY(
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
}

/// Compact geometry for the common Pinned layout where every top-level item
/// is one fixed-height row and no folder expands the stack.
struct SidebarPinnedListHitMetrics: Equatable {
    var frame: CGRect
    var rowCount: Int
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
    var frame: CGRect
    var dropFrame: CGRect
    var dropSlotFrames: [SidebarEssentialsDropSlotMetrics]
    var firstSyntheticRowSlot: Int
    var visibleItemCount: Int
    var visibleRowCount: Int
    var maxDropRowCount: Int
    var itemSize: CGSize
    var canAcceptDrop: Bool

    var dropHitFrame: CGRect {
        guard visibleItemCount == 0, canAcceptDrop else {
            return dropFrame
        }

        let minimumEmptyFrame = CGRect(
            x: dropFrame.minX,
            y: dropFrame.minY,
            width: max(dropFrame.width, frame.width, itemSize.width),
            height: max(dropFrame.height, itemSize.height)
        )
        return dropSlotFrames.reduce(dropFrame.union(minimumEmptyFrame)) { partial, slot in
            partial.union(slot.frame)
        }
    }

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
    var sectionFramesBySpace: [SidebarSectionGeometryKey: CGRect] = [:]
    var topLevelPinnedItemTargets: [UUID: SidebarTopLevelPinnedItemMetrics] = [:]
    var folderDropTargets: [UUID: SidebarFolderDropTargetMetrics] = [:]
    var folderChildDropTargets: [UUID: SidebarFolderChildDropTargetMetrics] = [:]
    var pinnedListHitTargets: [UUID: SidebarPinnedListHitMetrics] = [:]
    var regularListHitTargets: [UUID: SidebarRegularListHitMetrics] = [:]
    var essentialsLayoutMetricsBySpace: [UUID: SidebarEssentialsLayoutMetrics] = [:]
    var hitTestIndex: SidebarGeometryHitTestIndex = .empty
}

enum SidebarDragGeometryMutationKey: Hashable {
    case page(SidebarPageGeometryKey)
    case section(SidebarSectionGeometryKey)
    case folder(UUID, SidebarFolderDragRegion)
    case topLevelPinnedItem(UUID)
    case folderChild(UUID)
    case pinnedList(UUID)
    case regularList(UUID)
    case essentials(UUID)
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
