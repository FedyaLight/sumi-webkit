import Combine
import WebKit
import XCTest
import SumiWebRuntime

@testable import Sumi

@MainActor
final class TabWebViewMaterializationAndRebuildTests: XCTestCase {
    func testRefreshPrimarySelectsAnAlreadyRegisteredCandidate() {
        let repository = WebViewSessionRepository()
        let tab = Tab(
            url: URL(string: "https://example.com")!,
            webViewSessions: repository,
            loadsCachedFaviconOnInit: false
        )
        let windowID = UUID()
        let webView = WKWebView()
        register(webView, tabID: tab.id, windowID: windowID, in: repository)

        makeMaterializationService(
            repository: repository,
            primaryCandidate: { _ in
                (.init(tabID: tab.id, windowID: windowID), webView)
            }
        ).refreshPrimary(
            for: tab
        )

        XCTAssertEqual(tab.webViewSession.primaryWindowID, windowID)
        XCTAssertIdentical(tab.webViewSession.primaryWebView, webView)
    }

    func testCreatePrimaryForFileURLInvokesInitialDocumentHandoff() throws {
        let browserManager = BrowserManager()
        let repository = browserManager.webViewSessions
        let tab = browserManager.tabManager.tabFactory.makeTab(
            url: URL(fileURLWithPath: "/tmp/sumi-create-primary/index.html"),
            loadsCachedFaviconOnInit: false
        )
        tab.profileId = browserManager.currentProfile?.id
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        let parked = try XCTUnwrap(
            tab.makeNormalTabWebView(
                reason: "TabWebViewMaterializationAndRebuildTests.parked"
            )
        )
        tab.parkExistingWebView(parked)
        let windowID = UUID()
        let created = try XCTUnwrap(
            makeMaterializationService(repository: repository).webView(
                for: tab,
                in: windowID
            )
        )

        XCTAssertFalse(created === parked)
        XCTAssertIdentical(repository.webView(for: tab.id, in: windowID), created)
        XCTAssertIdentical(tab.webViewSession.primaryWebView, created)
    }

    func testAdoptingUntrackedPrimaryReschedulesInitialDocumentForTrackedResidence() {
        let repository = WebViewSessionRepository()
        let targetURL = URL(string: "https://example.com/adopt-primary")!
        let tab = Tab(
            url: targetURL,
            webViewSessions: repository,
            loadsCachedFaviconOnInit: false
        )
        let webView = WKWebView()
        tab.replaceUntrackedWebView(webView)
        let windowID = UUID()
        let adopted = makeMaterializationService(repository: repository).webView(
            for: tab,
            in: windowID
        )

        XCTAssertIdentical(adopted, webView)
        XCTAssertEqual(
            repository.residence(of: webView),
            .window(.init(tabID: tab.id, windowID: windowID))
        )
    }

    func testLiveReplacementRunsRuntimePreparationAfterCanonicalCommit() throws {
        let browserManager = makeIsolatedOwnershipBrowserManager()
        let repository = browserManager.webViewSessions
        let ownership = browserManager.testWebViewRuntime().ownershipService
        let tab = browserManager.tabManager.tabFactory.makeTab(
            url: URL(string: "https://example.com/extension-replacement")!,
            loadsCachedFaviconOnInit: false
        )
        tab.profileId = browserManager.currentProfile?.id
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        let previous = WKWebView()
        ownership.installUntracked(previous, for: tab)
        var preparationSawCanonicalResidence = false

        let replacement = try XCTUnwrap(
            ownership.replaceLiveWebView(
                for: tab,
                in: nil,
                reason: "TabWebViewMaterializationAndRebuildTests.replacement",
                prepareCommittedReplacement: { webView in
                    preparationSawCanonicalResidence =
                        repository.untrackedWebView(for: tab.id) === webView
                },
                validate: { _ in true }
            )
        )

        XCTAssertTrue(preparationSawCanonicalResidence)
        XCTAssertFalse(replacement === previous)
        XCTAssertIdentical(repository.untrackedWebView(for: tab.id), replacement)
        XCTAssertNil(repository.residence(of: previous))
    }

