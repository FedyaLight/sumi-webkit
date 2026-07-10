import Foundation

enum SplitLayoutFactory {
    static func make(kind: SplitLayoutKind, tabIds: [UUID]) -> SplitLayoutTree {
        let uniqueIds = uniqueSplitTabIdsPreservingOrder(tabIds).prefix(SplitGroup.maximumTabs)
        let ids = Array(uniqueIds)
        guard !ids.isEmpty else {
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

    static func equalSplit(axis: SplitAxis, tabIds: [UUID]) -> SplitLayoutTree {
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
            let columnIds = Array(tabIds[cursor..<cursor + take])
            let column = take == 1
                ? SplitLayoutTree.leaf(tabId: columnIds[0], size: 1)
                : equalSplit(axis: .column, tabIds: columnIds)
            columns.append(SplitLayoutSizing.settingSize(1, in: column))
            cursor += take
        }
        return SplitLayoutSizing.normalizingSiblingSizes(
            in: .split(axis: .row, size: 1, children: columns)
        )
    }
}
