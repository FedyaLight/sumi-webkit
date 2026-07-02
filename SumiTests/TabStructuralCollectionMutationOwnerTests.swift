import Foundation
@testable import Sumi
import XCTest

@MainActor
final class TabStructuralCollectionMutationOwnerTests: XCTestCase {
    func testSetTabsSortsAndRunsStructuralSideEffects() {
        let spaceId = UUID()
        let previousTab = Self.makeTab(index: 0)
        let laterTab = Self.makeTab(index: 2)
        let earlierTab = Self.makeTab(index: 1)
        let harness = Harness()
        harness.tabsBySpace[spaceId] = [previousTab]
        let owner = harness.makeOwner()

        owner.setTabs([laterTab, earlierTab], for: spaceId)

        XCTAssertEqual(harness.tabsBySpace[spaceId]?.map(\.id), [earlierTab.id, laterTab.id])
        XCTAssertEqual(harness.regularDirtySpaceIds, [spaceId])
        XCTAssertEqual(harness.regularChangeRecords.map { $0.previous.map(\.id) }, [[previousTab.id]])
        XCTAssertEqual(harness.regularChangeRecords.map { $0.current.map(\.id) }, [[earlierTab.id, laterTab.id]])
        XCTAssertEqual(harness.queuedLookupChanges.map { $0.previous.map(\.id) }, [[previousTab.id]])
        XCTAssertEqual(harness.queuedLookupChanges.map { $0.current.map(\.id) }, [[earlierTab.id, laterTab.id]])
        XCTAssertEqual(harness.publishCount, 1)
    }

    func testSetPinnedTabsSyncsAllShortcutCollectionsAndPublishes() {
        let profileId = UUID()
        let spaceId = UUID()
        let previousPin = Self.makePin(role: .essential, profileId: profileId, index: 0)
        let currentPin = Self.makePin(role: .essential, profileId: profileId, index: 1)
        let spacePin = Self.makePin(role: .spacePinned, spaceId: spaceId, index: 0)
        let harness = Harness()
        harness.pinnedByProfile[profileId] = [previousPin]
        harness.spacePinnedShortcuts[spaceId] = [spacePin]
        let owner = harness.makeOwner()

        owner.setPinnedTabs([currentPin], for: profileId)

        XCTAssertEqual(harness.pinnedByProfile[profileId]?.map(\.id), [currentPin.id])
        XCTAssertEqual(harness.syncedShortcutPinIds, [[currentPin.id, spacePin.id]])
        XCTAssertEqual(harness.pinnedDirtyProfileIds, [profileId])
        XCTAssertEqual(harness.shortcutPinChangeRecords.map { $0.previous.map(\.id) }, [[previousPin.id]])
        XCTAssertEqual(harness.shortcutPinChangeRecords.map { $0.current.map(\.id) }, [[currentPin.id]])
        XCTAssertEqual(harness.publishCount, 1)
    }

    func testSetFoldersRunsStructuralSideEffects() {
        let spaceId = UUID()
        let previousFolder = Self.makeFolder(name: "Previous", spaceId: spaceId, index: 0)
        let currentFolder = Self.makeFolder(name: "Current", spaceId: spaceId, index: 1)
        let harness = Harness()
        harness.foldersBySpace[spaceId] = [previousFolder]
        let owner = harness.makeOwner()

        owner.setFolders([currentFolder], for: spaceId)

        XCTAssertEqual(harness.foldersBySpace[spaceId]?.map(\.id), [currentFolder.id])
        XCTAssertEqual(harness.folderDirtySpaceIds, [spaceId])
        XCTAssertEqual(harness.folderChangeRecords.map { $0.previous.map(\.id) }, [[previousFolder.id]])
        XCTAssertEqual(harness.folderChangeRecords.map { $0.current.map(\.id) }, [[currentFolder.id]])
        XCTAssertEqual(harness.publishCount, 1)
    }

