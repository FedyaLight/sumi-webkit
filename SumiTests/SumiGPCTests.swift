import WebKit
import XCTest

@testable import Sumi
import SumiDomain

@MainActor
final class SumiGPCUserScriptTests: XCTestCase {
    func testScriptDefinesGlobalPrivacyControlOnNavigatorPrototype() {
        let script = SumiGPCUserScript()

        XCTAssertTrue(script.source.contains("Navigator.prototype"))
        XCTAssertTrue(script.source.contains("globalPrivacyControl"))
        XCTAssertTrue(script.source.contains("get: function() { return true; }"))
    }

    func testScriptRunsAtDocumentStartInAllFramesInThePageWorld() {
        let script = SumiGPCUserScript()

        XCTAssertEqual(script.injectionTime, .atDocumentStart)
        XCTAssertFalse(script.forMainFrameOnly, "GPC must apply to subframes too, per spec.")
        XCTAssertTrue(script.requiresRunInPageContentWorld, "Must be visible to page JS, not just the client world.")
        XCTAssertEqual(script.messageNames, [])
    }

    func testBuiltWKUserScriptMatchesDeclaredShape() {
        let script = SumiGPCUserScript()
        let wkScript = SumiUserScriptBuilder.makeWKUserScript(from: script)

        XCTAssertEqual(wkScript.source, script.source)
        XCTAssertEqual(wkScript.injectionTime, .atDocumentStart)
        XCTAssertFalse(wkScript.isForMainFrameOnly)
    }
}

final class SumiGPCRequestFactoryTests: XCTestCase {
    private let factory = SumiGPCRequestFactory()

    func testAddsHeaderToEligibleGETRequestMissingHeader() {
        let request = URLRequest(url: URL(string: "https://example.com/")!)

        let rewritten = factory.requestAddingGPCHeaderIfNeeded(to: request, isGPCEnabled: true)

        XCTAssertEqual(rewritten?.value(forHTTPHeaderField: "Sec-GPC"), "1")
    }

    func testReturnsNilWhenGPCDisabled() {
        let request = URLRequest(url: URL(string: "https://example.com/")!)

        let rewritten = factory.requestAddingGPCHeaderIfNeeded(to: request, isGPCEnabled: false)

        XCTAssertNil(rewritten)
    }

    func testReturnsNilWhenHeaderAlreadyPresentIdempotence() {
        var request = URLRequest(url: URL(string: "https://example.com/")!)
        request.setValue("1", forHTTPHeaderField: "Sec-GPC")

        let rewritten = factory.requestAddingGPCHeaderIfNeeded(to: request, isGPCEnabled: true)

        XCTAssertNil(rewritten, "Must not rewrite a request that already carries the header, to avoid a reload loop.")
    }

    func testSkipsPOSTRequests() {
        var request = URLRequest(url: URL(string: "https://example.com/login")!)
        request.httpMethod = "POST"
        request.httpBody = Data("user=me".utf8)

        let rewritten = factory.requestAddingGPCHeaderIfNeeded(to: request, isGPCEnabled: true)

        XCTAssertNil(rewritten, "Must never rewrite POSTs/form submissions.")
    }

    func testSkipsNonHTTPSchemes() {
        let request = URLRequest(url: URL(string: "sumi://newtab")!)

        let rewritten = factory.requestAddingGPCHeaderIfNeeded(to: request, isGPCEnabled: true)

        XCTAssertNil(rewritten)
    }

    func testDefaultsToGETWhenHTTPMethodIsUnset() {
        var request = URLRequest(url: URL(string: "https://example.com/")!)
        request.httpMethod = nil

        let rewritten = factory.requestAddingGPCHeaderIfNeeded(to: request, isGPCEnabled: true)

        XCTAssertEqual(rewritten?.value(forHTTPHeaderField: "Sec-GPC"), "1")
    }
}

@MainActor
final class SumiGPCNavigationResponderTests: XCTestCase {
    private var retainedTabs: [Tab] = []

    private func makeTab() -> Tab {
        let tab = Tab(url: URL(string: "https://example.com")!)
        retainedTabs.append(tab)
        return tab
    }

    private func mainFrameAction(url: URL, httpMethod: String? = nil) -> SumiNavigationAction {
        var request = URLRequest(url: url)
        request.httpMethod = httpMethod
        return SumiNavigationAction(
            request: request,
            url: url,
            sourceURL: nil,
            sourceFrame: nil,
            targetFrame: nil,
            isTargetingNewWindow: false,
            isForMainFrame: true,
            isUserInitiated: true,
            navigationType: .other,
            navigationTypeDescription: "0",
            redirectHistory: SumiNavigationRedirectHistory(),
            mainFrameNavigation: nil,
            modifierFlags: [],
            shouldDownload: false,
            isUserEnteredURL: false,
            isCustom: false,
            isClientRedirect: false
        )
    }

