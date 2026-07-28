@testable import Sumi
import XCTest

@MainActor
final class SidebarInventoryDescendantItemsTests: XCTestCase {
    private let rootFolder = UUID()
    private let nestedFolder = UUID()
    private let deepFolder = UUID()
    private let pinA = UUID()
    private let pinB = UUID()
    private let nestedPin = UUID()
    private let deepPin = UUID()
    private let splitGroup = UUID()

    private func makeSnapshot(
        spaceID: UUID = UUID(),
        folderItemsByFolderID: [UUID: [SidebarPinnedInventoryItem]]
    ) -> SidebarSpaceInventorySnapshot {
        SidebarSpaceInventorySnapshot(
            spaceID: spaceID,
            regularTabs: [],
            topLevelItems: [],
            topLevelFolders: [],
            topLevelPins: [],
            childFoldersByParentID: [:],
            folderPinsByFolderID: [:],
            folderItemsByFolderID: folderItemsByFolderID,
            foldersByID: [:],
            folderPresentationsByID: [:],
            pinsByID: [:],
            tabsByID: [:],
            splitGroupsByID: [:]
        )
    }

    func testStructuralSnapshotEqualityRejectsOnlyChangedStructure() {
        let spaceID = UUID()
        let items: [UUID: [SidebarPinnedInventoryItem]] = [
            rootFolder: [.shortcut(pinA)],
        ]

        XCTAssertEqual(
            makeSnapshot(
                spaceID: spaceID,
                folderItemsByFolderID: items
            ),
            makeSnapshot(
                spaceID: spaceID,
                folderItemsByFolderID: items
            )
        )
        XCTAssertNotEqual(
            makeSnapshot(
                spaceID: spaceID,
                folderItemsByFolderID: items
            ),
            makeSnapshot(
                spaceID: spaceID,
                folderItemsByFolderID: [
                    rootFolder: [.shortcut(pinB)],
                ]
            )
        )
    }

    func testDescendantsFollowDepthFirstPositionalOrderAndIncludeSplitGroups() {
        let snapshot = makeSnapshot(folderItemsByFolderID: [
            rootFolder: [.shortcut(pinA), .folder(nestedFolder), .splitGroup(splitGroup), .shortcut(pinB)],
            nestedFolder: [.shortcut(nestedPin), .folder(deepFolder)],
            deepFolder: [.shortcut(deepPin)],
        ])

        XCTAssertEqual(
            snapshot.descendantItems(for: rootFolder),
            [.shortcut(pinA), .shortcut(nestedPin), .shortcut(deepPin), .splitGroup(splitGroup), .shortcut(pinB)]
        )
        XCTAssertEqual(
            snapshot.orderedDescendantItemIDs(for: rootFolder),
            [pinA, nestedPin, deepPin, splitGroup, pinB]
        )
        XCTAssertEqual(
            snapshot.orderedDescendantItemIDs(for: nestedFolder),
            [nestedPin, deepPin]
        )
    }

    func testDescendantWalkSurvivesFolderCycles() {
        let snapshot = makeSnapshot(folderItemsByFolderID: [
            rootFolder: [.shortcut(pinA), .folder(nestedFolder)],
            nestedFolder: [.shortcut(nestedPin), .folder(rootFolder)],
        ])

        XCTAssertEqual(
            snapshot.orderedDescendantItemIDs(for: rootFolder),
            [pinA, nestedPin]
        )
    }
}
