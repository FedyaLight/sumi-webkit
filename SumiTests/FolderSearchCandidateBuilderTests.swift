@testable import Sumi
import SwiftUI
import XCTest

@MainActor
final class FolderSearchCandidateBuilderTests: XCTestCase {
    func testCandidatesFollowVisualOrderRecurseIntoNestedFoldersAndExcludeVisibleCollapsedProjection() throws {
        let tabManager = try makeInMemoryTabManager()
        let liveProvider = FakeFolderSearchLiveProvider()
        let space = Space(name: "Work")
        let root = TabFolder(name: "Root", spaceId: space.id, index: 0)
        let nested = TabFolder(name: "Nested", spaceId: space.id, parentFolderId: root.id, index: 1)
        let visible = try makePin(title: "Visible", folderId: root.id, spaceId: space.id, index: 0)
        let direct = try makePin(title: "Direct", folderId: root.id, spaceId: space.id, index: 1)
        let nestedPin = try makePin(title: "Nested Docs", folderId: nested.id, spaceId: space.id, index: 0)

        tabManager.folderCollectionStateOwner.replaceFoldersBySpace([
            space.id: [root, nested],
        ])
        tabManager.shortcutPinCollectionStateOwner.replaceSpacePinnedShortcuts([
            space.id: [visible, direct, nestedPin],
        ])

        let candidates = makeBuilder(tabManager: tabManager, liveProvider: liveProvider).candidates(
            for: root,
            in: space,
            excludingVisibleCollapsedProjectionIDs: [visible.id]
        )

        XCTAssertEqual(
            candidates.map(\.kind),
            [
                .shortcut(nestedPin.id),
                .shortcut(direct.id),
            ]
        )
        XCTAssertTrue(candidates[0].secondaryText.contains("Nested"))
        XCTAssertTrue(candidates[0].searchText.contains("nested"))
    }

    func testLiveFolderUsesVisibleItemSnapshot() throws {
        let tabManager = try makeInMemoryTabManager()
        let liveProvider = FakeFolderSearchLiveProvider()
        let space = Space(name: "Work")
        let folder = TabFolder(name: "Feed", spaceId: space.id)
        let source = SumiLiveFolderSource(
            folderId: folder.id,
            spaceId: space.id,
            profileId: nil,
            kind: .rss,
            title: "Feed",
            urlString: "https://example.com/feed.xml"
        )
        let item = SumiLiveFolderItem(
            id: "entry-1",
            sourceId: source.id,
            title: "Release Notes",
            urlString: "https://example.com/releases",
            subtitle: "Example",
            publishedAt: nil,
            updatedAt: nil,
            sortDate: nil,
            stateBadge: nil,
            iconSystemName: "doc.text",
            firstSeenAt: Date(),
            lastSeenAt: Date()
        )
        liveProvider.sourcesByFolderId[folder.id] = source
        liveProvider.itemsByFolderId[folder.id] = [item]

        let candidates = makeBuilder(tabManager: tabManager, liveProvider: liveProvider).candidates(
            for: folder,
            in: space,
            excludingVisibleCollapsedProjectionIDs: []
        )

        XCTAssertEqual(candidates.map(\.kind), [.liveItem(folderId: folder.id, itemId: item.id)])
        XCTAssertEqual(candidates.first?.title, "Release Notes")
        XCTAssertTrue(candidates.first?.searchText.contains("releases") == true)
    }

