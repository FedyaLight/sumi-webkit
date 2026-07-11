import XCTest

@testable import Sumi
import SumiDomain

@MainActor
final class RegularSplitSegmentResolverTests: XCTestCase {
    private func makeSpace() -> Space {
        Space(name: "Work")
    }

    private func makeTab(
        name: String = "Tab",
        shortcutPinID: UUID? = nil
    ) -> Tab {
        let tab = Tab(
            url: URL(string: "https://example.com")!,
            name: name,
            favicon: "globe"
        )
        tab.shortcutPinId = shortcutPinID
        return tab
    }

    private func makePin(
        id: UUID = UUID(),
        role: ShortcutPinRole = .spacePinned,
        spaceID: UUID? = nil,
        folderID: UUID? = nil
    ) -> ShortcutPin {
        ShortcutPin(
            id: id,
            role: role,
            spaceId: spaceID,
            index: 0,
            folderId: folderID,
            launchURL: URL(string: "https://example.com/pin")!,
            title: "Pin"
        )
    }

    private func regularGroup(
        _ tabs: [Tab],
        shortcut: (pinID: UUID, spaceID: UUID, liveTab: Tab)? = nil
    ) throws -> SplitGroup {
        var members = tabs.map { SplitMember.regularTab($0.id) }
        if let shortcut {
            members.append(
                .shortcutPin(
                    shortcut.pinID,
                    returnPlacement: .spacePinned(
                        spaceId: shortcut.spaceID,
                        folderId: nil,
                        index: 0
                    )
                )
            )
        }
        return try XCTUnwrap(
            SplitGroup.make(
                members: members,
                layoutKind: .vertical,
                container: .regularTabs(spaceId: tabs.first?.spaceId)
            )
        )
    }

    func testVisibleSplitGroupsReturnsEmptyWhileDragging() throws {
        let space = makeSpace()
        let resolver = RegularSplitSegmentResolver(
            space: space,
            isInteractive: true
        )
        let tabA = makeTab()
        let tabB = makeTab()
        let group = try regularGroup([tabA, tabB])

        XCTAssertTrue(
            resolver.visibleSplitGroups(
                currentTabs: [tabA, tabB],
                isDragging: true,
                splitGroup: { _ in group }
            ).isEmpty
        )
    }

    func testVisibleSplitGroupsExcludesShortcutSidebarGroups() throws {
        let space = makeSpace()
        let resolver = RegularSplitSegmentResolver(
            space: space,
            isInteractive: true
        )
        let firstPinID = UUID()
        let secondPinID = UUID()
        let group = try XCTUnwrap(
            SplitGroup.make(
                members: [
                    .shortcutPin(
                        firstPinID,
                        returnPlacement: .spacePinned(
                            spaceId: space.id,
                            folderId: nil,
                            index: 0
                        )
                    ),
                    .shortcutPin(
                        secondPinID,
                        returnPlacement: .spacePinned(
                            spaceId: space.id,
                            folderId: nil,
                            index: 1
                        )
                    ),
                ],
                layoutKind: .vertical,
                container: .shortcutSidebar(
                    spaceId: space.id,
                    profileId: nil,
                    folderId: nil,
                    index: 0
                )
            )
        )

        XCTAssertTrue(
            resolver.visibleSplitGroups(
                currentTabs: [makeTab(), makeTab()],
                isDragging: false,
                splitGroup: { _ in group }
            ).isEmpty
        )
    }

    func testVisibleSplitGroupsDeduplicatesByDurableGroupID() throws {
        let space = makeSpace()
        let resolver = RegularSplitSegmentResolver(
            space: space,
            isInteractive: true
        )
        let tabA = makeTab()
        let tabB = makeTab()
        let group = try regularGroup([tabA, tabB])

        let result = resolver.visibleSplitGroups(
            currentTabs: [tabA, tabB],
            isDragging: false,
            splitGroup: { _ in group }
        )

        XCTAssertEqual(result.map(\.id), [group.id])
    }

