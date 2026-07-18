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
            targetWindowState.presentationState.isFloatingBarVisible
        )
        XCTAssertFalse(
            harness.windowState.presentationState.isFloatingBarVisible
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
