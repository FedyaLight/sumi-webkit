import Network
import SwiftData
import WebKit
import XCTest

@testable import Sumi

/// Replicates the Proton Pass Safari login-fork pipeline end-to-end against a
/// synthetic extension and a loopback "account" server:
///
/// 1. The account page sends `{type: "fork", selector}` to the extension via
///    `externally_connectable` (`browser.runtime.sendMessage(extensionId, …)`).
/// 2. The MV3 service-worker background registers the same broker handler on
///    `runtime.onMessage` and `runtime.onMessageExternal` (as Proton does) and
///    relays `AUTH_PULL_FORK` back to the sender tab via `tabs.sendMessage`.
/// 3. The top-frame `fork.js` content script pulls the fork by fetching the
///    account origin, which must attach the page's session cookie.
/// 4. The server treats the selector as single-use: a second pull returns
///    "Invalid selector" — so any duplicated dispatch anywhere in the pipeline
///    fails the login exactly the way Proton Pass fails in the field.
@available(macOS 15.5, *)
@MainActor
final class SafariExtensionAccountForkPipelineTests: XCTestCase {
    func testAccountForkPipelinePullsSingleUseSelectorExactlyOnce() async throws {
        let server = try await AccountForkHTTPServer.start()
        addTeardownBlock {
            server.stop()
        }

        let harness = try await makeLoadedForkProbeHarness(server: server)

        // Content scripts must be injected before the fork round-trip: the
        // pull executes inside the account tab, exactly like Proton on Safari.
        try await waitForDatasetValue(
            in: harness.webView,
            key: "sumiForkReady",
            expected: "1",
            failureMessage: "fork.js content script was not injected into the account page"
        )
        try await waitForDatasetValue(
            in: harness.webView,
            key: "sumiInternalPing",
            expected: "ok",
            failureMessage: "content-script → background messaging failed (background service worker not reachable)"
        )

        let controllerIdentityAtLoad = harness.controllerIdentityDiagnostics

        // Layer diagnostic before any fork: a synchronous echo across the
        // page → extension external boundary. Isolates "external message not
        // delivered / sendResponse dropped" from fork-pipeline failures.
        let echo = try await sendExternalMessage(
            body: "{ type: 'echo' }",
            resultSlot: "__sumiEchoResult",
            harness: harness
        )
        XCTAssertTrue(
            echo["delivered"] as? Bool ?? false,
            "external echo not delivered: payload=\(echo)"
        )
        XCTAssertTrue(
            (echo["response"] as? [String: Any])?["echo"] as? Bool ?? false,
            "external echo sendResponse payload lost: payload=\(echo) tabLifecycle=[\(harness.tabLifecycleLog.summary)] atLoad=[\(controllerIdentityAtLoad)] atEcho=[\(harness.adapterResolutionDiagnostics)]"
        )

        let firstSelector = "selector-\(UUID().uuidString)"
        let first = try await sendForkMessage(
            selector: firstSelector,
            harness: harness
        )
        XCTAssertTrue(
            first.delivered,
            "account page could not reach the extension through externally_connectable: \(first.diagnostics)"
        )
        XCTAssertEqual(
            first.responseStatus,
            200,
            "fork pull failed: \(first.diagnostics)"
        )
        XCTAssertTrue(first.responseOK, "fork pull response not ok: \(first.diagnostics)")
        XCTAssertEqual(
            server.pullCount(for: firstSelector),
            1,
            "single-use fork selector was pulled more than once (this is the 'Invalid selector' failure mode)"
        )
        XCTAssertEqual(
            server.pullsMissingSessionCookie,
            0,
            "fork pull fetch did not attach the account page session cookie"
        )

        // The content script observed exactly one AUTH_PULL_FORK dispatch.
        let pullCount = try await datasetValue(in: harness.webView, key: "sumiForkPullCount")
        XCTAssertEqual(pullCount, "1", "AUTH_PULL_FORK was dispatched to fork.js more than once")

        // A second login attempt with a fresh selector must also succeed.
        let secondSelector = "selector-\(UUID().uuidString)"
        let second = try await sendForkMessage(
            selector: secondSelector,
            harness: harness
        )
        XCTAssertTrue(second.delivered, second.error ?? "-")
        XCTAssertTrue(second.responseOK, "second fork pull failed: \(second.responseError ?? "-")")
        XCTAssertEqual(server.pullCount(for: secondSelector), 1)

        // Replaying a consumed selector must propagate the server error to the
        // page (Proton parity for the user-visible "Invalid selector" path).
        let replay = try await sendForkMessage(
            selector: firstSelector,
            harness: harness
        )
        XCTAssertTrue(replay.delivered, replay.error ?? "-")
        XCTAssertFalse(replay.responseOK)
        XCTAssertEqual(replay.responseStatus, 422)
        XCTAssertEqual(replay.responseError, "Invalid selector")

        // Broker exactly-once accounting: each page message must be handled by
        // one event dispatch. Proton registers the same handler on both
        // onMessage and onMessageExternal, so double dispatch would consume
        // the selector twice.
        let stats = try await fetchBrokerStats(harness: harness)
        XCTAssertEqual(
            stats.forkHandled,
            3,
            "background broker handled a different number of fork messages than the page sent; events: \(stats.eventLog)"
        )
        // Internal one-shot messages: the fork.js startup ping plus this
        // stats-bridge request. Page-originated external messages must not
        // also fire runtime.onMessage (double dispatch would consume the
        // single-use fork selector twice).
        XCTAssertEqual(
            stats.onMessage,
            2,
            "runtime.onMessage must only see the content-script diagnostic pings; page-originated external messages must not also fire it; events: \(stats.eventLog)"
        )
        XCTAssertGreaterThanOrEqual(
            stats.onMessageExternal,
            4,
            "expected page messages (echo + 3 forks) to arrive through runtime.onMessageExternal (Safari parity); events: \(stats.eventLog)"
        )
    }

