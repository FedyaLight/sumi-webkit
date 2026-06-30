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
        tab.browserManager = browserManager

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

    private func makeTestContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }
}
