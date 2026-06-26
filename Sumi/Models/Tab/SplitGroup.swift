import CoreGraphics
import Foundation

private func uniqueSplitTabIdsPreservingOrder(_ tabIds: [UUID]) -> [UUID] {
    var seen = Set<UUID>()
    var result: [UUID] = []
    result.reserveCapacity(tabIds.count)
    for tabId in tabIds where seen.insert(tabId).inserted {
        result.append(tabId)
    }
    return result
}

enum SplitAxis: String, Codable, Hashable, Sendable {
    case row
    case column
}

enum SplitLayoutKind: String, Codable, CaseIterable, Hashable, Sendable {
    case grid
    case vertical
    case horizontal

    var primaryAxis: SplitAxis {
        switch self {
        case .grid, .vertical:
            return .row
        case .horizontal:
            return .column
        }
    }
}

enum SplitDropSide: String, Codable, Hashable, Sendable {
    case left
    case right
    case top
    case bottom
    case center

    var insertionAxis: SplitAxis? {
        switch self {
        case .left, .right:
            return .row
        case .top, .bottom:
            return .column
        case .center:
            return nil
        }
    }
}

enum SplitDropTargetScope: String, Codable, Hashable, Sendable {
    case pane
    case plane
    case group
}

enum SplitDropPreviewStyle: String, Codable, Hashable, Sendable {
    case edge
    case center
}

enum SplitDropTargetIntent: String, Codable, Hashable, Sendable {
    case firstSplit
    case rootEdge
    case planeEdge
    case siblingEdge
    case flatThreePair
    case flatFourPair
    case flatFourReorder
    case mixedThreeOnePair
    case fullGroupPanePair
    case paneCenter
}

enum SplitGroupHost: Codable, Equatable, Hashable, Sendable {
    case regular(spaceId: UUID?)
    case shortcutPinned(spaceId: UUID, profileId: UUID?, index: Int?)

    private enum CodingKeys: String, CodingKey {
        case kind
        case spaceId
        case profileId
        case index
    }

    private enum Kind: String, Codable {
        case regular
        case shortcutPinned
    }

    var isShortcutPinned: Bool {
        if case .shortcutPinned = self { return true }
        return false
    }

    var spaceId: UUID? {
        switch self {
        case .regular(let spaceId):
            return spaceId
        case .shortcutPinned(let spaceId, _, _):
            return spaceId
        }
    }

    var shortcutPinnedIndex: Int? {
        guard case .shortcutPinned(_, _, let index) = self else { return nil }
        return index
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .regular:
            self = .regular(spaceId: try container.decodeIfPresent(UUID.self, forKey: .spaceId))
        case .shortcutPinned:
            self = .shortcutPinned(
                spaceId: try container.decode(UUID.self, forKey: .spaceId),
                profileId: try container.decodeIfPresent(UUID.self, forKey: .profileId),
                index: try container.decodeIfPresent(Int.self, forKey: .index)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .regular(let spaceId):
            try container.encode(Kind.regular, forKey: .kind)
            try container.encodeIfPresent(spaceId, forKey: .spaceId)
        case .shortcutPinned(let spaceId, let profileId, let index):
            try container.encode(Kind.shortcutPinned, forKey: .kind)
            try container.encode(spaceId, forKey: .spaceId)
            try container.encodeIfPresent(profileId, forKey: .profileId)
            try container.encodeIfPresent(index, forKey: .index)
        }
    }

    func settingShortcutPinnedIndex(_ index: Int?) -> SplitGroupHost {
        switch self {
        case .regular:
            return self
        case .shortcutPinned(let spaceId, let profileId, _):
            return .shortcutPinned(spaceId: spaceId, profileId: profileId, index: index)
        }
    }
}

enum SplitGroupMemberOrigin: Codable, Equatable, Hashable, Sendable {
    case regular(spaceId: UUID?, index: Int?)
    case essential(profileId: UUID?, index: Int)
    case spacePinned(spaceId: UUID, folderId: UUID?, index: Int)
    case generatedSpacePinnedFromRegular(spaceId: UUID, index: Int)

    private enum CodingKeys: String, CodingKey {
        case kind
        case spaceId
        case profileId
        case folderId
        case index
    }

    private enum Kind: String, Codable {
        case regular
        case essential
        case spacePinned
        case generatedSpacePinnedFromRegular
    }

    var isShortcutBacked: Bool {
        switch self {
        case .regular:
            return false
        case .essential, .spacePinned, .generatedSpacePinnedFromRegular:
            return true
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .regular:
            self = .regular(
                spaceId: try container.decodeIfPresent(UUID.self, forKey: .spaceId),
                index: try container.decodeIfPresent(Int.self, forKey: .index)
            )
        case .essential:
            self = .essential(
                profileId: try container.decodeIfPresent(UUID.self, forKey: .profileId),
                index: try container.decode(Int.self, forKey: .index)
            )
        case .spacePinned:
            self = .spacePinned(
                spaceId: try container.decode(UUID.self, forKey: .spaceId),
                folderId: try container.decodeIfPresent(UUID.self, forKey: .folderId),
                index: try container.decode(Int.self, forKey: .index)
            )
        case .generatedSpacePinnedFromRegular:
            self = .generatedSpacePinnedFromRegular(
                spaceId: try container.decode(UUID.self, forKey: .spaceId),
                index: try container.decode(Int.self, forKey: .index)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .regular(let spaceId, let index):
            try container.encode(Kind.regular, forKey: .kind)
            try container.encodeIfPresent(spaceId, forKey: .spaceId)
            try container.encodeIfPresent(index, forKey: .index)
        case .essential(let profileId, let index):
            try container.encode(Kind.essential, forKey: .kind)
            try container.encodeIfPresent(profileId, forKey: .profileId)
            try container.encode(index, forKey: .index)
        case .spacePinned(let spaceId, let folderId, let index):
            try container.encode(Kind.spacePinned, forKey: .kind)
            try container.encode(spaceId, forKey: .spaceId)
            try container.encodeIfPresent(folderId, forKey: .folderId)
            try container.encode(index, forKey: .index)
        case .generatedSpacePinnedFromRegular(let spaceId, let index):
            try container.encode(Kind.generatedSpacePinnedFromRegular, forKey: .kind)
            try container.encode(spaceId, forKey: .spaceId)
            try container.encode(index, forKey: .index)
        }
    }
}

struct SplitGroupMember: Codable, Equatable, Hashable, Sendable {
    var tabId: UUID
    var pinId: UUID?
    var origin: SplitGroupMemberOrigin

    var stableId: UUID {
        pinId ?? tabId
    }

