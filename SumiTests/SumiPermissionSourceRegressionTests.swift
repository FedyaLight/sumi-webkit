import SwiftData
import XCTest

@testable import Sumi

final class SumiPermissionSourceRegressionTests: XCTestCase {
    @MainActor
    func testExternalSchemeBridgeDoesNotOpenResolverWhenPermissionDenies() async {
        let mailURL = URL(string: "mailto:test@example.com?subject=secret")!
        let resolver = SourceRegressionExternalSchemeResolver(handlerSchemes: ["mailto"])
        let coordinator = ExternalSchemeSourceCoordinator(
            decision: sourceRegressionExternalSchemeDecision(
                .denied,
                reason: "stored-deny"
            )
        )
        let bridge = SumiExternalSchemePermissionBridge(
            coordinator: coordinator,
            appResolver: resolver,
            pendingStrategy: .promptPresenterUnavailableBlock,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        var willOpenCalled = false

        let result = await bridge.evaluate(
            sourceRegressionExternalSchemeRequest(targetURL: mailURL),
            tabContext: sourceRegressionExternalSchemeTabContext(),
            willOpen: { willOpenCalled = true }
        )

        XCTAssertFalse(result.didOpen)
        XCTAssertFalse(willOpenCalled)
        XCTAssertEqual(resolver.appInfoURLs, [mailURL])
        XCTAssertTrue(resolver.openedURLs.isEmpty)
        let contexts = await coordinator.recordedContexts()
        XCTAssertEqual(contexts.count, 1)
        XCTAssertEqual(contexts.first?.request.permissionTypes, [.externalScheme("mailto")])
    }

    @MainActor
    func testBrowserManagerPermissionRuntimeRecordsPermissionEvents() async throws {
        let recentActivityStore = SumiPermissionRecentActivityStore()
        let siteActivityStore = SumiPermissionSiteActivityStore(
            userDefaults: try XCTUnwrap(
                UserDefaults(suiteName: "SumiPermissionSourceRegressionTests-\(UUID().uuidString)")
            )
        )
        let systemPermissionService = FakeSumiSystemPermissionService(
            states: sumiPermissionIntegrationAuthorizedSystemStates()
        )
        let permissionCoordinator = SumiPermissionCoordinator(
            policyResolver: DefaultSumiPermissionPolicyResolver(
                systemPermissionService: systemPermissionService
            ),
            persistentStore: nil,
            antiAbuseStore: nil,
            sessionOwnerId: "browser-permission-source-regression"
        )
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: try makeInMemoryStartupContainer()
            ),
            systemPermissionService: systemPermissionService,
            permissionCoordinator: permissionCoordinator,
            permissionRecentActivityStore: recentActivityStore,
            permissionSiteActivityStore: siteActivityStore
        )
        await Task.yield()

        let requestTask = Task {
            await browserManager.permissionCoordinator.requestPermission(
                sumiPermissionIntegrationContext([.camera])
            )
        }
        let query = await sumiPermissionIntegrationWaitForActiveQuery(
            browserManager.permissionCoordinator
        )

        await waitUntil {
            recentActivityStore.records.contains {
                $0.permissionType == .camera && $0.action == .asked
            } && siteActivityStore.records(
                forSiteOf: query.topOrigin,
                profilePartitionId: query.profilePartitionId,
                isEphemeralProfile: query.isEphemeralProfile
            ).contains {
                $0.permissionType == .camera && $0.hasRequested
            }
        }

