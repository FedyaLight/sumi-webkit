import SwiftData
import XCTest

@testable import Sumi

@MainActor
class SplitGroupTestCase: XCTestCase {
    func assertSplit(
        _ tree: SplitLayoutTree,
        axis expectedAxis: SplitAxis,
        tabIds expectedTabIds: [UUID],
        childCount expectedChildCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .split(let axis, _, let children) = tree else {
            return XCTFail("Expected split tree.", file: file, line: line)
        }
        XCTAssertEqual(axis, expectedAxis, file: file, line: line)
        XCTAssertEqual(children.flatMap(\.tabIds), expectedTabIds, file: file, line: line)
        XCTAssertEqual(children.count, expectedChildCount, file: file, line: line)
    }

    func assertImmediateChildSizes(
        _ tree: SplitLayoutTree,
        _ expectedSizes: [Double],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .split(_, _, let children) = tree else {
            return XCTFail("Expected split tree.", file: file, line: line)
        }
        XCTAssertEqual(children.count, expectedSizes.count, file: file, line: line)
        for (actual, expected) in zip(children.map(\.sizeInParent), expectedSizes) {
            XCTAssertEqual(actual, expected, accuracy: 0.0001, file: file, line: line)
        }
    }

    func canonicalFourPaneTopologies(ids: [UUID]) -> [(String, SplitLayoutTree)] {
        let row = SplitAxis.row
        let column = SplitAxis.column

        func equalLeaves(_ axis: SplitAxis, _ ids: ArraySlice<UUID>, size: Double) -> SplitLayoutTree {
            SplitLayoutTree.split(
                axis: axis,
                size: size,
                children: ids.map { .leaf(tabId: $0, size: 1 / Double(ids.count)) }
            )
        }

        var topologies: [(String, SplitLayoutTree)] = [
            (
                "4v",
                .split(axis: row, size: 1, children: ids.map { .leaf(tabId: $0, size: 0.25) })
            ),
            (
                "4h",
                .split(axis: column, size: 1, children: ids.map { .leaf(tabId: $0, size: 0.25) })
            ),
        ]

        for rootAxis in [row, column] {
            let childAxis = rootAxis == row ? column : row
            let rootName = rootAxis == row ? "v" : "h"
            let childName = childAxis == row ? "v" : "h"
            topologies.append(
                (
                    "2\(childName)+2\(childName)-root-\(rootName)",
                    .split(
                        axis: rootAxis,
                        size: 1,
                        children: [
                            equalLeaves(childAxis, ids[0..<2], size: 0.5),
                            equalLeaves(childAxis, ids[2..<4], size: 0.5),
                        ]
                    )
                )
            )
            topologies.append(
                (
                    "3\(childName)+1\(rootName)",
                    .split(
                        axis: rootAxis,
                        size: 1,
                        children: [
                            equalLeaves(childAxis, ids[0..<3], size: 0.5),
                            .leaf(tabId: ids[3], size: 0.5),
                        ]
                    )
                )
            )
            topologies.append(
                (
                    "1\(rootName)+3\(childName)",
                    .split(
                        axis: rootAxis,
                        size: 1,
                        children: [
                            .leaf(tabId: ids[0], size: 0.5),
                            equalLeaves(childAxis, ids[1..<4], size: 0.5),
                        ]
                    )
                )
            )

            for splitIndex in 0..<3 {
                var cursor = 0
                let children = (0..<3).map { index -> SplitLayoutTree in
                    if index == splitIndex {
                        let split = equalLeaves(childAxis, ids[cursor..<cursor + 2], size: 1.0 / 3.0)
                        cursor += 2
                        return split
                    }
                    let leaf = SplitLayoutTree.leaf(tabId: ids[cursor], size: 1.0 / 3.0)
                    cursor += 1
                    return leaf
                }
                topologies.append(
                    (
                        "1+2+1-root-\(rootName)-split-\(splitIndex)",
                        .split(axis: rootAxis, size: 1, children: children)
                    )
                )
            }
        }

        return topologies
    }