    func testTrackedLiveReplacementRunsRuntimePreparationAfterCanonicalCommit() throws {
        let browserManager = makeIsolatedOwnershipBrowserManager()
        let repository = browserManager.webViewSessions
        let ownership = browserManager.testWebViewRuntime().ownershipService
        let tab = browserManager.tabManager.tabFactory.makeTab(
            url: URL(string: "https://example.com/tracked-extension-replacement")!,
            loadsCachedFaviconOnInit: false
        )
        tab.profileId = browserManager.currentProfile?.id
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        let windowID = UUID()
        let previous = WKWebView()
        ownership.assign(previous, to: tab, in: windowID)
        var preparationSawCanonicalResidence = false

        let replacement = try XCTUnwrap(
            ownership.replaceLiveWebView(
                for: tab,
                in: windowID,
                reason: "TabWebViewMaterializationAndRebuildTests.trackedReplacement",
                prepareCommittedReplacement: { webView in
                    preparationSawCanonicalResidence =
                        repository.webView(for: tab.id, in: windowID) === webView
                },
                validate: { _ in true }
            )
        )

        XCTAssertTrue(preparationSawCanonicalResidence)
        XCTAssertFalse(replacement === previous)
        XCTAssertIdentical(repository.webView(for: tab.id, in: windowID), replacement)
        XCTAssertNil(repository.residence(of: previous))
    }

    func testTrackedInitialDocumentHandoffRejectsChangedWindowResidence() async {
        let repository = WebViewSessionRepository()
        let targetURL = URL(string: "https://example.com/tracked-initial")!
        let controller = AssignmentDelayedUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        let webView = AssignmentInitialDocumentRecordingWebView(
            frame: .zero,
            configuration: configuration
        )
        let tab = Tab(
            url: targetURL,
            webViewSessions: repository,
            loadsCachedFaviconOnInit: false
        )
        let originalOwner = TrackedWebViewOwner(tabID: tab.id, windowID: UUID())
        let replacementOwner = TrackedWebViewOwner(tabID: tab.id, windowID: UUID())
        register(
            webView,
            tabID: originalOwner.tabID,
            windowID: originalOwner.windowID,
            in: repository
        )

        NormalTabInitialDocumentRuntimeHandoff.scheduleTrackedInitialLoad(
            tab: tab,
            webView: webView,
            targetURL: targetURL,
            expectedOwner: originalOwner,
            profileId: nil,
            registrationReason:
                "TabWebViewMaterializationAndRebuildTests.staleResidence",
            updatesTabPresentation: false
        )

        for _ in 0..<20 {
            await Task.yield()
            if controller.waitCallCount > 0 {
                break
            }
        }
        XCTAssertEqual(controller.waitCallCount, 1)

        register(
            webView,
            tabID: replacementOwner.tabID,
            windowID: replacementOwner.windowID,
            in: repository
        )
        XCTAssertEqual(repository.residence(of: webView), .window(replacementOwner))

        controller.finishInitialUserContentInstallation()
        for _ in 0..<20 {
            await Task.yield()
        }

        XCTAssertTrue(webView.loadedRequests.isEmpty)
    }