        await browserManager.permissionCoordinator.dismiss(query.id)
        _ = await requestTask.value
    }

    @MainActor
    private func makeInMemoryStartupContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    @MainActor
    private func waitUntil(
        _ condition: @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<100 {
            if condition() {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for condition", file: file, line: line)
    }
}

@MainActor
private final class SourceRegressionExternalSchemeResolver: SumiExternalAppResolving {
    private let handlerSchemes: Set<String>
    private(set) var appInfoURLs: [URL] = []
    private(set) var openedURLs: [URL] = []

    init(handlerSchemes: Set<String>) {
        self.handlerSchemes = Set(handlerSchemes.map(SumiPermissionType.normalizedExternalScheme))
    }

    func appInfo(for url: URL) -> SumiExternalAppInfo? {
        appInfoURLs.append(url)
        guard let scheme = url.scheme,
              handlerSchemes.contains(SumiPermissionType.normalizedExternalScheme(scheme))
        else { return nil }
        return SumiExternalAppInfo(appDisplayName: "Mail")
    }

    func open(_ url: URL) -> Bool {
        openedURLs.append(url)
        return true
    }
}

private actor ExternalSchemeSourceCoordinator: SumiPermissionCoordinating {
    private let decision: SumiPermissionCoordinatorDecision
    private var contexts: [SumiPermissionSecurityContext] = []

    init(decision: SumiPermissionCoordinatorDecision) {
        self.decision = decision
    }

    func requestPermission(_ context: SumiPermissionSecurityContext) async -> SumiPermissionCoordinatorDecision {
        contexts.append(context)
        return decision
    }

    func queryPermissionState(_ context: SumiPermissionSecurityContext) async -> SumiPermissionCoordinatorDecision {
        contexts.append(context)
        return decision
    }

    func activeQuery(forPageId _: String) -> SumiPermissionAuthorizationQuery? {
        nil
    }

    func stateSnapshot() -> SumiPermissionCoordinatorState {
        SumiPermissionCoordinatorState()
    }

    func events() -> AsyncStream<SumiPermissionCoordinatorEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    @discardableResult
    func cancel(requestId _: String, reason: String) -> SumiPermissionCoordinatorDecision {
        sourceRegressionExternalSchemeDecision(.cancelled, reason: reason)
    }

    @discardableResult
    func cancel(pageId _: String, reason: String) -> SumiPermissionCoordinatorDecision {
        sourceRegressionExternalSchemeDecision(.cancelled, reason: reason)
    }

    @discardableResult
    func cancelNavigation(pageId _: String, reason: String) -> SumiPermissionCoordinatorDecision {
        sourceRegressionExternalSchemeDecision(.cancelled, reason: reason)
    }

    @discardableResult
    func cancelTab(tabId _: String, reason: String) -> SumiPermissionCoordinatorDecision {
        sourceRegressionExternalSchemeDecision(.cancelled, reason: reason)
    }

    func recordedContexts() -> [SumiPermissionSecurityContext] {
        contexts
    }
}

private func sourceRegressionExternalSchemeRequest(
    targetURL: URL,
    userActivation: SumiExternalSchemeUserActivationState = .navigationAction
) -> SumiExternalSchemePermissionRequest {
    SumiExternalSchemePermissionRequest(
        id: "external-source-regression",
        targetURL: targetURL,
        requestingOrigin: SumiPermissionOrigin(string: "https://request.example"),
        userActivation: userActivation,
        isMainFrame: true,
        isRedirectChain: false
    )
}

private func sourceRegressionExternalSchemeTabContext() -> SumiExternalSchemePermissionTabContext {
    SumiExternalSchemePermissionTabContext(
        tabId: "tab-a",
        pageId: "tab-a:1",
        surface: .normalTab,
        profilePartitionId: "profile-a",
        isEphemeralProfile: false,
        committedURL: URL(string: "https://top.example"),
        visibleURL: URL(string: "https://top.example/path"),
        mainFrameURL: URL(string: "https://top.example"),
        isActiveTab: true,
        isVisibleTab: true,
        navigationOrPageGeneration: "1"
    )
}

private func sourceRegressionExternalSchemeDecision(
    _ outcome: SumiPermissionCoordinatorOutcome,
    reason: String
) -> SumiPermissionCoordinatorDecision {
    SumiPermissionCoordinatorDecision(
        outcome: outcome,
        state: outcome == .granted ? .allow : .deny,
        persistence: outcome == .granted || outcome == .denied ? .persistent : nil,
        source: .user,
        reason: reason,
        permissionTypes: [.externalScheme("mailto")],
        keys: []
    )
}