    func testSetSpacePinnedShortcutsSyncsAllShortcutCollectionsAndPublishes() {
        let profileId = UUID()
        let spaceId = UUID()
        let profilePin = Self.makePin(role: .essential, profileId: profileId, index: 0)
        let previousSpacePin = Self.makePin(role: .spacePinned, spaceId: spaceId, index: 0)
        let currentSpacePin = Self.makePin(role: .spacePinned, spaceId: spaceId, index: 1)
        let harness = Harness()
        harness.pinnedByProfile[profileId] = [profilePin]
        harness.spacePinnedShortcuts[spaceId] = [previousSpacePin]
        let owner = harness.makeOwner()

        owner.setSpacePinnedShortcuts([currentSpacePin], for: spaceId)

        XCTAssertEqual(harness.spacePinnedShortcuts[spaceId]?.map(\.id), [currentSpacePin.id])
        XCTAssertEqual(harness.syncedShortcutPinIds, [[profilePin.id, currentSpacePin.id]])
        XCTAssertEqual(harness.spacePinnedDirtySpaceIds, [spaceId])
        XCTAssertEqual(harness.shortcutPinChangeRecords.map { $0.previous.map(\.id) }, [[previousSpacePin.id]])
        XCTAssertEqual(harness.shortcutPinChangeRecords.map { $0.current.map(\.id) }, [[currentSpacePin.id]])
        XCTAssertEqual(harness.publishCount, 1)
    }

    private static func makeTab(index: Int) -> Tab {
        Tab(
            url: URL(string: "https://example.com/\(index)")!,
            name: "Tab \(index)",
            index: index,
            loadsCachedFaviconOnInit: false
        )
    }

    private static func makePin(
        role: ShortcutPinRole,
        profileId: UUID? = nil,
        spaceId: UUID? = nil,
        index: Int
    ) -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: role,
            profileId: profileId,
            spaceId: spaceId,
            index: index,
            launchURL: URL(string: "https://example.com/\(index)")!,
            title: "Pin \(index)"
        )
    }

    private static func makeFolder(name: String, spaceId: UUID, index: Int) -> TabFolder {
        TabFolder(name: name, spaceId: spaceId, index: index)
    }

    @MainActor
    private final class Harness {
        var tabsBySpace: [UUID: [Tab]] = [:]
        var foldersBySpace: [UUID: [TabFolder]] = [:]
        var pinnedByProfile: [UUID: [ShortcutPin]] = [:]
        var spacePinnedShortcuts: [UUID: [ShortcutPin]] = [:]
        var syncedShortcutPinIds: [[UUID]] = []
        var regularDirtySpaceIds: [UUID] = []
        var folderDirtySpaceIds: [UUID] = []
        var pinnedDirtyProfileIds: [UUID] = []
        var spacePinnedDirtySpaceIds: [UUID] = []
        var regularChangeRecords: [(previous: [Tab], current: [Tab])] = []
        var folderChangeRecords: [(previous: [TabFolder], current: [TabFolder])] = []
        var shortcutPinChangeRecords: [(previous: [ShortcutPin], current: [ShortcutPin])] = []
        var queuedLookupChanges: [(previous: [Tab], current: [Tab])] = []
        var publishCount = 0

        func makeOwner() -> TabStructuralCollectionMutationOwner {
            TabStructuralCollectionMutationOwner(
                dependencies: TabStructuralCollectionMutationOwner.Dependencies(
                    tabsBySpace: { self.tabsBySpace },
                    setTabsBySpace: { self.tabsBySpace = $0 },
                    foldersBySpace: { self.foldersBySpace },
                    setFoldersBySpace: { self.foldersBySpace = $0 },
                    pinnedByProfile: { self.pinnedByProfile },
                    setPinnedByProfile: { self.pinnedByProfile = $0 },
                    spacePinnedShortcuts: { self.spacePinnedShortcuts },
                    setSpacePinnedShortcuts: { self.spacePinnedShortcuts = $0 },
                    syncShortcutPins: { self.syncedShortcutPinIds.append($0.map(\.id)) },
                    markRegularTabsSnapshotDirty: { self.regularDirtySpaceIds.append($0) },
                    markFoldersSnapshotDirty: { self.folderDirtySpaceIds.append($0) },
                    markPinnedSnapshotDirty: { self.pinnedDirtyProfileIds.append($0) },
                    markSpacePinnedSnapshotDirty: { self.spacePinnedDirtySpaceIds.append($0) },
                    recordRegularTabsStructuralChange: {
                        self.regularChangeRecords.append((previous: $0, current: $1))
                    },
                    recordFoldersStructuralChange: {
                        self.folderChangeRecords.append((previous: $0, current: $1))
                    },
                    recordShortcutPinsStructuralChange: {
                        self.shortcutPinChangeRecords.append((previous: $0, current: $1))
                    },
                    queueTabLookupEntries: {
                        self.queuedLookupChanges.append((previous: $0, current: $1))
                    },
                    requestStructuralPublish: {
                        self.publishCount += 1
                    }
                )
            )
        }
    }
}
