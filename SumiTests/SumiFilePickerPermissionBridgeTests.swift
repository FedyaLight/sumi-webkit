import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SumiFilePickerPermissionBridgeTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_800_000_100)

    func testUserActivatedFilePickerProceedsToFakePanel() async {
        let presenter = FilePickerFakePanelPresenter(nextResult: .selected([fileURL("one.txt")]))
        let bridge = makeBridge(presenter: presenter)

        let results = await resolve(
            bridge: bridge,
            request: filePickerRequest(userActivation: .directWebKit)
        )

        XCTAssertEqual(results, [[fileURL("one.txt")]])
        XCTAssertEqual(presenter.requests.count, 1)
    }

    func testNoUserActivationDeniesWithoutOpeningPanel() async {
        let presenter = FilePickerFakePanelPresenter(nextResult: .selected([fileURL("blocked.txt")]))
        let bridge = makeBridge(presenter: presenter)

        let results = await resolve(
            bridge: bridge,
            request: filePickerRequest(userActivation: .none)
        )

        XCTAssertEqual(results, [nil])
        XCTAssertTrue(presenter.requests.isEmpty)
    }

    func testMissingTrustedOriginDeniesWithoutOpeningPanel() async {
        let presenter = FilePickerFakePanelPresenter(nextResult: .selected([fileURL("blocked.txt")]))
        let bridge = makeBridge(presenter: presenter)

        let results = await resolve(
            bridge: bridge,
            request: filePickerRequest(
                requestingOrigin: .invalid(reason: "missing-origin"),
                userActivation: .directWebKit
            )
        )

        XCTAssertEqual(results, [nil])
        XCTAssertTrue(presenter.requests.isEmpty)
    }

    func testInternalPageDeniesThroughPolicyWithoutOrdinaryWebRules() async {
        let presenter = FilePickerFakePanelPresenter(nextResult: .selected([fileURL("blocked.txt")]))
        let bridge = makeBridge(presenter: presenter)

        let results = await resolve(
            bridge: bridge,
            request: filePickerRequest(userActivation: .directWebKit),
            tabContext: tabContext(
                committedURL: URL(string: "sumi://settings")!,
                visibleURL: URL(string: "sumi://settings")!,
                mainFrameURL: URL(string: "sumi://settings")!
            )
        )

        XCTAssertEqual(results, [nil])
        XCTAssertTrue(presenter.requests.isEmpty)
    }

    func testEphemeralProfileStillUsesOneTimePanelFlow() async {
        let presenter = FilePickerFakePanelPresenter(nextResult: .selected([fileURL("ephemeral.txt")]))
        let bridge = makeBridge(presenter: presenter)

        let results = await resolve(
            bridge: bridge,
            request: filePickerRequest(userActivation: .directWebKit),
            tabContext: tabContext(isEphemeralProfile: true)
        )

        XCTAssertEqual(results, [[fileURL("ephemeral.txt")]])
        XCTAssertEqual(presenter.requests.count, 1)
    }

    func testPanelCancelCompletesWithNoURLs() async {
        let presenter = FilePickerFakePanelPresenter(nextResult: .cancelled)
        let bridge = makeBridge(presenter: presenter)

        let results = await resolve(
            bridge: bridge,
            request: filePickerRequest(userActivation: .directWebKit)
        )

        XCTAssertEqual(results, [nil])
    }

    func testSelectedURLsCompleteExactlyOnce() async {
        let presenter = FilePickerFakePanelPresenter()
        let bridge = makeBridge(presenter: presenter)
        let expectation = XCTestExpectation(description: "File picker completion")
        var results: [[URL]?] = []
        let webView = WKWebView()

        bridge.handleOpenPanel(
            filePickerRequest(userActivation: .directWebKit),
            tabContext: tabContext(),
            webView: webView,
            currentPageId: { "tab-a:1" }
        ) { urls in
            results.append(urls)
            expectation.fulfill()
        }
        await waitUntilPresenterReceivesRequest(presenter)
        presenter.completeTwice(.selected([fileURL("selected.txt")]), then: .cancelled)

        await fulfillment(of: [expectation], timeout: 1)
        withExtendedLifetime(webView) {}
        XCTAssertEqual(results, [[fileURL("selected.txt")]])
    }

    func testNavigationCancellationPreventsSelectedFilesFromBeingDelivered() async {
        let presenter = FilePickerFakePanelPresenter()
        let bridge = makeBridge(presenter: presenter)
        let expectation = XCTestExpectation(description: "File picker cancelled")
        var results: [[URL]?] = []
        let webView = WKWebView()

        bridge.handleOpenPanel(
            filePickerRequest(userActivation: .directWebKit),
            tabContext: tabContext(),
            webView: webView,
            currentPageId: { "tab-a:1" }
        ) { urls in
            results.append(urls)
            expectation.fulfill()
        }
        await waitUntilPresenterReceivesRequest(presenter)
        bridge.cancel(pageId: "tab-a:1", reason: "navigation")
        presenter.complete(.selected([fileURL("late.txt")]))

        await fulfillment(of: [expectation], timeout: 1)
        withExtendedLifetime(webView) {}
        XCTAssertEqual(results, [nil])
    }

    func testPageGenerationMismatchPreventsSelectedFilesFromBeingDelivered() async {
        let presenter = FilePickerFakePanelPresenter()
        let bridge = makeBridge(presenter: presenter)
        let expectation = XCTestExpectation(description: "File picker generation mismatch")
        var currentPageId = "tab-a:1"
        var results: [[URL]?] = []
        let webView = WKWebView()

        bridge.handleOpenPanel(
            filePickerRequest(userActivation: .directWebKit),
            tabContext: tabContext(),
            webView: webView,
            currentPageId: { currentPageId }
        ) { urls in
            results.append(urls)
            expectation.fulfill()
        }
        await waitUntilPresenterReceivesRequest(presenter)
        currentPageId = "tab-a:2"
        presenter.complete(.selected([fileURL("late.txt")]))

        await fulfillment(of: [expectation], timeout: 1)
        withExtendedLifetime(webView) {}
        XCTAssertEqual(results, [nil])
    }

    func testWebViewTabCleanupDoesNotDoubleComplete() async {
        let presenter = FilePickerFakePanelPresenter()
        let bridge = makeBridge(presenter: presenter)
        let expectation = XCTestExpectation(description: "File picker tab cleanup")
        var results: [[URL]?] = []
        let webView = WKWebView()

        bridge.handleOpenPanel(
            filePickerRequest(userActivation: .directWebKit),
            tabContext: tabContext(),
            webView: webView,
            currentPageId: { "tab-a:1" }
        ) { urls in
            results.append(urls)
            expectation.fulfill()
        }
        await waitUntilPresenterReceivesRequest(presenter)
        bridge.cancel(tabId: "tab-a", reason: "cleanup")
        presenter.complete(.selected([fileURL("late.txt")]))

        await fulfillment(of: [expectation], timeout: 1)
        withExtendedLifetime(webView) {}
        XCTAssertEqual(results, [nil])
    }

    func testPanelParametersArePassedToPresenter() async {
        let presenter = FilePickerFakePanelPresenter(nextResult: .cancelled)
        let bridge = makeBridge(presenter: presenter)

        _ = await resolve(
            bridge: bridge,
            request: filePickerRequest(
                allowsMultipleSelection: true,
                allowsDirectories: true,
                allowedContentTypeIdentifiers: ["public.png"],
                allowedFileExtensions: ["txt"],
                userActivation: .directWebKit
            )
        )

        guard let presentation = presenter.requests.first else {
            XCTFail("Expected file picker presentation request")
            return
        }
        XCTAssertEqual(presentation.allowedContentTypeIdentifiers, ["public.png"])
        XCTAssertEqual(presentation.allowedFileExtensions, ["txt"])
        XCTAssertEqual(presentation.allowsMultipleSelection, true)
        XCTAssertEqual(presentation.allowsDirectories, true)
    }

    func testNoSwiftDataWriteOccursForFilePicker() async {
        let store = FilePickerPermissionStore()
        let presenter = FilePickerFakePanelPresenter(nextResult: .cancelled)
        let bridge = makeBridge(store: store, presenter: presenter)

        _ = await resolve(
            bridge: bridge,
            request: filePickerRequest(userActivation: .directWebKit)
        )

        let setCount = await store.setDecisionCallCount()
        XCTAssertEqual(setCount, 0)
    }

    func testNormalTabRunOpenPanelRoutesThroughBridge() throws {
        let source = try sourceFile("Sumi/Models/Tab/Tab+UIDelegate.swift")
        let methodStart = try XCTUnwrap(source.range(of: "runOpenPanelWith parameters: WKOpenPanelParameters"))
        let methodSource = String(source[methodStart.lowerBound...])

        XCTAssertTrue(methodSource.contains("filePickerPermissionBridge.handleOpenPanel("))
        XCTAssertFalse(methodSource.contains("let openPanel = NSOpenPanel()"))
    }

    private func makeBridge(
        store: FilePickerPermissionStore = FilePickerPermissionStore(),
        presenter: FilePickerFakePanelPresenter
    ) -> SumiFilePickerPermissionBridge {
        let coordinator = SumiPermissionCoordinator(
            policyResolver: DefaultSumiPermissionPolicyResolver(
                systemPermissionService: FakeSumiSystemPermissionService()
            ),
            persistentStore: store,
            now: { self.fixedDate }
        )
        return SumiFilePickerPermissionBridge(
            coordinator: coordinator,
            panelPresenter: presenter,
            now: { self.fixedDate }
        )
    }

    private func resolve(
        bridge: SumiFilePickerPermissionBridge,
        request: SumiFilePickerPermissionRequest,
        tabContext: SumiFilePickerPermissionTabContext? = nil
    ) async -> [[URL]?] {
        let expectation = XCTestExpectation(description: "File picker result")
        let webView = WKWebView()
        var results: [[URL]?] = []
        bridge.handleOpenPanel(
            request,
            tabContext: tabContext ?? self.tabContext(),
            webView: webView,
            currentPageId: { "tab-a:1" }
        ) { urls in
            results.append(urls)
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 2)
        withExtendedLifetime(webView) {}
        return results
    }

    private func waitUntilPresenterReceivesRequest(
        _ presenter: FilePickerFakePanelPresenter
    ) async {
        for _ in 0..<50 where presenter.requests.isEmpty {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    private func filePickerRequest(
        requestingOrigin: SumiPermissionOrigin = SumiPermissionOrigin(string: "https://example.com"),
        allowsMultipleSelection: Bool = false,
        allowsDirectories: Bool = false,
        allowedContentTypeIdentifiers: [String] = [],
        allowedFileExtensions: [String] = [],
        userActivation: SumiPopupUserActivationState
    ) -> SumiFilePickerPermissionRequest {
        SumiFilePickerPermissionRequest(
            id: "file-picker-a",
            requestingOrigin: requestingOrigin,
            frameURL: URL(string: "https://example.com/form"),
            isMainFrame: true,
            allowsMultipleSelection: allowsMultipleSelection,
            allowsDirectories: allowsDirectories,
            allowedContentTypeIdentifiers: allowedContentTypeIdentifiers,
            allowedFileExtensions: allowedFileExtensions,
            userActivation: userActivation
        )
    }

    private func tabContext(
        tabId: String = "tab-a",
        pageId: String = "tab-a:1",
        profilePartitionId: String = "profile-a",
        isEphemeralProfile: Bool = false,
        committedURL: URL? = URL(string: "https://example.com"),
        visibleURL: URL? = URL(string: "https://example.com/form"),
        mainFrameURL: URL? = URL(string: "https://example.com"),
        isActiveTab: Bool = true,
        isVisibleTab: Bool = true,
        navigationOrPageGeneration: String? = "1"
    ) -> SumiFilePickerPermissionTabContext {
        SumiFilePickerPermissionTabContext(
            tabId: tabId,
            pageId: pageId,
            profilePartitionId: profilePartitionId,
            isEphemeralProfile: isEphemeralProfile,
            committedURL: committedURL,
            visibleURL: visibleURL,
            mainFrameURL: mainFrameURL,
            isActiveTab: isActiveTab,
            isVisibleTab: isVisibleTab,
            navigationOrPageGeneration: navigationOrPageGeneration
        )
    }

    private func fileURL(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/\(name)")
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repoRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}

@MainActor
private final class FilePickerFakePanelPresenter: SumiFilePickerPanelPresenting {
    private let nextResult: SumiFilePickerPanelResult?
    private var completions: [@MainActor (SumiFilePickerPanelResult) -> Void] = []
    private(set) var requests: [SumiFilePickerPanelPresentationRequest] = []

    init(nextResult: SumiFilePickerPanelResult? = nil) {
        self.nextResult = nextResult
    }

    func presentFilePicker(
        _ request: SumiFilePickerPanelPresentationRequest,
        for webView: WKWebView?,
        completion: @escaping @MainActor (SumiFilePickerPanelResult) -> Void
    ) {
        requests.append(request)
        if let nextResult {
            completion(nextResult)
        } else {
            completions.append(completion)
        }
    }

    func complete(_ result: SumiFilePickerPanelResult) {
        guard !completions.isEmpty else { return }
        let completion = completions.removeFirst()
        completion(result)
    }

    func completeTwice(
        _ first: SumiFilePickerPanelResult,
        then second: SumiFilePickerPanelResult
    ) {
        guard !completions.isEmpty else { return }
        let completion = completions[0]
        completion(first)
        completion(second)
    }
}

private actor FilePickerPermissionStore: SumiPermissionStore {
    private var records: [String: SumiPermissionStoreRecord] = [:]
    private var setCount = 0

    func getDecision(for key: SumiPermissionKey) async throws -> SumiPermissionStoreRecord? {
        records[key.persistentIdentity]
    }

    func setDecision(for key: SumiPermissionKey, decision: SumiPermissionDecision) async throws {
        setCount += 1
        records[key.persistentIdentity] = SumiPermissionStoreRecord(key: key, decision: decision)
    }

    func resetDecision(for key: SumiPermissionKey) async throws {
        records.removeValue(forKey: key.persistentIdentity)
    }

    func listDecisions(profilePartitionId: String) async throws -> [SumiPermissionStoreRecord] {
        let profileId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        return records.values.filter { $0.key.profilePartitionId == profileId }
    }

    func listDecisions(
        forDisplayDomain displayDomain: String,
        profilePartitionId: String
    ) async throws -> [SumiPermissionStoreRecord] {
        let domain = SumiPermissionStoreRecord.normalizedDisplayDomain(displayDomain)
        return try await listDecisions(profilePartitionId: profilePartitionId)
            .filter { $0.displayDomain == domain }
    }

    func clearAll(profilePartitionId: String) async throws {
        let profileId = SumiPermissionKey.normalizedProfilePartitionId(profilePartitionId)
        records = records.filter { _, record in record.key.profilePartitionId != profileId }
    }

    func clearForDisplayDomains(
        _ displayDomains: Set<String>,
        profilePartitionId: String
    ) async throws {
        let domains = Set(displayDomains.map(SumiPermissionStoreRecord.normalizedDisplayDomain))
        records = records.filter { _, record in !domains.contains(record.displayDomain) }
    }

    func clearForOrigins(
        _ origins: Set<SumiPermissionOrigin>,
        profilePartitionId: String
    ) async throws {
        let identities = Set(origins.map(\.identity))
        records = records.filter { _, record in
            !identities.contains(record.key.requestingOrigin.identity)
                && !identities.contains(record.key.topOrigin.identity)
        }
    }

    @discardableResult
    func expireDecisions(now: Date) async throws -> Int {
        0
    }

    func recordLastUsed(for key: SumiPermissionKey, at date: Date) async throws {}

    func setDecisionCallCount() -> Int {
        setCount
    }
}
