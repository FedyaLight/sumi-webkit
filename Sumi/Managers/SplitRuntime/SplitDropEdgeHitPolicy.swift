import CoreGraphics
import SumiDomain

enum SplitDropEdgeHitPolicy {
    enum Mode {
        case create
        case rearrange
    }

    static let edgeZoneFraction: CGFloat = 0.25

    static func sides(
        at location: CGPoint,
        in bounds: CGRect,
        mode: Mode
    ) -> [SplitDropSide] {
        guard bounds.width > 0,
              bounds.height > 0,
              bounds.contains(location) else {
            return []
        }

        let distanceLeft = location.x - bounds.minX
        let distanceRight = bounds.maxX - location.x
        let distanceBottom = location.y - bounds.minY
        let distanceTop = bounds.maxY - location.y
        let horizontalThreshold = bounds.width * edgeZoneFraction
        let verticalThreshold = bounds.height * edgeZoneFraction

        var matchingEdges: [(side: SplitDropSide, distance: CGFloat)] = []
        if distanceLeft <= horizontalThreshold {
            matchingEdges.append((.left, distanceLeft))
        }
        if distanceRight <= horizontalThreshold {
            matchingEdges.append((.right, distanceRight))
        }
        if distanceTop <= verticalThreshold {
            matchingEdges.append((.top, distanceTop))
        }
        if distanceBottom <= verticalThreshold {
            matchingEdges.append((.bottom, distanceBottom))
        }

        if matchingEdges.isEmpty, mode == .rearrange {
            return [.center]
        }

        return matchingEdges
            .sorted { $0.distance < $1.distance }
            .map(\.side)
    }

    static func side(
        at location: CGPoint,
        in bounds: CGRect,
        mode: Mode
    ) -> SplitDropSide? {
        sides(at: location, in: bounds, mode: mode).first
    }
}
