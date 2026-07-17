import XCTest

@testable import Sumi

@MainActor
final class ClosedShortcutRestoreServiceTests: XCTestCase {
    // MARK: - Live instance

    func testRestoreLiveInstancePrefersSourceWindowWhenItStillExists() throws {
        let harness = makeHarness()
        let sourceWindow = harness.addWindow(spaceId: harness.space.id, profileId: harness.profile.id)
        let otherWindow = harness.addWindow(spaceId: harness.space.id, profileId: harness.profile.id)
        harness.windowRegistry.setActive(otherWindow)
        let pin = try harness.insertSpacePinnedLauncher(spaceId: harness.space.id)
        let shortcutState = makeLiveState(pin: pin, sourceWindowId: sourceWindow.id)

        XCTAssertTrue(harness.service.restoreLiveInstance(shortcutState))

        let restored = try XCTUnwrap(
            harness.browserManager.shortcutPresentationOwner
                .shortcutLiveTab(for: pin.id, in: sourceWindow.id)
        )
        XCTAssertEqual(restored.name, shortcutState.title)
        XCTAssertTrue(try XCTUnwrap(restored.restoredCanGoBack))
        XCTAssertTrue(try XCTUnwrap(restored.restoredCanGoForward))
        XCTAssertEqual(sourceWindow.currentTabId, restored.id)
    }

    func testRestoreLiveInstanceFallsBackToActiveWindowWhenSourceWindowIsGone() throws {
        let harness = makeHarness()
        let activeWindow = harness.addWindow(spaceId: harness.space.id, profileId: harness.profile.id)
        harness.windowRegistry.setActive(activeWindow)
        let pin = try harness.insertSpacePinnedLauncher(spaceId: harness.space.id)
        let shortcutState = makeLiveState(pin: pin, sourceWindowId: UUID())

        XCTAssertTrue(harness.service.restoreLiveInstance(shortcutState))

        XCTAssertNotNil(
            harness.browserManager.shortcutPresentationOwner
                .shortcutLiveTab(for: pin.id, in: activeWindow.id)
        )
        XCTAssertEqual(
            activeWindow.currentShortcutPinId,
            pin.id
        )
    }

    func testRestoreLiveInstanceRestoresMissingLauncherInsteadOfLiveTab() throws {
        let harness = makeHarness()
        let targetWindow = harness.addWindow(spaceId: harness.space.id, profileId: harness.profile.id)
        harness.windowRegistry.setActive(targetWindow)
        let deletedPin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: harness.space.id,
            index: 0,
            launchURL: try XCTUnwrap(URL(string: "https://pinned.example")),
            title: "Pinned"
        )
        let shortcutState = makeLiveState(pin: deletedPin, sourceWindowId: targetWindow.id)

        XCTAssertTrue(harness.service.restoreLiveInstance(shortcutState))