    func testGraphSettlementInvalidatesPermissionGenerationExactlyOnce() async throws {
        let repository = WebViewSessionRepository()
        let profile = Profile(name: "Permission Generation")
        let tab = Tab(
            url: URL(string: "https://example.com/permission-generation")!,
            webViewSessions: repository,
            loadsCachedFaviconOnInit: false
        )
        tab.profileId = profile.id
        tab.navigationRuntime.profileResolutionRuntime = TabProfileResolutionRuntime(
            ephemeralProfileForTab: { _, _ in nil },
            profile: { profileID in profileID == profile.id ? profile : nil },
            spaceProfile: { _ in nil },
            currentProfile: { profile },
            firstProfile: { profile }
        )
        let window = RebuildRuntimeWindowStub()
        let graph = makeWindowBoundRuntimeGraph(
            repository: repository,
            tab: tab,
            window: window
        )
        let oldWebView = try XCTUnwrap(
            tab.makeNormalTabWebView(reason: "permission-generation.old")
        )
        register(oldWebView, tabID: tab.id, windowID: window.id, in: repository)
        let originalPageID = tab.currentPermissionPageId()
        let targetURL = URL(
            string: "https://example.com/permission-generation/rebuilt"
        )!
        _ = tab.beginMainFrameNavigationIntent(to: targetURL)
        tab.url = targetURL

        let result = graph.rebuildService.rebuildLiveWebViewsResult(
            for: tab,
            preferredPrimaryWindowID: window.id,
            load: targetURL,
            reason: "permission-generation.rebuild"
        )

        XCTAssertEqual(result, .deferred)
        XCTAssertEqual(originalPageID, "\(tab.id.uuidString.lowercased()):0")
        await waitUntil {
            repository.residence(of: oldWebView) == nil
        }
        XCTAssertNil(repository.residence(of: oldWebView))
        XCTAssertEqual(
            tab.currentPermissionPageId(),
            "\(tab.id.uuidString.lowercased()):1"
        )
    }

    func testTrackedProfileAssignmentStaleCASRestoresAppliedReloadPolicyState() {
        let repository = WebViewSessionRepository()
        let oldProfile = Profile(name: "Old")
        let targetProfile = Profile(name: "Target")
        let tab = Tab(
            url: URL(string: "https://example.com/profile-tracked")!,
            webViewSessions: repository,
            loadsCachedFaviconOnInit: false
        )
        tab.profileId = oldProfile.id
        let oldState = SumiSafariContentBlockerAttachmentState.disabled(
            siteHost: "old.example"
        )
        let targetState = SumiSafariContentBlockerAttachmentState.disabled(
            siteHost: "target.example"
        )
        tab.reloadPolicyStateOwner.noteSafariContentBlockerAttachmentApplied(oldState)
        let oldWebView = WKWebView()
        let window = RebuildRuntimeWindowStub()
        register(oldWebView, tabID: tab.id, windowID: window.id, in: repository)
        let concurrentParked = WKWebView()
        var didInvalidateGeneration = false
        attachProfileRuntime(
            to: tab,
            profiles: [oldProfile.id: oldProfile, targetProfile.id: targetProfile],
            safariState: {
                if didInvalidateGeneration == false {
                    didInvalidateGeneration = true
                    tab.webViewSession.park(concurrentParked)
                }
                return targetState
            }
        )
        let graph = makeWindowBoundRuntimeGraph(
            repository: repository,
            tab: tab,
            window: window
        )
        let intent = tab.beginProfileAssignmentIntent(
            desiredProfileID: targetProfile.id,
            resolvedProfileID: targetProfile.id,
            targetURL: tab.url,
            requiresStructuralPersistence: true
        )

        let outcome = graph.profileAssignmentService
            .executeProfileAssignment(
            for: tab,
            targetProfile: targetProfile,
            intent: intent
        )

        XCTAssertEqual(outcome, .stale)
        XCTAssertEqual(tab.profileId, oldProfile.id)
        XCTAssertEqual(
            tab.reloadPolicyStateOwner.safariContentBlockerAppliedAttachmentState,
            oldState
        )
        XCTAssertIdentical(repository.webView(for: tab.id, in: window.id), oldWebView)
        XCTAssertIdentical(
            tab.webViewSession.parkedWebView,
            concurrentParked
        )
        tab.abortProfileAssignmentIntent(intent)
    }