    var isShortcutBacked: Bool {
        pinId != nil || origin.isShortcutBacked
    }
}

struct SplitDropTarget: Equatable {
    let tabId: UUID
    let side: SplitDropSide
    let targetRect: CGRect
    let scope: SplitDropTargetScope
    let previewStyle: SplitDropPreviewStyle
    let planePath: [Int]
    let intent: SplitDropTargetIntent
    let resolvedLayoutTree: SplitLayoutTree?

    init(
        tabId: UUID,
        side: SplitDropSide,
        targetRect: CGRect,
        scope: SplitDropTargetScope = .pane,
        previewStyle: SplitDropPreviewStyle = .edge,
        planePath: [Int] = [],
        intent: SplitDropTargetIntent? = nil,
        resolvedLayoutTree: SplitLayoutTree? = nil
    ) {
        self.tabId = tabId
        self.side = side
        self.targetRect = targetRect
        self.scope = scope
        self.previewStyle = previewStyle
        self.planePath = planePath
        self.intent = intent ?? {
            switch (scope, previewStyle) {
            case (_, .center):
                return .paneCenter
            case (.group, _):
                return .rootEdge
            case (.plane, _):
                return .planeEdge
            case (.pane, _):
                return .planeEdge
            }
        }()
        self.resolvedLayoutTree = resolvedLayoutTree
    }