    func assertZenCanonicalTree(
        _ tree: SplitLayoutTree,
        _ context: String,
        parentAxis: SplitAxis? = nil,
        depth: Int = 0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch tree {
        case .leaf:
            XCTAssertLessThanOrEqual(depth, 2, context, file: file, line: line)
        case .split(let axis, _, let children):
            XCTAssertLessThanOrEqual(depth, 1, context, file: file, line: line)
            XCTAssertGreaterThanOrEqual(children.count, 2, context, file: file, line: line)
            XCTAssertLessThanOrEqual(children.count, SplitGroup.maximumTabs, context, file: file, line: line)
            if let parentAxis {
                XCTAssertNotEqual(axis, parentAxis, "Same-axis nesting should be flattened: \(context)", file: file, line: line)
            }
            XCTAssertLessThanOrEqual(tree.tabIds.count, SplitGroup.maximumTabs, context, file: file, line: line)
            XCTAssertEqual(Set(tree.tabIds).count, tree.tabIds.count, context, file: file, line: line)
            for child in children {
                assertZenCanonicalTree(
                    child,
                    context,
                    parentAxis: axis,
                    depth: depth + 1,
                    file: file,
                    line: line
                )
            }
        }
    }

    func assertEqualChildSizesRecursively(
        _ tree: SplitLayoutTree,
        _ context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .split(_, _, let children) = tree else { return }
        let expectedSize = 1 / Double(children.count)
        for child in children {
            XCTAssertEqual(child.sizeInParent, expectedSize, accuracy: 0.0001, context, file: file, line: line)
            assertEqualChildSizesRecursively(child, context, file: file, line: line)
        }
    }

