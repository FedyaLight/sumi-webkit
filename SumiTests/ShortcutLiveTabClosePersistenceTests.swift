import AppKit
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class ShortcutLiveTabClosePersistenceTests: XCTestCase {
    func testSelectedCloseWithFallbackCommitsWindowSessionOnce() throws {
        let fixture = try makeFixture(hasFallback: true, liveTabIsSelected: true)

        XCTAssertTrue(fixture.closeLiveTab())

        XCTAssertEqual(fixture.probe.commits, [.retirement])
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
        let currentWebView = WKWebView()
        try XCTUnwrap(fixture.fallback).replaceUntrackedWebView(currentWebView)

        XCTAssertTrue(fixture.closeLiveTab())

        XCTAssertTrue(fixture.probe.commits.isEmpty)
        XCTAssertEqual(fixture.windowState.currentTabId, fixture.fallback?.id)
        XCTAssertIdentical(
            fixture.fallback?.resolvedCurrentWebView(),
            currentWebView
        )
        XCTAssertFalse(fixture.probe.didPerformVisualHandoff)
    }

    func testSelectedCloseWithoutFallbackCommitsFinalEmptyStateOnce() throws {
        let fixture = try makeFixture(hasFallback: false, liveTabIsSelected: true)

        XCTAssertTrue(fixture.closeLiveTab())

        XCTAssertEqual(fixture.probe.commits, [.retirement])
        XCTAssertNil(fixture.windowState.currentTabId)
        XCTAssertNil(fixture.windowState.currentShortcutPinId)
        XCTAssertTrue(fixture.windowState.isShowingEmptyState)
        XCTAssertTrue(fixture.probe.registryWasClearedBeforeEmptyHandoff)
        XCTAssertTrue(fixture.probe.teardownObservedAfterVisualHandoff)
    }

    func testStandaloneCloseRejectsEquivalentTabWithSameID() throws {
        let fixture = try makeFixture(
            hasFallback: true,
            liveTabIsSelected: true
        )
        let replacement = Tab(
            id: fixture.liveTab.id,
            url: fixture.liveTab.url
        )
        replacement.isShortcutLiveInstance = true
        replacement.shortcutPinId = fixture.pin.id
        replacement.shortcutPinRole = fixture.pin.role

        XCTAssertFalse(
            fixture.transaction.close(
                replacement,
                pinID: fixture.pin.id,
                in: fixture.windowState,
                publishingHistory: {
                    XCTFail("Rejected identity must not publish history")
                }
            )
        )
        XCTAssertTrue(
            fixture.tabManager.shortcutPresentationOwner.shortcutLiveTab(
                for: fixture.pin.id,
                in: fixture.windowState.id
            ) === fixture.liveTab
        )
        XCTAssertTrue(fixture.probe.commits.isEmpty)
    }
}

private extension ShortcutLiveTabClosePersistenceTests {
    @MainActor
    struct Fixture {
        let tabManager: BrowserManager
        let windowState: BrowserWindowState
        let pin: ShortcutPin
        let liveTab: Tab
        let fallback: Tab?
        let compositorContainer: NSView
        let transaction: ShortcutLiveTabStandaloneCloseTransaction
        let probe: PersistenceProbe

        func closeLiveTab() -> Bool {
            transaction.close(
                liveTab,
                pinID: pin.id,
                in: windowState,
                publishingHistory: {}
            )
        }
    }

    enum Commit: Equatable {
        case retirement
        case explicit
    }

    @MainActor
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
        let profile = Profile(name: "Shortcut close persistence")
        let tabManager = BrowserManager(runtimePorts: TestRuntimePorts.make(
            currentProfileId: { profile.id },
            defaultProfileId: { profile.id },
            profile: { $0 == profile.id ? profile : nil },
            windowState: { $0 == windowState.id ? windowState : nil },
            windows: { [(windowState.id, windowState)] },
            notifyTabClosedIfLoaded: { _ in
                probe.teardownObservedAfterVisualHandoff =
                    probe.didPerformVisualHandoff
            },
            persistWindowSession: { _ in probe.commits.append(.retirement) }
        ))
        let space = try XCTUnwrap(tabManager.sidebarSpaceLifecycle.createSpace(
            name: "Space",
            icon: SumiPersistentGlyph.spaceDefaultIconValue,
            profileID: profile.id
        ))
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

        let compositorContainer = NSView()
        let transaction = makeTransaction(
            tabManager: tabManager,
            windowState: windowState,
            pin: pin,
            compositorContainer: compositorContainer,
            probe: probe
        )
        return Fixture(
            tabManager: tabManager,
            windowState: windowState,
            pin: pin,
            liveTab: liveTab,
            fallback: fallback,
            compositorContainer: compositorContainer,
            transaction: transaction,
            probe: probe
        )
    }

    func makeTransaction(
        tabManager: BrowserManager,
        windowState: BrowserWindowState,
        pin: ShortcutPin,
        compositorContainer: NSView,
        probe: PersistenceProbe
    ) -> ShortcutLiveTabStandaloneCloseTransaction {
        tabManager.windowRegistry.register(windowState)
        let fallbackPlanner = BrowserTabCloseFallbackPlanner(
            selectionService: ShellSelectionService(
                splitQuery: tabManager.splitQuery
            ),
            tabStore: tabManager.runtimeStore
        )
        tabManager.webViewRuntime.compositorRuntime.registerContainer(
            compositorContainer,
            for: windowState.id,
            immediateVisualHandoffHandler: {
                probe.didPerformVisualHandoff = true
                probe.registryWasClearedBeforeEmptyHandoff =
                    tabManager.shortcutPresentationOwner
                        .shortcutLiveTab(
                            for: pin.id,
                            in: windowState.id
                        ) == nil
                return true
            }
        )
        return ShortcutLiveTabStandaloneCloseTransaction(
            tabStore: tabManager.runtimeStore,
            structuralLookup: tabManager.structuralLookupCoordinator,
            retirement: tabManager.shortcutLiveTabRetirement,
            selectionTarget: ShortcutLiveTabCloseSelectionTarget(
                fallbackPlanner: fallbackPlanner,
                splitMembership: tabManager.splitGroupMembership
            ),
            visuals: tabManager.shellRuntime.windowVisuals
        )
    }
}