    func resolving(
        targetRect: CGRect,
        resolvedLayoutTree: SplitLayoutTree
    ) -> SplitDropTarget {
        SplitDropTarget(
            tabId: tabId,
            side: side,
            targetRect: targetRect,
            scope: scope,
            previewStyle: previewStyle,
            planePath: planePath,
            intent: intent,
            resolvedLayoutTree: resolvedLayoutTree
        )
    }
}

struct SplitLayoutLeafHit: Equatable {
    let tabId: UUID
    let rect: CGRect
    let path: [Int]
}

struct SplitTilePlaneHit: Equatable {
    let path: [Int]
    let rect: CGRect
    let tabIds: [UUID]
}

struct SplitResolvedDrop: Equatable {
    let target: SplitDropTarget
    let layoutTree: SplitLayoutTree
}

indirect enum SplitLayoutTree: Codable, Equatable, Hashable, Sendable {
    case leaf(tabId: UUID, size: Double)
    case split(axis: SplitAxis, size: Double, children: [SplitLayoutTree])

    var sizeInParent: Double {
        switch self {
        case .leaf(_, let size), .split(_, let size, _):
            return size
        }
    }

    var tabIds: [UUID] {
        switch self {
        case .leaf(let tabId, _):
            return [tabId]
        case .split(_, _, let children):
            return children.flatMap(\.tabIds)
        }
    }

    var leafCount: Int {
        switch self {
        case .leaf:
            return 1
        case .split(_, _, let children):
            return children.reduce(0) { $0 + $1.leafCount }
        }
    }

    var isFlatFourLeafLine: Bool {
        guard case .split(_, _, let children) = self,
              children.count == SplitGroup.maximumTabs
        else {
            return false
        }
        return children.allSatisfy(\.isLeaf)
    }

    func contains(_ tabId: UUID) -> Bool {
        switch self {
        case .leaf(let id, _):
            return id == tabId
        case .split(_, _, let children):
            return children.contains { $0.contains(tabId) }
        }
    }

    func hasSameStructure(as other: SplitLayoutTree) -> Bool {
        switch (self, other) {
        case (.leaf(let lhsTabId, _), .leaf(let rhsTabId, _)):
            return lhsTabId == rhsTabId
        case (.split(let lhsAxis, _, let lhsChildren), .split(let rhsAxis, _, let rhsChildren)):
            guard lhsAxis == rhsAxis, lhsChildren.count == rhsChildren.count else {
                return false
            }
            return zip(lhsChildren, rhsChildren).allSatisfy { lhs, rhs in
                lhs.hasSameStructure(as: rhs)
            }
        default:
            return false
        }
    }

    func tilePlanes(in rect: CGRect) -> [SplitTilePlaneHit] {
        guard let canonical = canonicalTileTreePreservingSizes() else { return [] }
        return SplitLayoutGeometry.tilePlanes(
            in: canonical,
            rect: rect,
            includeChildPlanes: SplitLayoutGeometry.hasSecondaryPlane(in: canonical)
        )
    }

    func canonicalizedForTiles() -> SplitLayoutTree? {
        let ids = tabIds
        let uniqueIds = uniqueSplitTabIdsPreservingOrder(ids)
        guard uniqueIds.count >= SplitGroup.minimumTabs,
              uniqueIds.count <= SplitGroup.maximumTabs,
              uniqueIds.count == ids.count
        else {
            return nil
        }

        if let canonical = canonicalTileTreePreservingSizes() {
            return canonical.normalizingSiblingSizes()
        }

        let fallbackAxis: SplitAxis
        if case .split(let axis, _, _) = self {
            fallbackAxis = axis
        } else {
            fallbackAxis = .row
        }
        return SplitLayoutTree.equalSplit(axis: fallbackAxis, tabIds: uniqueIds)
    }

    func resolvingDrop(
        draggedTabId: UUID,
        target: SplitDropTarget,
        bounds: CGRect
    ) -> SplitResolvedDrop? {
        let original = canonicalizedForTiles() ?? self
        let resolvedTree = target.resolvedLayoutTree?.contains(draggedTabId) == true
            ? target.resolvedLayoutTree
            : original.resolvingTileDrop(tabId: draggedTabId, target: target)
        guard let canonicalTree = resolvedTree?.canonicalTileTreePreservingSizes() else {
            return nil
        }
        let dropTree = target.side == .center
            ? canonicalTree
            : canonicalTree.equalizingStructuralDropSizes()
        if contains(draggedTabId),
           dropTree.hasSameStructure(as: original) {
            return nil
        }
        guard let targetRect = dropTree.leafRect(for: draggedTabId, in: bounds) else {
            return nil
        }
        return SplitResolvedDrop(
            target: target.resolving(targetRect: targetRect, resolvedLayoutTree: dropTree),
            layoutTree: dropTree
        )
    }

    func node(at path: [Int]) -> SplitLayoutTree? {
        var node = self
        for index in path {
            guard case .split(_, _, let children) = node,
                  children.indices.contains(index)
            else {
                return nil
            }
            node = children[index]
        }
        return node
    }

    private var isLeaf: Bool {
        if case .leaf = self { return true }
        return false
    }

    private func canonicalTileTreePreservingSizes() -> SplitLayoutTree? {
        let ids = tabIds
        guard ids.count >= SplitGroup.minimumTabs,
              ids.count <= SplitGroup.maximumTabs,
              Set(ids).count == ids.count
        else {
            return nil
        }

        switch self {
        case .leaf:
            return nil
        case .split(let axis, let size, let children):
            guard children.count >= 2,
                  children.count <= SplitGroup.maximumTabs
            else {
                return nil
            }

            if let flattened = flatteningSameAxisChildren(axis: axis, size: size, children: children) {
                return flattened.canonicalTileTreePreservingSizes()
            }

            if children.allSatisfy(\.isLeaf) {
                return .split(axis: axis, size: size, children: children)
                    .normalizingSiblingSizes()
            }

            if let mixedFlatPair = normalizedMixedFlatPair(axis: axis, size: size, children: children) {
                return mixedFlatPair
            }

            guard children.count == 2 else { return nil }
            let normalizedChildren = children.compactMap { child -> SplitLayoutTree? in
                switch child {
                case .leaf:
                    return child
                case .split(let childAxis, let childSize, let grandchildren):
                    guard grandchildren.count >= 2,
                          grandchildren.count <= 3,
                          grandchildren.allSatisfy(\.isLeaf)
                    else {
                        return nil
                    }
                    return SplitLayoutTree.split(
                        axis: childAxis,
                        size: childSize,
                        children: grandchildren
                    )
                    .normalizingSiblingSizes()
                }
            }
            guard normalizedChildren.count == children.count else { return nil }
            return SplitLayoutTree.split(axis: axis, size: size, children: normalizedChildren)
                .normalizingSiblingSizes()
        }
    }

    private func normalizedMixedFlatPair(
        axis: SplitAxis,
        size: Double,
        children: [SplitLayoutTree]
    ) -> SplitLayoutTree? {
        guard children.count == 3,
              tabIds.count == SplitGroup.maximumTabs
        else {
            return nil
        }

        let splitIndices = children.indices.filter { index in
            if case .split(let childAxis, _, let grandchildren) = children[index] {
                return childAxis != axis && grandchildren.count == 2 && grandchildren.allSatisfy(\.isLeaf)
            }
            return false
        }
        guard splitIndices.count == 1 else { return nil }

        let normalizedChildren = children.enumerated().map { index, child -> SplitLayoutTree in
            index == splitIndices[0] ? child.normalizingSiblingSizes() : child
        }
        let total = normalizedChildren.reduce(0) { $0 + max(0.01, $1.sizeInParent) }
        guard total > 0 else { return nil }
        let resized = normalizedChildren.map { child in
            child.settingSize(max(0.01, child.sizeInParent) / total)
        }
        return .split(axis: axis, size: size, children: resized)
    }

    private func resolvingTileDrop(tabId: UUID, target: SplitDropTarget) -> SplitLayoutTree? {
        if target.side == .center {
            if contains(tabId) {
                guard tabId != target.tabId else { return nil }
                return swappingTabs(tabId, target.tabId).canonicalTileTreePreservingSizes()
            }
            return replacingTab(target.tabId, with: tabId).canonicalTileTreePreservingSizes()
        }

        if target.intent == .siblingEdge {
            if contains(tabId) {
                return movingTab(tabId, relativeTo: target.tabId, side: target.side)?
                    .canonicalTileTreePreservingSizes()
            }
            return inserting(tabId: tabId, relativeTo: target.tabId, side: target.side)
                .canonicalTileTreePreservingSizes()
        }

        if target.intent == .flatFourPair {
            return pairingFlatFour(tabId: tabId, targetTabId: target.tabId, side: target.side)
        }

        if target.intent == .flatThreePair {
            return pairingFlatThree(tabId: tabId, targetTabId: target.tabId, side: target.side)
        }

        if target.intent == .flatFourReorder {
            return reorderingFlatFour(tabId: tabId, targetTabId: target.tabId, side: target.side)
        }

        if target.intent == .mixedThreeOnePair {
            return pairingMixedThreeOne(tabId: tabId, targetTabId: target.tabId, side: target.side)
        }

        let originalTargetIds = node(at: target.planePath)?.tabIds ?? []
        let base: SplitLayoutTree
        var insertionPath = target.planePath
        if contains(tabId) {
            let targetIdsAfterMove = originalTargetIds.filter { $0 != tabId }
            guard targetIdsAfterMove.isEmpty == false else { return nil }
            base = removingForMove(tabId: tabId)
            if let adjustedPath = base.pathForNode(withTabIds: targetIdsAfterMove) {
                insertionPath = adjustedPath
            } else if base.node(at: insertionPath) == nil {
                return nil
            }
        } else {
            base = self
        }

        if target.intent == .rootEdge,
           let insertionAxis = target.side.insertionAxis,
           SplitLayoutGeometry.hasSecondaryPlane(in: base),
           case .split(let axis, _, _) = base,
           axis == insertionAxis {
            var ids = base.tabIds
            if target.side == .left || target.side == .top {
                ids.insert(tabId, at: 0)
            } else {
                ids.append(tabId)
            }
            return SplitLayoutTree.equalSplit(axis: insertionAxis, tabIds: ids)
                .canonicalTileTreePreservingSizes()
        }

        guard let inserted = base.insertingTile(tabId: tabId, at: insertionPath, side: target.side),
              inserted.tabIds.count <= SplitGroup.maximumTabs,
              Set(inserted.tabIds).count == inserted.tabIds.count
        else {
            return nil
        }
        return inserted.canonicalTileTreePreservingSizes()
    }

    private func pairingFlatThree(
        tabId: UUID,
        targetTabId: UUID,
        side: SplitDropSide
    ) -> SplitLayoutTree? {
        guard contains(targetTabId),
              let insertionAxis = side.insertionAxis,
              case .split(let rootAxis, let rootSize, let children) = self,
              children.count == 3,
              children.allSatisfy(\.isLeaf),
              insertionAxis != rootAxis,
              tabId != targetTabId
        else {
            return nil
        }

        let leafChildren: [(tabId: UUID, size: Double)] = children.compactMap { child in
            if case .leaf(let id, let size) = child {
                return (id, size)
            }
            return nil
        }
        guard leafChildren.count == children.count,
              leafChildren.contains(where: { $0.tabId == targetTabId })
        else {
            return nil
        }
        let pairedIds = (side == .left || side == .top)
            ? [tabId, targetTabId]
            : [targetTabId, tabId]

        let pairedPlane = SplitLayoutTree.equalSplit(axis: insertionAxis, tabIds: pairedIds)
        let updatedChildren = leafChildren.compactMap { leaf -> SplitLayoutTree? in
            if contains(tabId), leaf.tabId == tabId {
                return nil
            }
            if leaf.tabId == targetTabId {
                return pairedPlane.settingSize(leaf.size)
            }
            return SplitLayoutTree.leaf(tabId: leaf.tabId, size: leaf.size)
        }
        guard contains(tabId) == false || updatedChildren.count == 2 else {
            return nil
        }
        return SplitLayoutTree.split(axis: rootAxis, size: rootSize, children: updatedChildren)
        .canonicalTileTreePreservingSizes()
    }

    private func pairingFlatFour(
        tabId: UUID,
        targetTabId: UUID,
        side: SplitDropSide
    ) -> SplitLayoutTree? {
        guard contains(tabId),
              contains(targetTabId),
              tabId != targetTabId,
              let insertionAxis = side.insertionAxis,
              case .split(let rootAxis, let rootSize, let children) = self,
              children.count == SplitGroup.maximumTabs,
              children.allSatisfy(\.isLeaf),
              insertionAxis != rootAxis
        else {
            return nil
        }

        let leafChildren: [(tabId: UUID, size: Double)] = children.compactMap { child in
            if case .leaf(let id, let size) = child {
                return (id, size)
            }
            return nil
        }
        guard leafChildren.count == children.count,
              leafChildren.contains(where: { $0.tabId == targetTabId })
        else {
            return nil
        }
        let pairedIds = (side == .left || side == .top)
            ? [tabId, targetTabId]
            : [targetTabId, tabId]

        let pairedPlane = SplitLayoutTree.equalSplit(axis: insertionAxis, tabIds: pairedIds)
        let updatedChildren = leafChildren.compactMap { leaf -> SplitLayoutTree? in
            if leaf.tabId == tabId {
                return nil
            }
            if leaf.tabId == targetTabId {
                return pairedPlane.settingSize(leaf.size)
            }
            return SplitLayoutTree.leaf(tabId: leaf.tabId, size: leaf.size)
        }
        guard updatedChildren.count == 3 else { return nil }
        return SplitLayoutTree.split(axis: rootAxis, size: rootSize, children: updatedChildren)
        .canonicalTileTreePreservingSizes()
    }

    private func pairingMixedThreeOne(
        tabId: UUID,
        targetTabId: UUID,
        side: SplitDropSide
    ) -> SplitLayoutTree? {
        guard contains(tabId),
              contains(targetTabId),
              tabId != targetTabId,
              let insertionAxis = side.insertionAxis,
              case .split(let rootAxis, let rootSize, let children) = self,
              children.count == 2
        else {
            return nil
        }

        var splitInfo: (index: Int, axis: SplitAxis, size: Double, leaves: [(tabId: UUID, size: Double)])?
        var leafInfo: (index: Int, tabId: UUID, size: Double)?
        for (index, child) in children.enumerated() {
            switch child {
            case .leaf(let id, let size):
                leafInfo = (index, id, size)
            case .split(let axis, let size, let grandchildren):
                let leaves: [(tabId: UUID, size: Double)] = grandchildren.compactMap { grandchild in
                    if case .leaf(let id, let leafSize) = grandchild {
                        return (id, leafSize)
                    }
                    return nil
                }
                if leaves.count == 3 {
                    splitInfo = (index, axis, size, leaves)
                }
            }
        }

        guard let splitInfo,
              let leafInfo
        else {
            return nil
        }

        let splitIds = splitInfo.leaves.map(\.tabId)
        let draggedIsSingleton = leafInfo.tabId == tabId && splitIds.contains(targetTabId)
        let targetIsSingleton = leafInfo.tabId == targetTabId && splitIds.contains(tabId)
        guard draggedIsSingleton || targetIsSingleton else { return nil }

        let pairedIds = (side == .left || side == .top)
            ? [tabId, targetTabId]
            : [targetTabId, tabId]
        if insertionAxis != splitInfo.axis {
            let replacedTabId = draggedIsSingleton ? targetTabId : tabId
            let pairedPlane = SplitLayoutTree
                .equalSplit(axis: insertionAxis, tabIds: pairedIds)
            let updated = splitInfo.leaves.map { leaf -> SplitLayoutTree in
                if leaf.tabId == replacedTabId {
                    return pairedPlane.settingSize(leaf.size)
                }
                return SplitLayoutTree.leaf(tabId: leaf.tabId, size: leaf.size)
            }
            return SplitLayoutTree.split(axis: splitInfo.axis, size: rootSize, children: updated)
                .canonicalTileTreePreservingSizes()
        }

        let remainingIds = splitIds.filter { $0 != tabId && $0 != targetTabId }
        guard remainingIds.count == 2 else { return nil }
        let pairedPlane = SplitLayoutTree
            .equalSplit(axis: splitInfo.axis, tabIds: pairedIds)
        let remainingPlane = SplitLayoutTree
            .equalSplit(axis: splitInfo.axis, tabIds: remainingIds)

        var updated = children
        if draggedIsSingleton {
            updated[splitInfo.index] = pairedPlane.settingSize(splitInfo.size)
            updated[leafInfo.index] = remainingPlane.settingSize(leafInfo.size)
        } else {
            updated[splitInfo.index] = remainingPlane.settingSize(splitInfo.size)
            updated[leafInfo.index] = pairedPlane.settingSize(leafInfo.size)
        }

        return SplitLayoutTree.split(axis: rootAxis, size: rootSize, children: updated)
            .canonicalTileTreePreservingSizes()
    }

    private func flatteningSameAxisChildren(
        axis: SplitAxis,
        size: Double,
        children: [SplitLayoutTree]
    ) -> SplitLayoutTree? {
        var didFlatten = false
        let flattened = children.flatMap { child -> [SplitLayoutTree] in
            guard case .split(let childAxis, _, let grandchildren) = child,
                  childAxis == axis
            else {
                return [child]
            }
            didFlatten = true
            return grandchildren.map { grandchild in
                grandchild.settingSize(max(0.01, child.sizeInParent) * max(0.01, grandchild.sizeInParent))
            }
        }
        guard didFlatten,
              flattened.count >= 2,
              flattened.count <= SplitGroup.maximumTabs
        else {
            return nil
        }
        return .split(axis: axis, size: size, children: flattened)
    }

    private func reorderingFlatFour(
        tabId: UUID,
        targetTabId: UUID,
        side: SplitDropSide
    ) -> SplitLayoutTree? {
        guard contains(tabId),
              contains(targetTabId),
              tabId != targetTabId,
              let insertionAxis = side.insertionAxis,
              case .split(let rootAxis, let rootSize, let children) = self,
              children.count == SplitGroup.maximumTabs,
              children.allSatisfy(\.isLeaf),
              insertionAxis == rootAxis
        else {
            return nil
        }

        var ids = tabIds.filter { $0 != tabId }
        guard let targetIndex = ids.firstIndex(of: targetTabId) else { return nil }
        let insertBefore = side == .left || side == .top
        ids.insert(tabId, at: insertBefore ? targetIndex : targetIndex + 1)
        guard ids != tabIds else { return nil }
        return SplitLayoutTree.equalSplit(axis: rootAxis, tabIds: ids)
            .settingSize(rootSize)
            .canonicalTileTreePreservingSizes()
    }

    private func pathForNode(withTabIds ids: [UUID]) -> [Int]? {
        guard ids.isEmpty == false else { return nil }
        if tabIds == ids {
            return []
        }
        guard case .split(_, _, let children) = self else { return nil }
        for (index, child) in children.enumerated() {
            if let childPath = child.pathForNode(withTabIds: ids) {
                return [index] + childPath
            }
        }
        return nil
    }

    private func insertingTile(
        tabId: UUID,
        at path: [Int],
        side: SplitDropSide
    ) -> SplitLayoutTree? {
        guard path.isEmpty == false else {
            return insertingTileAtCurrentNode(tabId: tabId, side: side)
        }
        guard case .split(let axis, let size, let children) = self,
              let index = path.first,
              children.indices.contains(index)
        else {
            return nil
        }
        var updated = children
        guard let insertedChild = updated[index].insertingTile(
            tabId: tabId,
            at: Array(path.dropFirst()),
            side: side
        ) else {
            return nil
        }
        updated[index] = insertedChild
        return .split(axis: axis, size: size, children: updated)
    }

    private func insertingTileAtCurrentNode(
        tabId: UUID,
        side: SplitDropSide
    ) -> SplitLayoutTree? {
        guard let insertionAxis = side.insertionAxis else { return nil }
        let insertBefore = side == .left || side == .top
        let incoming = SplitLayoutTree.leaf(tabId: tabId, size: 1)

        switch self {
        case .leaf(let existingTabId, let size):
            let existing = SplitLayoutTree.leaf(tabId: existingTabId, size: 0.5)
            let inserted = SplitLayoutTree.leaf(tabId: tabId, size: 0.5)
            return .split(
                axis: insertionAxis,
                size: size,
                children: insertBefore ? [inserted, existing] : [existing, inserted]
            )

        case .split(let axis, let size, let children):
            if axis == insertionAxis {
                var updated = children.map { $0.settingSize(1) }
                if insertBefore {
                    updated.insert(incoming, at: 0)
                } else {
                    updated.append(incoming)
                }
                return SplitLayoutTree.split(axis: axis, size: size, children: updated)
                    .equalizingImmediateChildSizes()
            }

            let existing = settingSize(0.5)
            let inserted = SplitLayoutTree.leaf(tabId: tabId, size: 0.5)
            return .split(
                axis: insertionAxis,
                size: sizeInParent,
                children: insertBefore ? [inserted, existing] : [existing, inserted]
            )
        }
    }

    func settingSize(_ size: Double) -> SplitLayoutTree {
        switch self {
        case .leaf(let tabId, _):
            return .leaf(tabId: tabId, size: size)
        case .split(let axis, _, let children):
            return .split(axis: axis, size: size, children: children)
        }
    }

    func normalizingSiblingSizes() -> SplitLayoutTree {
        switch self {
        case .leaf:
            return self
        case .split(let axis, let size, let children):
            let normalizedChildren = children.map { $0.normalizingSiblingSizes() }
            let total = normalizedChildren.reduce(0) { $0 + max(0.01, $1.sizeInParent) }
            let equal = normalizedChildren.isEmpty ? 1 : 1 / Double(normalizedChildren.count)
            let resized = normalizedChildren.map { child -> SplitLayoutTree in
                if total > 0 {
                    return child.settingSize(max(0.01, child.sizeInParent) / total)
                }
                return child.settingSize(equal)
            }
            return .split(axis: axis, size: size, children: resized)
        }
    }

    private func equalizingImmediateChildSizes() -> SplitLayoutTree {
        switch self {
        case .leaf:
            return self
        case .split(let axis, let size, let children):
            let equalSize = children.isEmpty ? 1 : 1 / Double(children.count)
            return .split(
                axis: axis,
                size: size,
                children: children.map { $0.settingSize(equalSize) }
            )
        }
    }

    private func equalizingStructuralDropSizes() -> SplitLayoutTree {
        switch self {
        case .leaf:
            return self
        case .split(let axis, let size, let children):
            let equalizedChildren = children.map { $0.equalizingStructuralDropSizes() }
            let equalSize = equalizedChildren.isEmpty ? 1 : 1 / Double(equalizedChildren.count)
            return .split(
                axis: axis,
                size: size,
                children: equalizedChildren.map { $0.settingSize(equalSize) }
            )
        }
    }

    func removing(tabId: UUID) -> SplitLayoutTree? {
        switch self {
        case .leaf(let id, _):
            return id == tabId ? nil : self
        case .split(let axis, let size, let children):
            let kept = children.compactMap { $0.removing(tabId: tabId) }
            if kept.isEmpty {
                return nil
            }
            if kept.count == 1 {
                return kept[0].settingSize(size)
            }
            return SplitLayoutTree.split(axis: axis, size: size, children: kept).normalizingSiblingSizes()
        }
    }

    func replacingTab(_ oldTabId: UUID, with newTabId: UUID) -> SplitLayoutTree {
        switch self {
        case .leaf(let tabId, let size):
            return .leaf(tabId: tabId == oldTabId ? newTabId : tabId, size: size)
        case .split(let axis, let size, let children):
            return .split(
                axis: axis,
                size: size,
                children: children.map { $0.replacingTab(oldTabId, with: newTabId) }
            )
        }
    }

    func swappingTabs(_ firstTabId: UUID, _ secondTabId: UUID) -> SplitLayoutTree {
        guard firstTabId != secondTabId else { return self }
        switch self {
        case .leaf(let tabId, let size):
            if tabId == firstTabId {
                return .leaf(tabId: secondTabId, size: size)
            }
            if tabId == secondTabId {
                return .leaf(tabId: firstTabId, size: size)
            }
            return self
        case .split(let axis, let size, let children):
            return .split(
                axis: axis,
                size: size,
                children: children.map { $0.swappingTabs(firstTabId, secondTabId) }
            )
        }
    }

    func movingTab(
        _ tabId: UUID,
        relativeTo targetTabId: UUID,
        side: SplitDropSide
    ) -> SplitLayoutTree? {
        guard contains(tabId), contains(targetTabId), tabId != targetTabId else { return self }
        let remaining = tabIds.filter { $0 != tabId }
        guard remaining.contains(targetTabId), remaining.isEmpty == false else { return self }
        let baseTree = removingForMove(tabId: tabId)
        return baseTree.inserting(
            tabId: tabId,
            relativeTo: targetTabId,
            side: side,
            equalizeInsertedAxis: false
        )
        .canonicalizedForTiles()
    }

    func movingTabToRootEdge(_ tabId: UUID, side: SplitDropSide) -> SplitLayoutTree? {
        guard contains(tabId), side.insertionAxis != nil else { return nil }
        let baseTree = removingForMove(tabId: tabId)
        return baseTree.insertingAtRoot(
            tabId: tabId,
            side: side,
            equalizeInsertedAxis: false
        )
        .canonicalizedForTiles()
    }

    func updatingChildSizes(at path: [Int], sizes: [Double]) -> SplitLayoutTree {
        guard path.isEmpty == false else {
            return applyingChildSizes(sizes)
        }
        switch self {
        case .leaf:
            return self
        case .split(let axis, let size, let children):
            var updated = children
            let index = path[0]
            guard updated.indices.contains(index) else { return self }
            updated[index] = updated[index].updatingChildSizes(
                at: Array(path.dropFirst()),
                sizes: sizes
            )
            return .split(axis: axis, size: size, children: updated)
        }
    }

    private func removingForMove(tabId: UUID) -> SplitLayoutTree {
        switch self {
        case .leaf:
            return self
        case .split(let axis, let size, let children):
            let kept = children.compactMap { child -> SplitLayoutTree? in
                guard child.contains(tabId) else { return child }
                return child.removingForMoveIfPresent(tabId: tabId)
            }
            guard kept.count > 1 else {
                return (kept.first ?? self).settingSize(size)
            }
            return SplitLayoutTree.split(axis: axis, size: size, children: kept).normalizingSiblingSizes()
        }
    }

    private func removingForMoveIfPresent(tabId: UUID) -> SplitLayoutTree? {
        switch self {
        case .leaf(let id, _):
            return id == tabId ? nil : self
        case .split(let axis, let size, let children):
            let kept = children.compactMap { $0.removingForMoveIfPresent(tabId: tabId) }
            guard kept.isEmpty == false else { return nil }
            guard kept.count > 1 else { return kept[0].settingSize(size) }
            return SplitLayoutTree.split(axis: axis, size: size, children: kept).normalizingSiblingSizes()
        }
    }

    private func applyingChildSizes(_ sizes: [Double]) -> SplitLayoutTree {
        switch self {
        case .leaf:
            return self
        case .split(let axis, let size, let children):
            guard sizes.count == children.count else { return self }
            let total = sizes.reduce(0) { $0 + max(0.01, $1) }
            guard total > 0 else { return self }
            let resized = zip(children, sizes).map { child, rawSize in
                child.settingSize(max(0.01, rawSize) / total)
            }
            return .split(axis: axis, size: size, children: resized)
        }
    }

    func inserting(
        tabId: UUID,
        relativeTo targetTabId: UUID,
        side: SplitDropSide,
        equalizeInsertedAxis: Bool = true
    ) -> SplitLayoutTree {
        guard let axis = side.insertionAxis else {
            return replacingTab(targetTabId, with: tabId)
        }
        let inserted = inserting(
            tabId: tabId,
            relativeTo: targetTabId,
            axis: axis,
            before: side == .left || side == .top,
            equalizeInsertedAxis: equalizeInsertedAxis
        )
        return inserted.canonicalizedForTiles() ?? inserted.normalizingSiblingSizes()
    }

    func insertingAtRoot(
        tabId: UUID,
        side: SplitDropSide,
        equalizeInsertedAxis: Bool = true
    ) -> SplitLayoutTree {
        guard let insertionAxis = side.insertionAxis else { return self }
        let incoming = SplitLayoutTree.leaf(tabId: tabId, size: 1)
        let insertBefore = side == .left || side == .top

        if case .split(let axis, let size, let children) = self, axis == insertionAxis {
            var updated = equalizeInsertedAxis ? children.map { $0.settingSize(1) } : children
            if insertBefore {
                updated.insert(incoming, at: 0)
            } else {
                updated.append(incoming)
            }
            let inserted = SplitLayoutTree.split(axis: axis, size: size, children: updated)
            return inserted.canonicalizedForTiles() ?? inserted.normalizingSiblingSizes()
        }

        let existing = settingSize(1)
        let inserted = SplitLayoutTree.split(
            axis: insertionAxis,
            size: sizeInParent,
            children: insertBefore ? [incoming, existing] : [existing, incoming]
        )
        return inserted.canonicalizedForTiles() ?? inserted.normalizingSiblingSizes()
    }

    private func inserting(
        tabId: UUID,
        relativeTo targetTabId: UUID,
        axis insertionAxis: SplitAxis,
        before: Bool,
        equalizeInsertedAxis: Bool
    ) -> SplitLayoutTree {
        switch self {
        case .leaf(let existingTabId, let size):
            guard existingTabId == targetTabId else { return self }
            let existing = SplitLayoutTree.leaf(tabId: existingTabId, size: 0.5)
            let incoming = SplitLayoutTree.leaf(tabId: tabId, size: 0.5)
            return .split(
                axis: insertionAxis,
                size: size,
                children: before ? [incoming, existing] : [existing, incoming]
            )

        case .split(let axis, let size, let children):
            if axis == insertionAxis,
               let targetIndex = children.firstIndex(where: { $0.contains(targetTabId) && $0.leafCount == 1 })
            {
                var updated = children
                let insertionIndex = before ? targetIndex : targetIndex + 1
                updated.insert(.leaf(tabId: tabId, size: 1), at: insertionIndex)
                let split = SplitLayoutTree.split(axis: axis, size: size, children: updated)
                return equalizeInsertedAxis ? split.equalizingImmediateChildSizes() : split
            }

            return .split(
                axis: axis,
                size: size,
                children: children.map {
                    $0.contains(targetTabId)
                        ? $0.inserting(
                            tabId: tabId,
                            relativeTo: targetTabId,
                            axis: insertionAxis,
                            before: before,
                            equalizeInsertedAxis: equalizeInsertedAxis
                        )
                        : $0
                }
            )
        }
    }

    static func make(kind: SplitLayoutKind, tabIds: [UUID]) -> SplitLayoutTree {
        let uniqueIds = uniqueSplitTabIdsPreservingOrder(tabIds).prefix(SplitGroup.maximumTabs)
        let ids = Array(uniqueIds)
        guard ids.isEmpty == false else {
            return .split(axis: kind.primaryAxis, size: 1, children: [])
        }

        switch kind {
        case .vertical:
            return equalSplit(axis: .row, tabIds: ids)
        case .horizontal:
            return equalSplit(axis: .column, tabIds: ids)
        case .grid:
            return grid(tabIds: ids)
        }
    }

    private static func equalSplit(axis: SplitAxis, tabIds: [UUID]) -> SplitLayoutTree {
        let size = 1 / Double(max(1, tabIds.count))
        return .split(
            axis: axis,
            size: 1,
            children: tabIds.map { .leaf(tabId: $0, size: size) }
        )
    }

    private static func grid(tabIds: [UUID]) -> SplitLayoutTree {
        if tabIds.count <= 2 {
            return equalSplit(axis: .row, tabIds: tabIds)
        }

        var columns: [SplitLayoutTree] = []
        var cursor = 0
        while cursor < tabIds.count {
            let remaining = tabIds.count - cursor
            let take = remaining == 3 ? 1 : min(2, remaining)
            let columnIds = Array(tabIds[cursor ..< cursor + take])
            let column = take == 1
                ? SplitLayoutTree.leaf(tabId: columnIds[0], size: 1)
                : equalSplit(axis: .column, tabIds: columnIds)
            columns.append(column.settingSize(1))
            cursor += take
        }
        return SplitLayoutTree.split(axis: .row, size: 1, children: columns).normalizingSiblingSizes()
    }
}

struct SplitGroup: Identifiable, Codable, Equatable, Hashable, Sendable {
    static let maximumTabs = 4
    static let minimumTabs = 2

