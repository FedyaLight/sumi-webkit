import WebKit
import XCTest

@testable import Sumi
@testable import Navigation
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
        let wkScript = SumiPageScriptBuilder.makeWKUserScript(from: script)

        XCTAssertEqual(wkScript.source, script.source)
        XCTAssertEqual(wkScript.injectionTime, .atDocumentStart)
        XCTAssertFalse(wkScript.isForMainFrameOnly)
    }

    func testScriptOverridesWebKitNativeFalseValue() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.addUserScript(
            SumiPageScriptBuilder.makeWKUserScript(from: SumiGPCUserScript())
        )
        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            configuration: configuration
        )
        let didFinish = expectation(description: "GPC fixture loaded")
        let delegate = SumiGPCNavigationDelegateBox {
            didFinish.fulfill()
        }
        webView.navigationDelegate = delegate

        webView.loadHTMLString("<!doctype html><html></html>", baseURL: nil)
        await fulfillment(of: [didFinish], timeout: 5)

        let value = try await webView.evaluateJavaScript(
            "navigator.globalPrivacyControl"
        ) as? Bool
        XCTAssertEqual(value, true)
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

    private func mainFrameAction(
        url: URL,
        httpMethod: String? = nil,
        isUserInitiated: Bool = true
    ) -> SumiNavigationAction {
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
            isUserInitiated: isUserInitiated,
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
        preferences.globalPrivacyControlEnabled = nil
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
        XCTAssertNil(preferences.globalPrivacyControlEnabled)
        XCTAssertEqual(webView.loadedRequests.count, 1)
        XCTAssertEqual(webView.loadedRequests.first?.value(forHTTPHeaderField: "Sec-GPC"), "1")
    }

    func testNavigatorExpectReusesActiveNavigationIdentity() throws {
        let webView = SumiGPCLoadRecordingWebView()
        _ = makeTab().installNavigationDelegate(on: webView)
        let navigator = try XCTUnwrap(webView.navigator())
        let physicalNavigation = try XCTUnwrap(
            webView.load(URLRequest(url: URL(string: "about:blank")!))
        )

        let policyNavigation = navigator.expect(physicalNavigation)
        let submittedNavigation = navigator.expect(physicalNavigation)

        XCTAssertEqual(
            policyNavigation.stableIdentifier,
            submittedNavigation.stableIdentifier
        )
        XCTAssertTrue(
            policyNavigation.identityLifetime === submittedNavigation.identityLifetime
        )
    }

    func testReentrantPolicyIdentityCanJoinLateBrowserSubmission() async throws {
        let targetURL = URL(string: "https://example.com/first-navigation")!
        let webView = SumiGPCLoadRecordingWebView()
        let tab = makeTab()
        _ = tab.installNavigationDelegate(on: webView)
        let navigator = try XCTUnwrap(webView.navigator())
        _ = tab.beginMainFrameNavigationIntent(to: targetURL)
        let submissionLease = try XCTUnwrap(
            tab.mainFrameLoads.claimDirectSubmission(on: webView)
        )
        let physicalNavigation = try XCTUnwrap(
            webView.load(URLRequest(url: URL(string: "about:blank")!))
        )

        // WebKit may deliver decidePolicy before load(_:) returns. Model that
        // ordering by resolving policy identity before the browser binds the
        // submitted load returned from the same physical WKNavigation.
        let policyNavigation = navigator.expect(physicalNavigation)
        let submittedNavigation = navigator.expect(physicalNavigation)
        XCTAssertTrue(
            tab.mainFrameSubmission.bindSubmittedLoad(
                on: webView,
                navigationID: submittedNavigation.stableIdentifier,
                navigationLifetime: submittedNavigation.identityLifetime,
                matching: submissionLease
            )
        )

        var diagnostics: [SumiGPCNavigationRewriteFailure] = []
        let responder = SumiGPCNavigationResponder(
            tab: tab,
            isGPCEnabledProvider: { true },
            recordDiagnostic: { diagnostics.append($0) }
        )
        var preferences = sumiPreferences()

        let policy = await responder.decidePolicy(
            for: mainFrameAction(
                url: targetURL,
                isUserInitiated: false
            ),
            targetWebView: webView,
            context: SumiNavigationActionContext(
                navigationID: policyNavigation.stableIdentifier,
                navigationLifetime: policyNavigation.identityLifetime
            ),
            preferences: &preferences
        )

        XCTAssertEqual(policy, .cancel)
        XCTAssertTrue(diagnostics.isEmpty)
        XCTAssertEqual(
            webView.loadedRequests.last?.value(forHTTPHeaderField: "Sec-GPC"),
            "1"
        )
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

    func testUnavailableTransactionRuntimeReturnsTypedFailureBeforeLoading() async {
        let webView = SumiGPCLoadRecordingWebView()
        let tab = makeTab()
        var diagnostics: [SumiGPCNavigationRewriteFailure] = []
        let responder = SumiGPCNavigationResponder(
            tab: tab,
            isGPCEnabledProvider: { true },
            recordDiagnostic: { diagnostics.append($0) }
        )
        var preferences = sumiPreferences()
        let originalNavigation = NSObject()

        let policy = await responder.decidePolicy(
            for: mainFrameAction(url: URL(string: "https://example.com/private?token=secret")!),
            targetWebView: webView,
            context: SumiNavigationActionContext(
                navigationID: ObjectIdentifier(originalNavigation),
                navigationLifetime: originalNavigation
            ),
            preferences: &preferences
        )

        XCTAssertEqual(policy, .cancel)
        XCTAssertTrue(webView.loadedRequests.isEmpty)
        XCTAssertEqual(diagnostics, [.unavailableTransactionRuntime])
    }

    func testMismatchedOriginalIdentityReturnsTypedFailureBeforeLoading() async {
        let webView = SumiGPCLoadRecordingWebView()
        let tab = makeTab()
        _ = tab.installNavigationDelegate(on: webView)
        var diagnostics: [SumiGPCNavigationRewriteFailure] = []
        let responder = SumiGPCNavigationResponder(
            tab: tab,
            isGPCEnabledProvider: { true },
            recordDiagnostic: { diagnostics.append($0) }
        )
        var preferences = sumiPreferences()
        let navigationIDObject = NSObject()
        let differentLifetime = NSObject()

        let policy = await responder.decidePolicy(
            for: mainFrameAction(url: URL(string: "https://example.com/private?token=secret")!),
            targetWebView: webView,
            context: SumiNavigationActionContext(
                navigationID: ObjectIdentifier(navigationIDObject),
                navigationLifetime: differentLifetime
            ),
            preferences: &preferences
        )

        XCTAssertEqual(policy, .cancel)
        XCTAssertTrue(webView.loadedRequests.isEmpty)
        XCTAssertEqual(diagnostics, [.originalNavigationIdentityMismatch])
        XCTAssertFalse(diagnostics[0].rawValue.contains("secret"))
    }

    func testReplacementRevisionMismatchStopsLoadAndReportsTypedFailure() async {
        let originalURL = URL(string: "https://example.com/private?token=secret")!
        let supersedingURL = URL(string: "https://superseding.example/")!
        let webView = SumiGPCLoadRecordingWebView()
        let tab = makeTab()
        _ = tab.installNavigationDelegate(on: webView)
        var diagnostics: [SumiGPCNavigationRewriteFailure] = []
        let responder = SumiGPCNavigationResponder(
            tab: tab,
            isGPCEnabledProvider: { true },
            recordDiagnostic: { diagnostics.append($0) }
        )
        webView.afterLoad = {
            _ = tab.beginMainFrameNavigationIntent(to: supersedingURL)
        }
        var preferences = sumiPreferences()
        let originalNavigation = NSObject()

        let policy = await responder.decidePolicy(
            for: mainFrameAction(url: originalURL),
            targetWebView: webView,
            context: SumiNavigationActionContext(
                navigationID: ObjectIdentifier(originalNavigation),
                navigationLifetime: originalNavigation
            ),
            preferences: &preferences
        )

        XCTAssertEqual(policy, .cancel)
        XCTAssertEqual(webView.stopLoadingCallCount, 1)
        XCTAssertTrue(webView.activeLoadedRequests.isEmpty)
        XCTAssertNotNil(tab.mainFrameLoads.currentIntent(matching: supersedingURL))
        XCTAssertNil(tab.mainFrameLoads.currentIntent(matching: originalURL))
        XCTAssertEqual(diagnostics, [.replacementTransactionMismatch])
        XCTAssertFalse(diagnostics[0].rawValue.contains("secret"))
    }

    func testDiagnosticBucketsHaveNoURLPayloadShape() {
        XCTAssertFalse(SumiGPCNavigationRewriteFailure.allCases.isEmpty)
        for failure in SumiGPCNavigationRewriteFailure.allCases {
            XCTAssertNil(failure.rawValue.range(of: #"[/?:=&]"#, options: .regularExpression))
        }
    }

    func testOriginalCancellationCannotRetireRewrittenNavigation() async {
        let targetURL = URL(string: "https://example.com/rewrite")!
        let initialURL = URL(string: "https://example.com")!
        let webView = SumiGPCLoadRecordingWebView()
        let transaction = TabMainFrameRuntimeTransaction(initialURL: initialURL)
        let tab = Tab(
            url: initialURL,
            mainFrameRuntimeTransaction: transaction
        )
        retainedTabs.append(tab)
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

        tab.makeMainFrameLifecycleResponder().mainFrameNavigationDidTerminate(
            SumiMainFrameNavigationTermination(
                navigationID: originalID,
                navigationLifetime: originalNavigation,
                webView: webView,
                reason: .actionCancelled
            )
        )

        XCTAssertFalse(transaction.role(
            from: webView,
            navigationID: originalID,
            isCurrent: true
        ).isAuthority)
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

    func testNativeWebKitGPCUsesNavigationPreferenceWithoutReloading() async {
        let webView = SumiGPCLoadRecordingWebView()
        let tab = makeTab()
        _ = tab.installNavigationDelegate(on: webView)
        let responder = SumiGPCNavigationResponder(
            tab: tab,
            isGPCEnabledProvider: { true }
        )
        var preferences = sumiPreferences()
        preferences.globalPrivacyControlEnabled = false
        let policy = await responder.decidePolicy(
            for: mainFrameAction(url: URL(string: "https://example.com/")!),
            targetWebView: webView,
            preferences: &preferences
        )

        XCTAssertNil(policy)
        XCTAssertEqual(preferences.globalPrivacyControlEnabled, true)
        XCTAssertTrue(webView.loadedRequests.isEmpty)
    }

    func testNavigationPreferencesBridgeSupportsRuntimeGPCSelector() {
        let webKitPreferences = WKWebpagePreferences()
        var preferences = NavigationPreferences(
            userAgent: nil,
            preferences: webKitPreferences
        )

        XCTAssertNotNil(
            preferences.globalPrivacyControlEnabled,
            "The adapter must recognize the GPC selector exposed by the running WebKit."
        )

        preferences.globalPrivacyControlEnabled = true
        _ = preferences.applying(to: webKitPreferences)

        let key = webKitPreferences.responds(
            to: NSSelectorFromString("globalPrivacyControlStatus")
        ) ? "globalPrivacyControlStatus" : "globalPrivacyControlEnabled"
        XCTAssertEqual(webKitPreferences.value(forKey: key) as? Bool, true)
    }

    func testDoesNotRewriteBeforeSettingsAreAvailable() async {
        let webView = SumiGPCLoadRecordingWebView()
        let responder = SumiGPCNavigationResponder(tab: makeTab())
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
    func testGPCIsDisabledByDefault() {
        let settings = SumiSettingsService(userDefaults: TestDefaultsHarness().defaults)

        XCTAssertFalse(settings.isGPCEnabled)
    }

    func testGPCTogglePersistsAcrossReload() {
        let harness = TestDefaultsHarness()
        let settings = SumiSettingsService(userDefaults: harness.defaults)

        settings.isGPCEnabled = true

        let reloaded = SumiSettingsService(userDefaults: harness.defaults)
        XCTAssertTrue(reloaded.isGPCEnabled)
    }

    func testCoreUserScriptsIncludeGPCScriptWhenEnabled() {
        let settings = SumiSettingsService(userDefaults: TestDefaultsHarness().defaults)
        settings.isGPCEnabled = true
        let tab = Tab(url: URL(string: "https://example.com")!)
        tab.sumiSettings = settings

        let scripts = tab.normalTabCoreUserScripts()

        XCTAssertTrue(scripts.contains { $0 is SumiGPCUserScript })
    }

    func testCoreUserScriptsExcludeGPCScriptWhenDisabled() {
        let settings = SumiSettingsService(userDefaults: TestDefaultsHarness().defaults)
        let tab = Tab(url: URL(string: "https://example.com")!)
        tab.sumiSettings = settings

        let scripts = tab.normalTabCoreUserScripts()

        XCTAssertFalse(scripts.contains { $0 is SumiGPCUserScript })
    }

    func testCoreUserScriptsTrackGPCToggleChangesForExistingTab() {
        let settings = SumiSettingsService(userDefaults: TestDefaultsHarness().defaults)
        let tab = Tab(url: URL(string: "https://example.com")!)
        tab.sumiSettings = settings

        XCTAssertFalse(tab.normalTabCoreUserScripts().contains { $0 is SumiGPCUserScript })

        settings.isGPCEnabled = true
        XCTAssertTrue(tab.normalTabCoreUserScripts().contains { $0 is SumiGPCUserScript })

        settings.isGPCEnabled = false
        XCTAssertFalse(tab.normalTabCoreUserScripts().contains { $0 is SumiGPCUserScript })
    }

    func testCoreUserScriptsDefaultToDisabledBeforeSettingsAreAvailable() {
        let tab = Tab(url: URL(string: "https://example.com")!)

        let scripts = tab.normalTabCoreUserScripts()

        XCTAssertFalse(scripts.contains { $0 is SumiGPCUserScript })
    }
}

@MainActor
final class SumiGPCLoadRecordingWebView: WKWebView {
    private(set) var loadedRequests: [URLRequest] = []
    private(set) var activeLoadedRequests: [URLRequest] = []
    private(set) var stopLoadingCallCount = 0
    var afterLoad: (() -> Void)?

    override func load(_ request: URLRequest) -> WKNavigation? {
        loadedRequests.append(request)
        activeLoadedRequests.append(request)
        let navigation = super.load(request)
        afterLoad?()
        return navigation
    }

    override func stopLoading() {
        stopLoadingCallCount += 1
        activeLoadedRequests.removeAll()
        super.stopLoading()
    }
}

private final class SumiGPCNavigationDelegateBox: NSObject, WKNavigationDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        _ = webView
        _ = navigation
        onFinish()
    }
}