    func testCancelsAndReloadsWithHeaderWhenEnabledAndEligible() async {
        let webView = SumiGPCLoadRecordingWebView()
        let tab = makeTab()
        _ = tab.installNavigationDelegate(on: webView)
        let responder = SumiGPCNavigationResponder(
            tab: tab,
            isGPCEnabledProvider: { true }
        )
        var preferences = sumiPreferences()
        let originalNavigation = NSObject()

        let policy = await responder.decidePolicy(
            for: mainFrameAction(url: URL(string: "https://example.com/")!),
            targetWebView: webView,
            context: SumiNavigationActionContext(
                navigationID: ObjectIdentifier(originalNavigation),
                navigationLifetime: originalNavigation
            ),
            preferences: &preferences
        )

        XCTAssertEqual(policy, .cancel)
        XCTAssertEqual(webView.loadedRequests.count, 1)
        XCTAssertEqual(webView.loadedRequests.first?.value(forHTTPHeaderField: "Sec-GPC"), "1")
    }

    func testAllowsNavigationOnSecondPassOnceHeaderIsPresent() async {
        let webView = SumiGPCLoadRecordingWebView()
        let tab = makeTab()
        _ = tab.installNavigationDelegate(on: webView)
        let responder = SumiGPCNavigationResponder(
            tab: tab,
            isGPCEnabledProvider: { true }
        )
        var preferences = sumiPreferences()
        let originalNavigation = NSObject()

        let policy = await responder.decidePolicy(
            for: mainFrameAction(url: URL(string: "https://example.com/already-tagged")!, httpMethod: "GET"),
            targetWebView: webView,
            context: SumiNavigationActionContext(
                navigationID: ObjectIdentifier(originalNavigation),
                navigationLifetime: originalNavigation
            ),
            preferences: &preferences
        )
        // First pass rewrites and cancels.
        XCTAssertEqual(policy, .cancel)

        // Simulate the reissued request already carrying the header.
        var taggedRequest = URLRequest(url: URL(string: "https://example.com/already-tagged")!)
        taggedRequest.setValue("1", forHTTPHeaderField: "Sec-GPC")
        let secondAction = SumiNavigationAction(
            request: taggedRequest,
            url: taggedRequest.url,
            sourceURL: nil,
            sourceFrame: nil,
            targetFrame: nil,
            isTargetingNewWindow: false,
            isForMainFrame: true,
            isUserInitiated: true,
            navigationType: .other,
            navigationTypeDescription: "0",
            redirectHistory: SumiNavigationRedirectHistory(),
            mainFrameNavigation: nil,
            modifierFlags: [],
            shouldDownload: false,
            isUserEnteredURL: false,
            isCustom: false,
            isClientRedirect: false
        )
        let secondPolicy = await responder.decidePolicy(
            for: secondAction,
            targetWebView: webView,
            preferences: &preferences
        )

        XCTAssertNil(secondPolicy, "Once the header is present the responder must step aside (.next) for the rest of the chain.")
        XCTAssertEqual(webView.loadedRequests.count, 1, "Must not reload a second time.")
    }

    func testFailsClosedWithoutExactOriginalNavigationIdentity() async {
        let webView = SumiGPCLoadRecordingWebView()
        let tab = makeTab()
        _ = tab.installNavigationDelegate(on: webView)
        let responder = SumiGPCNavigationResponder(
            tab: tab,
            isGPCEnabledProvider: { true }
        )
        var preferences = sumiPreferences()

        let policy = await responder.decidePolicy(
            for: mainFrameAction(url: URL(string: "https://example.com/")!),
            targetWebView: webView,
            preferences: &preferences
        )

        XCTAssertEqual(policy, .cancel)
        XCTAssertTrue(webView.loadedRequests.isEmpty)
    }

