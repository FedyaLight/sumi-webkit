import AppKit
import SumiDomain
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class ShortcutLiveTabClosePersistenceTests: XCTestCase {
    func testSidebarUnloadReleasesFavoriteAndPinnedRuntimeInstances() throws {
        for role in [ShortcutPinRole.favorite, .spacePinned] {
            try assertSidebarUnloadReleasesRuntimeInstance(role: role)
        }
    }

    func testSidebarUnloadReleasesDriftedFavoriteAndPinnedRuntimeInstances()
        throws {
        for role in [ShortcutPinRole.favorite, .spacePinned] {
            try assertSidebarUnloadReleasesRuntimeInstance(
                role: role,
                drifted: true
            )
        }
    }

    func testSelectedCloseWithFallbackCommitsWindowSessionOnce() throws {
        let fixture = try makeFixture(hasFallback: true, liveTabIsSelected: true)

        XCTAssertTrue(
            fixture.tabManager.tabCloseOrchestration.closeTab(
                fixture.liveTab,
                in: fixture.windowState
            )
        )

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

    func testRestoredSelectedCloseUsesPreviousRegularCandidate() throws {
        let fixture = try makeFixture(
            hasFallback: true,
            liveTabIsSelected: true,
            restoredLiveSession: true
        )

        XCTAssertEqual(
            fixture.liveTab.url,
            URL(string: "https://shortcut.example/continued")
        )
        XCTAssertEqual(fixture.windowState.currentTabId, fixture.liveTab.id)
        XCTAssertEqual(
            fixture.windowState.currentShortcutPinId,
            fixture.pin.id
        )

        XCTAssertTrue(
            fixture.tabManager.tabCloseOrchestration.closeTab(
                fixture.liveTab,
                in: fixture.windowState
            )
        )

        XCTAssertEqual(fixture.windowState.currentTabId, fixture.fallback?.id)
        XCTAssertNil(fixture.windowState.currentShortcutPinId)
        XCTAssertNil(
            fixture.tabManager.shortcutPresentationOwner.shortcutLiveTab(
                for: fixture.pin.id,
                in: fixture.windowState.id
            )
        )
    }

    func testRestoredSelectedUnloadUsesPreviousRegularCandidate() throws {
        let fixture = try makeFixture(
            hasFallback: true,
            liveTabIsSelected: true,
            restoredLiveSession: true
        )

        let unloaded = fixture.tabManager
            .composeSidebarShortcutPinUnloadOwner()
            .unloadShortcutPin(
                fixture.pin,
                in: fixture.windowState,
                suppressNotification: true
            )

        XCTAssertTrue(unloaded)
        XCTAssertEqual(fixture.windowState.currentTabId, fixture.fallback?.id)
        XCTAssertNil(fixture.windowState.currentShortcutPinId)
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
        liveTabIsSelected: Bool,
        restoredLiveSession: Bool = false
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
        tabManager.tabResidenceAuthority.establishResidenceSession(
            on: windowState
        )
        let fallback = hasFallback
            ? tabManager.regularTabLifecycleOwner.createNewTab(
                url: "https://fallback.example",
                in: space,
                activate: false
            )
            : nil
        if restoredLiveSession, let fallback {
            _ = tabManager.regularTabLifecycleOwner.createNewTab(
                url: "https://other-fallback.example",
                in: space,
                activate: false
            )
            windowState.activeTabForSpace[space.id] = fallback.id
        }
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
        let liveTab: Tab
        if restoredLiveSession {
            windowState.currentTabId = UUID()
            windowState.currentShortcutPinId = pin.id
            windowState.currentShortcutPinRole = pin.role
            windowState.restorationState.stageShortcutLiveSessions([
                ShortcutLiveSessionSnapshot(
                    shortcutPinId: pin.id,
                    presentationSpaceId: space.id,
                    currentURL: try XCTUnwrap(
                        URL(string: "https://shortcut.example/continued")
                    ),
                    title: "Restored Shortcut"
                ),
            ])
            let restorer = WindowSessionShortcutRestorer(
                pins: tabManager.shortcutPinCollectionStateOwner,
                activation: tabManager.shortcutPresentationActivation
            )
            restorer.materializeRestoredLiveSessions(in: windowState)
            liveTab = try XCTUnwrap(
                tabManager.shortcutPresentationOwner.shortcutLiveTab(
                    for: pin.id,
                    in: windowState.id
                )
            )
        } else {
            liveTab = tabManager.shortcutTabMaterializer.materialize(
                pin,
                in: windowState.id,
                currentSpaceId: space.id
            )!
        }
        if liveTabIsSelected {
            if restoredLiveSession {
                XCTAssertTrue(
                    WindowSessionShortcutRestorer(
                        pins: tabManager.shortcutPinCollectionStateOwner,
                        activation: tabManager.shortcutPresentationActivation
                    ).materializeSelectionIfNeeded(in: windowState)
                )
            } else {
                windowState.currentTabId = liveTab.id
                windowState.currentShortcutPinId = pin.id
                windowState.currentShortcutPinRole = pin.role
            }
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

    private func assertSidebarUnloadReleasesRuntimeInstance(
        role: ShortcutPinRole,
        drifted: Bool = false
    ) throws {
        let windowRegistry = WindowRegistry()
        let browser = BrowserManager(windowRegistry: windowRegistry)
        let profile = Profile(name: "Runtime release")
        let space = Space(name: "Runtime release", profileId: profile.id)
        let window = BrowserWindowState()

        browser.profileManager.profiles = [profile]
        browser.currentProfile = profile
        browser.spaceStateOwner.replaceSpaces([space])
        browser.spaceStateOwner.replaceCurrentSpace(space)
        browser.tabResidenceAuthority.establishResidenceSession(on: window)
        window.currentSpaceId = space.id
        window.currentProfileId = profile.id
        XCTAssertEqual(windowRegistry.register(window), .registered)

        let pin = try XCTUnwrap(browser.shortcutPinStoreOwner.insert(
            ShortcutPin(
                id: UUID(),
                role: role,
                profileId: role == .favorite ? profile.id : nil,
                spaceId: role == .spacePinned ? space.id : nil,
                index: 0,
                launchURL: try XCTUnwrap(
                    URL(string: "https://runtime-release.example")
                ),
                title: "Runtime release"
            ),
            at: 0
        ))
        let hostRegistry = WindowWebContentHostRegistry()
        var retainedHost: SumiWebViewContainerView?
        weak var releasedTab: Tab?
        weak var releasedWebView: WKWebView?
        try autoreleasepool {
            let liveTab = try XCTUnwrap(
                browser.shortcutTabMaterializer.materialize(
                    pin,
                    in: window.id,
                    currentSpaceId: space.id
                )
            )
            let webView = WKWebView()
            liveTab.replaceUntrackedWebView(webView)
            if drifted {
                liveTab.url = try XCTUnwrap(
                    URL(string: "https://runtime-release.example/current")
                )
                XCTAssertNotEqual(liveTab.url, pin.launchURL)
                XCTAssertTrue(
                    browser.shortcutPresentationOwner.shortcutHasDrifted(
                        pin,
                        in: window
                    )
                )
                XCTAssertIdentical(
                    browser.shortcutTabMaterializer.materialize(
                        pin,
                        in: window.id,
                        currentSpaceId: space.id
                    ),
                    liveTab
                )
            }
            XCTAssertEqual(liveTab.webViewSession.allKnownWebViews.count, 1)
            XCTAssertIdentical(
                liveTab.webViewSession.allKnownWebViews.first,
                webView
            )
            let host = SumiWebViewContainerView(
                tabID: liveTab.id,
                webView: webView
            )
            retainedHost = host
            hostRegistry.parkHost(host)
            window.currentTabId = liveTab.id
            window.currentShortcutPinId = pin.id
            window.currentShortcutPinRole = role
            releasedTab = liveTab
            releasedWebView = webView

            XCTAssertTrue(
                browser.composeSidebarShortcutPinUnloadOwner()
                    .unloadShortcutPin(
                        pin,
                        in: window,
                        suppressNotification: true
                    )
            )
            XCTAssertNil(
                browser.liveShortcutTabs.tab(for: pin.id, in: window.id)
            )
            XCTAssertNil(browser.webViewSessions.residence(of: webView))
            XCTAssertNil(
                hostRegistry.parkedHost(
                    for: liveTab.id,
                    webView: webView
                )
            )
        }

        XCTAssertNotNil(retainedHost)
        XCTAssertNil(
            releasedTab,
            "Unloading a \(role) launcher must release its transient Tab"
        )
        XCTAssertNil(
            releasedWebView,
            "Unloading a \(role) launcher must release its WKWebView"
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
