import XCTest

@testable import Sumi

@MainActor
final class ShortcutLiveTabClosePersistenceTests: XCTestCase {
    func testSelectedCloseWithFallbackCommitsWindowSessionOnce() throws {
        let fixture = try makeFixture(hasFallback: true, liveTabIsSelected: true)

        XCTAssertTrue(fixture.service.close(fixture.liveTab, in: fixture.windowState))

        XCTAssertEqual(fixture.probe.commits, [.explicit])
        XCTAssertEqual(fixture.windowState.currentTabId, fixture.fallback?.id)
        XCTAssertNil(fixture.windowState.currentShortcutPinId)
        XCTAssertTrue(fixture.probe.teardownObservedAfterVisualHandoff)
        XCTAssertNil(
            fixture.tabManager.shortcutPresentationOwner.shortcutLiveTab(
                for: fixture.pin.id,
                in: fixture.windowState.id
            )
        )
    }

    func testBackgroundCloseDoesNotWriteUnchangedWindowSession() throws {
        let fixture = try makeFixture(hasFallback: true, liveTabIsSelected: false)

        XCTAssertTrue(fixture.service.close(fixture.liveTab, in: fixture.windowState))

        XCTAssertTrue(fixture.probe.commits.isEmpty)
        XCTAssertEqual(fixture.windowState.currentTabId, fixture.fallback?.id)
    }

    func testSelectedCloseWithoutFallbackCommitsFinalEmptyStateOnce() throws {
        let fixture = try makeFixture(hasFallback: false, liveTabIsSelected: true)

        XCTAssertTrue(fixture.service.close(fixture.liveTab, in: fixture.windowState))

        XCTAssertEqual(fixture.probe.commits, [.explicit])
        XCTAssertNil(fixture.windowState.currentTabId)
        XCTAssertNil(fixture.windowState.currentShortcutPinId)
        XCTAssertTrue(fixture.windowState.isShowingEmptyState)
        XCTAssertTrue(fixture.probe.registryWasClearedBeforeEmptyHandoff)
        XCTAssertTrue(fixture.probe.teardownObservedAfterVisualHandoff)
    }
}

private extension ShortcutLiveTabClosePersistenceTests {
    struct Fixture {
        let tabManager: TabManager
        let windowState: BrowserWindowState
        let pin: ShortcutPin
        let liveTab: Tab
        let fallback: Tab?
        let service: ShortcutLiveTabCloseService
        let probe: PersistenceProbe
    }

    enum Commit: Equatable {
        case retirement
        case explicit
    }

    final class PersistenceProbe {
        var commits: [Commit] = []
        var didPerformVisualHandoff = false
        var registryWasClearedBeforeEmptyHandoff = false
        var teardownObservedAfterVisualHandoff = false
    }

    func makeFixture(
        hasFallback: Bool,
        liveTabIsSelected: Bool
    ) throws -> Fixture {
        let windowState = BrowserWindowState()
        let probe = PersistenceProbe()
        let tabManager = try makeInMemoryTabManager(
            windowState: { $0 == windowState.id ? windowState : nil },
            windows: { [(windowState.id, windowState)] },
            unloadTab: { _ in
                probe.teardownObservedAfterVisualHandoff =
                    probe.didPerformVisualHandoff
            },
            persistWindowSession: { _ in probe.commits.append(.retirement) }
        )
        windowState.tabManager = tabManager
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
        windowState.currentSpaceId = space.id
        let fallback = hasFallback
            ? tabManager.regularTabLifecycleOwner.createNewTab(
                url: "https://fallback.example",
                in: space,
                activate: false
            )
            : nil
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: space.id,
            index: 0,
            launchURL: try XCTUnwrap(URL(string: "https://shortcut.example")),
            title: "Shortcut"
        )
        tabManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts(
            [pin],
            for: space.id
        )
        let liveTab = tabManager.shortcutTabMaterializer.materialize(
            pin,
            in: windowState.id,
            currentSpaceId: space.id
        )!
        if liveTabIsSelected {
            windowState.currentTabId = liveTab.id
            windowState.currentShortcutPinId = pin.id
            windowState.currentShortcutPinRole = pin.role
        } else {
            windowState.currentTabId = fallback?.id
        }

        let service = makeService(
            tabManager: tabManager,
            pin: pin,
            probe: probe
        )
        return Fixture(
            tabManager: tabManager,
            windowState: windowState,
            pin: pin,
            liveTab: liveTab,
            fallback: fallback,
            service: service,
            probe: probe
        )
    }

    func makeService(
        tabManager: TabManager,
        pin: ShortcutPin,
        probe: PersistenceProbe
    ) -> ShortcutLiveTabCloseService {
        ShortcutLiveTabCloseService(
            tabManager: { tabManager },
            recentlyClosedManager: { RecentlyClosedManager() },
            fallbackPlanner: {
                BrowserTabCloseFallbackPlanner(
                    selectionService: ShellSelectionService { _ in [] }
                )
            },
            selectTabWithoutPersistence: { tab, state in
                _ = WindowTabSelectionStateApplicator.apply(
                    tab,
                    to: state,
                    updateSpaceFromTab: true,
                    rememberSelection: true
                )
            },
            performImmediateVisualHandoffIfPossible: { _ in
                probe.didPerformVisualHandoff = true
            },
            persistWindowSession: { _ in probe.commits.append(.explicit) },
            showEmptyStateWithoutPersistence: { state in
                probe.registryWasClearedBeforeEmptyHandoff =
                    tabManager.shortcutPresentationOwner
                        .shortcutLiveTab(for: pin.id, in: state.id) == nil
                if let stillLive = tabManager.shortcutPresentationOwner
                    .shortcutLiveTab(for: pin.id, in: state.id) {
                    state.currentTabId = stillLive.id
                    state.currentShortcutPinId = pin.id
                    state.currentShortcutPinRole = pin.role
                    state.isShowingEmptyState = false
                } else {
                    state.currentTabId = nil
                    state.currentShortcutPinId = nil
                    state.currentShortcutPinRole = nil
                    state.isShowingEmptyState = true
                }
            },
            splitShortcuts: { nil },
            notifications: { nil }
        )
    }
}
