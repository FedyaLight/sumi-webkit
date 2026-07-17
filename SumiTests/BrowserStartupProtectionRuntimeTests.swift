import Foundation
import SumiDomain
import XCTest

@testable import Sumi

@MainActor
final class BrowserStartupProtectionRuntimeTests: XCTestCase {
    func testMaterializationPolicyDefersOnlyPrimaryNormalTabsUntilRestoreFinishes() {
        let fixture = makeBrowser(appliedLevel: .protection)
        let runtime = fixture.browser.startupProtectionRuntime
        let normalTab = Tab(
            url: URL(string: "https://example.com/article")!,
            loadsCachedFaviconOnInit: false
        )
        let emptyTab = Tab(
            url: SumiSurface.emptyTabURL,
            loadsCachedFaviconOnInit: false
        )
        let extensionTab = Tab(
            url: URL(string: "safari-web-extension://ext-74657374/index.html")!,
            loadsCachedFaviconOnInit: false
        )

        XCTAssertTrue(runtime.shouldDeferNormalTabMaterializationDuringStartup)
        XCTAssertFalse(runtime.canMaterializeWebViewDuringStartup(normalTab))
        XCTAssertTrue(runtime.canMaterializeWebViewDuringStartup(emptyTab))
        XCTAssertTrue(runtime.canMaterializeWebViewDuringStartup(extensionTab))

        runtime.finishStartupProtectionRestore()

        XCTAssertFalse(runtime.shouldDeferNormalTabMaterializationDuringStartup)
        XCTAssertTrue(runtime.canMaterializeWebViewDuringStartup(normalTab))

        let offFixture = makeBrowser(appliedLevel: .off)
        let offRuntime = offFixture.browser.startupProtectionRuntime

        XCTAssertFalse(offRuntime.shouldDeferNormalTabMaterializationDuringStartup)
        XCTAssertTrue(offRuntime.canMaterializeWebViewDuringStartup(normalTab))
    }

    func testFinishDrainsDeferredBackgroundTabsAndVisibleWindowHooksOnce()
        async {
        let deferredTab = Tab(
            url: URL(string: "https://example.com/deferred")!,
            loadsCachedFaviconOnInit: false
        )
        let missingTab = Tab(
            url: URL(string: "https://example.com/missing")!,
            loadsCachedFaviconOnInit: false
        )
        let firstWindow = BrowserWindowState()
        let secondWindow = BrowserWindowState()
        let fixture = makeBrowser(appliedLevel: .protection)
        let browser = fixture.browser
        browser.runtimePortConnection.attach(TestRuntimePorts.make())
        browser.tabCollectionMembershipOwner.attach(deferredTab)
        XCTAssertEqual(browser.windowRegistry.register(firstWindow), .registered)
        XCTAssertEqual(browser.windowRegistry.register(secondWindow), .registered)
        let runtime = browser.startupProtectionRuntime

        runtime.deferBackgroundTabUntilStartupReady(deferredTab)
        runtime.deferBackgroundTabUntilStartupReady(missingTab)
        runtime.deferBackgroundTabUntilStartupReady(deferredTab)
        runtime.finishStartupProtectionRestore()
        runtime.finishStartupProtectionRestore()
        await Task.yield()

        XCTAssertFalse(deferredTab.webViewSession.allKnownWebViews.isEmpty)
        XCTAssertTrue(missingTab.webViewSession.allKnownWebViews.isEmpty)
        XCTAssertEqual(firstWindow.compositorInvalidation.compositorVersion, 1)
        XCTAssertEqual(secondWindow.compositorInvalidation.compositorVersion, 1)
    }

    func testBeginInTestsOpensNormalTabMaterializationGate() {
        let fixture = makeBrowser(appliedLevel: .protection)
        let runtime = fixture.browser.startupProtectionRuntime
        let normalTab = Tab(
            url: URL(string: "https://example.com/startup")!,
            loadsCachedFaviconOnInit: false
        )

        XCTAssertFalse(runtime.canMaterializeWebViewDuringStartup(normalTab))

        runtime.beginProtectionRestoreForStartupIfNeeded()

        XCTAssertTrue(runtime.canMaterializeWebViewDuringStartup(normalTab))
        XCTAssertFalse(runtime.shouldDeferNormalTabMaterializationDuringStartup)
    }

    private func makeBrowser(
        appliedLevel: SumiProtectionLevel
    ) -> StartupProtectionBrowserFixture {
        let suiteName = "BrowserStartupProtectionRuntimeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let moduleRegistry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: defaults)
        )
        let settings = SumiProtectionSettings(userDefaults: defaults)
        settings.setAppliedLevel(appliedLevel)
        let adBlockingModule = SumiAdBlockingModule(
            moduleRegistry: moduleRegistry,
            preparedBundleResourceURL: nil,
            preparedBundleRemoteRootURL: nil
        )
        let protectionCoordinator = SumiProtectionCoordinator(
            settings: settings,
            adBlockingModule: adBlockingModule,
            bundleUpdateStatusStore: SumiProtectionBundleUpdateStatusStore(
                userDefaults: defaults
            )
        )
        let browser = BrowserManager(
            windowRegistry: WindowRegistry(),
            moduleRegistry: moduleRegistry,
            adBlockingModule: adBlockingModule,
            protectionCoordinator: protectionCoordinator
        )
        return StartupProtectionBrowserFixture(
            browser: browser,
            defaultsSuiteName: suiteName
        )
    }
}

@MainActor
private final class StartupProtectionBrowserFixture {
    let browser: BrowserManager
    private let defaultsSuiteName: String

    init(browser: BrowserManager, defaultsSuiteName: String) {
        self.browser = browser
        self.defaultsSuiteName = defaultsSuiteName
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: defaultsSuiteName)
    }
}
