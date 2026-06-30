import Combine
@testable import Sumi
import WebKit
import XCTest

@MainActor
final class NormalTabInitialDocumentRuntimeHandoffTests: XCTestCase {
    func testPerformRunsUserContentWarmupRegisterBeforeLoadInOrder() async {
        var events: [String] = []

        await NormalTabInitialDocumentRuntimeHandoff.perform {
            events.append("waitUserContent")
        } warmInitialDocumentContexts: {
            events.append("warmInitialDocumentContexts")
        } isStillValid: {
            true
        } register: {
            events.append("register")
        } load: {
            events.append("load")
        }

        XCTAssertEqual(
            events,
            [
                "waitUserContent",
                "warmInitialDocumentContexts",
                "register",
                "load",
            ]
        )
    }

    func testPerformSkipsWarmupWhenCommandIsNoLongerValidAfterUserContent() async {
        var events: [String] = []

        await NormalTabInitialDocumentRuntimeHandoff.perform {
            events.append("waitUserContent")
        } warmInitialDocumentContexts: {
            events.append("warmInitialDocumentContexts")
        } isStillValid: {
            false
        } register: {
            events.append("register")
        } load: {
            events.append("load")
        }

        XCTAssertEqual(
            events,
            [
                "waitUserContent",
            ]
        )
    }

    func testPerformStopsAfterWarmupWhenCommandIsNoLongerValidBeforeLoad() async {
        var events: [String] = []
        var isValid = true

        await NormalTabInitialDocumentRuntimeHandoff.perform {
            events.append("waitUserContent")
        } warmInitialDocumentContexts: {
            events.append("warmInitialDocumentContexts")
            isValid = false
        } isStillValid: {
            isValid
        } register: {
            events.append("register")
        } load: {
            events.append("load")
        }

        XCTAssertEqual(
            events,
            [
                "waitUserContent",
                "warmInitialDocumentContexts",
            ]
        )
    }

    func testTabSetupInitialLoadWaitsForInitialUserContent() async throws {
        let initialURL = URL(string: "about:blank")!
        let targetURL = URL(string: "https://example.com/deferred")!
        let controller = DelayedNormalTabUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        let tab = Tab(
            url: initialURL,
            existingWebView: webView,
            loadsCachedFaviconOnInit: false
        )
        tab._webView = webView
        tab._existingWebView = nil

        NormalTabInitialDocumentRuntimeHandoff.scheduleTabSetupInitialLoad(
            tab: tab,
            webView: webView,
            targetURL: targetURL,
            profileId: nil,
            registrationReason: "NormalTabInitialDocumentRuntimeHandoffTests",
            registrationGuard: .currentWebViewIdentity
        )

        for _ in 0..<20 {
            await Task.yield()
            if controller.waitCallCount > 0 {
                break
            }
        }

        XCTAssertEqual(controller.waitCallCount, 1)
        XCTAssertEqual(tab.url, initialURL)

        controller.finishInitialUserContentInstallation()

        for _ in 0..<20 {
            await Task.yield()
            if tab.url == targetURL {
                break
            }
        }

        XCTAssertEqual(tab.url, targetURL)
    }

    func testTabSetupInitialLoadWarmsInitialDocumentContextsThroughInjectedRuntime() async throws {
        let profileId = UUID()
        let targetURL = URL(string: "https://example.com/deferred")!
        let controller = DelayedNormalTabUserContentController()
        controller.hasInstalledInitialUserContent = true
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        let tab = Tab(
            url: URL(string: "about:blank")!,
            existingWebView: webView,
            loadsCachedFaviconOnInit: false
        )
        tab._webView = webView
        tab._existingWebView = nil

        var warmedProfileIds: [UUID] = []
        tab.normalWebViewExtensionRuntime = TabNormalWebViewExtensionRuntime(
            registerNormalTabWithExtensionRuntimeIfNeeded: { _, _ in },
            prepareWebViewForExtensionRuntime: { _, _, _ in },
            ensureInitialDocumentExtensionContextsLoadedIfNeeded: { warmedProfileId in
                warmedProfileIds.append(warmedProfileId)
            }
        )

        NormalTabInitialDocumentRuntimeHandoff.scheduleTabSetupInitialLoad(
            tab: tab,
            webView: webView,
            targetURL: targetURL,
            profileId: profileId,
            registrationReason: "NormalTabInitialDocumentRuntimeHandoffTests",
            registrationGuard: .currentWebViewIdentity
        )

        for _ in 0..<20 {
            await Task.yield()
            if warmedProfileIds.isEmpty == false {
                break
            }
        }

        XCTAssertNil(tab.browserManager)
        XCTAssertEqual(warmedProfileIds, [profileId])
    }
}

@MainActor
private final class DelayedNormalTabUserContentController:
    WKUserContentController,
    SumiNormalTabUserContentControlling {
    var normalTabUserScriptsProvider: SumiNormalTabUserScripts?
    var contentBlockingAssetSummary = SumiNormalTabContentBlockingAssetSummary(
        isInstalled: false,
        globalRuleListCount: 0,
        updateRuleCount: 0,
        isContentBlockingFeatureEnabled: false
    )
    var hasInstalledInitialUserContent = false
    private(set) var waitCallCount = 0
    private var continuation: CheckedContinuation<Void, Never>?

    var wkUserContentController: WKUserContentController {
        self
    }

    #if DEBUG
        var contentBlockingAssetSummaryPublisher: AnyPublisher<SumiNormalTabContentBlockingAssetSummary, Never> {
            Just(contentBlockingAssetSummary).eraseToAnyPublisher()
        }
    #endif

    func replaceNormalTabUserScripts(with provider: SumiNormalTabUserScripts) async {
        normalTabUserScriptsProvider = provider
    }

    func waitForContentBlockingAssetsInstalled() async {
        waitCallCount += 1
        guard hasInstalledInitialUserContent == false else { return }

        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func finishInitialUserContentInstallation() {
        hasInstalledInitialUserContent = true
        continuation?.resume()
        continuation = nil
    }

    func cleanUpBeforeClosing() {}
}
