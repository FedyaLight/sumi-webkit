import CoreGraphics
import Foundation

enum SplitLayoutGeometry {
    struct LeafHit: Equatable {
        let tabId: UUID
        let rect: CGRect
        let path: [Int]
    }

    struct TilePlane: Equatable {
        let path: [Int]
        let rect: CGRect
        let tabIds: [UUID]
    }

    static func leafTabId(
        in tree: SplitLayoutTree,
        at point: CGPoint,
        in rect: CGRect
    ) -> UUID? {
        leafHit(in: tree, at: point, in: rect)?.tabId
    }

    static func leafHit(
        in tree: SplitLayoutTree,
        at point: CGPoint,
        in rect: CGRect
    ) -> LeafHit? {
        leafHit(in: tree, at: point, in: rect, path: [])
    }

    static func leafHits(
        in tree: SplitLayoutTree,
        rect: CGRect
    ) -> [LeafHit] {
        leafHits(in: tree, rect: rect, path: [])
    }

    static func leafRects(
        in tree: SplitLayoutTree,
        rect: CGRect
    ) -> [UUID: CGRect] {
        Dictionary(uniqueKeysWithValues: leafHits(in: tree, rect: rect).map { ($0.tabId, $0.rect) })
    }

    static func leafRect(
        for tabId: UUID,
        in tree: SplitLayoutTree,
        rect: CGRect
    ) -> CGRect? {
        leafHit(for: tabId, in: tree, rect: rect, path: [])?.rect
    }

    static func edgeTabId(
        in tree: SplitLayoutTree,
        for side: SplitDropSide,
        in rect: CGRect
    ) -> UUID? {
        let leaves = leafHits(in: tree, rect: rect)
        guard leaves.isEmpty == false else { return nil }
        switch side {
        case .left:
            return leaves.min {
                if $0.rect.minX == $1.rect.minX { return $0.rect.maxY > $1.rect.maxY }
                return $0.rect.minX < $1.rect.minX
            }?.tabId
        case .right:
            return leaves.max {
                if $0.rect.maxX == $1.rect.maxX { return $0.rect.maxY < $1.rect.maxY }
                return $0.rect.maxX < $1.rect.maxX
            }?.tabId
        case .top:
            return leaves.max {
                if $0.rect.maxY == $1.rect.maxY { return $0.rect.minX > $1.rect.minX }
                return $0.rect.maxY < $1.rect.maxY
            }?.tabId
        case .bottom:
            return leaves.min {
                if $0.rect.minY == $1.rect.minY { return $0.rect.minX < $1.rect.minX }
                return $0.rect.minY < $1.rect.minY
            }?.tabId
        case .center:
            return nil
        }
    }

    static func hasSecondaryPlane(in tree: SplitLayoutTree) -> Bool {
        guard case .split(_, _, let children) = tree else { return false }
        return children.contains { isLeaf($0) == false }
    }

    static func tilePlanes(
        in tree: SplitLayoutTree,
        rect: CGRect,
        includeChildPlanes: Bool
    ) -> [TilePlane] {
        tilePlanes(in: tree, rect: rect, path: [], includeChildPlanes: includeChildPlanes)
    }

    private static func leafHit(
        in tree: SplitLayoutTree,
        at point: CGPoint,
        in rect: CGRect,
        path: [Int]
    ) -> LeafHit? {
        guard rect.width > 0, rect.height > 0, rect.contains(point) else { return nil }
        switch tree {
        case .leaf(let tabId, _):
            return LeafHit(tabId: tabId, rect: rect, path: path)
        case .split(let axis, _, let children):
            let childRects = childRects(in: rect, axis: axis, children: children)
            guard childRects.count == children.count else { return nil }
            for (index, child) in children.enumerated() {
                let childRect = childRects[index]
                if childRect.contains(point) {
                    return leafHit(in: child, at: point, in: childRect, path: path + [index])
                }
            }
            guard let lastIndex = children.indices.last else { return nil }
            return leafHit(in: children[lastIndex], at: point, in: childRects[lastIndex], path: path + [lastIndex])
        }
    }

    private static func leafHits(
        in tree: SplitLayoutTree,
        rect: CGRect,
        path: [Int]
    ) -> [LeafHit] {
        guard rect.width > 0, rect.height > 0 else { return [] }
        switch tree {
        case .leaf(let tabId, _):
            return [LeafHit(tabId: tabId, rect: rect, path: path)]
        case .split(let axis, _, let children):
            let childRects = childRects(in: rect, axis: axis, children: children)
            guard childRects.count == children.count else { return [] }
            return children.enumerated().flatMap { index, child -> [LeafHit] in
                leafHits(in: child, rect: childRects[index], path: path + [index])
            }
        }
    }

    private static func leafHit(
        for tabId: UUID,
        in tree: SplitLayoutTree,
        rect: CGRect,
        path: [Int]
    ) -> LeafHit? {
        guard rect.width > 0, rect.height > 0 else { return nil }
        switch tree {
        case .leaf(let id, _):
            return id == tabId ? LeafHit(tabId: id, rect: rect, path: path) : nil
        case .split(let axis, _, let children):
            let childRects = childRects(in: rect, axis: axis, children: children)
            guard childRects.count == children.count else { return nil }
            for (index, child) in children.enumerated() {
                guard let hit = leafHit(
                    for: tabId,
                    in: child,
                    rect: childRects[index],
                    path: path + [index]
                ) else {
                    continue
                }
                return hit
            }
            return nil
        }
    }

    private static func tilePlanes(
        in tree: SplitLayoutTree,
        rect: CGRect,
        path: [Int],
        includeChildPlanes: Bool
    ) -> [TilePlane] {
        var planes = [
            TilePlane(path: path, rect: rect, tabIds: tree.tabIds),
        ]
        guard includeChildPlanes,
              case .split(let axis, _, let children) = tree
        else {
            return planes
        }

        let childRects = childRects(in: rect, axis: axis, children: children)
        for (index, child) in children.enumerated() {
            planes.append(
                TilePlane(
                    path: path + [index],
                    rect: childRects[index],
                    tabIds: child.tabIds
                )
            )
        }
        return planes
    }

    private static func childRects(
        in rect: CGRect,
        axis: SplitAxis,
        children: [SplitLayoutTree]
    ) -> [CGRect] {
        let weights = SplitLayoutSizing.normalizedWeights(children.map(\.sizeInParent))
        guard weights.count == children.count else { return [] }
        var cursor: CGFloat = 0
        return weights.enumerated().map { index, weight in
            let fraction = CGFloat(weight)
            switch axis {
            case .row:
                let remaining = max(0, rect.width - cursor)
                let width = index == weights.count - 1
                    ? remaining
                    : min(remaining, rect.width * fraction)
                defer { cursor += width }
                return CGRect(x: rect.minX + cursor, y: rect.minY, width: width, height: rect.height)
            case .column:
                let remaining = max(0, rect.height - cursor)
                let height = index == weights.count - 1
                    ? remaining
                    : min(remaining, rect.height * fraction)
                defer { cursor += height }
                return CGRect(x: rect.minX, y: rect.maxY - cursor - height, width: rect.width, height: height)
            }
        }
    }

    private static func isLeaf(_ tree: SplitLayoutTree) -> Bool {
        if case .leaf = tree { return true }
        return false
    }
}