    /// Mirrors the real Proton Pass popup login path, which is the flow that
    /// fails in the field while the harness-created-tab pipeline passes:
    ///
    /// 1. The service worker opens the account tab itself via
    ///    `browser.tabs.create` (`useRequestFork` in the Pass popup).
    /// 2. The account page dispatches the fork by *broadcasting* the same
    ///    message to all four Pass extension IDs in parallel
    ///    (`broadcastMessage` in `packages/shared/lib/browser/extension.ts`);
    ///    only the Safari composed identifier may deliver.
    /// 3. A second login attempt through a second extension-created tab must
    ///    behave identically (the field failure happened on the re-login).
    func testAccountForkPipelineFromExtensionCreatedTabWithAccountBroadcast() async throws {
        let server = try await AccountForkHTTPServer.start()
        addTeardownBlock {
            server.stop()
        }

        let harness = try await makeLoadedForkProbeHarness(server: server)
        try await waitForDatasetValue(
            in: harness.webView,
            key: "sumiForkReady",
            expected: "1",
            failureMessage: "fork.js content script was not injected into the bootstrap page"
        )

        for attempt in 1...2 {
            let accountTab = try await openAccountTabThroughExtension(
                server: server,
                harness: harness,
                label: "attempt-\(attempt)"
            )
            let selector = "selector-\(UUID().uuidString)"
            let result = try await sendBroadcastForkMessage(
                selector: selector,
                webView: accountTab.webView,
                harness: harness
            )

            XCTAssertTrue(
                result.delivered,
                "attempt \(attempt): account broadcast did not reach the extension: \(result.diagnostics) adapter=[\(harness.adapterResolutionDiagnostics(for: accountTab.tab))]"
            )
            XCTAssertEqual(
                result.responseStatus,
                200,
                "attempt \(attempt): fork pull failed: \(result.diagnostics)"
            )
            XCTAssertTrue(
                result.responseOK,
                "attempt \(attempt): fork pull response not ok — this is the field 'Invalid selector' shape: \(result.diagnostics)"
            )
            XCTAssertEqual(
                server.pullCount(for: selector),
                1,
                "attempt \(attempt): single-use fork selector pulled \(server.pullCount(for: selector)) times (field failure mode)"
            )

            let injections = try await datasetValue(
                in: accountTab.webView,
                key: "sumiForkInjections"
            )
            XCTAssertEqual(
                injections,
                "1",
                "attempt \(attempt): fork.js was injected \(injections ?? "0") times into the extension-created tab; duplicated injection double-pulls the selector"
            )
            let pullCount = try await datasetValue(
                in: accountTab.webView,
                key: "sumiForkPullCount"
            )
            XCTAssertEqual(
                pullCount,
                "1",
                "attempt \(attempt): AUTH_PULL_FORK dispatched \(pullCount ?? "0") times to the extension-created tab"
            )
            XCTAssertEqual(
                server.pageHits(for: accountTab.cacheToken),
                1,
                "attempt \(attempt): the account page was served \(server.pageHits(for: accountTab.cacheToken)) times for one tab — a double page load double-produces forks in the field (manualLoad=\(accountTab.usedManualInitialLoad))"
            )
        }
    }

    /// The fork-diagnostics user script is injected as raw JS; a syntax error
    /// would make it fail silently in the field. Evaluating it on a
    /// non-account page must complete without throwing (the script
    /// early-returns off Proton hosts).
    func testAccountForkDiagnosticsUserScriptSourceParses() async throws {
        let webView = WKWebView(frame: .zero)
        let source = SafariExtensionAccountForkDiagnosticsUserScript().source
        _ = try await evaluateString(source + "; 'parsed'", in: webView)
    }

    // MARK: - Harness

    private struct ForkProbeHarness {
        /// Keeps the in-memory SwiftData container alive for the whole test:
        /// extension-requested tab opening reads persisted extension entities
        /// (`enabledPersistedExtensionEntities`), which traps if the container
        /// backing the manager's ModelContext has been deallocated.
        let container: ModelContainer
        let manager: ExtensionManager
        let webView: WKWebView
        let runtimeIdentifier: String
        let tabLifecycleLog: TabLifecycleLog
        let tab: Tab
        let extensionContext: WKWebExtensionContext
        let browserManager: BrowserManager

        /// Adapter/lookup state for an arbitrary tab (used for tabs the
        /// extension created itself through `tabs.create`).
        @MainActor
        func adapterResolutionDiagnostics(for probedTab: Tab) -> String {
            let adapter = manager.adapterResolutionOwner.stableAdapter(for: probedTab)
            let adapterWebView = adapter?.webView(for: extensionContext)
            let lookupTab = browserManager.tabManager.tabCollectionMembershipOwner.tab(for: probedTab.id)
            return "adapter=\(adapter == nil ? "nil" : "present") "
                + "adapterTabMatches=\(adapter?.tab === probedTab) "
                + "tabManagerLookup=\(lookupTab == nil ? "nil" : (lookupTab === probedTab ? "match" : "OTHER")) "
                + "adapterWebViewMatchesTab=\(adapterWebView === probedTab.resolvedCurrentWebView()) "
                + "tabEligible=\(manager.isTabEligibleForCurrentExtensionRuntime(probedTab)) "
                + "resolvedProfile=\(String(describing: manager.resolvedProfileId(for: probedTab))) "
                + "controllerAttached=\(probedTab.resolvedCurrentWebView()?.configuration.webExtensionController != nil) "
                + "tabMatchesContext=\(manager.tabMatchesExtensionContext(probedTab, extensionContext: extensionContext))"
        }