    var id: UUID
    var layoutKind: SplitLayoutKind
    var layoutTree: SplitLayoutTree
    var activeTabId: UUID?
    var host: SplitGroupHost
    var members: [SplitGroupMember]

    private enum CodingKeys: String, CodingKey {
        case id
        case layoutKind
        case layoutTree
        case activeTabId
        case host
        case members
    }

    init(
        id: UUID = UUID(),
        layoutKind: SplitLayoutKind,
        layoutTree: SplitLayoutTree,
        activeTabId: UUID? = nil,
        host: SplitGroupHost = .regular(spaceId: nil),
        members: [SplitGroupMember] = []
    ) {
        self.id = id
        self.layoutKind = layoutKind
        let normalizedTree = layoutTree.normalizingSiblingSizes()
        self.layoutTree = normalizedTree.canonicalizedForTiles() ?? normalizedTree
        self.activeTabId = activeTabId
        self.host = host
        self.members = Self.sanitizedMembers(members, validTabIds: Set(self.layoutTree.tabIds))
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        layoutKind = try container.decode(SplitLayoutKind.self, forKey: .layoutKind)
        let decodedTree = try container.decode(SplitLayoutTree.self, forKey: .layoutTree)
        let normalizedTree = decodedTree.normalizingSiblingSizes()
        layoutTree = normalizedTree.canonicalizedForTiles() ?? normalizedTree
        activeTabId = try container.decodeIfPresent(UUID.self, forKey: .activeTabId)
        host = try container.decodeIfPresent(SplitGroupHost.self, forKey: .host) ?? .regular(spaceId: nil)
        members = Self.sanitizedMembers(
            try container.decodeIfPresent([SplitGroupMember].self, forKey: .members) ?? [],
            validTabIds: Set(layoutTree.tabIds)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(layoutKind, forKey: .layoutKind)
        try container.encode(layoutTree, forKey: .layoutTree)
        try container.encodeIfPresent(activeTabId, forKey: .activeTabId)
        try container.encode(host, forKey: .host)
        try container.encode(members, forKey: .members)
    }

    var tabIds: [UUID] {
        layoutTree.tabIds
    }

    var isShortcutHosted: Bool {
        host.isShortcutPinned
    }

    var hostSpaceId: UUID? {
        host.spaceId
    }

    var shortcutPinnedIndex: Int? {
        host.shortcutPinnedIndex
    }

    var shortcutPinIds: Set<UUID> {
        Set(members.compactMap(\.pinId))
    }

    func member(for tabId: UUID) -> SplitGroupMember? {
        members.first { $0.tabId == tabId || $0.pinId == tabId }
    }

    func member(forPinId pinId: UUID) -> SplitGroupMember? {
        members.first { $0.pinId == pinId }
    }

    func containsPin(_ pinId: UUID) -> Bool {
        members.contains { $0.pinId == pinId }
    }

    var isValid: Bool {
        let ids = tabIds
        return ids.count >= Self.minimumTabs
            && ids.count <= Self.maximumTabs
            && uniqueSplitTabIdsPreservingOrder(ids).count == ids.count
    }

    func contains(_ tabId: UUID) -> Bool {
        layoutTree.contains(tabId) || containsPin(tabId)
    }

    func settingLayoutKind(_ kind: SplitLayoutKind) -> SplitGroup {
        SplitGroup(
            id: id,
            layoutKind: kind,
            layoutTree: .make(kind: kind, tabIds: tabIds),
            activeTabId: activeTabId,
            host: host,
            members: members
        )
    }

    func settingActiveTab(_ tabId: UUID?) -> SplitGroup {
        var copy = self
        copy.activeTabId = tabId.flatMap { contains($0) ? $0 : nil }
        return copy
    }

    func canonicalizedForTiles() -> SplitGroup? {
        guard let tree = layoutTree.canonicalizedForTiles() else { return nil }
        let resolvedActiveTabId = activeTabId.flatMap { tree.contains($0) ? $0 : nil } ?? tree.tabIds.first
        return SplitGroup(
            id: id,
            layoutKind: layoutKind,
            layoutTree: tree,
            activeTabId: resolvedActiveTabId,
            host: host,
            members: members
        )
    }

    func removing(tabId: UUID) -> SplitGroup? {
        guard let tree = layoutTree.removing(tabId: tabId) else { return nil }
        let remainingIds = tree.tabIds
        guard remainingIds.count >= Self.minimumTabs else { return nil }
        return SplitGroup(
            id: id,
            layoutKind: layoutKind,
            layoutTree: tree,
            activeTabId: activeTabId == tabId ? remainingIds.first : activeTabId,
            host: host,
            members: members.filter { $0.tabId != tabId && $0.pinId != tabId }
        )
    }

    func movingTab(_ tabId: UUID, relativeTo targetTabId: UUID, side: SplitDropSide) -> SplitGroup? {
        guard side != .center else {
            return swappingTabs(tabId, targetTabId)
        }
        guard let tree = layoutTree.movingTab(tabId, relativeTo: targetTabId, side: side) else {
            return nil
        }
        return SplitGroup(
            id: id,
            layoutKind: layoutKind,
            layoutTree: tree,
            activeTabId: tabId,
            host: host,
            members: members
        )
    }

    func movingTabToRootEdge(_ tabId: UUID, side: SplitDropSide) -> SplitGroup? {
        guard side != .center,
              contains(tabId),
              let tree = layoutTree.movingTabToRootEdge(tabId, side: side)
        else {
            return nil
        }
        return SplitGroup(
            id: id,
            layoutKind: layoutKind,
            layoutTree: tree,
            activeTabId: tabId,
            host: host,
            members: members
        )
    }

    func isMovingTabNoOpAtRootEdge(_ tabId: UUID, side: SplitDropSide) -> Bool {
        guard let moved = movingTabToRootEdge(tabId, side: side) else {
            return true
        }
        return moved.layoutTree.hasSameStructure(as: layoutTree)
    }

    func resolvingDrop(
        draggedTabId: UUID,
        target: SplitDropTarget,
        bounds: CGRect
    ) -> SplitResolvedDrop? {
        layoutTree.resolvingDrop(
            draggedTabId: draggedTabId,
            target: target,
            bounds: bounds
        )
    }

    func swappingTabs(_ firstTabId: UUID, _ secondTabId: UUID) -> SplitGroup? {
        guard contains(firstTabId), contains(secondTabId) else { return nil }
        return SplitGroup(
            id: id,
            layoutKind: layoutKind,
            layoutTree: layoutTree.swappingTabs(firstTabId, secondTabId),
            activeTabId: firstTabId,
            host: host,
            members: members.map { member in
                if member.tabId == firstTabId {
                    var copy = member
                    copy.tabId = secondTabId
                    return copy
                }
                if member.tabId == secondTabId {
                    var copy = member
                    copy.tabId = firstTabId
                    return copy
                }
                return member
            }
        )
    }

    func inserting(
        tabId: UUID,
        relativeTo targetTabId: UUID,
        side: SplitDropSide
    ) -> SplitGroup? {
        guard tabIds.contains(tabId) == false else { return settingActiveTab(tabId) }
        guard tabIds.count < Self.maximumTabs else { return nil }
        let tree = layoutTree.inserting(tabId: tabId, relativeTo: targetTabId, side: side)
        return SplitGroup(
            id: id,
            layoutKind: layoutKind,
            layoutTree: tree,
            activeTabId: tabId,
            host: host,
            members: members
        )
    }

    func insertingAtRoot(tabId: UUID, side: SplitDropSide) -> SplitGroup? {
        guard side != .center else { return settingActiveTab(tabId) }
        guard tabIds.contains(tabId) == false else { return settingActiveTab(tabId) }
        guard tabIds.count < Self.maximumTabs else { return nil }
        return SplitGroup(
            id: id,
            layoutKind: layoutKind,
            layoutTree: layoutTree.insertingAtRoot(tabId: tabId, side: side),
            activeTabId: tabId,
            host: host,
            members: members
        )
    }

    func settingHost(_ host: SplitGroupHost) -> SplitGroup {
        SplitGroup(
            id: id,
            layoutKind: layoutKind,
            layoutTree: layoutTree,
            activeTabId: activeTabId,
            host: host,
            members: members
        )
    }

    func settingMembers(_ members: [SplitGroupMember]) -> SplitGroup {
        SplitGroup(
            id: id,
            layoutKind: layoutKind,
            layoutTree: layoutTree,
            activeTabId: activeTabId,
            host: host,
            members: members
        )
    }

    func upsertingMember(_ member: SplitGroupMember) -> SplitGroup {
        var updated = members.filter {
            $0.tabId != member.tabId
                && (member.pinId == nil || $0.pinId != member.pinId)
                && $0.stableId != member.stableId
        }
        updated.append(member)
        return settingMembers(updated)
    }

    func removingMember(tabId: UUID) -> SplitGroup {
        settingMembers(members.filter { $0.tabId != tabId && $0.pinId != tabId })
    }

    func replacingMemberTab(_ oldTabId: UUID, with newTabId: UUID) -> SplitGroup {
        let updatedMembers = members.map { member -> SplitGroupMember in
            guard member.tabId == oldTabId || member.pinId == oldTabId else { return member }
            var copy = member
            copy.tabId = newTabId
            return copy
        }
        return SplitGroup(
            id: id,
            layoutKind: layoutKind,
            layoutTree: layoutTree.replacingTab(oldTabId, with: newTabId),
            activeTabId: activeTabId == oldTabId ? newTabId : activeTabId,
            host: host,
            members: updatedMembers
        )
    }

    static func make(
        tabIds: [UUID],
        layoutKind: SplitLayoutKind,
        activeTabId: UUID? = nil,
        host: SplitGroupHost = .regular(spaceId: nil),
        members: [SplitGroupMember] = []
    ) -> SplitGroup? {
        let uniqueIds = uniqueSplitTabIdsPreservingOrder(tabIds)
        guard uniqueIds.count >= minimumTabs, uniqueIds.count <= maximumTabs else { return nil }
        return SplitGroup(
            layoutKind: layoutKind,
            layoutTree: .make(kind: layoutKind, tabIds: uniqueIds),
            activeTabId: activeTabId ?? uniqueIds.last,
            host: host,
            members: members
        )
    }

    static func sanitized(_ groups: [SplitGroup]) -> [SplitGroup] {
        var usedGroupIds: Set<UUID> = []
        var usedMemberIds: Set<UUID> = []
        var result: [SplitGroup] = []
        for group in groups {
            guard let canonicalGroup = group.canonicalizedForTiles(),
                  canonicalGroup.isValid
            else {
                continue
            }
            guard usedGroupIds.insert(canonicalGroup.id).inserted else { continue }
            let ids = Set(canonicalGroup.tabIds).union(canonicalGroup.shortcutPinIds)
            guard ids.allSatisfy({ usedMemberIds.contains($0) == false }) else { continue }
            usedMemberIds.formUnion(ids)
            result.append(canonicalGroup)
        }
        return result
    }

    private static func sanitizedMembers(
        _ members: [SplitGroupMember],
        validTabIds: Set<UUID>
    ) -> [SplitGroupMember] {
        var seen = Set<UUID>()
        var result: [SplitGroupMember] = []
        for member in members {
            guard validTabIds.contains(member.tabId) || member.pinId.map(validTabIds.contains) == true else {
                continue
            }
            guard seen.insert(member.stableId).inserted else { continue }
            result.append(member)
        }
        return result
    }
}
