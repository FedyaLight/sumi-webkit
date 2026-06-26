import AppKit
import XCTest

@testable import Sumi

@MainActor
final class TabStructuralSnapshotMaterializerTests: XCTestCase {
    func testMaterializesDeltaWithOrderedSnapshotsAndNonPersistableDeletes() throws {
        let materializer = TabStructuralSnapshotMaterializer()

        let profileId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let otherProfileId = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let firstSpace = Space(id: UUID(), name: "First", icon: "square.grid.2x2", profileId: profileId)
        let secondSpace = Space(id: UUID(), name: "Second", icon: "globe", profileId: otherProfileId)
        let currentTabId = UUID()

        let persistedTab = makeTab(
            id: currentTabId,
            urlString: "https://example.com/keep",
            spaceId: secondSpace.id,
            index: 2,
            profileId: otherProfileId
        )
        persistedTab.folderId = UUID()
        persistedTab.canGoBack = true

        let nonPersistedTab = makeTab(
            urlString: "webkit-extension://extension-id/app.html",
            spaceId: secondSpace.id,
            index: 3,
            profileId: otherProfileId
        )
        let untouchedTab = makeTab(
            urlString: "https://example.com/untouched",
            spaceId: firstSpace.id,
            index: 0,
            profileId: profileId
        )

        let firstPin = try makePin(
            id: UUID(),
            role: .essential,
            profileId: profileId,
            index: 1,
            urlString: "https://example.com/essential-b",
            title: "Essential B"
        )
        let secondPin = try makePin(
            id: UUID(),
            role: .essential,
            profileId: profileId,
            index: 0,
            urlString: "https://example.com/essential-a",
            title: "Essential A"
        )
        let spacePin = try makePin(
            id: UUID(),
            role: .spacePinned,
            executionProfileId: otherProfileId,
            spaceId: secondSpace.id,
            index: 0,
            folderId: persistedTab.folderId,
            urlString: "https://example.com/space-pin",
            title: "Space Pin",
            iconAsset: "zen:book"
        )

        let folder = TabFolder(
            id: UUID(),
            name: "Docs",
            spaceId: secondSpace.id,
            parentFolderId: nil,
            icon: "zen:book",
            color: try XCTUnwrap(NSColor(hex: "#123456")),
            index: 0
        )
        folder.isOpen = true

        let splitGroup = try XCTUnwrap(
            SplitGroup.make(
                tabIds: [persistedTab.id, spacePin.id],
                layoutKind: .vertical,
                activeTabId: persistedTab.id
            )
        )

        var dirtySet = TabStructuralDirtySet()
        dirtySet.markSpacesDirty([secondSpace.id])
        dirtySet.markTabsDirty([persistedTab.id, nonPersistedTab.id, secondPin.id, firstPin.id, spacePin.id])
        dirtySet.markFoldersDirty([folder.id])
        dirtySet.markTabsDeleted([UUID()])
        dirtySet.markSplitGroupsDirty()

        let delta = materializer.makeStructuralDelta(
            from: dirtySet,
            spaces: [firstSpace, secondSpace],
            pinnedByProfile: [profileId: [firstPin, secondPin]],
            spacePinnedShortcuts: [secondSpace.id: [spacePin]],
            tabsBySpace: [
                firstSpace.id: [untouchedTab],
                secondSpace.id: [persistedTab, nonPersistedTab]
            ],
            foldersBySpace: [secondSpace.id: [folder]],
            splitGroups: [splitGroup],
            currentTabId: persistedTab.id,
            currentSpaceId: secondSpace.id,
            shouldPersistRegularTab: { tab in
                tab.url.scheme != "webkit-extension"
            }
        )

        XCTAssertEqual(delta.spaces.map(\.id), [secondSpace.id])
        XCTAssertEqual(delta.tabs.map(\.id), [secondPin.id, firstPin.id, spacePin.id, persistedTab.id])
        XCTAssertEqual(delta.tabs.map(\.index), [0, 1, 0, 2])
        XCTAssertEqual(delta.tabs.first?.profileId, profileId)
        XCTAssertEqual(delta.tabs[2].spaceId, secondSpace.id)
        XCTAssertEqual(delta.tabs[2].folderId, persistedTab.folderId)
        XCTAssertEqual(delta.tabs[3].currentURLString, "https://example.com/keep")
        XCTAssertTrue(delta.tabs[3].canGoBack)
        XCTAssertEqual(delta.folders.map(\.id), [folder.id])
        XCTAssertEqual(delta.folders.first?.icon, "zen:book")
        XCTAssertEqual(delta.folders.first?.color, "#123456")
        XCTAssertEqual(delta.splitGroups, [splitGroup])
        XCTAssertTrue(delta.deletedTabIds.contains(nonPersistedTab.id))
        XCTAssertEqual(delta.state.currentTabID, persistedTab.id)
        XCTAssertEqual(delta.state.currentSpaceID, secondSpace.id)
    }

    private func makeTab(
        id: UUID = UUID(),
        urlString: String,
        spaceId: UUID,
        index: Int,
        profileId: UUID
    ) -> Tab {
        let tab = Tab(
            id: id,
            url: URL(string: urlString)!,
            name: "Tab \(index)",
            spaceId: spaceId,
            index: index,
            loadsCachedFaviconOnInit: false
        )
        tab.profileId = profileId
        return tab
    }

    private func makePin(
        id: UUID,
        role: ShortcutPinRole,
        profileId: UUID? = nil,
        executionProfileId: UUID? = nil,
        spaceId: UUID? = nil,
        index: Int,
        folderId: UUID? = nil,
        urlString: String,
        title: String,
        iconAsset: String? = nil
    ) throws -> ShortcutPin {
        ShortcutPin(
            id: id,
            role: role,
            profileId: profileId,
            executionProfileId: executionProfileId,
            spaceId: spaceId,
            index: index,
            folderId: folderId,
            launchURL: try XCTUnwrap(URL(string: urlString)),
            title: title,
            iconAsset: iconAsset
        )
    }
}
