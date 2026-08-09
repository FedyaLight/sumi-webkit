import Combine
import Foundation
import SumiDomain
import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class PageRuntimePoisonedGenerationFeedbackLoopTests: XCTestCase {
    func testReloadSupersedesAndReportsBrowserOwnedWaitThatFreshRuntimeEscapes()
        async throws {
        try XCTSkipUnless(
            FileManager.default.fileExists(
                atPath: "/tmp/com.sumi.poisoned-runtime-feedback-loop.enabled"
            ),
            "Opt-in red feedback loop; production and the default suite stay zero-cost."
        )

        let profile = Profile(name: "Poisoned runtime feedback loop")
        let window = BrowserWindowState()
        var retainedTab: Tab?
        var destroyedWebViews: [WKWebView] = []
        let destroyRetiredGenerations: ([RetiredTabWebViewGeneration]) -> Void = {
            generations in
            let webViews = generations.flatMap(\.snapshot.allKnownWebViews)
            destroyedWebViews.append(contentsOf: webViews)
            retainedTab?.webViewsDidLeaveNavigationRuntime(
                webViews,
                preferredAuthorityWebView: nil
            )
            for webView in webViews {
                SumiWebViewShutdown.performTerminalShutdown(
                    on: webView,
                    runtime: .init(removeWebViewFromContainers: { _ in })
                )
            }
        }
        let retirement = TestRuntimePorts.RetirementCapabilities(
            canRetire: { _ in true },
            beginCommitted: { _ in true },
            committedRetirementIsExact: { _ in true },
            destroy: destroyRetiredGenerations,
            destroyAfterTerminalDrain: destroyRetiredGenerations
        )
        let runtime = TestRuntimePorts.make(
            currentProfileId: { profile.id },
            defaultProfileId: { profile.id },
            profile: { $0 == profile.id ? profile : nil },
            windowState: { $0 == window.id ? window : nil },
            windows: { [(window.id, window)] },
            windowStates: { [window] },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: retirement
            )
        )
        let browser = BrowserManager(runtimePorts: runtime)
        browser.tabResidenceAuthority.establishResidenceSession(on: window)
        browser.windowRegistry.register(window)
        let space = try XCTUnwrap(browser.sidebarSpaceLifecycle.createSpace(
            name: "Space",
            icon: SumiPersistentGlyph.spaceDefaultIconValue,
            profileID: profile.id
        ))
        window.currentSpaceId = space.id
        window.currentProfileId = profile.id
        let pin = try XCTUnwrap(browser.shortcutPinStoreOwner.insert(
            ShortcutPin(
                id: UUID(),
                role: .spacePinned,
                spaceId: space.id,
                index: 0,
                launchURL: URL(string: "https://poisoned-runtime.example/page")!,
                title: "Poisoned runtime"
            ),
            at: 0
        ))
        let originalTab = try XCTUnwrap(
            browser.shortcutTabMaterializer.materialize(
                pin,
                in: window.id,
                currentSpaceId: space.id
            )
        )
        retainedTab = originalTab
        window.currentTabId = originalTab.id
        window.currentShortcutPinId = pin.id
        window.currentShortcutPinRole = pin.role

        let heldController = PageRuntimePrerequisiteGate(isReady: false)
        let retainedWebView = PageRuntimeSubmissionRecordingWebView(
            controller: heldController
        )
        originalTab.replaceUntrackedWebView(retainedWebView)
        _ = originalTab.installNavigationDelegate(on: retainedWebView)

        let firstReload = scheduleReloadWaitingForBrowserPrerequisite(
            tab: originalTab,
            webView: retainedWebView
        )
        await yieldUntil { heldController.waitCount == 1 }

        guard case .waiting(let reportedFirstOwner) = firstReload.dispositions.only
        else {
            return XCTFail("Reload must report its exact prerequisite owner")
        }
        XCTAssertTrue(originalTab.loadingState.isLoading)
        XCTAssertTrue(retainedWebView.loadedRequests.isEmpty)
        guard case .waiting(let firstAttemptOwner) = originalTab.mainFrameLoads
            .attemptStatus(on: retainedWebView) else {
            return XCTFail("Held prerequisite must retain one exact attempt owner")
        }
        guard case .preparing = firstAttemptOwner.phase else {
            return XCTFail("Held prerequisite must remain in preparation")
        }
        XCTAssertEqual(reportedFirstOwner, firstAttemptOwner)

        let secondReload = scheduleReloadWaitingForBrowserPrerequisite(
            tab: originalTab,
            webView: retainedWebView
        )
        await yieldUntil { heldController.waitCount == 2 }

        guard case .waiting(let reportedSecondOwner) = secondReload.dispositions.only
        else {
            return XCTFail("Repeated Reload must report its replacement owner")
        }
        guard case .waiting(let secondAttemptOwner) = originalTab.mainFrameLoads
            .attemptStatus(on: retainedWebView) else {
            return XCTFail("Replacement reload must retain one exact attempt owner")
        }
        XCTAssertNotEqual(secondAttemptOwner.participantID, firstAttemptOwner.participantID)
        XCTAssertGreaterThan(
            secondAttemptOwner.intent.revision,
            firstAttemptOwner.intent.revision
        )
        XCTAssertEqual(reportedSecondOwner, secondAttemptOwner)
        XCTAssertIdentical(originalTab.resolvedCurrentWebView(), retainedWebView)
        let retirementResult = browser.shortcutLiveTabRetirement.retire(
            pinId: pin.id,
            in: window.id
        )

        XCTAssertTrue(retirementResult.didRetire)
        XCTAssertNil(browser.liveShortcutTabs.entry(tabId: originalTab.id))
        XCTAssertNil(browser.tabCollectionMembershipOwner.tab(for: originalTab.id))
        XCTAssertTrue(originalTab.webViewSession.allKnownWebViews.isEmpty)
        XCTAssertEqual(destroyedWebViews.map(ObjectIdentifier.init), [
            ObjectIdentifier(retainedWebView),
        ])
        XCTAssertNil(retainedWebView.navigationDelegate)

        let freshTab = try XCTUnwrap(
            browser.shortcutTabMaterializer.materialize(
                pin,
                in: window.id,
                currentSpaceId: space.id
            )
        )
        let readyController = PageRuntimePrerequisiteGate(isReady: true)
        let freshWebView = PageRuntimeSubmissionRecordingWebView(
            controller: readyController
        )
        freshTab.replaceUntrackedWebView(freshWebView)
        _ = freshTab.installNavigationDelegate(on: freshWebView)

        XCTAssertNotIdentical(freshTab, originalTab)
        XCTAssertNotIdentical(freshWebView, retainedWebView)
        XCTAssertEqual(freshTab.url, pin.launchURL)

        _ = scheduleReloadWaitingForBrowserPrerequisite(
            tab: freshTab,
            webView: freshWebView
        )
        await yieldUntil { freshWebView.loadedRequests.isEmpty == false }

        XCTAssertEqual(freshWebView.loadedRequests.map(\.url), [pin.launchURL])
        XCTAssertEqual(readyController.waitCount, 1)
    }

    private func scheduleReloadWaitingForBrowserPrerequisite(
        tab: Tab,
        webView: WKWebView
    ) -> PageReloadCommandOutcome {
        tab.navigationCommandOwner.refresh(
            tab,
            resolvedWebView: { webView },
            reason: "PageRuntimePoisonedGenerationFeedbackLoopTests.reload",
            deliverTrackedReload: { intent, policy in
                var submittedOwner: TabMainFramePendingAttemptOwner?
                var submittedNavigationID: ObjectIdentifier?
                var submission: WebRuntimeMainFrameReloadSubmission = .failed
                tab.navigationCommandOwner
                    .performMainFrameNavigationAfterContentBlockingAssetsIfNeeded(
                    on: webView,
                    tab: tab,
                    waitForContentBlockingAssets: true,
                    didClaim: { submittedOwner = $0 },
                    didSubmit: { navigationID, _ in
                        submittedNavigationID = navigationID
                    }
                ) { resolvedWebView, targetURL in
                    submission = WebRuntimeMainFrameReloader.reloadOrLoad(
                        targetURL,
                        on: resolvedWebView,
                        policy: policy,
                        fallback: .safeOrdinaryNavigation
                    )
                    return submission.navigation
                }

                if case .waiting(let owner) = tab.mainFrameLoads.attemptStatus(
                    on: webView
                ) {
                    return PageReloadCommandOutcome(.waiting(owner))
                }
                guard let submittedOwner, let submittedNavigationID else {
                    return .failed(
                        intent: intent,
                        webView: webView,
                        reason: .submissionFailed
                    )
                }
                let proof = PageReloadSubmission(
                    owner: submittedOwner,
                    navigationID: submittedNavigationID
                )
                switch submission {
                case .fallbackNavigation:
                    return PageReloadCommandOutcome(
                        .submittedFallbackNavigation(proof)
                    )
                case .reloaded:
                    return PageReloadCommandOutcome(.submitted(proof))
                case .failed:
                    return .failed(
                        intent: intent,
                        webView: webView,
                        reason: .submissionFailed
                    )
                }
            }
        )
    }

    private func yieldUntil(
        _ condition: @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<100 where condition() == false {
            await Task.yield()
        }
        XCTAssertTrue(condition(), file: file, line: line)
    }
}

