import SwiftData
import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionRequestedTabServicesTests: XCTestCase {
    func testRecentOpenRequestTrackerConsumesOnlyRecordedWebURLsOnce() {
        let history = ExtensionRecentTabRequestHistory()
        let url = URL(string: "https://example.com/login")!

        XCTAssertFalse(history.consume(url))

        history.record(url)

        XCTAssertTrue(history.consume(url))
        XCTAssertFalse(history.consume(url))
    }

    func testRecentOpenRequestTrackerIgnoresNonWebURLs() {
        let history = ExtensionRecentTabRequestHistory()
        let extensionURL = URL(string: "safari-web-extension://ext-id/popup.html")!

        history.record(extensionURL)

        XCTAssertFalse(history.consume(extensionURL))
    }

    func testActiveNormalTabWithoutTargetWindowKeepsMaterializedUntrackedWebView() throws {
        SafariExtensionLiveWebKitTestLease.holdForProcess()
        let container = try makeTestContainer()
        let profile = Profile(name: "Profile A")
        let manager = makeSafariExtensionTestExtensionManager(
            context: container.mainContext,
            initialProfile: profile
        )
        _ = manager.requestExtensionRuntime(
            reason: .attach,
            allowWithoutEnabledExtensions: true
        )
        let expectedController = manager.ensureExtensionController(for: profile.id)
        let browserManager = makeSafariExtensionTestBrowserManager(profile: profile)
        manager.attach(browserManager: browserManager)
        let materializer = manager.requestedTabWebViewMaterializer
        let tab = browserManager.tabManager.tabFactory.makeTab(
            url: URL(string: "https://example.com")!,
            name: "Extension requested"
        )
        tab.profileId = profile.id
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))

        materializer.materializeNormalTabIfNeeded(
            tab,
            isActive: true,
            targetWindow: nil
        )

        let materializedWebView = try XCTUnwrap(tab.resolvedCurrentWebView())
        XCTAssertNil(tab.resolvedPrimaryWindowId())
        XCTAssertIdentical(
            manager.ownedUntrackedCurrentWebView(for: tab),
            materializedWebView
        )
        XCTAssertIdentical(
            materializedWebView.configuration.webExtensionController,
            expectedController
        )

        materializer.materializeNormalTabIfNeeded(
            tab,
            isActive: true,
            targetWindow: nil
        )

        XCTAssertIdentical(tab.resolvedCurrentWebView(), materializedWebView)
    }

    func testRequestedTargetSpaceUsesContextProfileWhenCurrentSpaceBelongsToAnotherProfile() throws {
        let harness = try makeProfileRoutingHarness()
        let resolver = harness.manager.requestedTabTargetResolver

        let targetSpace = resolver.targetSpace(
            for: nil,
            contextProfileId: harness.profileB.id
        )

        XCTAssertEqual(targetSpace?.id, harness.spaceB.id)
    }

    func testRegularExtensionTabInheritsTargetSpaceProfileIdentity() throws {
        let harness = try makeProfileRoutingHarness()

        let tab = harness.browserManager.extensionBridgeComposition.tabMutation
            .createExtensionTab(
                url: URL(string: "https://example.com/profile-b")!,
                in: harness.spaceB,
                activate: false,
                webExtensionContextOverride: nil
            )

        XCTAssertEqual(tab.spaceId, harness.spaceB.id)
        XCTAssertNil(tab.profileId)
        XCTAssertIdentical(tab.resolveProfile(), harness.profileB)
    }

    func testExtensionTargetSpaceWithoutWindowDoesNotFallbackToGlobalCurrentSpace() throws {
        let harness = try makeProfileRoutingHarness()

        let targetSpace = harness.browserManager.extensionBridgeComposition
            .requestedTabTargets.extensionTargetSpace(
            for: nil as BrowserWindowState?
        )

        XCTAssertNil(targetSpace)
    }

    func testExtensionTargetSpaceForTabWithoutSpaceDoesNotFallbackToGlobalCurrentSpace() throws {
        let harness = try makeProfileRoutingHarness()
        let tab = Tab(
            url: URL(string: "https://example.com/no-space")!,
            name: "No Space"
        )

        let targetSpace = harness.browserManager.extensionBridgeComposition
            .requestedTabTargets.extensionTargetSpace(for: tab)

        XCTAssertNil(targetSpace)
    }

    func testActiveWindowCurrentTabDoesNotFallbackToGlobalTabManagerCurrentTab() throws {
        let harness = try makeProfileRoutingHarness()
        let tab = harness.browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/current",
            in: harness.spaceA,
            activate: true
        )

        XCTAssertEqual(harness.browserManager.tabManager.selectionStateOwner.currentTab?.id, tab.id)
        XCTAssertNil(
            harness.browserManager.extensionBridgeComposition.windows
                .currentExtensionTabForActiveWindow()
        )
    }

    func testPreferredExtensionWindowStateResolvesTransientTabFromDisplayedSpace() throws {
        let harness = try makeProfileRoutingHarness()
        let windowRegistry = WindowRegistry()
        harness.browserManager.windowRegistry = windowRegistry
        let windowState = BrowserWindowState()
        windowState.currentProfileId = harness.profileA.id
        windowState.currentSpaceId = harness.spaceA.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        let tab = harness.browserManager.tabManager.transientWebKitTabLifecycleOwner.createTransientExtensionTab(
            url: "safari-web-extension://extension-id/popup.html",
            in: harness.spaceA,
            webExtensionContextOverride: nil
        )

        XCTAssertTrue(harness.browserManager.tabManager.transientWebKitTabLifecycleOwner.isTransientExtensionTab(tab))
        XCTAssertFalse(
            harness.browserManager.tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot()[harness.spaceA.id]?.contains { $0.id == tab.id }
                ?? false
        )
        XCTAssertEqual(
            harness.browserManager.extensionBridgeComposition.windows
                .preferredExtensionWindowState(containing: tab)?.id,
            windowState.id
        )
    }

    func testExtensionTargetSpaceUsesWindowProfileBeforeCurrentSpaceFallback() throws {
        let harness = try makeProfileRoutingHarness()
        let windowState = BrowserWindowState()
        windowState.currentProfileId = harness.profileB.id
        windowState.currentSpaceId = harness.spaceA.id

        let targetSpace = harness.browserManager.extensionBridgeComposition
            .requestedTabTargets.extensionTargetSpace(for: windowState)

        XCTAssertEqual(targetSpace?.id, harness.spaceB.id)
    }

    private func makeTestContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private struct ProfileRoutingHarness {
        let manager: ExtensionManager
        let browserManager: BrowserManager
        let profileA: Profile
        let profileB: Profile
        let spaceA: Space
        let spaceB: Space
    }

    private func makeProfileRoutingHarness() throws -> ProfileRoutingHarness {
        let container = try makeTestContainer()
        let profileA = Profile(name: "Profile A")
        let profileB = Profile(name: "Profile B")
        let manager = makeSafariExtensionTestExtensionManager(
            context: container.mainContext,
            initialProfile: profileA
        )
        let browserManager = makeSafariExtensionTestBrowserManager(profile: profileA)
        browserManager.profileManager.profiles = [profileA, profileB]
        browserManager.currentProfile = profileA

        let spaceA = Space(name: "Space A", profileId: profileA.id)
        let spaceB = Space(name: "Space B", profileId: profileB.id)
        browserManager.tabManager.spaceStateOwner.replaceSpaces([spaceA, spaceB])
        browserManager.tabManager.spaceStateOwner.replaceCurrentSpace(spaceA)
        manager.attach(browserManager: browserManager)

        return ProfileRoutingHarness(
            manager: manager,
            browserManager: browserManager,
            profileA: profileA,
            profileB: profileB,
            spaceA: spaceA,
            spaceB: spaceB
        )
    }
}
