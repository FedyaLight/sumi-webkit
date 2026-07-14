import Foundation
import SumiDomain
@testable import Sumi
import XCTest

@MainActor
final class BrowserWindowSpaceTransitionServiceTests: XCTestCase {
    func testLiveTransitionRequiresExactActiveWindowIdentity() {
        UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey)
        defer {
            UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey)
        }

        let browserManager = BrowserManager()
        let windowID = UUID()
        let activeWindow = BrowserWindowState(id: windowID)
        let staleStateWithSameID = BrowserWindowState(id: windowID)
        let registry = WindowRegistry()
        browserManager.windowRegistry = registry
        activeWindow.tabManager = browserManager.tabManager
        staleStateWithSameID.tabManager = browserManager.tabManager
        registry.register(activeWindow)
        registry.setActive(activeWindow)
        let source = browserManager.tabManager.spaceServices.catalog
            .createSpace(name: "Source")
        let destination = browserManager.tabManager.spaceServices.catalog
            .createSpace(name: "Destination")
        browserManager.tabManager.spaceStateOwner.replaceCurrentSpace(source)
        staleStateWithSameID.currentSpaceId = source.id

        BrowserWindowSpaceTransitionService(browserManager: browserManager)
            .setActiveSpace(
                destination,
                in: staleStateWithSameID
            )

        XCTAssertIdentical(
            browserManager.tabManager.spaceStateOwner.currentSpace,
            source
        )
        XCTAssertEqual(staleStateWithSameID.currentSpaceId, destination.id)
    }

    func testActiveWindowTransitionPreservesCrossSubsystemOrder() throws {
        let harness = try BrowserWindowSpaceTransitionHarness()

        harness.makeService().setActiveSpace(
            harness.destination,
            in: harness.windowState
        )

        XCTAssertEqual(
            harness.events,
            [
                "focused-runtime", "theme", "select", "visual-handoff",
                "adopt", "persist", "split-focus",
            ]
        )
        XCTAssertTrue(harness.observedProcessActivationBeforeTheme)
        XCTAssertIdentical(
            harness.tabManager.spaceStateOwner.currentSpace,
            harness.destination
        )
        XCTAssertIdentical(
            harness.tabManager.selectionStateOwner.currentTab,
            harness.targetTab
        )
        XCTAssertEqual(harness.windowState.currentSpaceId, harness.destination.id)
        XCTAssertEqual(harness.windowState.currentProfileId, harness.destination.profileId)
        XCTAssertEqual(harness.windowState.currentTabId, harness.targetTab?.id)
        XCTAssertEqual(harness.events.filter { $0 == "persist" }.count, 1)
    }

    func testInactiveWindowTransitionDoesNotMutateProcessSpaceOrAdoptProfile() throws {
        let harness = try BrowserWindowSpaceTransitionHarness()
        harness.isActiveWindow = false

        harness.makeService().setActiveSpace(
            harness.destination,
            in: harness.windowState
        )

        XCTAssertEqual(
            harness.events,
            ["theme", "select", "visual-handoff", "persist", "split-focus"]
        )
        XCTAssertIdentical(
            harness.tabManager.spaceStateOwner.currentSpace,
            harness.source
        )
        XCTAssertNil(harness.tabManager.selectionStateOwner.currentTab)
        XCTAssertEqual(harness.windowState.currentSpaceId, harness.destination.id)
        XCTAssertEqual(harness.events.filter { $0 == "persist" }.count, 1)
    }

    func testEmptyDestinationPresentsEmptyStateWithoutVisualHandoff() throws {
        let harness = try BrowserWindowSpaceTransitionHarness(hasTargetTab: false)

        harness.makeService().setActiveSpace(
            harness.destination,
            in: harness.windowState
        )

        XCTAssertEqual(
            harness.events,
            [
                "focused-runtime", "theme", "empty", "adopt", "persist",
                "split-focus",
            ]
        )
        XCTAssertNil(harness.tabManager.selectionStateOwner.currentTab)
    }

    func testSameSpaceFastPathRefreshesContextAndPersistsWithoutActivation() throws {
        let harness = try BrowserWindowSpaceTransitionHarness()
        let targetTab = try XCTUnwrap(harness.targetTab)
        harness.windowState.currentSpaceId = harness.destination.id
        harness.windowState.currentProfileId = nil
        harness.windowState.currentTabId = targetTab.id

        harness.makeService().setActiveSpace(
            harness.destination,
            in: harness.windowState
        )

        XCTAssertEqual(
            harness.events,
            ["sanitize", "focused-runtime", "shortcut-sync", "persist"]
        )
        XCTAssertIdentical(
            harness.tabManager.spaceStateOwner.currentSpace,
            harness.source
        )
        XCTAssertEqual(harness.windowState.currentProfileId, harness.destination.profileId)
        XCTAssertEqual(harness.events.filter { $0 == "persist" }.count, 1)
    }

    func testStaleInteractiveIdentityHasNoSideEffects() throws {
        let harness = try BrowserWindowSpaceTransitionHarness()
        let currentIdentity = SpaceTransitionIdentity(
            sourceSpaceId: harness.source.id,
            destinationSpaceId: harness.destination.id
        )
        harness.windowState.windowThemeState.beginInteractive(
            identity: currentIdentity,
            from: harness.source.workspaceTheme,
            to: harness.destination.workspaceTheme,
            initialProgress: 0.5
        )
        let staleIdentity = SpaceTransitionIdentity(
            sourceSpaceId: harness.source.id,
            destinationSpaceId: harness.destination.id
        )

        harness.makeService().setActiveSpace(
            harness.destination,
            in: harness.windowState,
            completingTransition: staleIdentity
        )

        XCTAssertTrue(harness.events.isEmpty)
        XCTAssertEqual(harness.windowState.currentSpaceId, harness.source.id)
        XCTAssertIdentical(
            harness.tabManager.spaceStateOwner.currentSpace,
            harness.source
        )
    }

    func testMatchingInteractiveIdentityUsesFinishInsteadOfProgrammaticTheme() throws {
        let harness = try BrowserWindowSpaceTransitionHarness()
        let identity = SpaceTransitionIdentity(
            sourceSpaceId: harness.source.id,
            destinationSpaceId: harness.destination.id
        )
        harness.windowState.windowThemeState.beginInteractive(
            identity: identity,
            from: harness.source.workspaceTheme,
            to: harness.destination.workspaceTheme,
            initialProgress: 0.5
        )

        harness.makeService().setActiveSpace(
            harness.destination,
            in: harness.windowState,
            completingTransition: identity
        )

        XCTAssertEqual(
            harness.events,
            [
                "focused-runtime", "finish", "select", "visual-handoff",
                "adopt", "persist", "split-focus",
            ]
        )
        XCTAssertTrue(harness.observedProcessActivationBeforeTheme)
    }
}

