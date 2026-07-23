import AppKit
import SumiDomain
import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class BrowserShortcutCommandRoutingTests: XCTestCase {
    func testResolvedWindowOwnsCommandsAcrossShortcutDomains() throws {
        let harness = try makeHarness()
        let targetWindowState = BrowserWindowState()
        harness.browserManager.tabResidenceAuthority.establishResidenceSession(
            on: targetWindowState
        )
        targetWindowState.currentProfileId = harness.profile.id
        targetWindowState.currentSpaceId = harness.space.id
        XCTAssertEqual(
            harness.registry.register(targetWindowState),
            .registered
        )
        let targetAppKitWindow = NSWindow()
        harness.registry.bindAppKitWindow(
            targetAppKitWindow,
            to: targetWindowState
        )
        harness.registry.setActive(harness.windowState)

        let secondSpace = Space(
            name: "Second",
            profileId: harness.profile.id
        )
        harness.browserManager.spaceStateOwner.replaceSpaces([
            harness.space,
            secondSpace,
        ])
        guard case .browser(let context) = harness.browserManager
            .shortcutTargetResolver.resolve(keyWindow: targetAppKitWindow)
        else { return XCTFail("Expected browser shortcut context") }
        let router = harness.browserManager.shortcutActionRouter

        XCTAssertTrue(router.execute(.toggleSidebar, in: context))
        XCTAssertFalse(targetWindowState.isSidebarVisible)
        XCTAssertTrue(harness.windowState.isSidebarVisible)

        XCTAssertTrue(router.execute(.nextSpace, in: context))
        XCTAssertEqual(targetWindowState.currentSpaceId, secondSpace.id)
        XCTAssertEqual(harness.windowState.currentSpaceId, harness.space.id)

        XCTAssertTrue(router.execute(.viewHistory, in: context))
        let nativeTabID = try XCTUnwrap(targetWindowState.currentTabId)
        let nativeTab = try XCTUnwrap(
            harness.browserManager.regularTabCollectionOwner.tab(
                for: nativeTabID
            )
        )
        XCTAssertEqual(nativeTab.spaceId, secondSpace.id)
        XCTAssertNil(harness.windowState.currentTabId)

        XCTAssertTrue(router.execute(.closeTab, in: context))
        XCTAssertNil(targetWindowState.currentTabId)
        XCTAssertNil(
            harness.browserManager.regularTabCollectionOwner.tab(
                for: nativeTabID
            )
        )

        XCTAssertTrue(router.execute(.focusAddressBar, in: context))
        XCTAssertTrue(
            targetWindowState.presentationState.isCommandPaletteVisible
        )
        XCTAssertFalse(
            harness.windowState.presentationState.isCommandPaletteVisible
        )
    }

    func testTabCyclingSelectsRelativeIndexAndWraps() throws {
        let harness = try makeHarness()
        let first = createTab("https://first.example", in: harness)
        let second = createTab("https://second.example", in: harness)
        let third = createTab("https://third.example", in: harness)
        harness.windowState.currentTabId = second.id

        execute(.nextTab, in: harness)
        XCTAssertEqual(harness.windowState.currentTabId, third.id)
        execute(.nextTab, in: harness)
        XCTAssertEqual(harness.windowState.currentTabId, first.id)
        execute(.previousTab, in: harness)
        XCTAssertEqual(harness.windowState.currentTabId, third.id)
    }

    func testCloseTabShortcutUnloadsEntireShortcutHostedSplitGroup() throws {
        let harness = try makeHarness()
        let pins = try (0..<2).map { index in
            try XCTUnwrap(harness.browserManager.shortcutPinStoreOwner.insert(
                ShortcutPin(
                    id: UUID(),
                    role: .spacePinned,
                    spaceId: harness.space.id,
                    index: index,
                    launchURL: URL(string: "https://split-\(index).example")!,
                    title: "Split \(index)"
                ),
                at: index
            ))
        }
        let liveTabs = try pins.map { pin in
            try XCTUnwrap(
                harness.browserManager.shortcutTabMaterializer.materialize(
                    pin,
                    in: harness.windowState.id,
                    currentSpaceId: harness.space.id
                )
            )
        }
        let group = try XCTUnwrap(SplitGroup.make(
            members: pins.map { .shortcutPin($0.id) },
            layoutKind: .vertical,
            container: .shortcutSidebar(
                spaceId: harness.space.id,
                profileId: harness.profile.id,
                folderId: nil,
                index: 0
            )
        ))
        XCTAssertTrue(harness.browserManager.splitGroupMutations.insert(
            group,
            persist: false
        ))
        harness.windowState.currentTabId = liveTabs[0].id
        harness.windowState.currentShortcutPinId = pins[0].id
        harness.windowState.currentShortcutPinRole = .spacePinned
        harness.windowState.splitSelection = WindowSplitSelection(
            groupID: group.id,
            activeMemberID: .shortcutPin(pins[0].id)
        )
        execute(.closeTab, in: harness)

        XCTAssertEqual(
            harness.browserManager.splitGroupStore.group(id: group.id),
            group
        )
        XCTAssertTrue(liveTabs.allSatisfy { tab in
            harness.browserManager.liveShortcutTabs.entry(tabId: tab.id) == nil
        })
        XCTAssertNil(harness.windowState.splitSelection)
        XCTAssertNil(harness.windowState.currentTabId)
        XCTAssertNil(harness.windowState.currentShortcutPinId)
    }

    func testCloseTabShortcutClosesEntireRegularSplitGroup() throws {
        let harness = try makeHarness()
        let tabs = [
            createTab("https://split-first.example", in: harness),
            createTab("https://split-second.example", in: harness),
        ]
        let group = try XCTUnwrap(SplitGroup.make(
            members: tabs.map { .regularTab($0.id) },
            layoutKind: .vertical,
            container: .regularTabs(spaceId: harness.space.id)
        ))
        XCTAssertTrue(harness.browserManager.splitGroupMutations.insert(
            group,
            persist: false
        ))
        harness.windowState.currentTabId = tabs[0].id
        harness.windowState.splitSelection = WindowSplitSelection(
            groupID: group.id,
            activeMemberID: .regularTab(tabs[0].id)
        )

        execute(.closeTab, in: harness)

        XCTAssertTrue(tabs.allSatisfy { tab in
            harness.browserManager.regularTabCollectionOwner.tab(
                for: tab.id
            ) == nil
        })
        XCTAssertNil(harness.browserManager.splitGroupStore.group(id: group.id))
        XCTAssertNil(harness.windowState.splitSelection)
    }

    func testSelectByIndexAndLastUseVisibleTabsForActiveWindow() throws {
        let harness = try makeHarness()
        let first = createTab("https://first.example", in: harness)
        let second = createTab("https://second.example", in: harness)
        harness.windowState.currentTabId = first.id
        execute(.goToTab2, in: harness)
        XCTAssertEqual(harness.windowState.currentTabId, second.id)
        execute(.goToTab5, in: harness)
        XCTAssertEqual(harness.windowState.currentTabId, second.id)
        execute(.goToLastTab, in: harness)
        XCTAssertEqual(harness.windowState.currentTabId, second.id)
    }

    func testSplitLayoutCreatesThenUpdatesActiveSplit() throws {
        let harness = try makeHarness()
        let tab = createTab("https://split.example", in: harness)
        harness.windowState.currentTabId = tab.id
        XCTAssertEqual(tab.spaceId, harness.windowState.currentSpaceId)
        XCTAssertIdentical(
            harness.browserManager.shellRuntime.windowTabs.currentTab(
                for: harness.windowState
            ),
            tab
        )
        execute(.splitVertical, in: harness)
        XCTAssertEqual(
            harness.browserManager.splitWindowContext.query
                .group(in: harness.windowState.id)?.layoutKind,
            .vertical
        )

        execute(.splitGrid, in: harness)
        XCTAssertEqual(
            harness.browserManager.splitWindowContext.query
                .group(in: harness.windowState.id)?.layoutKind,
            .grid
        )
    }

    func testSpaceCyclingWrapsThroughCanonicalSpaceCatalog() throws {
        let harness = try makeHarness()
        let second = Space(name: "Second", profileId: harness.profile.id)
        let third = Space(name: "Third", profileId: harness.profile.id)
        harness.browserManager.spaceStateOwner.replaceSpaces([
            harness.space,
            second,
            third,
        ])
        harness.browserManager.spaceStateOwner.replaceCurrentSpace(third)
        harness.windowState.currentSpaceId = third.id
        execute(.nextSpace, in: harness)
        XCTAssertEqual(harness.windowState.currentSpaceId, harness.space.id)
        execute(.previousSpace, in: harness)
        XCTAssertEqual(harness.windowState.currentSpaceId, third.id)
    }

    /// Every covered position, including the first, reaches its ordinal route.
    func testGoToSpaceSelectsTheSpaceAtThatCatalogPosition() throws {
        let harness = try makeHarness()
        let second = Space(name: "Second", profileId: harness.profile.id)
        let third = Space(name: "Third", profileId: harness.profile.id)
        let spaces = [harness.space, second, third]
        harness.browserManager.spaceStateOwner.replaceSpaces(spaces)
        harness.browserManager.spaceStateOwner.replaceCurrentSpace(third)
        harness.windowState.currentSpaceId = third.id

        for (index, expected) in spaces.enumerated() {
            let action = try XCTUnwrap(SpaceSwitchShortcuts.action(forSpaceAt: index))
            execute(action, in: harness)
            XCTAssertEqual(
                harness.windowState.currentSpaceId,
                expected.id,
                "position \(index) must activate \(expected.name)"
            )
        }
    }

    func testGoToSpaceUsesMountedSidebarTransitionInsteadOfCommittingImmediately() throws {
        let harness = try makeHarness()
        let second = Space(name: "Second", profileId: harness.profile.id)
        harness.browserManager.spaceStateOwner.replaceSpaces([
            harness.space,
            second,
        ])
        let presentation = harness.windowState.presentationState.spaceSwitch
        let consumerID = UUID()
        presentation.registerConsumer(consumerID)
        defer { presentation.unregisterConsumer(consumerID) }

        execute(.goToSpace2, in: harness)

        XCTAssertEqual(harness.windowState.currentSpaceId, harness.space.id)
        XCTAssertEqual(presentation.request?.targetSpaceID, second.id)
    }

    func testGoToSpacePastTheCatalogLeavesTheActiveSpaceAlone() throws {
        let harness = try makeHarness()
        harness.browserManager.spaceStateOwner.replaceSpaces([harness.space])
        harness.windowState.currentSpaceId = harness.space.id

        execute(.goToSpace10, in: harness)

        XCTAssertEqual(harness.windowState.currentSpaceId, harness.space.id)
    }

    func testGoToSpaceDoesNotExposeTheRegularCatalogInAPrivateWindow() throws {
        let harness = try makeHarness()
        let second = Space(name: "Second", profileId: harness.profile.id)
        harness.browserManager.spaceStateOwner.replaceSpaces([harness.space, second])
        harness.browserManager.spaceStateOwner.replaceCurrentSpace(second)
        harness.windowState.currentSpaceId = second.id
        harness.windowState.isIncognito = true

        execute(.goToSpace1, in: harness)

        XCTAssertEqual(harness.windowState.currentSpaceId, second.id)
    }

    func testExpandAllFoldersUsesActiveWindowSpace() throws {
        let harness = try makeHarness()
        let folder = TabFolder(name: "Folder", spaceId: harness.space.id)
        folder.isOpen = false
        harness.browserManager.folderCollectionStateOwner
            .replaceFoldersBySpace([harness.space.id: [folder]])

        execute(.expandAllFolders, in: harness)

        XCTAssertTrue(folder.isOpen)
    }

    private func createTab(
        _ url: String,
        in harness: Harness
    ) -> Tab {
        harness.browserManager.regularTabLifecycleOwner.createNewTab(
            url: url,
            in: harness.space,
            activate: false
        )
    }

    private func execute(
        _ action: ShortcutAction,
        in harness: Harness,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .browser(let context) = harness.browserManager
            .shortcutTargetResolver.resolve(keyWindow: harness.appKitWindow)
        else {
            return XCTFail(
                "Expected browser shortcut context",
                file: file,
                line: line
            )
        }
        XCTAssertTrue(
            harness.browserManager.shortcutActionRouter.execute(
                action,
                in: context
            ),
            file: file,
            line: line
        )
    }

    private func makeHarness() throws -> Harness {
        let registry = WindowRegistry()
        let browserManager = BrowserManager(
            windowRegistry: registry,
            startupPersistence: BrowserManagerStartupPersistence(
                container: try makeInMemoryStartupContainer()
            )
        )
        let profile = Profile(name: "Primary")
        let space = Space(name: "Work", profileId: profile.id)
        let windowState = BrowserWindowState()
        browserManager.tabResidenceAuthority.establishResidenceSession(on: windowState)
        windowState.restorationState.isAwaitingInitialResolution = false
        windowState.currentProfileId = profile.id
        windowState.currentSpaceId = space.id

        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile
        browserManager.spaceStateOwner.replaceSpaces([space])
        browserManager.spaceStateOwner.replaceCurrentSpace(space)
        registry.register(windowState)
        registry.setActive(windowState)
        let appKitWindow = NSWindow()
        registry.bindAppKitWindow(appKitWindow, to: windowState)

        return Harness(
            browserManager: browserManager,
            registry: registry,
            windowState: windowState,
            appKitWindow: appKitWindow,
            profile: profile,
            space: space
        )
    }

    private func makeInMemoryStartupContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }
}

private struct Harness {
    let browserManager: BrowserManager
    let registry: WindowRegistry
    let windowState: BrowserWindowState
    let appKitWindow: NSWindow
    let profile: Profile
    let space: Space
}
