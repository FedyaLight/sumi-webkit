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

    func testCloseTabFromCommandPaletteUnloadsStandaloneLauncher() throws {
        let harness = try makeHarness()
        let pin = try XCTUnwrap(
            harness.browserManager.shortcutPinStoreOwner.insert(
                ShortcutPin(
                    id: UUID(),
                    role: .spacePinned,
                    spaceId: harness.space.id,
                    index: 0,
                    launchURL: URL(string: "https://launcher.example")!,
                    title: "Launcher"
                ),
                at: 0
            )
        )
        let liveTab = try XCTUnwrap(
            harness.browserManager.shortcutTabMaterializer.materialize(
                pin,
                in: harness.windowState.id,
                currentSpaceId: harness.space.id
            )
        )
        harness.windowState.currentTabId = liveTab.id
        harness.windowState.currentShortcutPinId = pin.id
        harness.windowState.currentShortcutPinRole = .spacePinned
        harness.windowState.presentationState.isCommandPaletteVisible = true

        guard case .browser(let context) = harness.browserManager
            .shortcutTargetResolver.resolve(keyWindow: harness.appKitWindow)
        else { return XCTFail("Expected browser shortcut context") }
        let outcome = try XCTUnwrap(
            harness.browserManager.shortcutActionRouter
                .executeFromCommandPalette(.closeTab, in: context)
        )

        guard case .dismissPalette = outcome else {
            return XCTFail("Close Tab should dismiss the command palette")
        }
        XCTAssertNil(
            harness.browserManager.liveShortcutTabs.entry(tabId: liveTab.id)
        )
        XCTAssertTrue(
            harness.browserManager.shortcutPinCollectionStateOwner
                .spacePinnedPins(for: harness.space.id)
                .contains(where: { $0.id == pin.id })
        )
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

    func testSplitLayoutFromCommandPaletteKeepsNewSplitPickerAlive() throws {
        let harness = try makeHarness()
        let tab = createTab("https://split-palette.example", in: harness)
        harness.windowState.currentTabId = tab.id
        harness.windowState.presentationState.isCommandPaletteVisible = true

        guard case .browser(let context) = harness.browserManager
            .shortcutTargetResolver.resolve(keyWindow: harness.appKitWindow)
        else { return XCTFail("Expected browser shortcut context") }
        let outcome = try XCTUnwrap(
            harness.browserManager.shortcutActionRouter
                .executeFromCommandPalette(.splitVertical, in: context)
        )

        guard case .paletteReplaced = outcome else {
            return XCTFail(
                "A newly created split must retain its replacement palette"
            )
        }
        XCTAssertEqual(
            harness.browserManager.splitWindowContext.query
                .group(in: harness.windowState.id)?.layoutKind,
            .vertical
        )
        XCTAssertTrue(
            harness.windowState.presentationState.isCommandPaletteVisible
        )
    }

    func testArcDirectionalSplitCommandsInsertOnTheRequestedSide() throws {
        let cases: [
            (
                action: ShortcutAction,
                layout: SplitLayoutKind,
                originalIndex: Int
            )
        ] = [
            (.addSplitTop, .horizontal, 1),
            (.addSplitLeft, .vertical, 1),
            (.addSplitRight, .vertical, 0),
            (.addSplitBottom, .horizontal, 0),
        ]

        for testCase in cases {
            let harness = try makeHarness()
            let tab = createTab(
                "https://\(testCase.action.rawValue).example",
                in: harness
            )
            harness.windowState.currentTabId = tab.id
            harness.windowState.presentationState
                .isCommandPaletteVisible = true
            guard case .browser(let context) = harness.browserManager
                .shortcutTargetResolver.resolve(
                    keyWindow: harness.appKitWindow
                ) else {
                return XCTFail("Expected browser shortcut context")
            }

            let outcome = try XCTUnwrap(
                harness.browserManager.shortcutActionRouter
                    .executeFromCommandPalette(
                        testCase.action,
                        in: context
                    )
            )

            guard case .paletteReplaced = outcome else {
                return XCTFail(
                    "\(testCase.action) must keep the split picker open"
                )
            }
            let group = try XCTUnwrap(
                harness.browserManager.splitWindowContext.query
                    .group(in: harness.windowState.id)
            )
            XCTAssertEqual(group.layoutKind, testCase.layout)
            XCTAssertEqual(
                group.memberIDs.firstIndex(of: .regularTab(tab.id)),
                testCase.originalIndex
            )
        }
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

    func testReferenceCatalogPresentationCommandsUseNativeOwners() throws {
        let harness = try makeHarness()

        execute(.newFolder, in: harness)
        XCTAssertEqual(
            harness.browserManager.folderCollectionStateOwner
                .folders(for: harness.space.id)
                .map(\.name),
            ["New Folder"]
        )

        execute(.openSettings, in: harness)
        let settingsTabID = try XCTUnwrap(
            harness.windowState.currentTabId
        )
        let settingsTab = try XCTUnwrap(
            harness.browserManager.regularTabCollectionOwner.tab(
                for: settingsTabID
            )
        )
        XCTAssertEqual(
            settingsTab.url,
            SettingsTabs.general.settingsSurfaceURL
        )
        guard case .browser(let settingsContext) = harness.browserManager
            .shortcutTargetResolver.resolve(
                keyWindow: harness.appKitWindow
            ) else {
                return XCTFail("Expected browser shortcut context")
            }
        for action in [
            ShortcutAction.refresh,
            .clearCookiesAndRefresh,
            .openDevTools,
            .copyCurrentURL,
            .hardReload,
            .printPage,
            .captureScreenshot,
        ] {
            XCTAssertFalse(
                harness.browserManager.shortcutActionRouter.canExecute(
                    action,
                    in: settingsContext
                ),
                "\(action) must not be offered for a native settings page"
            )
        }
        XCTAssertNil(
            harness.browserManager.shortcutActionRouter
                .executeFromCommandPalette(
                    .printPage,
                    in: settingsContext
                )
        )

        execute(.manageExtensions, in: harness)
        XCTAssertEqual(
            settingsTab.url,
            SettingsTabs.extensions.settingsSurfaceURL
        )
    }

    func testPinAndUnpinRoundTripPreservesTheLiveTab() throws {
        let harness = try makeHarness()
        let tab = createTab("https://pin-command.example", in: harness)
        harness.windowState.currentTabId = tab.id

        execute(.pinTab, in: harness)

        XCTAssertTrue(
            harness.browserManager.regularTabCollectionOwner
                .tabs(in: harness.space.id).isEmpty
        )
        let pin = try XCTUnwrap(
            harness.browserManager.shortcutPinCollectionStateOwner
                .spacePinnedPins(for: harness.space.id).first
        )
        XCTAssertEqual(pin.launchURL, tab.url)
        XCTAssertEqual(harness.windowState.currentTabId, tab.id)
        XCTAssertEqual(harness.windowState.currentShortcutPinId, pin.id)
        XCTAssertEqual(harness.windowState.currentShortcutPinRole, .spacePinned)

        execute(.unpinTab, in: harness)

        XCTAssertTrue(
            harness.browserManager.shortcutPinCollectionStateOwner
                .spacePinnedPins(for: harness.space.id).isEmpty
        )
        XCTAssertEqual(
            harness.browserManager.regularTabCollectionOwner
                .tabs(in: harness.space.id).map(\.id),
            [tab.id]
        )
        XCTAssertEqual(harness.windowState.currentTabId, tab.id)
        XCTAssertNil(harness.windowState.currentShortcutPinId)
        XCTAssertNil(harness.windowState.currentShortcutPinRole)
    }

    func testAddRegularTabToEssentialsCreatesProfileLauncher() throws {
        let harness = try makeHarness()
        let tab = createTab("https://essential-command.example", in: harness)
        harness.windowState.currentTabId = tab.id

        execute(.addToEssentials, in: harness)

        XCTAssertTrue(
            harness.browserManager.regularTabCollectionOwner
                .tabs(in: harness.space.id).isEmpty
        )
        let pin = try XCTUnwrap(
            harness.browserManager.shortcutPinCollectionStateOwner
                .essentialPins(for: harness.profile.id).first
        )
        XCTAssertEqual(pin.launchURL, tab.url)
        XCTAssertEqual(harness.windowState.currentShortcutPinId, pin.id)
        XCTAssertEqual(harness.windowState.currentShortcutPinRole, .essential)
    }

    func testAddSpaceLauncherToEssentialsCopiesWithoutMovingSource() throws {
        let harness = try makeHarness()
        let source = try XCTUnwrap(
            harness.browserManager.shortcutPinStoreOwner.insert(
                ShortcutPin(
                    id: UUID(),
                    role: .spacePinned,
                    spaceId: harness.space.id,
                    index: 0,
                    launchURL: URL(string: "https://copy-essential.example")!,
                    title: "Space Launcher"
                ),
                at: 0
            )
        )
        let liveTab = try XCTUnwrap(
            harness.browserManager.shortcutTabMaterializer.materialize(
                source,
                in: harness.windowState.id,
                currentSpaceId: harness.space.id
            )
        )
        harness.windowState.currentTabId = liveTab.id
        harness.windowState.currentShortcutPinId = source.id
        harness.windowState.currentShortcutPinRole = .spacePinned

        execute(.addToEssentials, in: harness)

        XCTAssertEqual(
            harness.browserManager.shortcutPinCollectionStateOwner
                .spacePinnedPins(for: harness.space.id).map(\.id),
            [source.id]
        )
        let essential = try XCTUnwrap(
            harness.browserManager.shortcutPinCollectionStateOwner
                .essentialPins(for: harness.profile.id).first
        )
        XCTAssertNotEqual(essential.id, source.id)
        XCTAssertEqual(essential.launchURL, source.launchURL)
        XCTAssertEqual(harness.windowState.currentShortcutPinId, source.id)
    }

    func testRemoveCurrentEssentialMovesLauncherToCurrentSpace() throws {
        let harness = try makeHarness()
        let source = try XCTUnwrap(
            harness.browserManager.shortcutPinStoreOwner.insert(
                ShortcutPin(
                    id: UUID(),
                    role: .essential,
                    profileId: harness.profile.id,
                    index: 0,
                    launchURL: URL(string: "https://remove-essential.example")!,
                    title: "Essential"
                ),
                at: 0
            )
        )
        let liveTab = try XCTUnwrap(
            harness.browserManager.shortcutTabMaterializer.materialize(
                source,
                in: harness.windowState.id,
                currentSpaceId: harness.space.id
            )
        )
        harness.windowState.currentTabId = liveTab.id
        harness.windowState.currentShortcutPinId = source.id
        harness.windowState.currentShortcutPinRole = .essential

        execute(.removeFromEssentials, in: harness)

        XCTAssertTrue(
            harness.browserManager.shortcutPinCollectionStateOwner
                .essentialPins(for: harness.profile.id).isEmpty
        )
        let moved = try XCTUnwrap(
            harness.browserManager.shortcutPinCollectionStateOwner
                .spacePinnedPins(for: harness.space.id).first
        )
        XCTAssertEqual(moved.id, source.id)
        XCTAssertEqual(moved.role, .spacePinned)
        XCTAssertEqual(harness.windowState.currentTabId, liveTab.id)
        XCTAssertEqual(harness.windowState.currentShortcutPinId, moved.id)
        XCTAssertEqual(harness.windowState.currentShortcutPinRole, .spacePinned)
    }

    func testZenAppearanceAndSidebarPositionCommandsAreContextual() throws {
        let harness = try makeHarness()
        guard case .browser(let context) = harness.browserManager
            .shortcutTargetResolver.resolve(keyWindow: harness.appKitWindow)
        else { return XCTFail("Expected browser shortcut context") }
        let router = harness.browserManager.shortcutActionRouter

        XCTAssertFalse(
            router.canExecute(.switchToAutomaticAppearance, in: context)
        )
        XCTAssertTrue(router.canExecute(.switchToLightMode, in: context))
        XCTAssertTrue(router.canExecute(.switchToDarkMode, in: context))

        execute(.switchToLightMode, in: harness)
        XCTAssertEqual(harness.settings.windowSchemeMode, .light)
        XCTAssertFalse(router.canExecute(.switchToLightMode, in: context))
        XCTAssertTrue(
            router.canExecute(.switchToAutomaticAppearance, in: context)
        )

        XCTAssertEqual(harness.settings.sidebarPosition, .left)
        execute(.toggleTabsOnRight, in: harness)
        XCTAssertEqual(harness.settings.sidebarPosition, .right)
        execute(.toggleTabsOnRight, in: harness)
        XCTAssertEqual(harness.settings.sidebarPosition, .left)
    }

    func testPinAndEssentialsCommandsMoveTheWholeActiveSplitAtomically() throws {
        let harness = try makeHarness()
        let tabs = [
            createTab("https://split-pin-one.example", in: harness),
            createTab("https://split-pin-two.example", in: harness),
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

        execute(.pinTab, in: harness)

        let pinned = try XCTUnwrap(
            harness.browserManager.splitGroupStore.group(id: group.id)
        )
        guard case .shortcutSidebar(let spaceID, _, nil, _) =
                pinned.container else {
            return XCTFail("Pinned split should become a space launcher")
        }
        XCTAssertEqual(spaceID, harness.space.id)
        XCTAssertTrue(pinned.memberIDs.allSatisfy {
            if case .shortcutPin = $0 { return true }
            return false
        })

        execute(.unpinTab, in: harness)

        let unpinned = try XCTUnwrap(
            harness.browserManager.splitGroupStore.group(id: group.id)
        )
        guard case .regularTabs(let unpinnedSpaceID) = unpinned.container else {
            return XCTFail("Unpinned split should return to regular tabs")
        }
        XCTAssertEqual(unpinnedSpaceID, harness.space.id)
        XCTAssertEqual(unpinned.memberIDs, group.memberIDs)
        XCTAssertEqual(
            harness.windowState.splitSelection?.groupID,
            group.id
        )

        execute(.pinTab, in: harness)
        execute(.addToEssentials, in: harness)

        let essential = try XCTUnwrap(
            harness.browserManager.splitGroupStore.group(id: group.id)
        )
        guard case .essentialSidebar(let profileID, _) =
                essential.container else {
            return XCTFail("Split should move into Essentials")
        }
        XCTAssertEqual(profileID, harness.profile.id)

        execute(.removeFromEssentials, in: harness)

        let restored = try XCTUnwrap(
            harness.browserManager.splitGroupStore.group(id: group.id)
        )
        guard case .shortcutSidebar(let restoredSpaceID, _, nil, _) =
                restored.container else {
            return XCTFail("Split should return to the current Space")
        }
        XCTAssertEqual(restoredSpaceID, harness.space.id)
        XCTAssertEqual(
            harness.windowState.splitSelection?.groupID,
            group.id
        )
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
        let settings = SumiSettingsService(
            userDefaults: TestDefaultsHarness().defaults
        )
        browserManager.sumiSettings = settings
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
            space: space,
            settings: settings
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
    let settings: SumiSettingsService
}
