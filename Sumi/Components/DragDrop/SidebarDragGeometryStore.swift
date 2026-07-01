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

struct SidebarRegularListHitMetrics: Equatable {
    var frame: CGRect
    var itemCount: Int
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

struct SidebarRuntimeGeometryStore {
    var pageGeometryByKey: [SidebarPageGeometryKey: SidebarPageGeometryMetrics] = [:]
    var sectionFramesBySpace: [SidebarSectionGeometryKey: CGRect] = [:]
    var topLevelPinnedItemTargets: [UUID: SidebarTopLevelPinnedItemMetrics] = [:]
    var folderDropTargets: [UUID: SidebarFolderDropTargetMetrics] = [:]
    var folderChildDropTargets: [UUID: SidebarFolderChildDropTargetMetrics] = [:]
    var regularListHitTargets: [UUID: SidebarRegularListHitMetrics] = [:]
    var essentialsLayoutMetricsBySpace: [UUID: SidebarEssentialsLayoutMetrics] = [:]
}

enum SidebarDragGeometryMutationKey: Hashable {
    case page(SidebarPageGeometryKey)
    case section(SidebarSectionGeometryKey)
    case folder(UUID, SidebarFolderDragRegion)
    case topLevelPinnedItem(UUID)
    case folderChild(UUID)
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
    var pageGeometryByKey: [SidebarPageGeometryKey: SidebarPageGeometryMetrics] = [:]
    var sectionFramesBySpace: [SidebarSectionGeometryKey: CGRect] = [:]
    var topLevelPinnedItemTargets: [UUID: SidebarTopLevelPinnedItemMetrics] = [:]
    var folderDropTargets: [UUID: SidebarFolderDropTargetMetrics] = [:]
    var folderChildDropTargets: [UUID: SidebarFolderChildDropTargetMetrics] = [:]
    var regularListHitTargets: [UUID: SidebarRegularListHitMetrics] = [:]
    var essentialsLayoutMetricsBySpace: [UUID: SidebarEssentialsLayoutMetrics] = [:]

    static let empty = SidebarGeometrySnapshot()
}

enum SidebarSectionPrefix: Hashable {
    case essentials
    case spacePinned
    case spaceRegular
}

@MainActor
extension SidebarDragState {
    var sectionFramesBySpace: [SidebarSectionGeometryKey: CGRect] {
        geometrySnapshot.sectionFramesBySpace
    }

    var pageGeometryByKey: [SidebarPageGeometryKey: SidebarPageGeometryMetrics] {
        geometrySnapshot.pageGeometryByKey
    }

    var folderDropTargets: [UUID: SidebarFolderDropTargetMetrics] {
        geometrySnapshot.folderDropTargets
    }

    var topLevelPinnedItemTargets: [UUID: SidebarTopLevelPinnedItemMetrics] {
        geometrySnapshot.topLevelPinnedItemTargets
    }

    var folderChildDropTargets: [UUID: SidebarFolderChildDropTargetMetrics] {
        geometrySnapshot.folderChildDropTargets
    }

    var regularListHitTargets: [UUID: SidebarRegularListHitMetrics] {
        geometrySnapshot.regularListHitTargets
    }

    var essentialsLayoutMetricsBySpace: [UUID: SidebarEssentialsLayoutMetrics] {
        geometrySnapshot.essentialsLayoutMetricsBySpace
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
        pageGeometryByKey.values
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