    func testDetachedProfileAssignmentStaleCASRestoresAppliedReloadPolicyState() {
        let repository = WebViewSessionRepository()
        let graph = makeTestWebViewRuntimeGraph(webViewSessions: repository)
        let oldProfile = Profile(name: "Old")
        let targetProfile = Profile(name: "Target")
        let tab = Tab(
            url: URL(string: "https://example.com/profile-detached")!,
            webViewSessions: repository,
            loadsCachedFaviconOnInit: false
        )
        tab.profileId = oldProfile.id
        let oldState = SumiSafariContentBlockerAttachmentState.disabled(
            siteHost: "old.example"
        )
        let targetState = SumiSafariContentBlockerAttachmentState.disabled(
            siteHost: "target.example"
        )
        tab.reloadPolicyStateOwner.noteSafariContentBlockerAttachmentApplied(oldState)
        let oldWebView = WKWebView()
        tab.webViewSession.park(oldWebView)
        var didInvalidateGeneration = false
        attachProfileRuntime(
            to: tab,
            profiles: [oldProfile.id: oldProfile, targetProfile.id: targetProfile],
            safariState: {
                if didInvalidateGeneration == false {
                    didInvalidateGeneration = true
                    XCTAssertTrue(
                        tab.webViewSession.adoptParkedAsUntracked(oldWebView)
                    )
                }
                return targetState
            }
        )
        let intent = tab.beginProfileAssignmentIntent(
            desiredProfileID: targetProfile.id,
            resolvedProfileID: targetProfile.id,
            targetURL: tab.url,
            requiresStructuralPersistence: true
        )

        let outcome = graph.profileAssignmentService
            .executeProfileAssignment(
            for: tab,
            targetProfile: targetProfile,
            intent: intent
        )

        XCTAssertEqual(outcome, .stale)
        XCTAssertEqual(tab.profileId, oldProfile.id)
        XCTAssertEqual(
            tab.reloadPolicyStateOwner.safariContentBlockerAppliedAttachmentState,
            oldState
        )
        XCTAssertIdentical(
            tab.webViewSession.untrackedWebView,
            oldWebView
        )
        tab.abortProfileAssignmentIntent(intent)
    }

    private func makeMaterializationService(
        repository: WebViewSessionRepository,
        primaryCandidate: @escaping @MainActor @Sendable (UUID) -> (
            owner: TrackedWebViewOwner,
            webView: WKWebView
        )? = { _ in nil }
    ) -> TabWebViewMaterializationService {
        TabWebViewMaterializationService(
            runtime: .init(
                webViewSessions: repository,
                initialDocumentWarmup: {
                    InitialDocumentWarmupRuntime(
                        needsInitialDocumentExtensionContextLoad: { _ in false },
                        ensureInitialExtensionContextsLoaded: { _ in },
                        refreshCompositorForWindow: { _ in }
                    )
                },
                register: { [weak self] webView, tabID, windowID in
                    self?.register(
                        webView,
                        tabID: tabID,
                        windowID: windowID,
                        in: repository
                    )
                },
                promotePrimary: { owner, webView in
                    WebViewTrackingLifecycleOwner()
                        .promoteTrackedWebViewToPrimary(
                            owner: owner,
                            expectedWebView: webView,
                            in: repository
                        )
                },
                primaryCandidate: primaryCandidate,
                notifyActivatedIfCurrent: { _, _ in }
            ),
            planner: WebViewCreationPlanner()
        )
    }

