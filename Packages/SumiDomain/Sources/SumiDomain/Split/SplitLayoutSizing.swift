import Foundation

/// Weight policy for split layouts. Normalization guarantees finite,
/// positive sibling weights with a unit sum.
public enum SplitLayoutSizing {
    private static let minimumRelativeWeight = 0.01

    public static func settingWeight(
        _ weight: Double,
        in tree: SplitLayoutTree
    ) -> SplitLayoutTree {
        switch tree {
        case .leaf(let member, _):
            return .leaf(member: member, weight: weight)
        case .split(let axis, _, let children):
            return .split(axis: axis, weight: weight, children: children)
        }
    }

    public static func normalizingSiblingWeights(
        in tree: SplitLayoutTree
    ) -> SplitLayoutTree {
        switch tree {
        case .leaf:
            return tree
        case .split(let axis, let weight, let children):
            let normalizedChildren = children.map(normalizingSiblingWeights)
            let weights = normalizedWeights(
                normalizedChildren.map(\.weightInParent)
            )
            let resized = zip(normalizedChildren, weights).map { child, weight in
                settingWeight(weight, in: child)
            }
            return .split(axis: axis, weight: weight, children: resized)
        }
    }

    public static func equalizingImmediateChildWeights(
        in tree: SplitLayoutTree
    ) -> SplitLayoutTree {
        switch tree {
        case .leaf:
            return tree
        case .split(let axis, let weight, let children):
            let equalWeight = children.isEmpty ? 1 : 1 / Double(children.count)
            return .split(
                axis: axis,
                weight: weight,
                children: children.map { settingWeight(equalWeight, in: $0) }
            )
        }
    }

    public static func equalizingAllSiblingWeights(
        in tree: SplitLayoutTree
    ) -> SplitLayoutTree {
        switch tree {
        case .leaf:
            return tree
        case .split(let axis, let weight, let children):
            let equalizedChildren = children.map(equalizingAllSiblingWeights)
            let equalWeight = equalizedChildren.isEmpty
                ? 1
                : 1 / Double(equalizedChildren.count)
            return .split(
                axis: axis,
                weight: weight,
                children: equalizedChildren.map {
                    settingWeight(equalWeight, in: $0)
                }
            )
        }
    }

    public static func updatingChildWeights(
        in tree: SplitLayoutTree,
        at path: [Int],
        weights: [Double]
    ) -> SplitLayoutTree {
        guard !path.isEmpty else {
            return applyingChildWeights(weights, to: tree)
        }
        guard case .split(let axis, let weight, let children) = tree else {
            return tree
        }
        var updated = children
        let index = path[0]
        guard updated.indices.contains(index) else { return tree }
        updated[index] = updatingChildWeights(
            in: updated[index],
            at: Array(path.dropFirst()),
            weights: weights
        )
        return .split(axis: axis, weight: weight, children: updated)
    }

    public static func normalizedWeights(_ values: [Double]) -> [Double] {
        let sanitized = values.map(sanitizedWeight)
        guard let scale = sanitized.max() else { return [] }
        let scaled = sanitized.map {
            max(minimumRelativeWeight, $0 / scale)
        }
        let total = scaled.reduce(0, +)
        return scaled.map { $0 / total }
    }

    public static func sanitizedWeight(_ value: Double) -> Double {
        value.isFinite
            ? max(minimumRelativeWeight, value)
            : minimumRelativeWeight
    }

    private static func applyingChildWeights(
        _ weights: [Double],
        to tree: SplitLayoutTree
    ) -> SplitLayoutTree {
        guard case .split(let axis, let weight, let children) = tree,
              weights.count == children.count else {
            return tree
        }
        let normalized = normalizedWeights(weights)
        let resized = zip(children, normalized).map { child, weight in
            settingWeight(weight, in: child)
        }
        return .split(axis: axis, weight: weight, children: resized)
    }
}