private extension Array {
    var only: Element? { count == 1 ? self[0] : nil }
}

@MainActor
private final class PageRuntimePrerequisiteGate:
    WKUserContentController,
    SumiNormalTabUserContentControlling {
    var normalTabUserScriptsProvider: SumiNormalTabUserScripts?
    let contentBlockingAssetSummary: SumiNormalTabContentBlockingAssetSummary
    private(set) var hasInstalledInitialUserContent: Bool
    private(set) var waitCount = 0
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    init(isReady: Bool) {
        hasInstalledInitialUserContent = isReady
        contentBlockingAssetSummary = SumiNormalTabContentBlockingAssetSummary(
            isInstalled: isReady,
            globalRuleListCount: 0,
            updateRuleCount: 0,
            isContentBlockingFeatureEnabled: false
        )
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var wkUserContentController: WKUserContentController { self }

    #if DEBUG
        var contentBlockingAssetSummaryPublisher:
            AnyPublisher<SumiNormalTabContentBlockingAssetSummary, Never> {
            Just(contentBlockingAssetSummary).eraseToAnyPublisher()
        }
    #endif

    func replaceNormalTabUserScripts(with provider: SumiNormalTabUserScripts) async {
        normalTabUserScriptsProvider = provider
    }

    func waitForContentBlockingAssetsInstalled() async
        -> PageNavigationPrerequisiteResult {
        waitCount += 1
        guard hasInstalledInitialUserContent == false else { return .ready }

        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiters[id] = continuation
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.resumeWaiter(id)
            }
        }
        return Task.isCancelled ? .cancelled : .ready
    }

    func cleanUpBeforeClosing() {
        // Production cleanup does not complete an uninstalled asset wait.
    }

    private func resumeWaiter(_ id: UUID) {
        waiters.removeValue(forKey: id)?.resume()
    }
}

@MainActor
private final class PageRuntimeSubmissionRecordingWebView: WKWebView {
    private(set) var loadedRequests: [URLRequest] = []

    init(controller: WKUserContentController) {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        super.init(frame: .zero, configuration: configuration)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func reload() -> WKNavigation? { nil }

    override func load(_ request: URLRequest) -> WKNavigation? {
        loadedRequests.append(request)
        return super.loadHTMLString(
            "<html><body>feedback-loop</body></html>",
            baseURL: request.url
        )
    }
}
