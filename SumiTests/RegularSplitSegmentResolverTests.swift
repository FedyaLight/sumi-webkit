import AppKit
import SwiftUI
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
    ) -> Sumi.Tab {
        let tab = Sumi.Tab(
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

    private func regularGroup(_ tabs: [Sumi.Tab]) throws -> SplitGroup {
        let members = tabs.map { SplitMember.regularTab($0.id) }
        return try XCTUnwrap(
            SplitGroup.make(
                members: members,
                layoutKind: .vertical,
                container: .regularTabs(spaceId: tabs.first?.spaceId)
            )
        )
    }

    func testVisibleSplitGroupsKeepsGroupVisibleForDragging() throws {
        let space = makeSpace()
        let resolver = RegularSplitSegmentResolver(
            space: space,
            isInteractive: true
        )
        let tabA = makeTab()
        let tabB = makeTab()
        let group = try regularGroup([tabA, tabB])

        XCTAssertEqual(
            resolver.visibleSplitGroups(
                currentTabs: [tabA, tabB],
                splitGroup: { _ in group }
            ).map(\.id),
            [group.id]
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
                    .shortcutPin(firstPinID),
                    .shortcutPin(secondPinID),
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
            splitGroup: { _ in group }
        )

        XCTAssertEqual(result.map(\.id), [group.id])
    }

    func testSplitGroupItemsKeepRegularTabIdentity() throws {
        let space = makeSpace()
        let resolver = RegularSplitSegmentResolver(
            space: space,
            isInteractive: true
        )
        let regularTab = makeTab(name: "Regular")
        let secondTab = makeTab(name: "Second")
        let group = try regularGroup([regularTab, secondTab])

        let items = resolver.splitGroupItems(
            for: group,
            tabByID: [regularTab.id: regularTab],
            regularTab: { $0 == secondTab.id ? secondTab : nil },
            shortcutLiveTab: { _ in nil },
            shortcutPin: { _ in nil }
        )

        XCTAssertEqual(
            items.map(\.id),
            [.regularTab(regularTab.id), .regularTab(secondTab.id)]
        )
        XCTAssertEqual(items.last?.tab?.id, secondTab.id)
        XCTAssertEqual(items.last?.persistentID, secondTab.id)
    }

    func testRegularSplitUsesMemberCloseActionsInsteadOfGroupAction() throws {
        let regularTab = makeTab()
        let group = try regularGroup([regularTab, makeTab()])
        let regularItem = try XCTUnwrap(
            SplitGroupSidebarItem.regular(
                .regularTab(regularTab.id),
                tab: regularTab
            )
        )
        XCTAssertNil(
            SplitGroupSidebarModel.rowAction(
                for: group,
                items: [regularItem]
            )
        )
        XCTAssertEqual(
            SplitGroupSidebarModel.memberAction(
                for: regularItem,
                in: group
            ),
            .close
        )
    }

    func testSavedSplitRowOffersUnloadWhileLoadedAndCloseWhileUnloaded() throws {
        let space = makeSpace()
        let firstPin = makePin(spaceID: space.id)
        let secondPin = makePin(spaceID: space.id)
        let group = try XCTUnwrap(SplitGroup.make(
            members: [
                .shortcutPin(firstPin.id),
                .shortcutPin(secondPin.id),
            ],
            layoutKind: .vertical,
            container: .shortcutSidebar(
                spaceId: space.id,
                profileId: nil,
                folderId: nil,
                index: 0
            )
        ))
        let firstMember = try XCTUnwrap(group.members.first)
        let secondMember = try XCTUnwrap(group.members.last)
        let loaded = try XCTUnwrap(SplitGroupSidebarItem.shortcut(
            firstMember,
            pin: firstPin,
            liveTab: makeTab(shortcutPinID: firstPin.id)
        ))
        let unloaded = try XCTUnwrap(SplitGroupSidebarItem.shortcut(
            secondMember,
            pin: secondPin,
            liveTab: nil
        ))

        XCTAssertEqual(
            SplitGroupSidebarModel.rowAction(
                for: group,
                items: [loaded, unloaded]
            ),
            .unload
        )
        XCTAssertEqual(
            SplitGroupSidebarModel.rowAction(
                for: group,
                items: [unloaded]
            ),
            .close
        )
        XCTAssertNil(
            SplitGroupSidebarModel.memberAction(for: loaded, in: group)
        )
    }

    func testSplitRowDisplayProjectionRefreshesLoadedStateWithoutChangingMemberIdentity() throws {
        let space = makeSpace()
        let pin = makePin(spaceID: space.id)
        let group = try XCTUnwrap(SplitGroup.make(
            members: [
                .shortcutPin(pin.id),
                .shortcutPin(UUID()),
            ],
            layoutKind: .vertical,
            container: .shortcutSidebar(
                spaceId: space.id,
                profileId: nil,
                folderId: nil,
                index: 0
            )
        ))
        let member = try XCTUnwrap(group.members.first)
        let loaded = try XCTUnwrap(SplitGroupSidebarItem.shortcut(
            member,
            pin: pin,
            liveTab: makeTab(shortcutPinID: pin.id)
        ))
        let unloaded = try XCTUnwrap(SplitGroupSidebarItem.shortcut(
            member,
            pin: pin,
            liveTab: nil
        ))

        let projected = SplitGroupSidebarModel.displayItems(
            current: [unloaded],
            animationSnapshot: [loaded]
        )

        XCTAssertEqual(projected.map(\.id), [loaded.id])
        XCTAssertNil(projected.first?.tab)
    }

    func testSplitShortcutIconPresentationTreatsUnloadedMemberLikeLauncher() throws {
        let pin = makePin()
        let group = try XCTUnwrap(SplitGroup.make(
            members: [
                .shortcutPin(pin.id),
                .shortcutPin(UUID()),
            ],
            layoutKind: .vertical,
            container: .shortcutSidebar(
                spaceId: UUID(),
                profileId: nil,
                folderId: nil,
                index: 0
            )
        ))
        let item = try XCTUnwrap(SplitGroupSidebarItem.shortcut(
            try XCTUnwrap(group.members.first),
            pin: pin,
            liveTab: nil
        ))

        let presentation = SplitGroupMemberIconResolver.resolve(
            item: item,
            loadedStoredFavicon: nil,
            faviconPartition: .regular(
                pin.executionProfileId ?? pin.profileId
            ),
            imageReader: TabDependencyIsolationDefaults.faviconCapabilities.images
        )

        XCTAssertTrue(presentation.shouldDesaturate)
        XCTAssertNotEqual(presentation.kind, .liveFavicon)
    }

    func testSplitShortcutIconPresentationDoesNotReplaceStoredIconWithLiveGlobe() throws {
        let pin = makePin()
        let group = try XCTUnwrap(SplitGroup.make(
            members: [
                .shortcutPin(pin.id),
                .shortcutPin(UUID()),
            ],
            layoutKind: .vertical,
            container: .shortcutSidebar(
                spaceId: UUID(),
                profileId: nil,
                folderId: nil,
                index: 0
            )
        ))
        let item = try XCTUnwrap(SplitGroupSidebarItem.shortcut(
            try XCTUnwrap(group.members.first),
            pin: pin,
            liveTab: makeTab(shortcutPinID: pin.id)
        ))

        let presentation = SplitGroupMemberIconResolver.resolve(
            item: item,
            loadedStoredFavicon: Image(systemName: "star.fill"),
            faviconPartition: .regular(
                pin.executionProfileId ?? pin.profileId
            ),
            imageReader: TabDependencyIsolationDefaults.faviconCapabilities.images
        )

        XCTAssertEqual(presentation.kind, .storedLauncher)
        XCTAssertFalse(presentation.shouldDesaturate)
    }

    func testUnloadedSplitUsesResolvedSpaceProfileFaviconPartition() throws {
        let profileID = UUID()
        let pin = makePin()
        let group = try XCTUnwrap(SplitGroup.make(
            members: [
                .shortcutPin(pin.id),
                .shortcutPin(UUID()),
            ],
            layoutKind: .vertical,
            container: .shortcutSidebar(
                spaceId: UUID(),
                profileId: profileID,
                folderId: nil,
                index: 0
            )
        ))
        let item = try XCTUnwrap(SplitGroupSidebarItem.shortcut(
            try XCTUnwrap(group.members.first),
            pin: pin,
            liveTab: nil
        ))
        let reader = PartitionedSplitFaviconReader(
            availablePartition: .regular(profileID)
        )

        let presentation = SplitGroupMemberIconResolver.resolve(
            item: item,
            loadedStoredFavicon: nil,
            faviconPartition: .regular(profileID),
            imageReader: reader
        )

        XCTAssertEqual(presentation.kind, .storedLauncher)
        XCTAssertTrue(presentation.shouldDesaturate)
    }

    func testSegmentedSplitRowKeepsStandardSidebarRowHeight() throws {
        let browser = BrowserManager()
        let context = browser.composeSidebarBrowserContext(
            spaceLifecycle: browser.sidebarSpaceLifecycle
        )
        let windowState = BrowserWindowState()
        let first = makeTab(name: "First")
        let second = makeTab(name: "Second")
        let group = try regularGroup([first, second])
        let items = try group.members.enumerated().map { index, member in
            try XCTUnwrap(SplitGroupSidebarItem.regular(
                member,
                tab: index == 0 ? first : second
            ))
        }
        let row = SplitGroupSidebarRow(
            group: group,
            items: items,
            spaceId: UUID(),
            isAppKitInteractionEnabled: false,
            faviconImageReader:
                TabDependencyIsolationDefaults.faviconCapabilities.images,
            splitLayout: context.splitLayout,
            emptySplitCreation: context.emptySplitCreation,
            groupEditor: context.splitGroupEditor,
            memberAction: { item in
                SplitGroupSidebarModel.memberAction(for: item, in: group)
            },
            contextMenuEntries: { _ in [] },
            onActivateMember: { _ in },
            onMemberAction: { _ in }
        )
        .environment(windowState)
        .frame(width: 280)
        let host = NSHostingView(rootView: row)

        XCTAssertEqual(
            host.fittingSize.height,
            SidebarRowLayout.rowHeight,
            accuracy: 0.5
        )
    }

    func testThreeMemberDropHighlightFillsIndentedListLane() throws {
        let browser = BrowserManager()
        let context = browser.composeSidebarBrowserContext(
            spaceLifecycle: browser.sidebarSpaceLifecycle
        )
        let windowState = BrowserWindowState()
        let tabs = (0..<3).map { makeTab(name: "Tab \($0)") }
        let group = try regularGroup(tabs)
        let items = try zip(group.members, tabs).map { member, tab in
            try XCTUnwrap(
                SplitGroupSidebarItem.regular(member, tab: tab)
            )
        }
        let row = SplitGroupSidebarRow(
            group: group,
            items: items,
            spaceId: UUID(),
            isAppKitInteractionEnabled: false,
            faviconImageReader:
                TabDependencyIsolationDefaults.faviconCapabilities.images,
            splitLayout: context.splitLayout,
            emptySplitCreation: context.emptySplitCreation,
            groupEditor: context.splitGroupEditor,
            contextMenuEntries: { _ in [] },
            onActivateMember: { _ in }
        )
        .environment(windowState)
        .environment(SidebarInteractionState())
        .padding(.leading, 28)
        .sidebarDropContainmentBackdrop(isVisible: true)
        .frame(width: 280, height: SidebarRowLayout.rowHeight)

        let image = try render(row, size: CGSize(
            width: 280,
            height: SidebarRowLayout.rowHeight
        ))
        let edgeColor = try XCTUnwrap(
            image.colorAt(x: 1, y: image.pixelsHigh / 2)?
                .usingColorSpace(.deviceRGB)
        )
        let cornerColor = try XCTUnwrap(
            image.colorAt(x: 1, y: 1)?
                .usingColorSpace(.deviceRGB)
        )

        XCTAssertGreaterThan(
            edgeColor.alphaComponent,
            0.01,
            "The containment backdrop must fill the list lane behind folder indentation"
        )
        XCTAssertGreaterThan(
            cornerColor.alphaComponent,
            0.01,
            "The containment backdrop must remain rectangular without rounded corners"
        )
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
        let companion = makeTab()
        let group = try regularGroup([tab, companion])
        let item = try XCTUnwrap(
            SplitGroupSidebarItem.regular(
                .regularTab(tab.id),
                tab: tab
            )
        )

        let source = resolver.dragSource(
            for: item,
            in: group,
            faviconImageReader: TabDependencyIsolationDefaults.faviconCapabilities.images,
            splitPresentation: SidebarSplitDragPresentation(
                members: [tab, companion].map { member in
                    SidebarSplitDragPresentation.Member(
                        icon: member.favicon,
                        glyphText: nil,
                        systemImageName: nil,
                        accentColor: .clear,
                        title: member.name
                    )
                }
            ),
            isGroupSelected: false
        )

        XCTAssertEqual(source?.sourceZone, .spaceRegular(space.id))
        XCTAssertEqual(source?.item.kind, .splitGroup)
        XCTAssertEqual(source?.item.tabId, group.id)
        XCTAssertNil(source?.item.splitMemberID)
        XCTAssertEqual(source?.item.splitGroupID, group.id)
        XCTAssertEqual(source?.splitPresentation?.members.count, 2)
    }

    func testCanonicalVisualOrderingCollapsesRegularSplitIntoOneBlock() throws {
        let first = makeTab(name: "First")
        let splitA = makeTab(name: "Split A")
        let splitB = makeTab(name: "Split B")
        let last = makeTab(name: "Last")
        let group = try regularGroup([splitA, splitB])

        let run = SidebarVisualSceneProjection.regularRun(
            tabIDs: [first, splitA, splitB, last].map(\.id),
            groups: [group]
        )

        XCTAssertEqual(
            run.rows.map(\.identity),
            [.tab(first.id), .splitGroup(group.id), .tab(last.id)]
        )
        XCTAssertEqual(run.rows[1].tabIDs, [splitA.id, splitB.id])
        XCTAssertEqual(
            (0...3).map {
                run.rawInsertionIndex(atVisualBoundary: $0)
            },
            [0, 1, 3, 4]
        )
        XCTAssertEqual(
            SidebarVisualSceneProjection.regularRawInsertionIndex(
                movingGroupID: group.id,
                atModelBoundary: 0,
                rows: run.rows
            ),
            0
        )
        XCTAssertEqual(
            SidebarVisualSceneProjection.regularRawInsertionIndex(
                movingGroupID: group.id,
                atModelBoundary: 1,
                rows: run.rows
            ),
            1
        )
        XCTAssertEqual(
            SidebarVisualSceneProjection.regularRawInsertionIndex(
                movingGroupID: group.id,
                atModelBoundary: 3,
                rows: run.rows
            ),
            1
        )
        XCTAssertEqual(
            SidebarVisualSceneProjection.regularRawInsertionIndex(
                movingGroupID: group.id,
                atModelBoundary: 4,
                rows: run.rows
            ),
            2
        )
    }

    private func render<Content: View>(
        _ content: Content,
        size: CGSize
    ) throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: content)
        host.wantsLayer = true
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: host.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = host
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let image = try XCTUnwrap(
            host.bitmapImageRepForCachingDisplay(in: host.bounds)
        )
        host.cacheDisplay(in: host.bounds, to: image)
        return image
    }
}

private final class PartitionedSplitFaviconReader:
    BrowserFaviconImageReading,
    @unchecked Sendable
{
    let availablePartition: SumiFaviconPartition
    let image = NSImage(size: NSSize(width: 16, height: 16))

    init(availablePartition: SumiFaviconPartition) {
        self.availablePartition = availablePartition
    }

    func cachedPreparedImage(
        for request: SumiPreparedFaviconRequest
    ) -> NSImage? {
        request.partition == availablePartition ? image : nil
    }

    func cachedSelection(
        for _: URL,
        partition _: SumiFaviconPartition
    ) -> SumiStoredFaviconSelection? {
        nil
    }

    func preparedImage(
        for _: SumiPreparedFaviconRequest,
        priority _: SumiFaviconFetchPriority,
        scheduleFetchOnMiss _: Bool
    ) async -> NSImage? {
        nil
    }
}
