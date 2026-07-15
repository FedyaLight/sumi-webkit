import AppKit
import SumiDomain
import SwiftData
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class ShortcutPhysicalSourceRoutingTests: XCTestCase {
    func testResolverRejectsMismatchedExecutionDataStore() throws {
        let harness = try makeHarness(
            role: .essential,
            sourceDataStore: .nonPersistent()
        )
        defer { closePublishedShells(in: harness.registry) }

        XCTAssertNil(harness.resolver.resolve(harness.sourceWebView))
    }

    func testWindowLocalShortcutLeaseRejectsWrongWindowClone() throws {
        let harness = try makeHarness(role: .spacePinned)
        defer { closePublishedShells(in: harness.registry) }
        let secondWindow = BrowserWindowState()
        secondWindow.tabManager = harness.browser.tabManager
        secondWindow.currentProfileId = harness.presentationProfile.id
        secondWindow.currentSpaceId = harness.space.id
        secondWindow.currentTabId = harness.sourceTab.id
        harness.registry.register(secondWindow)

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = harness.executionProfile.dataStore
        let wrongWindowClone = FocusableWKWebView(
            frame: .zero,
            configuration: configuration
        )
        wrongWindowClone.owningTab = harness.sourceTab
        harness.browser.testWebViewRuntime().trackedWebViewAdmission
            .registerAuxiliaryTrackedWebView(
                wrongWindowClone,
                for: harness.sourceTab,
                in: secondWindow.id
            )

        XCTAssertNil(harness.resolver.resolve(wrongWindowClone))
        let exact = try XCTUnwrap(
            harness.resolver.resolve(harness.sourceWebView)
        )
        XCTAssertEqual(exact.residence, .windowShortcut(.spacePinned))
        XCTAssertIdentical(exact.window, harness.sourceWindow)
    }

    func testEssentialAndSpacePinnedRoutesPreserveExecutionPartition()
        throws {
        for role in [ShortcutPinRole.essential, .spacePinned] {
            let harness = try makeHarness(role: role)
            defer { closePublishedShells(in: harness.registry) }
            let receipt = try XCTUnwrap(
                harness.resolver.resolve(harness.sourceWebView)
            )
            XCTAssertEqual(receipt.residence, .windowShortcut(role))
            XCTAssertIdentical(receipt.presentationSpace, harness.space)
            XCTAssertIdentical(
                receipt.presentationProfile,
                harness.presentationProfile
            )
            XCTAssertIdentical(
                receipt.executionProfile,
                harness.executionProfile
            )

            let tabURL = try XCTUnwrap(URL(
                string: "https://\(role.rawValue).example/link-tab"
            ))
            XCTAssertTrue(harness.sourceTab.linkPresentationCommands.open(
                tabURL,
                from: harness.sourceWebView,
                disposition: .newTab(selected: false)
            ))
            let linkTab = try XCTUnwrap(
                harness.browser.tabManager.regularTabCollectionOwner
                    .tabs(in: harness.space)
                    .first(where: { $0.url == tabURL })
            )
            XCTAssertEqual(linkTab.profileId, harness.executionProfile.id)
            XCTAssertEqual(linkTab.spaceId, harness.space.id)

            let existingWindowIDs = Set(harness.registry.windows.keys)
            let windowURL = try XCTUnwrap(URL(
                string: "https://\(role.rawValue).example/link-window"
            ))
            XCTAssertTrue(harness.sourceTab.linkPresentationCommands.open(
                windowURL,
                from: harness.sourceWebView,
                disposition: .newWindow(selected: false)
            ))
            let childWindow = try XCTUnwrap(
                harness.registry.allWindows.first(where: {
                    existingWindowIDs.contains($0.id) == false
                })
            )
            let childTabID = try XCTUnwrap(childWindow.currentTabId)
            let windowTab = try XCTUnwrap(
                harness.browser.tabManager.tabCollectionMembershipOwner
                    .tab(for: childTabID)
            )
            XCTAssertEqual(childWindow.currentProfileId, harness.presentationProfile.id)
            XCTAssertEqual(childWindow.currentSpaceId, harness.space.id)
            XCTAssertEqual(windowTab.profileId, harness.executionProfile.id)
            XCTAssertEqual(windowTab.spaceId, harness.space.id)

            let popupConfiguration = WKWebViewConfiguration()
            popupConfiguration.websiteDataStore =
                harness.executionProfile.dataStore
            let popup = try XCTUnwrap(
                harness.sourceTab.navigationRuntime.webKitChildTabOpening?
                    .open(
                        configuration: popupConfiguration,
                        requestURL: URL(
                            string: "https://\(role.rawValue).example/popup"
                        ),
                        from: harness.sourceWebView,
                        selected: false,
                        isExtensionOriginated: false
                    ) as? FocusableWKWebView
            )
            let popupTab = try XCTUnwrap(popup.owningTab)
            XCTAssertEqual(popupTab.profileId, harness.executionProfile.id)
            XCTAssertEqual(popupTab.spaceId, harness.space.id)
            XCTAssertIdentical(
                popup.configuration.websiteDataStore,
                harness.executionProfile.dataStore
            )
        }
    }

    func testExtensionWebKitChildWindowRejectsCrossProfileSourceBeforeMutation()
        throws {
        let harness = try makeHarness(role: .essential)
        defer { closePublishedShells(in: harness.registry) }
        let existingWindowIDs = Set(harness.registry.windows.keys)
        let existingTabIDs = Set(
            harness.browser.tabManager.regularTabCollectionStateOwner
                .allTabsSnapshot().map(\.id)
        )
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = harness.executionProfile.dataStore

        let childWebView = harness.sourceTab.navigationRuntime
            .webKitChildWindowOpening?.open(
                configuration: configuration,
                requestURL: URL(
                    string: "https://extension.example/cross-profile"
                ),
                from: harness.sourceWebView,
                activate: true,
                isExtensionOriginated: true
            )

        XCTAssertNil(childWebView)
        XCTAssertEqual(Set(harness.registry.windows.keys), existingWindowIDs)
        XCTAssertEqual(
            Set(
                harness.browser.tabManager.regularTabCollectionStateOwner
                    .allTabsSnapshot().map(\.id)
            ),
            existingTabIDs
        )
        XCTAssertEqual(
            harness.sourceWindow.currentTabId,
            harness.sourceTab.id
        )
    }

    private func makeHarness(
        role: ShortcutPinRole,
        sourceDataStore: WKWebsiteDataStore? = nil
    ) throws -> Harness {
        let browser = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: try ModelContainer(
                    for: SumiStartupPersistence.schema,
                    configurations: [ModelConfiguration(
                        isStoredInMemoryOnly: true
                    )]
                )
            )
        )
        let settings = SumiSettingsService(
            userDefaults: TestDefaultsHarness().defaults
        )
        let registry = WindowRegistry()
        let presentationProfile = Profile(name: "Presentation")
        let executionProfile = Profile(name: "Execution")
        let space = Space(
            name: "Presentation Space",
            profileId: presentationProfile.id
        )
        let sourceWindow = BrowserWindowState()

        browser.sumiSettings = settings
        browser.profileManager.profiles = [
            presentationProfile,
            executionProfile,
        ]
        browser.currentProfile = presentationProfile
        browser.windowRegistry = registry
        browser.windowShellContentViewFactory = { _, _ in NSView() }
        browser.tabManager.spaceStateOwner.replaceSpaces([space])
        browser.tabManager.spaceStateOwner.replaceCurrentSpace(space)
        sourceWindow.tabManager = browser.tabManager
        sourceWindow.currentProfileId = presentationProfile.id
        sourceWindow.currentSpaceId = space.id
        registry.register(sourceWindow)
        registry.setActive(sourceWindow)
        installRegistrationRestoration(from: browser, on: registry)

        let pin = ShortcutPin(
            id: UUID(),
            role: role,
            profileId: role == .essential ? presentationProfile.id : nil,
            executionProfileId: executionProfile.id,
            spaceId: role == .spacePinned ? space.id : nil,
            index: 0,
            launchURL: URL(string: "https://source.example")!,
            title: "Source"
        )
        let canonicalPin = try XCTUnwrap(
            browser.tabManager.shortcutPinStoreOwner.insert(pin, at: 0)
        )
        let sourceTab = browser.tabManager.shortcutTabMaterializer.materialize(
            canonicalPin,
            in: sourceWindow.id,
            currentSpaceId: space.id
        )!
        sourceWindow.currentTabId = sourceTab.id

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = sourceDataStore
            ?? executionProfile.dataStore
        let sourceWebView = FocusableWKWebView(
            frame: .zero,
            configuration: configuration
        )
        sourceWebView.owningTab = sourceTab
        browser.testWebViewRuntime().trackedWebViewAdmission.registerAuxiliaryTrackedWebView(
            sourceWebView,
            for: sourceTab,
            in: sourceWindow.id
        )
        let resolver = PhysicalWebViewSourceResolver(
            ownership: browser.testWebViewRuntime().ownershipQuery,
            tabs: browser.tabManager,
            profiles: browser.profileManager,
            registry: { [weak registry] in registry }
        )
        XCTAssertTrue(sourceTab.hasBrowserRuntime)
        return Harness(
            browser: browser,
            settings: settings,
            registry: registry,
            sourceWindow: sourceWindow,
            presentationProfile: presentationProfile,
            executionProfile: executionProfile,
            space: space,
            sourceTab: sourceTab,
            sourceWebView: sourceWebView,
            resolver: resolver
        )
    }

    private func installRegistrationRestoration(
        from browser: BrowserManager,
        on registry: WindowRegistry
    ) {
        let restoration = browser.windowSessionBundle.restoration
        installWindowRegistryTestEventSink(
            on: registry,
            prepareWindowRegistration: { [weak restoration] window in
                restoration?.prepareRegistration(window)
            },
            publishWindowRegistration: { [weak restoration] window in
                restoration?.commitRegistration(window)
            }
        )
    }

    private func closePublishedShells(in registry: WindowRegistry) {
        for window in registry.allWindows {
            let shell = registry.appKitWindow(for: window)
            registry.unregister(window.id)
            shell?.orderOut(nil)
        }
    }
}

@MainActor
private struct Harness {
    let browser: BrowserManager
    let settings: SumiSettingsService
    let registry: WindowRegistry
    let sourceWindow: BrowserWindowState
    let presentationProfile: Profile
    let executionProfile: Profile
    let space: Space
    let sourceTab: Tab
    let sourceWebView: FocusableWKWebView
    let resolver: PhysicalWebViewSourceResolver
}