        /// Snapshot of the adapter state WebKit consults when resolving the
        /// sender tab for a page message (`getCurrentTab` iterates open tabs
        /// and compares each adapter's `webView(for:)` page).
        @MainActor
        var adapterResolutionDiagnostics: String {
            let adapter = manager.adapterResolutionOwner.stableAdapter(for: tab)
            let adapterWebView = adapter?.webView(for: extensionContext)
            let eligible = manager.isTabEligibleForCurrentExtensionRuntime(tab)
            let adapterTab = adapter?.tab
            let lookupTab = browserManager.tabManager.tabCollectionMembershipOwner.tab(for: tab.id)
            let containingSpaces = browserManager.tabManager.regularTabCollectionStateOwner.tabsBySpaceSnapshot()
                .filter { _, tabs in tabs.contains(where: { $0 === tab }) }
                .keys
            return "adapter=\(adapter == nil ? "nil" : "present") "
                + "adapterTab=\(adapterTab == nil ? "nil" : (adapterTab === tab ? "harnessTab" : "OTHER")) "
                + "tabManagerLookup=\(lookupTab == nil ? "nil" : (lookupTab === tab ? "harnessTab" : "OTHER")) "
                + "tabSpaceId=\(String(describing: tab.spaceId)) "
                + "containingSpaces=\(Array(containingSpaces)) "
                + "allSpaces=\(browserManager.tabManager.spaceStateOwner.spaces.map { "\($0.id):profile=\(String(describing: $0.profileId))" }) "
                + "currentSpaceId=\(String(describing: browserManager.tabManager.spaceStateOwner.currentSpace?.id)) "
                + "adapterWebView=\(adapterWebView == nil ? "nil" : (adapterWebView === webView ? "harnessWebView" : "OTHER webview \(String(describing: adapterWebView))")) "
                + "tabEligible=\(eligible) "
                + "tabWebViewIsHarness=\(tab.resolvedCurrentWebView() === webView) "
                + "primaryWindowId=\(String(describing: tab.resolvedPrimaryWindowId())) "
                + "currentWebViewIsHarness=\(tab.resolvedCurrentWebView() === webView) "
                + "owningTabMatches=\((webView as? FocusableWKWebView)?.owningTab === tab) "
                + "resolvedProfile=\(String(describing: manager.resolvedProfileId(for: tab))) "
                + "controllerAttached=\(webView.configuration.webExtensionController != nil) "
                + "tabMatchesContext=\(manager.tabMatchesExtensionContext(tab, extensionContext: extensionContext)) "
                + "resolvedLiveWebView=\(manager.resolvedLiveWebView(for: tab) == nil ? "nil" : (manager.resolvedLiveWebView(for: tab) === webView ? "harnessWebView" : "OTHER")) "
                + "contextProfile=\(String(describing: manager.profileId(for: extensionContext))) "
                + controllerIdentityDiagnostics
        }

        @MainActor
        var controllerIdentityDiagnostics: String {
            let profileId = manager.resolvedProfileId(for: tab)
            let expected = profileId.flatMap { manager.profileRuntimeOwner.controller(for: $0) }
            let attached = webView.configuration.webExtensionController
            let expectedDescription = expected.map { "\(ObjectIdentifier($0))" } ?? "nil"
            let attachedDescription = attached.map { "\(ObjectIdentifier($0))" } ?? "nil"
            return "expectedController=\(expectedDescription) attachedController=\(attachedDescription) controllersMatch=\(expected === attached)"
        }
    }

    /// Records WebKit-facing tab open/close/defer notifications so a test
    /// failure can show whether the account tab was dropped mid-pipeline
    /// (WebKit answers external messages with an empty response when the
    /// sender tab is unknown — see `runtimeWebPageSendMessage`).
    final class TabLifecycleLog {
        private(set) var entries: [String] = []

        func append(_ entry: String) {
            entries.append(entry)
        }

        var summary: String {
            entries.joined(separator: " | ")
        }
    }

    private struct ForkSendResult {
        let delivered: Bool
        let error: String?
        let responseOK: Bool
        let responseStatus: Int?
        let responseError: String?
        let rawPayload: [String: Any]

        var diagnostics: String {
            "payload=\(rawPayload)"
        }
    }

    private struct BrokerStats {
        let onMessage: Int
        let onMessageExternal: Int
        let forkHandled: Int
        let eventLog: String
    }

    private func makeLoadedForkProbeHarness(
        server: AccountForkHTTPServer
    ) async throws -> ForkProbeHarness {
        let container = try makeTestContainer()
        let profile = Profile(name: "Account Fork Profile")
        let browserConfiguration = BrowserConfiguration()
        let manager = makeSafariExtensionTestExtensionManager(
            context: container.mainContext,
            initialProfile: profile,
            browserConfiguration: browserConfiguration
        )
        let browserManager = makeSafariExtensionTestBrowserManager(profile: profile)
        manager.attach(browserManager: browserManager)

        // The startup restore task replaces the tab-manager structural state
        // when it lands; wait for it so the account tab created below is not
        // dropped from the tab lookup mid-pipeline (a dropped sender tab makes
        // WebKit answer external page messages with an empty response).
        await browserManager.tabManager.storeRestore.startupRestoreTask?.value

        let tabLifecycleLog = TabLifecycleLog()
        manager.testHooks.didOpenTab = { tabId in
            tabLifecycleLog.append("didOpenTab \(tabId)")
        }
        manager.testHooks.didCloseTab = { tabId in
            tabLifecycleLog.append("didCloseTab \(tabId)")
        }
        manager.testHooks.didDeferOpenTab = { tabId, reason in
            tabLifecycleLog.append("didDeferOpenTab \(tabId) reason=\(reason)")
        }

        let installed = try await installAccountForkProbeExtension(
            manager: manager,
            scratchDirectory: makeScratchDirectory()
        )
        _ = try await manager.installationFlowOwner.enableExtension(installed.id)
        manager.setDefaultSiteAccess(
            .allow,
            extensionId: installed.id,
            profileId: profile.id
        )
        let extensionContext = try XCTUnwrap(
            manager.getExtensionContext(for: installed.id, profileId: profile.id)
        )
        XCTAssertTrue(extensionContext.isLoaded)

        // In the real login flow the service worker is already awake (the
        // action popup woke it before opening the account tab), so the probe
        // wakes it explicitly the same way.
        _ = try await manager.ensureBackgroundAvailableIfRequired(
            for: extensionContext.webExtension,
            context: extensionContext,
            reason: .enable
        )

        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            surface: .extensionOptions
        )
        manager.prepareWebViewConfigForExtensionRuntime(
            configuration,
            profileId: profile.id,
            reason: "SafariExtensionAccountForkPipelineTests"
        )

