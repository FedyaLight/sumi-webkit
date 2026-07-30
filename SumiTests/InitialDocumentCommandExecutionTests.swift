import Combine
@testable import Sumi
import SumiWebRuntime
import WebKit
import XCTest

@MainActor
extension InitialDocumentRuntimeHandoffTests {
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
        } warmPostPublicationBackground: {
            events.append("warmPostPublicationBackground")
        } load: {
            events.append("load")
        }

        XCTAssertEqual(
            events,
            [
                "waitUserContent",
                "warmInitialDocumentContexts",
                "register",
                "warmPostPublicationBackground",
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
        } warmPostPublicationBackground: {
            events.append("warmPostPublicationBackground")
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
        } warmPostPublicationBackground: {
            events.append("warmPostPublicationBackground")
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

    func testPerformStopsAfterPostPublicationWarmupWhenCommandBecomesInvalid() async {
        var events: [String] = []
        var isValid = true

        await NormalTabInitialDocumentRuntimeHandoff.perform {
            events.append("waitUserContent")
        } warmInitialDocumentContexts: {
            events.append("warmInitialDocumentContexts")
        } isStillValid: {
            isValid
        } register: {
            events.append("register")
        } warmPostPublicationBackground: {
            events.append("warmPostPublicationBackground")
            isValid = false
        } load: {
            events.append("load")
        }

        XCTAssertEqual(
            events,
            [
                "waitUserContent",
                "warmInitialDocumentContexts",
                "register",
                "warmPostPublicationBackground",
            ]
        )
    }

    func testTabSetupInitialLoadWaitsForInitialUserContent() async {
        let targetURL = URL(string: "https://example.com/deferred")!
        let controller = DelayedNormalTabUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let webView = InitialDocumentRecordingWebView(
            frame: .zero,
            configuration: configuration
        )
        let tab = Tab(
            url: targetURL,
            existingWebView: webView,
            loadsCachedFaviconOnInit: false
        )
        tab.replaceUntrackedWebView(webView)
        tab.clearParkedExistingWebView()
        _ = tab.installNavigationDelegate(on: webView)

        NormalTabInitialDocumentRuntimeHandoff.scheduleTabSetupInitialLoad(
            tab: tab,
            webView: webView,
            targetURL: targetURL,
            profileId: nil,
            registrationReason: "InitialDocumentRuntimeHandoffTests"
        )

        for _ in 0..<20 {
            await Task.yield()
            if controller.waitCallCount > 0 {
                break
            }
        }

        XCTAssertEqual(controller.waitCallCount, 1)
        XCTAssertTrue(webView.loadedRequests.isEmpty)

        controller.finishInitialUserContentInstallation()

        for _ in 0..<20 {
            await Task.yield()
            if webView.loadedRequests.isEmpty == false {
                break
            }
        }

        XCTAssertEqual(webView.loadedRequests.compactMap(\.url), [targetURL])
        XCTAssertEqual(tab.url, targetURL)
    }

    func testTabSetupInitialLoadDoesNotOverwriteNewerNavigationOnSameWebView() async {
        let initialURL = URL(string: "https://example.com/initial")!
        let newerURL = URL(string: "https://example.com/newer")!
        let controller = DelayedNormalTabUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let webView = InitialDocumentRecordingWebView(
            frame: .zero,
            configuration: configuration
        )
        let tab = Tab(
            url: initialURL,
            existingWebView: webView,
            loadsCachedFaviconOnInit: false
        )
        tab.replaceUntrackedWebView(webView)
        tab.clearParkedExistingWebView()
        _ = tab.installNavigationDelegate(on: webView)

        NormalTabInitialDocumentRuntimeHandoff.scheduleTabSetupInitialLoad(
            tab: tab,
            webView: webView,
            targetURL: initialURL,
            profileId: nil,
            registrationReason: "InitialDocumentRuntimeHandoffTests.stale"
        )

        for _ in 0..<20 {
            await Task.yield()
            if controller.waitCallCount > 0 {
                break
            }
        }
        XCTAssertEqual(controller.waitCallCount, 1)

        webView.returnsConcreteNavigation = true
        tab.loadURL(newerURL)
        XCTAssertEqual(tab.url, newerURL)
        XCTAssertEqual(webView.loadedRequests.compactMap(\.url), [newerURL])

        controller.finishInitialUserContentInstallation()
        for _ in 0..<20 {
            await Task.yield()
        }

        XCTAssertEqual(tab.url, newerURL)
        XCTAssertEqual(webView.loadedRequests.compactMap(\.url), [newerURL])
    }

    func testDelayedInitialLoadSurvivesUntrackedToWindowAdoption() async {
        let targetURL = URL(string: "https://example.com/adopted")!
        let controller = DelayedNormalTabUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let webView = InitialDocumentRecordingWebView(
            frame: .zero,
            configuration: configuration
        )
        let sessions = WebViewSessionRepository()
        let tab = Tab(
            url: targetURL,
            webViewSessions: sessions,
            loadsCachedFaviconOnInit: false
        )
        tab.replaceUntrackedWebView(webView)
        _ = tab.beginMainFrameNavigationIntent(to: targetURL)
        _ = tab.installNavigationDelegate(on: webView)

        NormalTabInitialDocumentRuntimeHandoff.scheduleTabSetupInitialLoad(
            tab: tab,
            webView: webView,
            targetURL: targetURL,
            profileId: nil,
            registrationReason: "InitialDocumentRuntimeHandoffTests.adopted"
        )
        for _ in 0..<20 where controller.waitCallCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(controller.waitCallCount, 1)

        let owner = TrackedWebViewOwner(tabID: tab.id, windowID: UUID())
        WebViewTrackingLifecycleOwner().registerTrackedWebView(
            webView,
            for: owner,
            in: sessions,
            removeFromContainers: { _ in /* No-op. */ },
            installRuntimeObservations: { _ in /* No-op. */ },
            uninstallRuntimeObservationsIfUntracked: { _ in /* No-op. */ },
            pruneInvalidDeferredCommands: { _ in /* No-op. */ },
            canDisplaceWebView: { _ in true },
            removeRecentVisibility: { _ in /* No-op. */ },
            cleanupDisplacedWebView: { _, _ in /* No-op. */ }
        )
        XCTAssertEqual(sessions.residence(of: webView), .window(owner))

        controller.finishInitialUserContentInstallation()
        for _ in 0..<20 where webView.loadedRequests.isEmpty {
            await Task.yield()
        }

        XCTAssertEqual(webView.loadedRequests.compactMap(\.url), [targetURL])
    }

    func testStopLoadingInvalidatesDelayedInitialDocumentBeforeItCanLoad() async {
        let targetURL = URL(string: "https://example.com/cancelled-initial")!
        let controller = DelayedNormalTabUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let webView = InitialDocumentRecordingWebView(
            frame: .zero,
            configuration: configuration
        )
        let tab = Tab(
            url: targetURL,
            existingWebView: webView,
            loadsCachedFaviconOnInit: false
        )
        tab.replaceUntrackedWebView(webView)
        tab.clearParkedExistingWebView()
        _ = tab.installNavigationDelegate(on: webView)

        NormalTabInitialDocumentRuntimeHandoff.scheduleTabSetupInitialLoad(
            tab: tab,
            webView: webView,
            targetURL: targetURL,
            profileId: nil,
            registrationReason: "InitialDocumentRuntimeHandoffTests.cancelled"
        )

        for _ in 0..<20 {
            await Task.yield()
            if controller.waitCallCount > 0 { break }
        }
        XCTAssertEqual(controller.waitCallCount, 1)

        tab.stopLoading(on: webView)
        controller.finishInitialUserContentInstallation()
        for _ in 0..<20 {
            await Task.yield()
        }

        XCTAssertTrue(webView.loadedRequests.isEmpty)
        XCTAssertTrue(webView.loadedFileURLs.isEmpty)
    }

    func testTabSetupInitialLoadUsesFileURLLoadingForNonHTTPDocument() async {
        let targetURL = URL(fileURLWithPath: "/tmp/sumi-initial-document/index.html")
        let controller = DelayedNormalTabUserContentController()
        controller.hasInstalledInitialUserContent = true
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let webView = InitialDocumentRecordingWebView(
            frame: .zero,
            configuration: configuration
        )
        let tab = Tab(
            url: targetURL,
            existingWebView: webView,
            loadsCachedFaviconOnInit: false
        )
        tab.replaceUntrackedWebView(webView)
        tab.clearParkedExistingWebView()
        _ = tab.installNavigationDelegate(on: webView)

        NormalTabInitialDocumentRuntimeHandoff.scheduleTabSetupInitialLoad(
            tab: tab,
            webView: webView,
            targetURL: targetURL,
            profileId: nil,
            registrationReason: "InitialDocumentRuntimeHandoffTests.file"
        )

        for _ in 0..<20 {
            await Task.yield()
            if webView.loadedFileURLs.isEmpty == false { break }
        }

        XCTAssertTrue(webView.loadedRequests.isEmpty)
        XCTAssertEqual(webView.loadedFileURLs.map(\.url), [targetURL])
        XCTAssertEqual(
            webView.loadedFileURLs.map(\.readAccessURL),
            [targetURL.deletingLastPathComponent()]
        )
    }

    func testTabSetupInitialLoadWarmsInitialDocumentContextsThroughInjectedRuntime() async {
        let profileId = UUID()
        let targetURL = URL(string: "https://example.com/deferred")!
        let controller = DelayedNormalTabUserContentController()
        controller.hasInstalledInitialUserContent = true
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        let tab = Tab(
            url: targetURL,
            existingWebView: webView,
            loadsCachedFaviconOnInit: false
        )
        tab.replaceUntrackedWebView(webView)
        tab.clearParkedExistingWebView()
        _ = tab.installNavigationDelegate(on: webView)

        var warmedProfileIds: [UUID] = []
        tab.navigationRuntime.normalWebViewExtensionRuntime = TabNormalWebViewExtensionRuntime(
            registerTabWithExtensionRuntimeIfNeeded: { _, _ in /* No-op. */ },
            prepareWebViewForExtensionRuntime: { _, _, _ in /* No-op. */ },
            ensureInitialExtensionContextsIfNeeded: { warmedProfileId in
                warmedProfileIds.append(warmedProfileId)
            },
            warmInitialDocumentNativeMessagingIfNeeded: { _ in }
        )

        NormalTabInitialDocumentRuntimeHandoff.scheduleTabSetupInitialLoad(
            tab: tab,
            webView: webView,
            targetURL: targetURL,
            profileId: profileId,
            registrationReason: "InitialDocumentRuntimeHandoffTests"
        )

        for _ in 0..<20 {
            await Task.yield()
            if warmedProfileIds.isEmpty == false {
                break
            }
        }

        XCTAssertFalse(tab.hasBrowserRuntime)
        XCTAssertEqual(warmedProfileIds, [profileId])
    }

}