@MainActor
private final class BrowserWindowSpaceTransitionHarness {
    let tabManager: TabManager
    let source: Space
    let destination: Space
    let targetTab: Tab?
    let windowState = BrowserWindowState()

    var isActiveWindow = true
    var events: [String] = []
    var observedProcessActivationBeforeTheme = false

    init(hasTargetTab: Bool = true) throws {
        tabManager = try makeInMemoryTabManager()
        source = Space(name: "Source", profileId: UUID())
        destination = Space(
            name: "Destination",
            workspaceTheme: WorkspaceTheme(gradientTheme: .incognito),
            profileId: UUID()
        )
        targetTab = hasTargetTab
            ? Tab(
                url: URL(string: "https://space-transition.example")
                    ?? URL(fileURLWithPath: "/"),
                name: "Destination",
                spaceId: destination.id,
                loadsCachedFaviconOnInit: false
            )
            : nil

        tabManager.spaceStateOwner.replaceSpaces([source, destination])
        tabManager.spaceStateOwner.replaceCurrentSpace(source)
        tabManager.regularTabCollectionStateOwner.replaceTabsBySpace([
            destination.id: targetTab.map { [$0] } ?? [],
        ])
        destination.activeTabId = targetTab?.id
        windowState.currentSpaceId = source.id
        windowState.currentProfileId = source.profileId
        windowState.tabManager = tabManager
    }

    func makeService() -> BrowserWindowSpaceTransitionService {
        let selectionService = ShellSelectionService { _ in [] }
        let tabContext = BrowserWindowTabContext(
            selectionService: { selectionService },
            tabStore: { [weak tabManager] in tabManager?.runtimeStore },
            windows: { [weak windowState] in windowState.map { [$0] } ?? [] },
            liveShortcutTabs: { [weak tabManager] windowId in
                tabManager?.runtimeStore.liveShortcutTabs(in: windowId) ?? []
            },
            visibleSplitTabIds: { _ in [] }
        )
        let selectionHandoff = BrowserWindowSpaceSelectionHandoff(
            tabContext: tabContext,
            applyTabSelection: { [weak self] tab, windowState in
                windowState.currentTabId = tab.id
                self?.events.append("select")
            },
            performImmediateVisualHandoff: { [weak self] _ in
                self?.events.append("visual-handoff")
            },
            showEmptyState: { [weak self] _ in
                self?.events.append("empty")
            }
        )
        let contextTransition = BrowserWindowSpaceContextTransition(
            contextReconciler: BrowserWindowSpaceContextReconciler(
                tabManager: tabManager,
                commitWorkspaceTheme: { _, _ in
                    XCTFail("Space transition must not commit a second theme")
                }
            ),
            sanitizeFloatingBarState: { [weak self] _ in
                self?.events.append("sanitize")
            },
            syncShortcutSelectionState: { [weak self] _ in
                self?.events.append("shortcut-sync")
            },
            updateWorkspaceTheme: { [weak self] _, _, _ in
                self?.recordThemeEvent("theme")
            },
            finishInteractiveTransition: { [weak self] _, _, _ in
                self?.recordThemeEvent("finish")
            }
        )

        return BrowserWindowSpaceTransitionService(
            spaceActivation: tabManager.spaceServices.activation,
            isActiveWindow: { [weak self] _ in
                self?.isActiveWindow ?? false
            },
            selectionHandoff: selectionHandoff,
            contextTransition: contextTransition,
            synchronizeFocusedSpaceContext: { [weak self] windowState in
                self?.recordFocusedRuntimeSynchronization(for: windowState)
            },
            adoptProfileForSpaceChange: { [weak self] _ in
                self?.events.append("adopt")
            },
            persistWindowSession: { [weak self] _ in
                self?.events.append("persist")
            },
            completePendingSplitGroupFocus: { [weak self] _, _ in
                self?.events.append("split-focus")
            }
        )
    }

    private func recordThemeEvent(_ event: String) {
        observedProcessActivationBeforeTheme =
            tabManager.spaceStateOwner.currentSpace === destination
        events.append(event)
    }

    private func recordFocusedRuntimeSynchronization(
        for windowState: BrowserWindowState
    ) {
        XCTAssertEqual(windowState.currentSpaceId, destination.id)
        XCTAssertEqual(windowState.currentProfileId, destination.profileId)
        events.append("focused-runtime")
    }
}
