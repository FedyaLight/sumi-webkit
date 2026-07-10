import Foundation

/// Ratio policy for the tree. Normalization entry points guarantee finite,
/// positive sibling weights with a unit sum, even for corrupt persisted input.
enum SplitLayoutSizing {
    private static let minimumRelativeWeight = 0.01

    static func settingSize(_ size: Double, in tree: SplitLayoutTree) -> SplitLayoutTree {
        switch tree {
        case .leaf(let tabId, _):
            return .leaf(tabId: tabId, size: size)
        case .split(let axis, _, let children):
            return .split(axis: axis, size: size, children: children)
        }
    }

    static func normalizingSiblingSizes(in tree: SplitLayoutTree) -> SplitLayoutTree {
        switch tree {
        case .leaf:
            return tree
        case .split(let axis, let size, let children):
            let normalizedChildren = children.map(normalizingSiblingSizes)
            let weights = normalizedWeights(
                normalizedChildren.map(\.sizeInParent)
            )
            let resized = zip(normalizedChildren, weights).map { child, weight in
                settingSize(weight, in: child)
            }
            return .split(axis: axis, size: size, children: resized)
        }
    }

    static func equalizingImmediateChildSizes(in tree: SplitLayoutTree) -> SplitLayoutTree {
        switch tree {
        case .leaf:
            return tree
        case .split(let axis, let size, let children):
            let equalSize = children.isEmpty ? 1 : 1 / Double(children.count)
            return .split(
                axis: axis,
                size: size,
                children: children.map { settingSize(equalSize, in: $0) }
            )
        }
    }

    static func equalizingStructuralDropSizes(in tree: SplitLayoutTree) -> SplitLayoutTree {
        switch tree {
        case .leaf:
            return tree
        case .split(let axis, let size, let children):
            let equalizedChildren = children.map(equalizingStructuralDropSizes)
            let equalSize = equalizedChildren.isEmpty ? 1 : 1 / Double(equalizedChildren.count)
            return .split(
                axis: axis,
                size: size,
                children: equalizedChildren.map { settingSize(equalSize, in: $0) }
            )
        }
    }

    static func updatingChildSizes(
        in tree: SplitLayoutTree,
        at path: [Int],
        sizes: [Double]
    ) -> SplitLayoutTree {
        guard !path.isEmpty else {
            return applyingChildSizes(sizes, to: tree)
        }
        guard case .split(let axis, let size, let children) = tree else {
            return tree
        }
        var updated = children
        let index = path[0]
        guard updated.indices.contains(index) else { return tree }
        updated[index] = updatingChildSizes(
            in: updated[index],
            at: Array(path.dropFirst()),
            sizes: sizes
        )
        return .split(axis: axis, size: size, children: updated)
    }

    private static func applyingChildSizes(
        _ sizes: [Double],
        to tree: SplitLayoutTree
    ) -> SplitLayoutTree {
        guard case .split(let axis, let size, let children) = tree,
              sizes.count == children.count
        else {
            return tree
        }
        let weights = normalizedWeights(sizes)
        let resized = zip(children, weights).map { child, weight in
            settingSize(weight, in: child)
        }
        return .split(axis: axis, size: size, children: resized)
    }

    static func normalizedWeights(_ values: [Double]) -> [Double] {
        let sanitized = values.map(sanitizedWeight)
        guard let scale = sanitized.max() else { return [] }
        let scaled = sanitized.map {
            max(minimumRelativeWeight, $0 / scale)
        }
        let total = scaled.reduce(0, +)
        return scaled.map { $0 / total }
    }

    static func sanitizedWeight(_ value: Double) -> Double {
        value.isFinite ? max(minimumRelativeWeight, value) : minimumRelativeWeight
    }
}
