//
//  RegularSplitSegmentResolverTests.swift
//  SumiTests
//

import XCTest

@testable import Sumi

@MainActor
final class RegularSplitSegmentResolverTests: XCTestCase {
    private func makeSpace() -> Space {
        Space(name: "Work")
    }

    private func makeTab(name: String = "Tab", shortcutPinId: UUID? = nil) -> Tab {
        let tab = Tab(url: URL(string: "https://example.com")!, name: name, favicon: "globe")
        tab.shortcutPinId = shortcutPinId
        return tab
    }

    private func makePin(
        id: UUID = UUID(),
        role: ShortcutPinRole = .spacePinned,
        spaceId: UUID? = nil,
        folderId: UUID? = nil
    ) -> ShortcutPin {
        ShortcutPin(
            id: id,
            role: role,
            spaceId: spaceId,
            index: 0,
            folderId: folderId,
            launchURL: URL(string: "https://example.com/pin")!,
            title: "Pin"
        )
    }

    // MARK: - visibleSplitGroups

    func testVisibleSplitGroupsReturnsEmptyWhileDragging() throws {
        let space = makeSpace()
        let resolver = RegularSplitSegmentResolver(space: space, isInteractive: true)
        let tabA = makeTab()
        let tabB = makeTab()
        let group = try XCTUnwrap(SplitGroup.make(tabIds: [tabA.id, tabB.id], layoutKind: .vertical))

        let result = resolver.visibleSplitGroups(
            currentTabs: [tabA, tabB],
            isDragging: true,
            splitGroup: { _ in group }
        )

        XCTAssertTrue(result.isEmpty)
    }

    func testVisibleSplitGroupsExcludesShortcutHostedGroups() throws {
        let space = makeSpace()
        let resolver = RegularSplitSegmentResolver(space: space, isInteractive: true)
        let tabA = makeTab()
        let tabB = makeTab()
        let group = try XCTUnwrap(SplitGroup.make(
            tabIds: [tabA.id, tabB.id],
            layoutKind: .vertical,
            host: .shortcutPinned(spaceId: space.id, profileId: nil, index: nil)
        ))

        let result = resolver.visibleSplitGroups(
            currentTabs: [tabA, tabB],
            isDragging: false,
            splitGroup: { _ in group }
        )

        XCTAssertTrue(result.isEmpty)
    }

    func testVisibleSplitGroupsDedupesAndRequiresVisibleOverlap() throws {
        let space = makeSpace()
        let resolver = RegularSplitSegmentResolver(space: space, isInteractive: true)
        let tabA = makeTab()
        let tabB = makeTab()
        let group = try XCTUnwrap(SplitGroup.make(tabIds: [tabA.id, tabB.id], layoutKind: .vertical))

        let result = resolver.visibleSplitGroups(
            currentTabs: [tabA, tabB],
            isDragging: false,
            splitGroup: { _ in group }
        )

        XCTAssertEqual(result.map(\.id), [group.id])
    }

    // MARK: - splitGroupItems

    func testSplitGroupItemsResolvesLiveTabsAndShortcutMembers() throws {
        let space = makeSpace()
        let resolver = RegularSplitSegmentResolver(space: space, isInteractive: true)
        let tabA = makeTab(name: "Live")
        let pinId = UUID()
        let restoredTabId = UUID()
        let pin = makePin(id: pinId)
        let group = try XCTUnwrap(SplitGroup.make(
            tabIds: [tabA.id, restoredTabId],
            layoutKind: .vertical,
            members: [
                SplitGroupMember(tabId: restoredTabId, pinId: pinId, origin: .spacePinned(spaceId: space.id, folderId: nil, index: 0)),
            ]
        ))

        let items = resolver.splitGroupItems(
            for: group,
            tabById: [tabA.id: tabA],
            liveTab: { _ in nil },
            shortcutPin: { $0 == pinId ? pin : nil }
        )

        XCTAssertEqual(items.map(\.id), [tabA.id, pinId])
        XCTAssertEqual(items.first?.tab?.id, tabA.id)
        XCTAssertEqual(items.last?.pin?.id, pinId)
    }

    // MARK: - action / member

    func testActionIsRestoreForShortcutBackedMember() throws {
        let space = makeSpace()
        let resolver = RegularSplitSegmentResolver(space: space, isInteractive: true)
        let pinId = UUID()
        let pin = makePin(id: pinId)
        let group = try XCTUnwrap(SplitGroup.make(
            tabIds: [UUID(), UUID()],
            layoutKind: .vertical
        ))
        let item = SplitGroupSidebarItem.pin(pin)

        // No member registered for this pin id yet -> action should be nil (no tab, no shortcut member).
        XCTAssertNil(resolver.action(for: item, in: group))
        XCTAssertNil(resolver.member(for: item, in: group))
    }

