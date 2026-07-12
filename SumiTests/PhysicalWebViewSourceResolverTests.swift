import SwiftData
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class PhysicalWebViewSourceResolverTests: XCTestCase {
    func testPrivateSourceRequiresExactManagedEphemeralProfileLease() throws {
        let browser = try makeBrowser()
        let registry = WindowRegistry()
        let window = BrowserWindowState()
        let profile = browser.profileManager.createEphemeralProfile(
            for: window.id
        )
        let fixture = try installPrivateSource(
            browser: browser,
            registry: registry,
            window: window,
            profile: profile
        )

        let receipt = try XCTUnwrap(
            fixture.resolver.resolve(fixture.webView)
        )

        XCTAssertEqual(receipt.residence, .privateEphemeral)
        XCTAssertIdentical(receipt.window, window)
        XCTAssertIdentical(receipt.tab, fixture.tab)
        XCTAssertIdentical(receipt.presentationProfile, profile)
        XCTAssertIdentical(receipt.executionProfile, profile)
        XCTAssertIdentical(receipt.dataStore, profile.dataStore)
        XCTAssertTrue(
            browser.profileManager.hasEphemeralProfileLease(
                profile,
                forWindowID: window.id
            )
        )
    }

    func testPrivateSourceAcceptsExplicitlySharedChildWindowLease() throws {
        let browser = try makeBrowser()
        let registry = WindowRegistry()
        let sourceWindowID = UUID()
        let childWindow = BrowserWindowState()
        let profile = browser.profileManager.createEphemeralProfile(
            for: sourceWindowID
        )
        XCTAssertIdentical(
            browser.profileManager.shareEphemeralProfile(
                from: sourceWindowID,
                with: childWindow.id
            ),
            profile
        )
        let fixture = try installPrivateSource(
            browser: browser,
            registry: registry,
            window: childWindow,
            profile: profile
        )

        let receipt = try XCTUnwrap(
            fixture.resolver.resolve(fixture.webView)
        )

        XCTAssertIdentical(receipt.window, childWindow)
        XCTAssertIdentical(receipt.executionProfile, profile)
        XCTAssertTrue(
            browser.profileManager.hasEphemeralProfileLease(
                profile,
                forWindowID: sourceWindowID
            )
        )
        XCTAssertTrue(
            browser.profileManager.hasEphemeralProfileLease(
                profile,
                forWindowID: childWindow.id
            )
        )
    }

    func testPrivateSourceRejectsAnotherWindowsUnsharedLeaseWithoutMutation()
        throws {
        let browser = try makeBrowser()
        let registry = WindowRegistry()
        let leaseWindowID = UUID()
        let counterfeitWindow = BrowserWindowState()
        let profile = browser.profileManager.createEphemeralProfile(
            for: leaseWindowID
        )
        let fixture = try installPrivateSource(
            browser: browser,
            registry: registry,
            window: counterfeitWindow,
            profile: profile
        )
        let tabSnapshot = counterfeitWindow.ephemeralTabs
        let currentTabID = counterfeitWindow.currentTabId

        XCTAssertNil(fixture.resolver.resolve(fixture.webView))

        XCTAssertEqual(counterfeitWindow.ephemeralTabs.map(\.id), tabSnapshot.map(\.id))
        XCTAssertEqual(counterfeitWindow.currentTabId, currentTabID)
        XCTAssertIdentical(
            browser.testWebViewRuntime().ownershipQuery.webView(
                for: fixture.tab.id,
                in: counterfeitWindow.id
            ),
            fixture.webView
        )
        XCTAssertTrue(
            browser.profileManager.hasEphemeralProfileLease(
                profile,
                forWindowID: leaseWindowID
            )
        )
        XCTAssertFalse(
            browser.profileManager.hasEphemeralProfileLease(
                profile,
                forWindowID: counterfeitWindow.id
            )
        )
    }

    func testPrivateSourceRejectsPersistentProfileWithoutMutation() throws {
        let browser = try makeBrowser()
        let registry = WindowRegistry()
        let window = BrowserWindowState()
        let profile = Profile(name: "Persistent")
        browser.profileManager.profiles = [profile]
        let fixture = try installPrivateSource(
            browser: browser,
            registry: registry,
            window: window,
            profile: profile
        )
        let tabSnapshot = window.ephemeralTabs
        let currentTabID = window.currentTabId

        XCTAssertNil(fixture.resolver.resolve(fixture.webView))

        XCTAssertTrue(profile.dataStore.isPersistent)
        XCTAssertEqual(window.ephemeralTabs.map(\.id), tabSnapshot.map(\.id))
        XCTAssertEqual(window.currentTabId, currentTabID)
        XCTAssertIdentical(
            browser.testWebViewRuntime().ownershipQuery.webView(
                for: fixture.tab.id,
                in: window.id
            ),
            fixture.webView
        )
        XCTAssertFalse(
            browser.profileManager.hasEphemeralProfileLease(
                profile,
                forWindowID: window.id
            )
        )
    }

    func testReceiptBecomesStaleWhenExactTrackedSlotIsReplaced() throws {
        let browser = try makeBrowser()
        let registry = WindowRegistry()
        let window = BrowserWindowState()
        let profile = browser.profileManager.createEphemeralProfile(
            for: window.id
        )
        let fixture = try installPrivateSource(
            browser: browser,
            registry: registry,
            window: window,
            profile: profile
        )
        let receipt = try XCTUnwrap(
            fixture.resolver.resolve(fixture.webView)
        )
        let replacement = makeWebView(profile: profile, tab: fixture.tab)

        browser.testWebViewRuntime().trackedWebViewAdmission.registerAuxiliaryTrackedWebView(
            replacement,
            for: fixture.tab,
            in: window.id
        )

        XCTAssertFalse(fixture.resolver.isCurrent(receipt))
        XCTAssertNil(fixture.resolver.resolve(fixture.webView))
        let replacementReceipt = try XCTUnwrap(
            fixture.resolver.resolve(replacement)
        )
        XCTAssertTrue(fixture.resolver.isCurrent(replacementReceipt))
        XCTAssertIdentical(replacementReceipt.webView, replacement)
    }

    private func installPrivateSource(
        browser: BrowserManager,
        registry: WindowRegistry,
        window: BrowserWindowState,
        profile: Profile
    ) throws -> PrivatePhysicalSourceFixture {
        browser.windowRegistry = registry
        let space = Space(name: "Private", profileId: profile.id)
        space.isEphemeral = true
        window.isIncognito = true
        window.ephemeralProfile = profile
        window.ephemeralSpaces = [space]
        window.currentProfileId = profile.id
        window.currentSpaceId = space.id
        window.tabManager = browser.tabManager
        registry.register(window)

        let tab = browser.tabManager.ephemeralLifecycleOwner.createEphemeralTab(
            url: try XCTUnwrap(URL(string: "https://private.example")),
            in: window,
            profile: profile
        )
        let webView = makeWebView(profile: profile, tab: tab)
        browser.testWebViewRuntime().trackedWebViewAdmission.registerAuxiliaryTrackedWebView(
            webView,
            for: tab,
            in: window.id
        )
        let resolver = PhysicalWebViewSourceResolver(
            ownership: browser.testWebViewRuntime().ownershipQuery,
            tabs: browser.tabManager,
            profiles: browser.profileManager,
            registry: { [weak registry] in registry }
        )
        return PrivatePhysicalSourceFixture(
            resolver: resolver,
            tab: tab,
            webView: webView
        )
    }

    private func makeWebView(
        profile: Profile,
        tab: Tab
    ) -> FocusableWKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = profile.dataStore
        let webView = FocusableWKWebView(
            frame: .zero,
            configuration: configuration
        )
        webView.owningTab = tab
        return webView
    }

    private func makeBrowser() throws -> BrowserManager {
        BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: try ModelContainer(
                    for: SumiStartupPersistence.schema,
                    configurations: [
                        ModelConfiguration(isStoredInMemoryOnly: true),
                    ]
                )
            )
        )
    }
}

@MainActor
private struct PrivatePhysicalSourceFixture {
    let resolver: PhysicalWebViewSourceResolver
    let tab: Tab
    let webView: FocusableWKWebView
}
