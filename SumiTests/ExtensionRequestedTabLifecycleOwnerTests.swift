import SwiftData
import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionRequestedTabLifecycleOwnerTests: XCTestCase {
    func testRecentOpenRequestTrackerConsumesOnlyRecordedWebURLsOnce() {
        let owner = ExtensionRequestedTabLifecycleOwner()
        let url = URL(string: "https://example.com/login")!

        XCTAssertFalse(owner.consumeRecentlyOpenedTabRequest(for: url))

        owner.recordRecentlyOpenedTabRequest(for: url)

        XCTAssertTrue(owner.consumeRecentlyOpenedTabRequest(for: url))
        XCTAssertFalse(owner.consumeRecentlyOpenedTabRequest(for: url))
    }

    func testRecentOpenRequestTrackerIgnoresNonWebURLs() {
        let owner = ExtensionRequestedTabLifecycleOwner()
        let extensionURL = URL(string: "safari-web-extension://ext-id/popup.html")!

        owner.recordRecentlyOpenedTabRequest(for: extensionURL)

        XCTAssertFalse(owner.consumeRecentlyOpenedTabRequest(for: extensionURL))
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
        let owner = ExtensionRequestedTabLifecycleOwner()
        let tab = Tab(
            url: URL(string: "https://example.com")!,
            name: "Extension requested"
        )
        tab.profileId = profile.id
        tab.attachBrowserRuntime(browserManager.makeTabBrowserRuntime())

        owner.materializeNormalTabIfNeeded(
            tab,
            isActive: true,
            targetWindow: nil,
            manager: manager
        )

        let materializedWebView = try XCTUnwrap(tab.currentWebView)
        XCTAssertNil(tab.primaryWindowId)
        XCTAssertIdentical(
            manager.ownedUntrackedCurrentWebView(for: tab),
            materializedWebView
        )
        XCTAssertIdentical(
            materializedWebView.configuration.webExtensionController,
            expectedController
        )

        owner.materializeNormalTabIfNeeded(
            tab,
            isActive: true,
            targetWindow: nil,
            manager: manager
        )

        XCTAssertIdentical(tab.currentWebView, materializedWebView)
    }

    func testRequestedTargetSpaceUsesContextProfileWhenCurrentSpaceBelongsToAnotherProfile() throws {
        let harness = try makeProfileRoutingHarness()
        let owner = ExtensionRequestedTabLifecycleOwner()

        let targetSpace = owner.requestedTargetSpace(
            for: nil,
            contextProfileId: harness.profileB.id,
            manager: harness.manager
        )

        XCTAssertEqual(targetSpace?.id, harness.spaceB.id)
    }

    func testExtensionTargetSpaceWithoutWindowDoesNotFallbackToGlobalCurrentSpace() throws {
        let harness = try makeProfileRoutingHarness()

        let targetSpace = harness.browserManager.extensionTargetSpace(
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

        let targetSpace = harness.browserManager.extensionTargetSpace(for: tab)

        XCTAssertNil(targetSpace)
    }

    func testPopupCurrentTabDoesNotFallbackToGlobalTabManagerCurrentTab() throws {
        let harness = try makeProfileRoutingHarness()
        let tab = harness.browserManager.tabManager.createNewTab(
            url: "https://example.com/current",
            in: harness.spaceA,
            activate: true
        )

        XCTAssertEqual(harness.browserManager.tabManager.currentTab?.id, tab.id)
        XCTAssertNil(harness.browserManager.currentExtensionTabForPopup())
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

        let tab = harness.browserManager.tabManager.createTransientExtensionTab(
            url: "safari-web-extension://extension-id/popup.html",
            in: harness.spaceA,
            webExtensionContextOverride: nil
        )

        XCTAssertTrue(harness.browserManager.tabManager.isTransientExtensionTab(tab))
        XCTAssertFalse(
            harness.browserManager.tabManager.tabsBySpace[harness.spaceA.id]?.contains { $0.id == tab.id }
                ?? false
        )
        XCTAssertEqual(
            harness.browserManager.preferredExtensionWindowState(containing: tab)?.id,
            windowState.id
        )
    }

    func testExtensionTargetSpaceUsesWindowProfileBeforeCurrentSpaceFallback() throws {
        let harness = try makeProfileRoutingHarness()
        let windowState = BrowserWindowState()
        windowState.currentProfileId = harness.profileB.id
        windowState.currentSpaceId = harness.spaceA.id

        let targetSpace = harness.browserManager.extensionTargetSpace(for: windowState)

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
        browserManager.tabManager.spaces = [spaceA, spaceB]
        browserManager.tabManager.currentSpace = spaceA
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