    func testOriginalCancellationCannotRetireRewrittenNavigation() async {
        let targetURL = URL(string: "https://example.com/rewrite")!
        let webView = SumiGPCLoadRecordingWebView()
        let tab = makeTab()
        _ = tab.installNavigationDelegate(on: webView)
        let responder = SumiGPCNavigationResponder(
            tab: tab,
            isGPCEnabledProvider: { true }
        )
        var preferences = sumiPreferences()
        let originalNavigation = NSObject()
        let originalID = ObjectIdentifier(originalNavigation)

        let policy = await responder.decidePolicy(
            for: mainFrameAction(url: targetURL),
            targetWebView: webView,
            context: SumiNavigationActionContext(
                navigationID: originalID,
                navigationLifetime: originalNavigation
            ),
            preferences: &preferences
        )
        XCTAssertEqual(policy, .cancel)

        SumiTabLifecycleNavigationResponder(tab: tab).mainFrameNavigationDidTerminate(
            SumiMainFrameNavigationTermination(
                navigationID: originalID,
                navigationLifetime: originalNavigation,
                webView: webView,
                reason: .actionCancelled
            )
        )

        XCTAssertFalse(tab.shouldAcceptMainFrameLifecycle(
            from: webView,
            navigationID: originalID,
            isCurrent: true
        ))
        XCTAssertNotNil(tab.mainFrameLoads.currentIntent(matching: targetURL))
    }

    func testDoesNotRewriteWhenGPCDisabled() async {
        let webView = SumiGPCLoadRecordingWebView()
        let responder = SumiGPCNavigationResponder(
            tab: makeTab(),
            isGPCEnabledProvider: { false }
        )
        var preferences = sumiPreferences()

        let policy = await responder.decidePolicy(
            for: mainFrameAction(url: URL(string: "https://example.com/")!),
            targetWebView: webView,
            preferences: &preferences
        )

        XCTAssertNil(policy)
        XCTAssertTrue(webView.loadedRequests.isEmpty)
    }

    func testIgnoresSubframeNavigations() async {
        let webView = SumiGPCLoadRecordingWebView()
        let responder = SumiGPCNavigationResponder(
            tab: makeTab(),
            isGPCEnabledProvider: { true }
        )
        var preferences = sumiPreferences()
        let subframeAction = SumiNavigationAction(
            request: URLRequest(url: URL(string: "https://embedded.example/frame")!),
            url: URL(string: "https://embedded.example/frame"),
            sourceURL: nil,
            sourceFrame: nil,
            targetFrame: nil,
            isTargetingNewWindow: false,
            isForMainFrame: false,
            isUserInitiated: true,
            navigationType: .other,
            navigationTypeDescription: "0",
            redirectHistory: SumiNavigationRedirectHistory(),
            mainFrameNavigation: nil,
            modifierFlags: [],
            shouldDownload: false,
            isUserEnteredURL: false,
            isCustom: false,
            isClientRedirect: false
        )

        let policy = await responder.decidePolicy(
            for: subframeAction,
            targetWebView: webView,
            preferences: &preferences
        )

        XCTAssertNil(policy)
        XCTAssertTrue(webView.loadedRequests.isEmpty)
    }

    private func sumiPreferences() -> SumiNavigationPreferences {
        SumiNavigationPreferences(
            userAgent: nil,
            contentMode: .recommended,
            javaScriptEnabled: true,
            autoplayPolicy: nil,
            mustApplyAutoplayPolicy: false
        )
    }
}

@MainActor
final class SumiGPCSettingsTests: XCTestCase {
    func testGPCIsEnabledByDefault() {
        let settings = SumiSettingsService(userDefaults: TestDefaultsHarness().defaults)

        XCTAssertTrue(settings.isGPCEnabled)
    }

    func testGPCTogglePersistsAcrossReload() {
        let harness = TestDefaultsHarness()
        let settings = SumiSettingsService(userDefaults: harness.defaults)

        settings.isGPCEnabled = false

        let reloaded = SumiSettingsService(userDefaults: harness.defaults)
        XCTAssertFalse(reloaded.isGPCEnabled)
    }

    func testCoreUserScriptsIncludeGPCScriptWhenEnabled() {
        let settings = SumiSettingsService(userDefaults: TestDefaultsHarness().defaults)
        let tab = Tab(url: URL(string: "https://example.com")!)
        tab.sumiSettings = settings

        let scripts = tab.normalTabCoreUserScripts()

        XCTAssertTrue(scripts.contains { $0 is SumiGPCUserScript })
    }

    func testCoreUserScriptsExcludeGPCScriptWhenDisabled() {
        let settings = SumiSettingsService(userDefaults: TestDefaultsHarness().defaults)
        settings.isGPCEnabled = false
        let tab = Tab(url: URL(string: "https://example.com")!)
        tab.sumiSettings = settings

        let scripts = tab.normalTabCoreUserScripts()

        XCTAssertFalse(scripts.contains { $0 is SumiGPCUserScript })
    }
}

@MainActor
final class SumiGPCLoadRecordingWebView: WKWebView {
    private(set) var loadedRequests: [URLRequest] = []

    override func load(_ request: URLRequest) -> WKNavigation? {
        loadedRequests.append(request)
        return super.load(request)
    }
}