    func assertRectEqual(
        _ actual: CGRect,
        _ expected: CGRect,
        _ context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.origin.x, expected.origin.x, accuracy: 0.0001, context, file: file, line: line)
        XCTAssertEqual(actual.origin.y, expected.origin.y, accuracy: 0.0001, context, file: file, line: line)
        XCTAssertEqual(actual.size.width, expected.size.width, accuracy: 0.0001, context, file: file, line: line)
        XCTAssertEqual(actual.size.height, expected.size.height, accuracy: 0.0001, context, file: file, line: line)
    }

    func assertRectContained(
        _ rect: CGRect,
        in container: CGRect,
        _ context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertGreaterThanOrEqual(rect.minX, container.minX - 0.0001, context, file: file, line: line)
        XCTAssertGreaterThanOrEqual(rect.minY, container.minY - 0.0001, context, file: file, line: line)
        XCTAssertLessThanOrEqual(rect.maxX, container.maxX + 0.0001, context, file: file, line: line)
        XCTAssertLessThanOrEqual(rect.maxY, container.maxY + 0.0001, context, file: file, line: line)
    }

    func localHalfRect(for side: SplitDropSide, in rect: CGRect) -> CGRect {
        switch side {
        case .left:
            return CGRect(x: rect.minX, y: rect.minY, width: rect.width / 2, height: rect.height)
        case .right:
            return CGRect(x: rect.midX, y: rect.minY, width: rect.width / 2, height: rect.height)
        case .top:
            return CGRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2)
        case .bottom:
            return CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height / 2)
        case .center:
            return rect
        }
    }

    func makeHarness() throws -> SplitGroupTestHarness {
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let browserManager = BrowserManager()
        let tabManager = TabManager(
            runtimeContext: .live(browserManager: browserManager),
            context: container.mainContext,
            loadPersistedState: false
        )
        let windowRegistry = WindowRegistry()
        let windowState = BrowserWindowState()
        windowState.tabManager = tabManager
        browserManager.tabManager = tabManager
        browserManager.webViewCoordinator = WebViewCoordinator()
        browserManager.windowRegistry = windowRegistry
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)
        return SplitGroupTestHarness(
            browserManager: browserManager,
            tabManager: tabManager,
            windowRegistry: windowRegistry,
            windowState: windowState
        )
    }

    func configure(
        _ captureView: SplitDropCaptureView,
        harness: SplitGroupTestHarness
    ) {
        captureView.configure(
            runtime: SplitDropCaptureRuntime(
                splitManager: harness.browserManager.splitManager,
                sidebarDragState: SidebarDragState(),
                windowState: { [weak windowRegistry = harness.windowRegistry] windowId in
                    windowRegistry?.windows[windowId]
                },
                resolveDragTab: { [weak tabManager = harness.tabManager] tabId in
                    tabManager?.sidebarDragRoutingOwner.resolveDragTab(for: tabId)
                }
            ),
            windowId: harness.windowState.id
        )
    }

    func makeSpacePin(spaceId: UUID, index: Int, title: String) -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            profileId: nil,
            spaceId: spaceId,
            index: index,
            folderId: nil,
            launchURL: URL(string: "https://\(title.lowercased()).example")!,
            title: title
        )
    }

    func makeEssentialPin(profileId: UUID, index: Int, title: String) -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: profileId,
            spaceId: nil,
            index: index,
            folderId: nil,
            launchURL: URL(string: "https://\(title.lowercased()).example")!,
            title: title
        )
    }

    func makeIDs(_ count: Int) -> [UUID] {
        (0..<count).map { _ in UUID() }
    }

    func edgePoint(for side: SplitDropSide, in rect: CGRect) -> CGPoint {
        switch side {
        case .left:
            return CGPoint(x: rect.minX + 4, y: rect.midY)
        case .right:
            return CGPoint(x: rect.maxX - 4, y: rect.midY)
        case .top:
            return CGPoint(x: rect.midX, y: rect.maxY - 4)
        case .bottom:
            return CGPoint(x: rect.midX, y: rect.minY + 4)
        case .center:
            return CGPoint(x: rect.midX, y: rect.midY)
        }
    }

    func isSameSlotNoOp(
        in tree: SplitLayoutTree,
        draggedTabId: UUID,
        targetTabId: UUID,
        side: SplitDropSide
    ) -> Bool {
        guard let axis = side.insertionAxis else { return false }
        return isSameSlotNoOp(
            in: tree,
            draggedTabId: draggedTabId,
            targetTabId: targetTabId,
            axis: axis,
            insertBefore: side == .left || side == .top
        )
    }

    func isSameSlotNoOp(
        in tree: SplitLayoutTree,
        draggedTabId: UUID,
        targetTabId: UUID,
        axis expectedAxis: SplitAxis,
        insertBefore: Bool
    ) -> Bool {
        switch tree {
        case .leaf:
            return false
        case .split(let axis, _, let children):
            if axis == expectedAxis {
                let childIds = children.map(\.tabIds)
                guard let draggedIndex = childIds.firstIndex(where: { $0 == [draggedTabId] }),
                      let targetIndex = childIds.firstIndex(where: { $0 == [targetTabId] })
                else {
                    return children.contains {
                        isSameSlotNoOp(
                            in: $0,
                            draggedTabId: draggedTabId,
                            targetTabId: targetTabId,
                            axis: expectedAxis,
                            insertBefore: insertBefore
                        )
                    }
                }
                return insertBefore
                    ? draggedIndex + 1 == targetIndex
                    : draggedIndex == targetIndex + 1
            }
            return children.contains {
                isSameSlotNoOp(
                    in: $0,
                    draggedTabId: draggedTabId,
                    targetTabId: targetTabId,
                    axis: expectedAxis,
                    insertBefore: insertBefore
                )
            }
        }
    }
}

extension SplitDropTarget {
    var usesPaneLocalPreview: Bool {
        switch intent {
        case .flatThreePair, .flatFourPair, .mixedThreeOnePair, .fullGroupPanePair:
            return true
        case .firstSplit, .rootEdge, .planeEdge, .siblingEdge, .flatFourReorder, .paneCenter:
            return false
        }
    }
}

@MainActor
struct SplitGroupTestHarness {
    let browserManager: BrowserManager
    let tabManager: TabManager
    let windowRegistry: WindowRegistry
    let windowState: BrowserWindowState
}