    func testActionIsCloseForPlainTab() throws {
        let space = makeSpace()
        let resolver = RegularSplitSegmentResolver(space: space, isInteractive: true)
        let tab = makeTab()
        let group = try XCTUnwrap(SplitGroup.make(tabIds: [tab.id, UUID()], layoutKind: .vertical))
        let item = SplitGroupSidebarItem.tab(tab)

        XCTAssertEqual(resolver.action(for: item, in: group), .close)
    }

    func testActionIsRestoreWhenTabIsShortcutBackedMember() throws {
        let space = makeSpace()
        let resolver = RegularSplitSegmentResolver(space: space, isInteractive: true)
        let pinId = UUID()
        let tab = makeTab(shortcutPinId: pinId)
        let group = try XCTUnwrap(SplitGroup.make(
            tabIds: [tab.id, UUID()],
            layoutKind: .vertical,
            members: [
                SplitGroupMember(tabId: tab.id, pinId: pinId, origin: .spacePinned(spaceId: space.id, folderId: nil, index: 0)),
            ]
        ))
        let item = SplitGroupSidebarItem.tab(tab)

        XCTAssertEqual(resolver.action(for: item, in: group), .restore)
    }

    // MARK: - sourceZone

    func testSourceZoneForEssentialPinIsEssentials() {
        let space = makeSpace()
        let resolver = RegularSplitSegmentResolver(space: space, isInteractive: true)
        let pin = makePin(role: .essential)

        XCTAssertEqual(resolver.sourceZone(for: pin), .essentials)
    }

    func testSourceZoneForFolderPinIsFolder() {
        let space = makeSpace()
        let resolver = RegularSplitSegmentResolver(space: space, isInteractive: true)
        let folderId = UUID()
        let pin = makePin(role: .spacePinned, folderId: folderId)

        XCTAssertEqual(resolver.sourceZone(for: pin), .folder(folderId))
    }

    func testSourceZoneForSpacePinnedFallsBackToResolverSpace() {
        let space = makeSpace()
        let resolver = RegularSplitSegmentResolver(space: space, isInteractive: true)
        let pin = makePin(role: .spacePinned, spaceId: nil, folderId: nil)

        XCTAssertEqual(resolver.sourceZone(for: pin), .spacePinned(space.id))
    }

    // MARK: - dragSource

    func testDragSourceForPlainTabUsesSpaceRegularZone() throws {
        let space = makeSpace()
        let resolver = RegularSplitSegmentResolver(space: space, isInteractive: true)
        let tab = makeTab()
        let group = try XCTUnwrap(SplitGroup.make(tabIds: [tab.id, UUID()], layoutKind: .vertical))
        let item = SplitGroupSidebarItem.tab(tab)

        let dragSource = resolver.dragSource(
            for: item,
            in: group,
            shortcutPin: { _ in nil },
            onActivateTab: { _ in },
            onActivateGroup: {}
        )

        XCTAssertEqual(dragSource?.sourceZone, .spaceRegular(space.id))
        XCTAssertEqual(dragSource?.item.tabId, tab.id)
    }

    func testDragSourceForShortcutBackedTabUsesPinSourceZone() throws {
        let space = makeSpace()
        let resolver = RegularSplitSegmentResolver(space: space, isInteractive: true)
        let pinId = UUID()
        let tab = makeTab(shortcutPinId: pinId)
        let pin = makePin(id: pinId, role: .essential)
        let group = try XCTUnwrap(SplitGroup.make(
            tabIds: [tab.id, UUID()],
            layoutKind: .vertical,
            members: [
                SplitGroupMember(tabId: tab.id, pinId: pinId, origin: .spacePinned(spaceId: space.id, folderId: nil, index: 0)),
            ]
        ))
        let item = SplitGroupSidebarItem.tab(tab)

        let dragSource = resolver.dragSource(
            for: item,
            in: group,
            shortcutPin: { $0 == pinId ? pin : nil },
            onActivateTab: { _ in },
            onActivateGroup: {}
        )

        XCTAssertEqual(dragSource?.sourceZone, .essentials)
        XCTAssertEqual(dragSource?.item.tabId, tab.id)
    }

    func testDragSourceIsDisabledWhenResolverIsNotInteractive() throws {
        let space = makeSpace()
        let resolver = RegularSplitSegmentResolver(space: space, isInteractive: false)
        let tab = makeTab()
        let group = try XCTUnwrap(SplitGroup.make(tabIds: [tab.id, UUID()], layoutKind: .vertical))
        let item = SplitGroupSidebarItem.tab(tab)

        let dragSource = resolver.dragSource(
            for: item,
            in: group,
            shortcutPin: { _ in nil },
            onActivateTab: { _ in },
            onActivateGroup: {}
        )

        XCTAssertEqual(dragSource?.isEnabled, false)
    }
}