        let restoredPin = try XCTUnwrap(
            harness.browserManager.shortcutPinCollectionStateOwner
                .shortcutPin(by: deletedPin.id)
        )
        XCTAssertEqual(restoredPin.spaceId, harness.space.id)
        XCTAssertNil(
            harness.browserManager.shortcutPresentationOwner
                .shortcutLiveTab(for: deletedPin.id, in: targetWindow.id)
        )
    }

    // MARK: - Launcher

    func testRestoreEssentialLauncherFailsWhenProfileIsGone() {
        let harness = makeHarness()
        let pin = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: UUID(),
            index: 0,
            launchURL: URL(string: "https://essential.example")!,
            title: "Essential"
        )

        XCTAssertFalse(harness.service.restoreLauncher(from: RecentlyClosedShortcutPinState(pin: pin)))

        XCTAssertNil(
            harness.browserManager.shortcutPinCollectionStateOwner
                .shortcutPin(by: pin.id)
        )
    }

    func testRestoreEssentialLauncherWithExistingProfileSucceeds() throws {
        let harness = makeHarness()
        let pin = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: harness.profile.id,
            index: 0,
            launchURL: try XCTUnwrap(URL(string: "https://essential.example")),
            title: "Essential"
        )

        XCTAssertTrue(harness.service.restoreLauncher(from: RecentlyClosedShortcutPinState(pin: pin)))

        let restored = try XCTUnwrap(
            harness.browserManager.shortcutPinCollectionStateOwner
                .shortcutPin(by: pin.id)
        )
        XCTAssertEqual(restored.role, .essential)
        XCTAssertEqual(restored.profileId, harness.profile.id)
    }

    func testRestoreSpacePinnedLauncherUsesSourceSpaceInsteadOfGlobalFallback() throws {
        let harness = makeHarness()
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: harness.space.id,
            index: 0,
            launchURL: try XCTUnwrap(URL(string: "https://shortcut.example")),
            title: "Shortcut"
        )

        XCTAssertTrue(harness.service.restoreLauncher(from: RecentlyClosedShortcutPinState(pin: pin)))

        let restored = try XCTUnwrap(
            harness.browserManager.shortcutPinCollectionStateOwner
                .shortcutPin(by: pin.id)
        )
        XCTAssertEqual(restored.spaceId, harness.space.id)
        XCTAssertEqual(
            harness.browserManager.shortcutPinCollectionStateOwner
                .spacePinnedPins(for: harness.space.id).map(\.id),
            [pin.id]
        )
        XCTAssertTrue(
            harness.browserManager.shortcutPinCollectionStateOwner
                .spacePinnedPins(for: harness.otherSpace.id).isEmpty
        )
    }

    func testRestoreSpacePinnedLauncherFailsWhenSpaceCannotBeResolved() {
        let harness = makeHarness()
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: nil,
            index: 0,
            launchURL: URL(string: "https://shortcut.example")!,
            title: "Shortcut"
        )

        XCTAssertFalse(harness.service.restoreLauncher(from: RecentlyClosedShortcutPinState(pin: pin)))

        XCTAssertNil(
            harness.browserManager.shortcutPinCollectionStateOwner
                .shortcutPin(by: pin.id)
        )
        XCTAssertTrue(
            harness.browserManager.shortcutPinCollectionStateOwner
                .spacePinnedPins(for: harness.space.id).isEmpty
        )
    }

    func testRestoreSpacePinnedLauncherDropsFolderBelongingToAnotherSpace() throws {
        let harness = makeHarness()
        let foreignFolder = try XCTUnwrap(
            harness.browserManager.sidebarFolderCommands.createFolder(
                in: harness.otherSpace.id,
                name: "Foreign"
            )
        )
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: harness.space.id,
            index: 0,
            folderId: foreignFolder.id,
            launchURL: try XCTUnwrap(URL(string: "https://shortcut.example")),
            title: "Shortcut"
        )

        XCTAssertTrue(harness.service.restoreLauncher(from: RecentlyClosedShortcutPinState(pin: pin)))

        let restored = try XCTUnwrap(
            harness.browserManager.shortcutPinCollectionStateOwner
                .shortcutPin(by: pin.id)
        )
        XCTAssertEqual(restored.spaceId, harness.space.id)
        XCTAssertNil(restored.folderId)
    }

    func testRestoreSpacePinnedLauncherKeepsFolderBelongingToResolvedSpace() throws {
        let harness = makeHarness()
        let folder = try XCTUnwrap(
            harness.browserManager.sidebarFolderCommands.createFolder(
                in: harness.space.id,
                name: "Local"
            )
        )
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: harness.space.id,
            index: 0,
            folderId: folder.id,
            launchURL: try XCTUnwrap(URL(string: "https://shortcut.example")),
            title: "Shortcut"
        )

        XCTAssertTrue(harness.service.restoreLauncher(from: RecentlyClosedShortcutPinState(pin: pin)))

        let restored = try XCTUnwrap(
            harness.browserManager.shortcutPinCollectionStateOwner
                .shortcutPin(by: pin.id)
        )
        XCTAssertEqual(restored.folderId, folder.id)
    }

    func testRestoreSpacePinnedLauncherMovesOutOfFolderThatBecameLive() throws {
        let harness = makeHarness()
        let folder = try XCTUnwrap(
            harness.browserManager.sidebarFolderCommands.createFolder(
                in: harness.space.id,
                name: "Now Live"
            )
        )
        harness.browserManager.tabRuntimeLifecycle.shutdown()
        harness.browserManager.runtimePortConnection.attach(
            TestRuntimePorts.make(isLiveFolder: { $0 == folder.id })
        )
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: harness.space.id,
            index: 0,
            folderId: folder.id,
            launchURL: try XCTUnwrap(URL(string: "https://shortcut.example")),
            title: "Shortcut"
        )

        XCTAssertTrue(
            harness.service.restoreLauncher(
                from: RecentlyClosedShortcutPinState(pin: pin)
            )
        )

        let restored = try XCTUnwrap(
            harness.browserManager.shortcutPinCollectionStateOwner
                .shortcutPin(by: pin.id)
        )
        XCTAssertEqual(restored.spaceId, harness.space.id)
        XCTAssertNil(restored.folderId)
        XCTAssertEqual(
            harness.browserManager.spacePinnedStructureOwner
                .topLevelSpacePinnedItems(for: harness.space.id)
                .compactMap { item -> UUID? in
                    guard case .shortcut(let pin) = item else { return nil }
                    return pin.id
                },
            [pin.id]
        )
        XCTAssertTrue(
            harness.browserManager.shortcutPinCollectionStateOwner
                .folderPinnedPins(for: folder.id, in: harness.space.id)
                .isEmpty
        )
    }

    // MARK: - Harness

    private func makeLiveState(
        pin: ShortcutPin,
        sourceWindowId: UUID?
    ) -> RecentlyClosedShortcutLiveState {
        RecentlyClosedShortcutLiveState(
            id: UUID(),
            pin: RecentlyClosedShortcutPinState(pin: pin),
            title: "Live shortcut",
            url: URL(string: "https://pinned.example/current")!,
            sourceWindowId: sourceWindowId,
            canGoBack: true,
            canGoForward: true
        )
    }

    private func makeHarness() -> Harness {
        let browserManager = BrowserManager()
        let windowRegistry = browserManager.windowRegistry
        let profile = Profile(name: "Primary")
        let space = Space(name: "Primary", profileId: profile.id)
        let otherSpace = Space(name: "Other", profileId: profile.id)

        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile
        browserManager.spaceStateOwner.replaceSpaces([space, otherSpace])
        browserManager.spaceStateOwner.replaceCurrentSpace(space)

        let launcherRestore = ClosedShortcutLauncherRestoreTransaction(
            pins: browserManager.shortcutPinCollectionStateOwner,
            pinStore: browserManager.shortcutPinStoreOwner,
            persistence: browserManager.structuralPersistence,
            destinations: ClosedShortcutLauncherDestinationResolver(
                folders: browserManager.folderCollectionStateOwner,
                runtimeConnection: browserManager.runtimePortConnection,
                spaces: browserManager.spaceStateOwner,
                profiles: browserManager.profileManager
            )
        )
        let service = ClosedShortcutRestoreService(
            liveInstances: ClosedShortcutLiveRestoreTransaction(
                pins: browserManager.shortcutPinCollectionStateOwner,
                activation: browserManager.shortcutPresentationActivation,
                windows: ClosedShortcutWindowQuery(windows: windowRegistry),
                selection: browserManager.browserTabSelection,
                launchers: launcherRestore
            ),
            launchers: launcherRestore
        )
        return Harness(
            browserManager: browserManager,
            windowRegistry: windowRegistry,
            profile: profile,
            space: space,
            otherSpace: otherSpace,
            service: service
        )
    }

    @MainActor
    private struct Harness {
        let browserManager: BrowserManager
        let windowRegistry: WindowRegistry
        let profile: Profile
        let space: Space
        let otherSpace: Space
        let service: ClosedShortcutRestoreService

        func addWindow(spaceId: UUID, profileId: UUID) -> BrowserWindowState {
            let windowState = BrowserWindowState()
            windowState.currentSpaceId = spaceId
            windowState.currentProfileId = profileId
            windowRegistry.register(windowState)
            return windowState
        }

        func insertSpacePinnedLauncher(spaceId: UUID) throws -> ShortcutPin {
            let pin = ShortcutPin(
                id: UUID(),
                role: .spacePinned,
                spaceId: spaceId,
                index: 0,
                launchURL: try XCTUnwrap(URL(string: "https://pinned.example/launch")),
                title: "Pinned"
            )
            return try XCTUnwrap(
                browserManager.shortcutPinStoreOwner.insert(pin, at: 0)
            )
        }
    }
}