    func testShortcutHostedSplitGroupMembersBecomeCandidates() throws {
        let tabManager = try makeInMemoryTabManager()
        let liveProvider = FakeFolderSearchLiveProvider()
        let space = Space(name: "Work")
        let folder = TabFolder(name: "Split Folder", spaceId: space.id)
        let first = try makePin(title: "First Pane", folderId: folder.id, spaceId: space.id, index: 0)
        let second = try makePin(title: "Second Pane", folderId: folder.id, spaceId: space.id, index: 1)
        let group = try XCTUnwrap(
            SplitGroup.make(
                tabIds: [first.id, second.id],
                layoutKind: .vertical,
                host: .shortcutPinned(spaceId: space.id, profileId: nil, index: first.index),
                members: [
                    SplitGroupMember(
                        tabId: first.id,
                        pinId: first.id,
                        origin: .spacePinned(spaceId: space.id, folderId: folder.id, index: first.index)
                    ),
                    SplitGroupMember(
                        tabId: second.id,
                        pinId: second.id,
                        origin: .spacePinned(spaceId: space.id, folderId: folder.id, index: second.index)
                    ),
                ]
            )
        )

        tabManager.folderCollectionStateOwner.replaceFoldersBySpace([
            space.id: [folder],
        ])
        tabManager.shortcutPinCollectionStateOwner.replaceSpacePinnedShortcuts([
            space.id: [first, second],
        ])
        tabManager.splitGroupCollectionStateOwner.replaceSplitGroups([group])

        let candidates = makeBuilder(tabManager: tabManager, liveProvider: liveProvider).candidates(
            for: folder,
            in: space,
            excludingVisibleCollapsedProjectionIDs: []
        )

        XCTAssertEqual(
            candidates.map(\.kind),
            [
                .splitGroupItem(groupId: group.id, itemId: first.id),
                .splitGroupItem(groupId: group.id, itemId: second.id),
            ]
        )
        XCTAssertEqual(candidates.map(\.title), ["First Pane", "Second Pane"])
    }

    func testSearchMatcherIsCaseAndDiacriticInsensitiveAcrossTitleHostAndURL() {
        let first = makeCandidate(
            id: "first",
            title: "Cafe Docs",
            components: ["Café Docs", "docs.example", "https://docs.example/cafe"]
        )
        let second = makeCandidate(
            id: "second",
            title: "Release Notes",
            components: ["Release Notes", "updates.example", "https://updates.example/releases"]
        )

        XCTAssertEqual(
            FolderSearchMatcher.filteredCandidates([first, second], query: "CAFÉ").map(\.id),
            ["first"]
        )
        XCTAssertEqual(
            FolderSearchMatcher.filteredCandidates([first, second], query: "updates.example").map(\.id),
            ["second"]
        )
        XCTAssertEqual(
            FolderSearchMatcher.filteredCandidates([first, second], query: "").map(\.id),
            ["first", "second"]
        )
    }

    func testFolderSearchPopoverTransientKindPinsSidebarAndBlocksDrag() {
        XCTAssertTrue(SidebarTransientUIKind.folderSearchPopover.pinsCollapsedSidebar)
        XCTAssertTrue(SidebarTransientUIKind.folderSearchPopover.blocksSidebarDragSources)
        XCTAssertFalse(SidebarTransientUIKind.folderSearchPopover.freezesSidebarHoverState)
    }

    private func makeBuilder(
        tabManager: TabManager,
        liveProvider: FolderSearchLiveFolderProviding
    ) -> FolderSearchCandidateBuilder {
        FolderSearchCandidateBuilder(
            tabManager: tabManager,
            liveFolderProvider: liveProvider,
            actions: FolderSearchActivationActions(
                activateShortcut: { _ in },
                activateLiveItem: { _ in },
                activateSplitGroupItem: { _, _ in }
            )
        )
    }

    private func makePin(
        title: String,
        folderId: UUID,
        spaceId: UUID,
        index: Int
    ) throws -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: spaceId,
            index: index,
            folderId: folderId,
            launchURL: try XCTUnwrap(URL(string: "https://example.com/\(title.replacingOccurrences(of: " ", with: "-"))")),
            title: title
        )
    }

    private func makeCandidate(
        id: String,
        title: String,
        components: [String]
    ) -> FolderSearchCandidate {
        FolderSearchCandidate(
            id: id,
            kind: .shortcut(UUID()),
            title: title,
            secondaryText: "",
            icon: Image(systemName: "link"),
            searchText: FolderSearchMatcher.searchText(components: components),
            activate: {}
        )
    }
}

private final class FakeFolderSearchLiveProvider: FolderSearchLiveFolderProviding {
    var sourcesByFolderId: [UUID: SumiLiveFolderSource] = [:]
    var itemsByFolderId: [UUID: [SumiLiveFolderItem]] = [:]

    func source(for folderId: UUID) -> SumiLiveFolderSource? {
        sourcesByFolderId[folderId]
    }

    func visibleItems(for folderId: UUID) -> [SumiLiveFolderItem] {
        itemsByFolderId[folderId] ?? []
    }
}