    private func makeIsolatedOwnershipBrowserManager() -> BrowserManager {
        let defaults = UserDefaults(
            suiteName: "TabWebViewMaterializationAndRebuildTests.\(UUID().uuidString)"
        )!
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: defaults)
        )
        registry.disable(.extensions)
        let browserManager = BrowserManager(moduleRegistry: registry)
        return browserManager
    }

    private func attachProfileRuntime(
        to tab: Tab,
        profiles: [UUID: Profile],
        safariState: @escaping () -> SumiSafariContentBlockerAttachmentState
    ) {
        var runtime = TabBrowserRuntime.inactive
        runtime.profileResolutionRuntime = TabProfileResolutionRuntime(
            ephemeralProfileForTab: { _, _ in nil },
            profile: { profiles[$0] },
            spaceProfile: { _ in nil },
            currentProfile: { profiles.values.first },
            firstProfile: { profiles.values.first }
        )
        runtime.webViewConfigurationContext = {
            TabWebViewConfigurationContext(
                browserConfiguration: BrowserConfiguration(),
                extensionNormalTabUserScripts: { [] },
                userscriptsNormalTabUserScripts: { _, _, _, _ in [] },
                boostsNormalTabUserScripts: { _, _, _ in [] },
                protectionDecision: { _, _ in nil },
                protectionDesiredAttachmentState: {
                    .disabled(siteHost: $0?.host)
                },
                safariContentBlockerAttachmentState: { _ in safariState() },
                safariBlockerDesiredAttachmentState: { _ in safariState() },
                enabledSafariContentBlockingServices: { _, _ in [] },
                prepareWebViewConfigForExtensionRuntime: { _, _, _ in }
            )
        }
        tab.attachBrowserRuntime(runtime)
    }

    private func register(
        _ webView: WKWebView,
        tabID: UUID,
        windowID: UUID,
        in repository: WebViewSessionRepository
    ) {
        WebViewTrackingLifecycleOwner().registerTrackedWebView(
            webView,
            for: .init(tabID: tabID, windowID: windowID),
            in: repository,
            removeFromContainers: { _ in },
            installRuntimeObservations: { _ in },
            uninstallRuntimeObservationsIfUntracked: { _ in },
            pruneInvalidDeferredCommands: { _ in },
            canDisplaceWebView: { _ in true },
            removeRecentVisibility: { _ in },
            cleanupDisplacedWebView: { _, _ in }
        )
    }

    private func makeWindowBoundRuntimeGraph(
        repository: WebViewSessionRepository,
        tab: Tab,
        window: RebuildRuntimeWindowStub
    ) -> WebViewRuntimeGraph {
        let tabID = tab.id
        let windowID = window.id
        return makeTestWebViewRuntimeGraph(
            webViewSessions: repository,
            resolveRuntimeTab: { id in id == tabID ? tab : nil },
            windowServices: WebViewWindowServices(
                liveWindowIDs: { [windowID] },
                containsWindow: { $0 == windowID },
                currentTabID: { $0 == windowID ? tabID : nil },
                selectTab: { _, _ in },
                refreshCompositor: { _ in },
                notifyTabActivatedIfCurrent: { _, _ in }
            ),
            visibleContext: WebViewVisibleRuntimeContext(
                windowState: { id in id == windowID ? window : nil },
                currentTabId: { _ in tabID },
                splitVisibleTabIds: { _ in [] },
                resolveTab: { id, _ in id == tabID ? tab : nil },
                canMaterializeWebViewDuringStartup: { _ in true },
                markTabAccessed: { _ in },
                globallyVisibleTabIDs: { [tabID] in [tabID] },
                scheduleTabSuspensionReconcile: { _ in },
                scheduleBackgroundMediaReconcile: { _ in },
                refreshCompositor: { _ in }
            ),
            initialDocumentContext: InitialDocumentWebViewRuntimeContext(
                needsInitialDocumentExtensionContextLoad: { _ in false },
                ensureInitialExtensionContextsLoaded: { _ in },
                refreshCompositorForWindow: { _ in }
            ),
            shutdownContext: WebViewShutdownRuntimeContext(
                cleanupUserScripts: { _, _ in }
            )
        )
    }

    private func waitUntil(
        _ condition: @MainActor () -> Bool
    ) async {
        for _ in 0..<100 {
            if condition() { return }
            await Task.yield()
        }
    }
}

@MainActor
private final class RebuildRuntimeWindowStub: WebRuntimeWindowHandle {
    let id = UUID()
    var ephemeralTabHandles: [any WebRuntimeTabHandle] = []
}

@MainActor
private final class AssignmentInitialDocumentRecordingWebView: WKWebView {
    private(set) var loadedRequests: [URLRequest] = []

    override func load(_ request: URLRequest) -> WKNavigation? {
        loadedRequests.append(request)
        return nil
    }
}

@MainActor
private final class AssignmentDelayedUserContentController:
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
