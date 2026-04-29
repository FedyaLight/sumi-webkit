import CoreGraphics
import Foundation

enum SidebarFolderDragRegion: Hashable {
    case header
    case body
    case after
}

enum SidebarTopLevelPinnedItemKind: Equatable {
    case shortcut(UUID)
    case folder(UUID)
}

struct SidebarTopLevelPinnedItemMetrics: Equatable {
    let itemId: UUID
    var kind: SidebarTopLevelPinnedItemKind
    var spaceId: UUID
    var topLevelIndex: Int
    var frame: CGRect
}

struct SidebarFolderDropTargetMetrics: Equatable {
    let folderId: UUID
    var spaceId: UUID
    var topLevelIndex: Int
    var childCount: Int
    var isOpen: Bool
    var headerFrame: CGRect? = nil
    var bodyFrame: CGRect? = nil
    var afterFrame: CGRect? = nil
}

struct SidebarFolderChildDropTargetMetrics: Equatable {
    let childId: UUID
    var folderId: UUID
    var index: Int
    var frame: CGRect
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
    var columnCount: Int
    var firstSyntheticRowSlot: Int
    var visibleItemCount: Int
    var visibleRowCount: Int
    var maxDropRowCount: Int
    var itemSize: CGSize
    var gridSpacing: CGFloat
    var canAcceptDrop: Bool
}

struct SidebarEssentialsDropSlotMetrics: Equatable {
    var slot: Int
    var frame: CGRect
}

struct SidebarEssentialsPreviewState: Equatable {
    var expandedDropRowCount: Int
    var ghostSlot: Int?
}

struct SidebarRuntimeGeometryStore {
    var pageGeometryByKey: [SidebarPageGeometryKey: SidebarPageGeometryMetrics] = [:]
    var sectionFramesBySpace: [SidebarSectionGeometryKey: CGRect] = [:]
    var topLevelPinnedItemTargets: [UUID: SidebarTopLevelPinnedItemMetrics] = [:]
    var folderDropTargets: [UUID: SidebarFolderDropTargetMetrics] = [:]
    var folderChildDropTargets: [UUID: SidebarFolderChildDropTargetMetrics] = [:]
    var regularListHitTargets: [UUID: SidebarRegularListHitMetrics] = [:]
    var essentialsLayoutMetricsBySpace: [UUID: SidebarEssentialsLayoutMetrics] = [:]

    var hasDetailedDragGeometry: Bool {
        !topLevelPinnedItemTargets.isEmpty
            || !folderDropTargets.isEmpty
            || !folderChildDropTargets.isEmpty
            || !regularListHitTargets.isEmpty
            || !essentialsLayoutMetricsBySpace.isEmpty
    }

    mutating func removeDetailedDragGeometry() {
        topLevelPinnedItemTargets = [:]
        folderDropTargets = [:]
        folderChildDropTargets = [:]
        regularListHitTargets = [:]
        essentialsLayoutMetricsBySpace = [:]
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