        let accountURL = server.accountPageURL
        let tab = browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
            url: accountURL.absoluteString,
            in: browserManager.tabManager.spaceStateOwner.currentSpace,
            activate: false,
            webViewConfigurationOverride: configuration
        )
        tab.profileId = profile.id
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))

        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        webView.owningTab = tab
        tab.replaceUntrackedWebView(webView)

        manager.registerTabWithExtensionRuntime(
            tab,
            reason: "SafariExtensionAccountForkPipelineTests"
        )

        let didFinish = expectation(description: "account page loaded")
        let delegate = NavigationDelegateBox {
            didFinish.fulfill()
        }
        webView.navigationDelegate = delegate
        webView.load(
            URLRequest(url: accountURL, cachePolicy: .reloadIgnoringLocalCacheData)
        )
        await fulfillment(of: [didFinish], timeout: 10)
        webView.navigationDelegate = nil

        return ForkProbeHarness(
            container: container,
            manager: manager,
            webView: webView,
            runtimeIdentifier: extensionContext.uniqueIdentifier,
            tabLifecycleLog: tabLifecycleLog,
            tab: tab,
            extensionContext: extensionContext,
            browserManager: browserManager
        )
    }

    private func sendForkMessage(
        selector: String,
        harness: ForkProbeHarness
    ) async throws -> ForkSendResult {
        let payload = try await sendExternalMessage(
            body: "{ type: 'fork', selector: '\(selector)' }",
            resultSlot: "__sumiForkResult",
            harness: harness
        )
        let response = payload["response"] as? [String: Any]
        return ForkSendResult(
            delivered: payload["delivered"] as? Bool ?? false,
            error: payload["error"] as? String,
            responseOK: response?["ok"] as? Bool ?? false,
            responseStatus: response?["status"] as? Int,
            responseError: response?["error"] as? String,
            rawPayload: payload
        )
    }

    private enum ForkProbeFailure: Error {
        case contentScriptNotInjected
    }

    private struct ExtensionCreatedAccountTab {
        let tab: Tab
        let webView: WKWebView
        let cacheToken: String
        /// True when the harness had to trigger the initial load itself
        /// because the deferred initial-document handoff never fired in the
        /// windowless test environment.
        let usedManualInitialLoad: Bool
    }

    /// Live snapshot of the extension-created tab's page: what URL actually
    /// loaded, whether the orchestrator content script made it in, and how
    /// many times the server actually served this unique page URL.
    private func pageStateDiagnostics(
        webView: WKWebView,
        accountURL: URL,
        server: AccountForkHTTPServer
    ) async -> String {
        let href = (try? await evaluateString("String(location.href)", in: webView)) ?? nil
        let readyState = (try? await evaluateString("String(document.readyState)", in: webView)) ?? nil
        let orchestrator = (try? await datasetValue(in: webView, key: "sumiOrchestratorReady")) ?? nil
        let cacheToken = URLComponents(url: accountURL, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "cache" }?
            .value ?? "?"
        return "href=\(href ?? "nil") readyState=\(readyState ?? "nil") "
            + "orchestratorReady=\(orchestrator ?? "nil") "
            + "webViewURL=\(webView.url?.absoluteString ?? "nil") "
            + "isLoading=\(webView.isLoading) "
            + "serverPageHits=\(server.pageHits(for: cacheToken))"
    }

    /// Asks the probe's service worker to open the account page via
    /// `browser.tabs.create` — the same call the Proton Pass popup makes —
    /// then waits for Sumi to materialize the tab's web view and for fork.js
    /// to be injected into the loaded page.
    private func openAccountTabThroughExtension(
        server: AccountForkHTTPServer,
        harness: ForkProbeHarness,
        label: String
    ) async throws -> ExtensionCreatedAccountTab {
        let accountURL = server.accountPageURL
        let open = try await sendExternalMessage(
            body: "{ type: 'open-account-tab', url: '\(accountURL.absoluteString)' }",
            resultSlot: "__sumiOpenTabResult",
            harness: harness
        )
        let openResponse = open["response"] as? [String: Any]
        XCTAssertTrue(
            openResponse?["ok"] as? Bool ?? false,
            "\(label): worker tabs.create failed: \(open)"
        )

        var createdTab: Tab?
        for _ in 0..<100 {
            let allTabs = harness.browserManager.tabManager.tabCollectionMembershipOwner.allTabs()
                + harness.browserManager.tabManager.shortcutPresentationOwner.activeEssentialTabs(
                    for: harness.browserManager.tabManager.runtimePorts?.currentProfileId
                )
            if let match = allTabs.first(where: {
                $0.url.absoluteString == accountURL.absoluteString
            }) {
                createdTab = match
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let tab = try XCTUnwrap(
            createdTab,
            "\(label): tabs.create did not surface a tab for \(accountURL) in the tab manager; lifecycle=[\(harness.tabLifecycleLog.summary)]"
        )

        var materializedWebView: WKWebView?
        for _ in 0..<100 {
            if let webView = tab.resolvedCurrentWebView() {
                materializedWebView = webView
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let webView = try XCTUnwrap(
            materializedWebView,
            "\(label): Sumi never materialized a web view for the extension-created tab (isUnloaded=\(tab.isUnloaded)); adapter=[\(harness.adapterResolutionDiagnostics(for: tab))]"
        )

        let cacheToken = URLComponents(url: accountURL, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "cache" }?
            .value ?? "?"

        // The initial navigation is deferred through the initial-document
        // runtime handoff. Give it a generous window; when it never fires
        // (windowless test environment lacks the window coordinator that
        // completes materialization in the app), drive the same load the
        // coordinator would have issued.
        var usedManualInitialLoad = false
        var pageLoaded = false
        for _ in 0..<100 {
            if server.pageHits(for: cacheToken) > 0 {
                pageLoaded = true
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        if pageLoaded == false {
            usedManualInitialLoad = true
            tab.loadURL(accountURL)
            for _ in 0..<100 {
                if server.pageHits(for: cacheToken) > 0 {
                    pageLoaded = true
                    break
                }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        if pageLoaded == false {
            let pageDiagnostics = await pageStateDiagnostics(
                webView: webView,
                accountURL: accountURL,
                server: server
            )
            XCTFail(
                "\(label): extension-created tab never loaded its URL (manualLoadTried=\(usedManualInitialLoad)); page=[\(pageDiagnostics)] adapter=[\(harness.adapterResolutionDiagnostics(for: tab))]"
            )
            throw ForkProbeFailure.contentScriptNotInjected
        }

        // The load may have swapped the tab's web view (replacement path);
        // always talk to the tab's current one from here on.
        let loadedWebView = tab.resolvedCurrentWebView() ?? webView

        var forkInjected = false
        for _ in 0..<100 {
            if try await datasetValue(in: loadedWebView, key: "sumiForkReady") == "1" {
                forkInjected = true
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        if forkInjected == false {
            let pageDiagnostics = await pageStateDiagnostics(
                webView: loadedWebView,
                accountURL: accountURL,
                server: server
            )
            XCTFail(
                "\(label): fork.js was not injected into the extension-created account tab (manualLoad=\(usedManualInitialLoad)); page=[\(pageDiagnostics)] adapter=[\(harness.adapterResolutionDiagnostics(for: tab))]"
            )
            throw ForkProbeFailure.contentScriptNotInjected
        }
        return ExtensionCreatedAccountTab(
            tab: tab,
            webView: loadedWebView,
            cacheToken: cacheToken,
            usedManualInitialLoad: usedManualInitialLoad
        )
    }

    /// Sends the fork exactly the way the real account app does
    /// (`broadcastMessage`): the same message dispatched in parallel to all
    /// four known Pass extension IDs; the first `ok` response wins, otherwise
    /// the last response is surfaced (that is where the field
    /// "Invalid selector" text comes from).
    private func sendBroadcastForkMessage(
        selector: String,
        webView: WKWebView,
        harness: ForkProbeHarness
    ) async throws -> ForkSendResult {
        let resultSlot = "__sumiBroadcastForkResult"
        let storeIDs = [
            "ghmbeldphafepmbegfdlkpapadhbakde",
            "hlaiofkbmjenhgeinjlmkafaipackfjh",
            "gcllgfdnfnllodcaambdaknbipemelie",
        ]
        let idsLiteral = (storeIDs + [harness.runtimeIdentifier])
            .map { "'\($0)'" }
            .joined(separator: ", ")
        let sendScript = """
        (() => {
          const slot = '\(resultSlot)';
          window[slot] = null;
          const api =
            (globalThis.browser && globalThis.browser.runtime &&
             typeof globalThis.browser.runtime.sendMessage === 'function')
              ? globalThis.browser
              : (globalThis.chrome && globalThis.chrome.runtime) ? globalThis.chrome : null;
          if (!api) {
            window[slot] = JSON.stringify({ delivered: false, error: 'runtime.sendMessage unavailable in page world' });
            return 'unavailable';
          }
          const message = { type: 'fork', selector: '\(selector)' };
          const sendOne = (id) => new Promise((resolve) => {
            let settled = false;
            const finish = (result) => {
              if (!settled) { settled = true; resolve(result); }
            };
            try {
              const returned = api.runtime.sendMessage(id, message, (response) => {
                const lastError = api.runtime.lastError
                  ? String(api.runtime.lastError.message || api.runtime.lastError)
                  : null;
                finish({
                  id,
                  ok: lastError === null && response !== undefined && response !== null,
                  response: response === undefined ? null : response,
                  error: lastError
                });
              });
              if (returned && typeof returned.then === 'function') {
                returned.then((response) => {
                  finish({
                    id,
                    ok: response !== undefined && response !== null,
                    response: response === undefined ? null : response,
                    error: null
                  });
                }).catch((error) => {
                  finish({ id, ok: false, response: null, error: String((error && error.message) || error) });
                });
              }
            } catch (error) {
              finish({ id, ok: false, response: null, error: String((error && error.message) || error) });
            }
          });
          const ids = [\(idsLiteral)];
          Promise.all(ids.map(sendOne)).then((results) => {
            const winner = results.find((r) => r.ok) || results[results.length - 1];
            window[slot] = JSON.stringify({
              delivered: winner.ok,
              winnerId: winner.id,
              response: winner.response,
              error: winner.error,
              all: results
            });
          });
          return 'sent';
        })();
        """
        _ = try await evaluateString(sendScript, in: webView)

        for _ in 0..<200 {
            if let json = try await evaluateString("window['\(resultSlot)']", in: webView),
                let data = json.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let response = object["response"] as? [String: Any]
                return ForkSendResult(
                    delivered: object["delivered"] as? Bool ?? false,
                    error: object["error"] as? String,
                    responseOK: response?["ok"] as? Bool ?? false,
                    responseStatus: response?["status"] as? Int,
                    responseError: response?["error"] as? String,
                    rawPayload: object
                )
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTFail("Timed out waiting for broadcast fork result")
        return ForkSendResult(
            delivered: false,
            error: "timeout",
            responseOK: false,
            responseStatus: nil,
            responseError: nil,
            rawPayload: [:]
        )
    }

    /// Reads broker counters through the content-script path (DOM attribute
    /// handshake with fork.js), which keeps working even when the page →
    /// extension external path is what's being diagnosed.
    private func fetchBrokerStats(
        harness: ForkProbeHarness
    ) async throws -> BrokerStats {
        let token = UUID().uuidString
        _ = try await evaluateString(
            "document.documentElement.setAttribute('data-sumi-stats-request', '\(token)'); 'requested'",
            in: harness.webView
        )
        for _ in 0..<100 {
            if let json = try await evaluateString(
                "document.documentElement.dataset.sumiStatsResult || null",
                in: harness.webView
            ),
                let data = json.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                object["token"] as? String == token {
                let state = object["state"] as? [String: Any]
                if state == nil {
                    XCTFail("Broker stats bridge returned no state; raw bridge payload: \(json)")
                }
                let events = (state?["events"] as? [[String: Any]]) ?? []
                let eventLog = events
                    .map { event in
                        "\(event["event"] ?? "?"):\(event["type"] ?? "?") tab=\(event["senderTab"] ?? "nil") url=\(event["senderUrl"] ?? "nil")"
                    }
                    .joined(separator: " | ")
                return BrokerStats(
                    onMessage: state?["onMessage"] as? Int ?? -1,
                    onMessageExternal: state?["onMessageExternal"] as? Int ?? -1,
                    forkHandled: state?["forkHandled"] as? Int ?? -1,
                    eventLog: eventLog
                )
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTFail("Timed out waiting for broker stats through the content-script path")
        return BrokerStats(onMessage: -1, onMessageExternal: -1, forkHandled: -1, eventLog: "")
    }

    /// Sends a message from the page world to the extension the way
    /// account.proton.me does, then polls for the promise result.
    private func sendExternalMessage(
        body: String,
        resultSlot: String,
        harness: ForkProbeHarness
    ) async throws -> [String: Any] {
        let sendScript = """
        (() => {
          const slot = '\(resultSlot)';
          window[slot] = null;
          const api =
            (globalThis.browser && globalThis.browser.runtime &&
             typeof globalThis.browser.runtime.sendMessage === 'function')
              ? globalThis.browser
              : (globalThis.chrome && globalThis.chrome.runtime &&
                 typeof globalThis.chrome.runtime.sendMessage === 'function')
                ? globalThis.chrome
                : null;
          if (!api) {
            window[slot] = JSON.stringify({
              delivered: false,
              error: 'runtime.sendMessage unavailable in page world',
              apiShape: {
                browser: typeof globalThis.browser,
                chrome: typeof globalThis.chrome,
                browserRuntime: globalThis.browser ? typeof globalThis.browser.runtime : 'n/a',
                chromeRuntime: globalThis.chrome ? typeof globalThis.chrome.runtime : 'n/a'
              }
            });
            return 'unavailable';
          }
          const finish = (result) => {
            if (window[slot] === null) {
              window[slot] = JSON.stringify(result);
            }
          };
          try {
            const callbackResult = { used: false };
            const returned = api.runtime.sendMessage(
              '\(harness.runtimeIdentifier)',
              \(body),
              (response) => {
                callbackResult.used = true;
                const lastError = api.runtime.lastError
                  ? String(api.runtime.lastError.message || api.runtime.lastError)
                  : null;
                finish({
                  delivered: lastError === null,
                  via: 'callback',
                  response: response === undefined ? null : response,
                  error: lastError
                });
              }
            );
            if (returned && typeof returned.then === 'function') {
              returned.then((response) => {
                finish({
                  delivered: true,
                  via: 'promise',
                  response: response === undefined ? null : response,
                  error: null
                });
              }).catch((error) => {
                finish({
                  delivered: false,
                  via: 'promise',
                  error: String((error && error.message) || error)
                });
              });
            }
            return 'sent returned=' + typeof returned;
          } catch (error) {
            finish({
              delivered: false,
              via: 'throw',
              error: String((error && error.message) || error)
            });
            return 'threw';
          }
        })();
        """
        _ = try await evaluateString(sendScript, in: harness.webView)

        for _ in 0..<100 {
            if let json = try await evaluateString(
                "window['\(resultSlot)']",
                in: harness.webView
            ),
                let data = json.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return object
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        XCTFail("Timed out waiting for external message result in \(resultSlot)")
        return [:]
    }

    // MARK: - Page polling

    private func waitForDatasetValue(
        in webView: WKWebView,
        key: String,
        expected: String,
        failureMessage: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        for _ in 0..<100 {
            if try await datasetValue(in: webView, key: key) == expected {
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTFail(failureMessage, file: file, line: line)
    }

    private func datasetValue(
        in webView: WKWebView,
        key: String
    ) async throws -> String? {
        try await evaluateString(
            "document.documentElement.dataset['\(key)'] || null",
            in: webView
        )
    }

    private func evaluateString(
        _ script: String,
        in webView: WKWebView
    ) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if result is NSNull {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: result as? String)
            }
        }
    }

    // MARK: - Probe extension

    private func installAccountForkProbeExtension(
        manager: ExtensionManager,
        scratchDirectory: URL
    ) async throws -> InstalledExtension {
        let directoryURL = scratchDirectory.appendingPathComponent(
            "AccountForkProbeExtension",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        // Mirrors manifest-safari.json of Proton Pass: MV3 service worker,
        // externally_connectable for the account origin, an all-frames
        // orchestrator plus a top-frame-only fork content script.
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "AccountForkProbeExtension",
            "version": "1.0",
            "background": ["service_worker": "background.js"],
            "content_scripts": [
                [
                    "matches": ["*://127.0.0.1/*", "*://localhost/*"],
                    "js": ["orchestrator.js"],
                    "all_frames": true,
                    "run_at": "document_end",
                ],
                [
                    "matches": ["*://127.0.0.1/*", "*://localhost/*"],
                    "js": ["fork.js"],
                    "all_frames": false,
                    "run_at": "document_end",
                ],
            ],
            "externally_connectable": [
                "matches": ["*://127.0.0.1/*", "*://localhost/*"],
            ],
            "permissions": ["storage", "scripting"],
            "host_permissions": ["*://127.0.0.1/*", "*://localhost/*"],
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
            .write(
                to: directoryURL.appendingPathComponent("manifest.json"),
                options: [.atomic]
            )

        let backgroundScript = """
        const state = { onMessage: 0, onMessageExternal: 0, forkHandled: 0, events: [] };

        const recordEvent = (eventName, message, sender) => {
          state.events.push({
            event: eventName,
            type: message && message.type ? String(message.type) : typeof message,
            senderTab: sender && sender.tab ? (sender.tab.id ?? null) : null,
            senderUrl: sender && sender.url ? String(sender.url) : null
          });
        };

        const handleBrokerMessage = (message, sender, sendResponse) => {
          if (!message || typeof message.type !== 'string') {
            return undefined;
          }
          if (message.type === 'echo') {
            sendResponse({ ok: true, echo: true, senderTab: sender && sender.tab ? (sender.tab.id ?? null) : null });
            return undefined;
          }
          if (message.type === 'probe-stats') {
            sendResponse({ ok: true, state });
            return undefined;
          }
          if (message.type === 'open-account-tab') {
            browser.tabs.create({ url: message.url }).then((tab) => {
              sendResponse({ ok: true, tabId: tab && tab.id !== undefined ? tab.id : null });
            }).catch((error) => {
              sendResponse({ ok: false, error: 'tabs-create-failed: ' + String((error && error.message) || error) });
            });
            return true;
          }
          if (message.type === 'fork') {
            state.forkHandled += 1;
            const tabId = sender && sender.tab ? sender.tab.id : null;
            if (tabId === null || tabId === undefined) {
              sendResponse({ ok: false, error: 'missing-sender-tab' });
              return undefined;
            }
            browser.tabs.sendMessage(tabId, {
              type: 'AUTH_PULL_FORK',
              selector: message.selector
            }).then((result) => {
              sendResponse(result || { ok: false, error: 'empty-pull-response' });
            }).catch((error) => {
              sendResponse({
                ok: false,
                error: 'tabs-send-failed: ' + String((error && error.message) || error)
              });
            });
            return true;
          }
          return undefined;
        };

        browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
          state.onMessage += 1;
          recordEvent('onMessage', message, sender);
          return handleBrokerMessage(message, sender, sendResponse);
        });
        browser.runtime.onMessageExternal.addListener((message, sender, sendResponse) => {
          state.onMessageExternal += 1;
          recordEvent('onMessageExternal', message, sender);
          return handleBrokerMessage(message, sender, sendResponse);
        });
        """
        try Data(backgroundScript.utf8)
            .write(
                to: directoryURL.appendingPathComponent("background.js"),
                options: [.atomic]
            )

        let forkScript = """
        (() => {
          let pulls = 0;
          // Injection accounting: a duplicated content-script injection means
          // two AUTH_PULL_FORK listeners, i.e. a double single-use pull.
          const injections = Number(document.documentElement.dataset.sumiForkInjections || '0') + 1;
          document.documentElement.dataset.sumiForkInjections = String(injections);
          document.documentElement.dataset.sumiForkReady = '1';
          // Layer diagnostic: content-script → background round trip.
          try {
            Promise.resolve(
              browser.runtime.sendMessage({ type: 'probe-stats' })
            ).then((response) => {
              document.documentElement.dataset.sumiInternalPing =
                response && response.ok === true ? 'ok' : ('bad:' + JSON.stringify(response || null));
            }).catch((error) => {
              document.documentElement.dataset.sumiInternalPing =
                'error:' + String((error && error.message) || error);
            });
          } catch (error) {
            document.documentElement.dataset.sumiInternalPing =
              'threw:' + String((error && error.message) || error);
          }
          // Stats bridge: the test (page world) sets data-sumi-stats-request,
          // the content script fetches broker state over the internal path and
          // mirrors it into data-sumi-stats-result. The raw response is
          // included so a broken response channel is distinguishable from a
          // missing state payload.
          new MutationObserver(() => {
            const token = document.documentElement.getAttribute('data-sumi-stats-request');
            if (!token) { return; }
            Promise.resolve(
              browser.runtime.sendMessage({ type: 'probe-stats' })
            ).then((response) => {
              document.documentElement.dataset.sumiStatsResult = JSON.stringify({
                token,
                state: (response && response.state) || null,
                raw: response === undefined ? 'undefined' : JSON.stringify(response)
              });
            }).catch((error) => {
              document.documentElement.dataset.sumiStatsResult = JSON.stringify({
                token,
                error: String((error && error.message) || error)
              });
            });
          }).observe(document.documentElement, {
            attributes: true,
            attributeFilter: ['data-sumi-stats-request']
          });
          browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
            if (!message || message.type !== 'AUTH_PULL_FORK') {
              return undefined;
            }
            pulls += 1;
            document.documentElement.dataset.sumiForkPullCount = String(pulls);
            fetch('/pull?selector=' + encodeURIComponent(message.selector))
              .then(async (response) => {
                let payload = {};
                try { payload = await response.json(); } catch (_) {}
                sendResponse({
                  ok: response.ok && payload.ok === true,
                  status: response.status,
                  error: payload.error || null
                });
              })
              .catch((error) => {
                sendResponse({
                  ok: false,
                  error: 'fetch-failed: ' + String((error && error.message) || error)
                });
              });
            return true;
          });
        })();
        """
        try Data(forkScript.utf8)
            .write(
                to: directoryURL.appendingPathComponent("fork.js"),
                options: [.atomic]
            )

        let orchestratorScript = """
        (() => {
          document.documentElement.dataset.sumiOrchestratorReady = '1';
          browser.runtime.onMessage.addListener((message) => {
            if (!message || message.type !== 'AUTH_PULL_FORK') {
              return undefined;
            }
            const seen = Number(
              document.documentElement.dataset.sumiOrchestratorForkSeen || '0'
            );
            document.documentElement.dataset.sumiOrchestratorForkSeen = String(seen + 1);
            return undefined;
          });
        })();
        """
        try Data(orchestratorScript.utf8)
            .write(
                to: directoryURL.appendingPathComponent("orchestrator.js"),
                options: [.atomic]
            )

        let resolvedExtensionId = UUID().uuidString
        let destinationDirectory = ExtensionUtils.extensionsDirectory()
            .appendingPathComponent(resolvedExtensionId, isDirectory: true)
        if FileManager.default.fileExists(atPath: destinationDirectory.path) {
            try FileManager.default.removeItem(at: destinationDirectory)
        }
        try FileManager.default.copyItem(at: directoryURL, to: destinationDirectory)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: destinationDirectory)
        }

        let installedManifest = try ExtensionUtils.validateManifest(
            at: destinationDirectory.appendingPathComponent("manifest.json"),
            policy: .safariWebExtension
        )
        let record = try manager.makeInstalledRecord(
            extensionId: resolvedExtensionId,
            manifest: installedManifest,
            extensionRoot: destinationDirectory,
            isEnabled: false,
            sourceKind: .safariAppExtension,
            sourceBundlePath: scratchDirectory
                .appendingPathComponent("missing-\(resolvedExtensionId).appex")
                .path,
            sourceFingerprintURL: destinationDirectory,
            existingEntity: nil
        )
        try manager.persist(record: record)
        _ = manager.installationFlowOwner.loadInstalledExtensionMetadata()
        return record
    }

    // MARK: - Test infrastructure

    private func makeTestContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private func makeScratchDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    private final class NavigationDelegateBox: NSObject, WKNavigationDelegate {
        private let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func webView(
            _: WKWebView,
            didFinish _: WKNavigation! // swiftlint:disable:this implicitly_unwrapped_optional
        ) {
            onFinish()
        }
    }
}

/// Loopback "account.proton.me" stand-in: serves the account page with a
/// session cookie and a single-use fork-selector pull endpoint that requires
/// that cookie — mirroring Proton's `GET /auth/v4/sessions/forks/{selector}`
/// semantics ("Invalid selector" on re-use).
private final class AccountForkHTTPServer: @unchecked Sendable {
    static let sessionCookieName = "sumi_probe_session"
    static let sessionCookieValue = "account-session-ok"

    private let listener: NWListener
    private let queue = DispatchQueue(label: "sumi.account-fork.http-server")
    private let lock = NSLock()
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var pullCounts: [String: Int] = [:]
    private var pageHitsByCacheToken: [String: Int] = [:]
    private var missingCookiePulls = 0

    static func start() async throws -> AccountForkHTTPServer {
        let server = try AccountForkHTTPServer()
        try await server.start()
        return server
    }

    private init() throws {
        listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: 0)!)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
    }

    var port: UInt16 {
        listener.port?.rawValue ?? 0
    }

    var accountPageURL: URL {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = Int(port)
        components.path = "/account.html"
        components.queryItems = [URLQueryItem(name: "cache", value: UUID().uuidString)]
        return components.url!
    }

    func pullCount(for selector: String) -> Int {
        lock.withLock { pullCounts[selector] ?? 0 }
    }

    /// How many times the account page identified by its cache-busting token
    /// was served — more than one means the same tab loaded the page twice
    /// (e.g. a web-view replacement re-navigation).
    func pageHits(for cacheToken: String) -> Int {
        lock.withLock { pageHitsByCacheToken[cacheToken] ?? 0 }
    }

    var pullsMissingSessionCookie: Int {
        lock.withLock { missingCookiePulls }
    }

    func stop() {
        listener.cancel()
    }

    private func start() async throws {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                startContinuation = continuation
            }
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.finishStart(.success(()))
                case .failed(let error):
                    self?.finishStart(.failure(error))
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    private func finishStart(_ result: Result<Void, Error>) {
        let continuation = lock.withLock {
            let continuation = startContinuation
            startContinuation = nil
            return continuation
        }
        switch result {
        case .success:
            continuation?.resume()
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, accumulatedData: Data())
    }

    private func receiveRequest(
        on connection: NWConnection,
        accumulatedData: Data
    ) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 16_384
        ) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var requestData = accumulatedData
            if let data {
                requestData.append(data)
            }
            let headerTerminator = Data("\r\n\r\n".utf8)
            guard requestData.range(of: headerTerminator) != nil || isComplete || error != nil else {
                self.receiveRequest(on: connection, accumulatedData: requestData)
                return
            }
            self.respond(to: requestData, on: connection)
        }
    }

    private func respond(
        to requestData: Data,
        on connection: NWConnection
    ) {
        let requestText = String(decoding: requestData, as: UTF8.self)
        let lines = requestText.components(separatedBy: "\r\n")
        let requestTarget = lines.first?
            .split(separator: " ")
            .dropFirst()
            .first
            .map(String.init) ?? "/"
        let path = requestTarget.split(separator: "?", maxSplits: 1).first
            .map(String.init) ?? requestTarget
        let query = requestTarget.split(separator: "?", maxSplits: 1)
            .dropFirst()
            .first
            .map(String.init) ?? ""
        let cookieHeader = lines
            .first { $0.lowercased().hasPrefix("cookie:") }?
            .dropFirst("cookie:".count)
            .trimmingCharacters(in: .whitespaces) ?? ""

        switch path {
        case "/account.html", "/":
            let cacheToken = query
                .split(separator: "&")
                .compactMap { pair -> String? in
                    let parts = pair.split(separator: "=", maxSplits: 1)
                    guard parts.first == "cache", parts.count == 2 else { return nil }
                    return String(parts[1]).removingPercentEncoding
                }
                .first
            if let cacheToken {
                lock.withLock {
                    pageHitsByCacheToken[cacheToken, default: 0] += 1
                }
            }
            let body = Data(
                "<!doctype html><meta charset=\"utf-8\"><title>account-fork-probe</title><h1>Account</h1>".utf8
            )
            send(
                status: "200 OK",
                headers: [
                    "Content-Type: text/html; charset=utf-8",
                    "Set-Cookie: \(Self.sessionCookieName)=\(Self.sessionCookieValue); Path=/",
                ],
                body: body,
                on: connection
            )
        case "/pull":
            respondToPull(query: query, cookieHeader: cookieHeader, on: connection)
        default:
            send(
                status: "404 Not Found",
                headers: ["Content-Type: text/plain; charset=utf-8"],
                body: Data("Not Found".utf8),
                on: connection
            )
        }
    }

    private func respondToPull(
        query: String,
        cookieHeader: String,
        on connection: NWConnection
    ) {
        let selector = query
            .split(separator: "&")
            .compactMap { pair -> String? in
                let parts = pair.split(separator: "=", maxSplits: 1)
                guard parts.first == "selector", parts.count == 2 else { return nil }
                return String(parts[1]).removingPercentEncoding
            }
            .first ?? ""

        let hasSessionCookie = cookieHeader
            .contains("\(Self.sessionCookieName)=\(Self.sessionCookieValue)")

        let previousPulls: Int = lock.withLock {
            if hasSessionCookie == false {
                missingCookiePulls += 1
                return -1
            }
            let count = pullCounts[selector] ?? 0
            pullCounts[selector] = count + 1
            return count
        }

        if previousPulls == -1 {
            send(
                status: "401 Unauthorized",
                headers: ["Content-Type: application/json; charset=utf-8"],
                body: Data("{\"ok\":false,\"error\":\"Missing session cookie\"}".utf8),
                on: connection
            )
            return
        }

        if previousPulls > 0 {
            send(
                status: "422 Unprocessable Entity",
                headers: ["Content-Type: application/json; charset=utf-8"],
                body: Data("{\"ok\":false,\"error\":\"Invalid selector\"}".utf8),
                on: connection
            )
            return
        }

        send(
            status: "200 OK",
            headers: ["Content-Type: application/json; charset=utf-8"],
            body: Data("{\"ok\":true}".utf8),
            on: connection
        )
    }

    private func send(
        status: String,
        headers: [String],
        body: Data,
        on connection: NWConnection
    ) {
        let head = ([
            "HTTP/1.1 \(status)",
        ] + headers + [
            "Content-Length: \(body.count)",
            "Cache-Control: no-store",
            "Connection: close",
            "",
            "",
        ]).joined(separator: "\r\n")
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