    func testSplitGroupItemsKeepShortcutPinIdentityWhenLiveTabExists() throws {
        let space = makeSpace()
        let resolver = RegularSplitSegmentResolver(
            space: space,
            isInteractive: true
        )
        let regularTab = makeTab(name: "Regular")
        let pinID = UUID()
        let liveTab = makeTab(name: "Live", shortcutPinID: pinID)
        let pin = makePin(id: pinID)
        let group = try regularGroup(
            [regularTab],
            shortcut: (pinID, space.id, liveTab)
        )

        let items = resolver.splitGroupItems(
            for: group,
            tabByID: [regularTab.id: regularTab],
            regularTab: { _ in nil },
            shortcutLiveTab: { $0 == pinID ? liveTab : nil },
            shortcutPin: { $0 == pinID ? pin : nil }
        )

        XCTAssertEqual(
            items.map(\.id),
            [.regularTab(regularTab.id), .shortcutPin(pinID)]
        )
        XCTAssertEqual(items.last?.tab?.id, liveTab.id)
        XCTAssertNotEqual(items.last?.persistentID, liveTab.id)
    }

    func testActionsFollowTypedMemberKind() throws {
        let space = makeSpace()
        let resolver = RegularSplitSegmentResolver(
            space: space,
            isInteractive: true
        )
        let regularTab = makeTab()
        let pinID = UUID()
        let liveTab = makeTab(shortcutPinID: pinID)
        let pin = makePin(id: pinID)
        let group = try regularGroup(
            [regularTab],
            shortcut: (pinID, space.id, liveTab)
        )
        let regularItem = try XCTUnwrap(
            SplitGroupSidebarItem.regular(
                .regularTab(regularTab.id),
                tab: regularTab
            )
        )
        let shortcutItem = try XCTUnwrap(
            SplitGroupSidebarItem.shortcut(
                try XCTUnwrap(group.member(for: .shortcutPin(pinID))),
                pin: pin,
                liveTab: liveTab
            )
        )

        XCTAssertEqual(resolver.action(for: regularItem, in: group), .close)
        XCTAssertEqual(resolver.action(for: shortcutItem, in: group), .restore)
    }

    func testSourceZonesMatchLauncherPlacement() {
        let space = makeSpace()
        let resolver = RegularSplitSegmentResolver(
            space: space,
            isInteractive: true
        )
        let folderID = UUID()

        XCTAssertEqual(
            resolver.sourceZone(for: makePin(role: .essential)),
            .essentials
        )
        XCTAssertEqual(
            resolver.sourceZone(
                for: makePin(role: .spacePinned, folderID: folderID)
            ),
            .folder(folderID)
        )
        XCTAssertEqual(
            resolver.sourceZone(for: makePin(role: .spacePinned)),
            .spacePinned(space.id)
        )
    }

    func testDragPayloadCarriesTypedRegularMember() throws {
        let space = makeSpace()
        let resolver = RegularSplitSegmentResolver(
            space: space,
            isInteractive: true
        )
        let tab = makeTab()
        let group = try regularGroup([tab, makeTab()])
        let item = try XCTUnwrap(
            SplitGroupSidebarItem.regular(
                .regularTab(tab.id),
                tab: tab
            )
        )

        let source = resolver.dragSource(
            for: item,
            in: group,
            shortcutPin: { _ in nil },
            onActivateMember: {}
        )

        XCTAssertEqual(source?.sourceZone, .spaceRegular(space.id))
        XCTAssertEqual(source?.item.splitMemberID, .regularTab(tab.id))
        XCTAssertEqual(source?.item.splitGroupID, group.id)
    }

    func testShortcutDragPayloadUsesPinIDRatherThanLiveTabID() throws {
        let space = makeSpace()
        let resolver = RegularSplitSegmentResolver(
            space: space,
            isInteractive: true
        )
        let regularTab = makeTab()
        let pinID = UUID()
        let liveTab = makeTab(shortcutPinID: pinID)
        let pin = makePin(id: pinID, role: .essential)
        let group = try regularGroup(
            [regularTab],
            shortcut: (pinID, space.id, liveTab)
        )
        let item = try XCTUnwrap(
            SplitGroupSidebarItem.shortcut(
                try XCTUnwrap(group.member(for: .shortcutPin(pinID))),
                pin: pin,
                liveTab: liveTab
            )
        )

        let source = resolver.dragSource(
            for: item,
            in: group,
            shortcutPin: { $0 == pinID ? pin : nil },
            onActivateMember: {}
        )

        XCTAssertEqual(source?.sourceZone, .essentials)
        XCTAssertEqual(source?.item.tabId, pinID)
        XCTAssertEqual(source?.item.splitMemberID, .shortcutPin(pinID))
        XCTAssertNotEqual(source?.item.tabId, liveTab.id)
    }
}
