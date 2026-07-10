import CoreGraphics
import Foundation

enum SplitDropTargetGeometry {
    static func isNearInternalDivider(
        location: CGPoint,
        leafRect: CGRect,
        bounds: CGRect,
        rootAxis: SplitAxis,
        threshold: CGFloat = 24
    ) -> Bool {
        let internalEdge: CGFloat?
        let coordinate: CGFloat

        switch rootAxis {
        case .row:
            coordinate = location.x
            if leafRect.minX > bounds.minX {
                internalEdge = leafRect.minX
            } else if leafRect.maxX < bounds.maxX {
                internalEdge = leafRect.maxX
            } else {
                internalEdge = nil
            }
        case .column:
            coordinate = location.y
            if leafRect.minY > bounds.minY {
                internalEdge = leafRect.minY
            } else if leafRect.maxY < bounds.maxY {
                internalEdge = leafRect.maxY
            } else {
                internalEdge = nil
            }
        }

        guard let internalEdge else { return false }
        return abs(coordinate - internalEdge) <= threshold
    }

    static func rankedEdgeSides(
        at location: CGPoint,
        in rect: CGRect
    ) -> [SplitDropSide] {
        guard rect.width > 0, rect.height > 0, rect.contains(location) else {
            return []
        }

        let threshold: CGFloat = 1.0 / 3.0
        let candidates: [(side: SplitDropSide, distance: CGFloat, length: CGFloat)] = [
            (.left, location.x - rect.minX, rect.width),
            (.right, rect.maxX - location.x, rect.width),
            (.top, rect.maxY - location.y, rect.height),
            (.bottom, location.y - rect.minY, rect.height),
        ]
        return candidates
            .compactMap { candidate -> (side: SplitDropSide, distance: CGFloat)? in
                guard candidate.length > 0 else { return nil }
                let normalizedDistance = candidate.distance / candidate.length
                guard normalizedDistance <= threshold else { return nil }
                return (candidate.side, normalizedDistance)
            }
            .sorted { lhs, rhs in
                if lhs.distance == rhs.distance {
                    return lhs.side.rawValue < rhs.side.rawValue
                }
                return lhs.distance < rhs.distance
            }
            .map(\.side)
    }

    static func middleRootSide(
        for rootAxis: SplitAxis,
        at location: CGPoint,
        in rect: CGRect
    ) -> SplitDropSide? {
        guard rect.width > 0, rect.height > 0, rect.contains(location) else {
            return nil
        }

        let lowerBound: CGFloat = 1.0 / 3.0
        let upperBound: CGFloat = 2.0 / 3.0
        switch rootAxis {
        case .row:
            let normalizedY = (location.y - rect.minY) / rect.height
            guard normalizedY > lowerBound, normalizedY < upperBound else {
                return nil
            }
            return location.y >= rect.midY ? .top : .bottom
        case .column:
            let normalizedX = (location.x - rect.minX) / rect.width
            guard normalizedX > lowerBound, normalizedX < upperBound else {
                return nil
            }
            return location.x >= rect.midX ? .right : .left
        }
    }

    static func halfRect(for side: SplitDropSide, in rect: CGRect) -> CGRect {
        switch side {
        case .left:
            return CGRect(
                x: rect.minX,
                y: rect.minY,
                width: rect.width / 2,
                height: rect.height
            )
        case .right:
            return CGRect(
                x: rect.midX,
                y: rect.minY,
                width: rect.width / 2,
                height: rect.height
            )
        case .top:
            return CGRect(
                x: rect.minX,
                y: rect.midY,
                width: rect.width,
                height: rect.height / 2
            )
        case .bottom:
            return CGRect(
                x: rect.minX,
                y: rect.minY,
                width: rect.width,
                height: rect.height / 2
            )
        case .center:
            return rect
        }
    }

    static func planesContainingLocation(
        in tree: SplitLayoutTree,
        location: CGPoint,
        bounds: CGRect
    ) -> [SplitLayoutGeometry.TilePlane] {
        SplitLayoutGeometry.tilePlanes(
            in: tree,
            rect: bounds,
            includeChildPlanes: SplitLayoutGeometry.hasSecondaryPlane(in: tree)
        )
        .filter { $0.rect.contains(location) }
        .sorted { lhs, rhs in
            if lhs.path.count != rhs.path.count {
                return lhs.path.count > rhs.path.count
            }
            return lhs.rect.width * lhs.rect.height < rhs.rect.width * rhs.rect.height
        }
    }

    static func firstSplitPreviewRect(
        currentTabId: UUID,
        previewTabId: UUID,
        side: SplitDropSide,
        bounds: CGRect
    ) -> CGRect? {
        let previewTree = SplitLayoutTree.leaf(tabId: currentTabId, size: 1)
            .insertingAtRoot(tabId: previewTabId, side: side)
        return SplitLayoutGeometry.leafRect(
            for: previewTabId,
            in: previewTree,
            rect: bounds
        )
    }
}
