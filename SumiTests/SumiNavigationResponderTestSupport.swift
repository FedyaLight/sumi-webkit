import AppKit
import SwiftData
import WebKit
import XCTest

@testable import Navigation
@testable import Sumi
import SumiDomain


@MainActor
class SumiNavigationResponderTestCase: XCTestCase {
    var retainedAutoplayTabs: [Tab] = []

    func navigationAction(
        url: URL,
        navigationType: NavigationType,
        shouldDownload: Bool = false,
        requestCachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy,
        httpMethod: String? = nil,
        httpBody: Data? = nil,
        webView: WKWebView? = nil,
        sourceURL: URL? = nil,
        sourceSecurityOrigin: SumiSecurityOrigin? = nil,
        isUserInitiated: Bool = true,
        isMainFrame: Bool = true,
        targetFrameIsMainFrame: Bool? = nil,
        isTargetingNewWindow: Bool = false,
        redirectHistory: [NavigationAction]? = nil,
        mainFrameNavigation: Navigation? = nil,
        modifierFlags: NSEvent.ModifierFlags = []
    ) -> NavigationAction {
        let webView = webView ?? WKWebView(frame: .zero)
        let frameURL = sourceURL ?? url
        let securityOrigin = sourceSecurityOrigin ?? SumiSecurityOrigin(
            protocol: frameURL.scheme ?? "",
            host: frameURL.host ?? "",
            port: frameURL.port ?? 0
        )
        let frame = securityOrigin.navigationFrameInfo(
            webView: webView,
            handle: FrameHandle(rawValue: UInt64(1))!,
            isMainFrame: isMainFrame,
            url: frameURL
        )
        let targetFrame = isTargetingNewWindow ? nil : securityOrigin.navigationFrameInfo(
            webView: webView,
            handle: FrameHandle(rawValue: UInt64(2))!,
            isMainFrame: targetFrameIsMainFrame ?? isMainFrame,
            url: frameURL
        )
        var request = URLRequest(url: url, cachePolicy: requestCachePolicy)
        request.httpMethod = httpMethod
        request.httpBody = httpBody
        var action = NavigationAction(
            request: request,
            navigationType: navigationType,
            currentHistoryItemIdentity: nil,
            redirectHistory: redirectHistory,
            isUserInitiated: isUserInitiated,
            sourceFrame: frame,
            targetFrame: targetFrame,
            shouldDownload: shouldDownload,
            mainFrameNavigation: mainFrameNavigation
        )
        action.modifierFlags = modifierFlags
        return action
    }

    func sumiNavigationPreferences() -> SumiNavigationPreferences {
        SumiNavigationPreferences(
            userAgent: nil,
            contentMode: .recommended,
            javaScriptEnabled: true,
            autoplayPolicy: nil,
            mustApplyAutoplayPolicy: false
        )
    }

    func mainFrameNavigation(receiving action: NavigationAction, isCurrent: Bool = false) -> Navigation {
        let navigation = Navigation(
            identity: NavigationIdentity(nil),
            responders: ResponderChain(),
            state: .expected(nil),
            isCurrent: isCurrent
        )
        // Production NavigationActions already carry the exact owning
        // Navigation. Rebuild the synthetic action with the same contract so
        // terminal callbacks exercise identity routing instead of a test-only
        // nil back-reference.
        let linkedAction = NavigationAction(
            request: action.request,
            navigationType: action.navigationType,
            currentHistoryItemIdentity: nil,
            redirectHistory: action.redirectHistory,
            isUserInitiated: action.isUserInitiated,
            sourceFrame: action.sourceFrame,
            targetFrame: action.targetFrame,
            shouldDownload: action.shouldDownload,
            mainFrameNavigation: navigation
        )
        navigation.navigationActionReceived(linkedAction)
        return navigation
    }

    func evaluateActionPolicy(
        with responders: [any NavigationResponder & AnyObject],
        action: NavigationAction,
        preferences: inout NavigationPreferences
    ) async -> NavigationActionPolicy? {
        var chain = ResponderChain()
        chain.setResponders(responders.map { ResponderRefMaker.strong($0) })
        for responder in chain {
            if let policy = await responder.decidePolicy(for: action, preferences: &preferences) {
                return policy
            }
        }
        return .next
    }

    func evaluateResponsePolicy(
        with responders: [any NavigationResponder & AnyObject],
        response: NavigationResponse
    ) async -> NavigationResponsePolicy? {
        var chain = ResponderChain()
        chain.setResponders(responders.map { ResponderRefMaker.strong($0) })
        for responder in chain {
            if let policy = await responder.decidePolicy(for: response) {
                return policy
            }
        }
        return .next
    }

    func makeAutoplayHarness() throws -> (
        container: ModelContainer,
        adapter: SumiAutoplayPolicyStoreAdapter
    ) {
        let container = try ModelContainer(
            for: Schema([PermissionDecisionEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let store = SwiftDataPermissionStore(container: container)
        return (
            container,
            SumiAutoplayPolicyStoreAdapter(persistentStore: store)
        )
    }

    func makeAutoplayResponder(
        store: SumiAutoplayPolicyStoreAdapter,
        profile: Profile
    ) -> SumiAutoplayPolicyNavigationResponder {
        let tab = Tab(url: URL(string: "https://video.example")!)
        retainedAutoplayTabs.append(tab)
        return SumiAutoplayPolicyNavigationResponder(
            tab: tab,
            autoplayPolicyStore: store,
            profileProvider: { _ in profile }
        )
    }

    func makeProfile(_ id: String) -> Profile {
        Profile(id: UUID(uuidString: id)!, name: "Profile", icon: "person")
    }

    func makeMouseEvent(
        type: NSEvent.EventType,
        modifierFlags: NSEvent.ModifierFlags
    ) -> NSEvent {
        guard let event = NSEvent.mouseEvent(
            with: type,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ) else {
            fatalError("Failed to create mouse event")
        }
        return event
    }

    func assertExternalSchemeOpenDoesNotCloseAfterCompletion(
        webView: SumiNavigationClosingTrackingWebView,
        complete: (SumiNavigationResponderAdapter, Navigation) -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let tab = Tab(url: URL(string: "https://example.com")!)
        let resolver = NavigationExternalSchemeFakeResolver(handlerSchemes: ["mailto"])
        let bridge = SumiExternalSchemePermissionBridge(
            coordinator: NavigationExternalSchemeFakeCoordinator(
                decision: navigationExternalCoordinatorDecision(.granted, reason: "stored-allow")
            ),
            appResolver: resolver,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        let responder = SumiExternalSchemeNavigationResponder(
            tab: tab,
            permissionBridge: bridge,
            tabContextProvider: { _ in navigationExternalTabContext() }
        )
        let adapter = SumiNavigationResponderAdapter(target: responder)
        let navigation = mainFrameNavigation(receiving: navigationAction(
            url: URL(string: "https://request.example/page")!,
            navigationType: .linkActivated(isMiddleClick: false),
            webView: webView
        ))
        var preferences = NavigationPreferences.default

        complete(adapter, navigation)

        let policy = await adapter.decidePolicy(
            for: navigationAction(
                url: URL(string: "mailto:test@example.com")!,
                navigationType: .linkActivated(isMiddleClick: false),
                webView: webView,
                sourceURL: URL(string: "https://request.example/page")!,
                sourceSecurityOrigin: SumiSecurityOrigin(protocol: "https", host: "request.example", port: 0)
            ),
            preferences: &preferences
        )

        XCTAssertEqual(policy?.isCancel, true, file: file, line: line)
        XCTAssertEqual(resolver.openedURLs, [URL(string: "mailto:test@example.com")!], file: file, line: line)
        XCTAssertEqual(webView.closeScriptEvaluations, 0, file: file, line: line)
    }
}

@MainActor
final class SumiNavigationTerminalProbeResponder: SumiNavigationTerminalResponding {
    private(set) var terminations: [SumiMainFrameNavigationTermination] = []
    private(set) var terminatedWebViews: [WKWebView] = []

    func mainFrameNavigationDidTerminate(
        _ termination: SumiMainFrameNavigationTermination
    ) {
        terminations.append(termination)
    }

    func webContentProcessDidTerminate(on webView: WKWebView) {
        terminatedWebViews.append(webView)
    }
}

func XCTAssertActionPolicy(
    _ actual: NavigationActionPolicy?,
    _ expected: NavigationActionPolicy,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    switch (actual, expected) {
    case (.some(.allow), .allow),
        (.some(.cancel), .cancel),
        (.some(.download), .download):
        break
    default:
        XCTFail(
            "Expected \(expected.debugDescription), got \(actual?.debugDescription ?? "nil")",
            file: file,
            line: line
        )
    }
}

func XCTAssertAuthDisposition(
    _ actual: AuthChallengeDisposition?,
    _ expected: AuthChallengeDisposition,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    switch (actual, expected) {
    case (.some(.credential(let actualCredential)), .credential(let expectedCredential)):
        XCTAssertEqual(actualCredential.user, expectedCredential.user, file: file, line: line)
        XCTAssertEqual(actualCredential.password, expectedCredential.password, file: file, line: line)
        XCTAssertEqual(actualCredential.persistence, expectedCredential.persistence, file: file, line: line)
    case (.some(.cancel), .cancel),
        (.some(.rejectProtectionSpace), .rejectProtectionSpace):
        break
    default:
        XCTFail("Expected \(expected), got \(String(describing: actual))", file: file, line: line)
    }
}

func makeAuthenticationChallenge() -> URLAuthenticationChallenge {
    URLAuthenticationChallenge(
        protectionSpace: URLProtectionSpace(
            host: "auth.example",
            port: 443,
            protocol: "https",
            realm: "SumiNavigationResponderTests",
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        ),
        proposedCredential: nil,
        previousFailureCount: 0,
        failureResponse: nil,
        error: nil,
        sender: SumiURLAuthenticationChallengeSenderMock()
    )
}

extension NavigationActionPolicy {
    var isCancel: Bool {
        if case .cancel = self { return true }
        return false
    }

    var isDownload: Bool {
        if case .download = self { return true }
        return false
    }
}

extension SumiAuthChallengeDisposition {
    var isCancel: Bool {
        if case .cancel = self { return true }
        return false
    }

    var isRejectProtectionSpace: Bool {
        if case .rejectProtectionSpace = self { return true }
        return false
    }
}

@MainActor
extension NavigationPreferences {
    static var `default`: NavigationPreferences {
        NavigationPreferences(userAgent: nil, preferences: WKWebpagePreferences())
    }
}

@MainActor
final class SumiNavigationClosingTrackingWebView: WKWebView {
    private(set) var closeScriptEvaluations = 0

    override func evaluateJavaScript(
        _ javaScriptString: String,
        completionHandler: (@MainActor @Sendable (Any?, (any Error)?) -> Void)? = nil
    ) {
        if javaScriptString == "window.close()" {
            closeScriptEvaluations += 1
            completionHandler?(nil, nil)
            return
        }

        super.evaluateJavaScript(javaScriptString, completionHandler: completionHandler)
    }
}

final class SumiNavigationURLReportingWebView: WKWebView {
    var reportedURL: URL?

    override var url: URL? {
        reportedURL
    }
}

@MainActor
final class RecordingTabLifecycleNavigationRuntime {
    var authDisposition: SumiAuthChallengeDisposition? = .next
    var isPreparingForDestructiveCleanup = false
    private(set) var resetRevisitProtectionTabIds: [UUID] = []
    private(set) var preparedExtensionWebViewIds: [ObjectIdentifier] = []
    private(set) var preparedExtensionURLs: [URL] = []
    private(set) var preparedExtensionReasons: [String] = []
    private(set) var beforeCommitTabIds: [UUID] = []
    private(set) var beforeCommitURLs: [URL] = []
    private(set) var markedEligibleTabIds: [UUID] = []
    private(set) var zoomTabIds: [UUID] = []
    private(set) var adblockWebViewIds: [ObjectIdentifier] = []
    private(set) var adblockURLs: [URL] = []
    private(set) var siteDataPolicyTabIds: [UUID] = []
    private(set) var authChallengeHosts: [String] = []
    private(set) var authTabIds: [UUID] = []
    private(set) var cleanupCheckWebViewIds: [ObjectIdentifier] = []
    private(set) var finishedCleanupWebViewIds: [ObjectIdentifier] = []

    var runtime: TabLifecycleNavigationRuntime {
        TabLifecycleNavigationRuntime(
            resetRevisitProtection: { [weak self] tab in
                self?.resetRevisitProtectionTabIds.append(tab.id)
            },
            prepareExtensionWebView: { [weak self] webView, url, reason in
                self?.preparedExtensionWebViewIds.append(ObjectIdentifier(webView))
                self?.preparedExtensionURLs.append(url)
                self?.preparedExtensionReasons.append(reason)
            },
            prepareExtensionRuntimeBeforeCommit: { [weak self] tab, url, _ in
                self?.beforeCommitTabIds.append(tab.id)
                self?.beforeCommitURLs.append(url)
            },
            markExtensionEligibleAfterCommit: { [weak self] tab, _ in
                self?.markedEligibleTabIds.append(tab.id)
            },
            loadZoomForTab: { [weak self] tabId, _ in
                self?.zoomTabIds.append(tabId)
            },
            applyAdblockZapperRulesAfterNavigation: { [weak self] webView, url, _ in
                self?.adblockWebViewIds.append(ObjectIdentifier(webView))
                self?.adblockURLs.append(url)
            },
            enforceSiteDataPolicyAfterNavigation: { [weak self] tab in
                self?.siteDataPolicyTabIds.append(tab.id)
            },
            resolveAuthenticationChallenge: { [weak self] challenge, tab in
                guard let self else { return .next }
                authChallengeHosts.append(challenge.protectionSpace.host)
                authTabIds.append(tab.id)
                return authDisposition
            },
            destructiveDataCleanupNavigationWillStart: { _, _, _, _, _ in },
            isPreparingForDataCleanupNavigation: { [weak self] webView, _, _ in
                self?.cleanupCheckWebViewIds.append(ObjectIdentifier(webView))
                return self?.isPreparingForDestructiveCleanup == true
            },
            finishDestructiveDataCleanupNavigation: { [weak self] webView, _, _, _ in
                self?.finishedCleanupWebViewIds.append(ObjectIdentifier(webView))
            },
            handleDestructiveDataCleanupProcessTermination: { _ in false }
        )
    }
}

@MainActor
final class NavigationRecordingTabExtensionPropertiesRuntime {
    private(set) var tabIds: [UUID] = []
    private(set) var properties: [WKWebExtension.TabChangedProperties] = []

    var runtime: TabExtensionPropertiesRuntime {
        TabExtensionPropertiesRuntime(
            notifyTabPropertiesChanged: { [weak self] tab, properties in
                self?.tabIds.append(tab.id)
                self?.properties.append(properties)
            }
        )
    }
}

final class WeakTestReference<Value: AnyObject> {
    weak var value: Value?

    init(_ value: Value?) {
        self.value = value
    }
}

@MainActor
final class SumiNativeContextMenuProbe: NSObject {
    var onAction: (() -> Void)?

    @objc func performAction(_: Any?) {
        onAction?()
    }
}

final class SumiWKNavigationActionMock: NSObject {
    @objc var sourceFrame: WKFrameInfo?
    @objc var targetFrame: WKFrameInfo?
    @objc var navigationType: WKNavigationType
    @objc var request: URLRequest
    @objc var shouldPerformDownload = false
    @objc var modifierFlags: NSEvent.ModifierFlags = []
    @objc var buttonNumber = 0
    @objc var isUserInitiated = false
    @objc var mainFrameNavigation: Any?

    init(
        sourceFrame: WKFrameInfo?,
        targetFrame: WKFrameInfo?,
        navigationType: WKNavigationType,
        request: URLRequest
    ) {
        self.sourceFrame = sourceFrame
        self.targetFrame = targetFrame
        self.navigationType = navigationType
        self.request = request
    }

    var navigationAction: WKNavigationAction {
        withUnsafePointer(to: self) {
            $0.withMemoryRebound(to: WKNavigationAction.self, capacity: 1) { $0 }
        }.pointee
    }
}

final class SumiWKFrameInfoMock: NSObject {
    @objc var isMainFrame: Bool
    @objc var request: URLRequest?
    @objc var securityOrigin: WKSecurityOrigin
    @objc weak var webView: WKWebView?

    init(
        isMainFrame: Bool,
        request: URLRequest?,
        securityOrigin: WKSecurityOrigin,
        webView: WKWebView?
    ) {
        self.isMainFrame = isMainFrame
        self.request = request
        self.securityOrigin = securityOrigin
        self.webView = webView
    }

    var frameInfo: WKFrameInfo {
        withUnsafePointer(to: self) {
            $0.withMemoryRebound(to: WKFrameInfo.self, capacity: 1) { $0 }
        }.pointee
    }
}

@objc
final class SumiWKSecurityOriginMock: WKSecurityOrigin {
    private var mockedProtocol = ""
    private var mockedHost = ""
    private var mockedPort = 0

    override var `protocol`: String { mockedProtocol }
    override var host: String { mockedHost }
    override var port: Int { mockedPort }

    private func setURL(_ url: URL) {
        mockedProtocol = url.scheme ?? ""
        mockedHost = url.host ?? ""
        mockedPort = url.port ?? 0
    }

    static func new(url: URL) -> SumiWKSecurityOriginMock {
        let mock = perform(NSSelectorFromString("alloc"))
            .takeUnretainedValue() as! SumiWKSecurityOriginMock
        mock.setURL(url)
        return mock
    }
}

@MainActor
final class ActionPolicyProbeResponder: NavigationResponder {
    private let name: String
    private let decision: NavigationActionPolicy?
    private let mutatePreferences: ((inout NavigationPreferences) -> Void)?
    private(set) var callCount = 0
    private(set) var observedActions: [NavigationAction] = []
    private(set) var observedPreferences: [NavigationPreferences] = []

    init(
        name: String,
        decision: NavigationActionPolicy?,
        mutatePreferences: ((inout NavigationPreferences) -> Void)? = nil
    ) {
        self.name = name
        self.decision = decision
        self.mutatePreferences = mutatePreferences
    }

    func decidePolicy(
        for navigationAction: NavigationAction,
        preferences: inout NavigationPreferences
    ) async -> NavigationActionPolicy? {
        callCount += 1
        observedActions.append(navigationAction)
        observedPreferences.append(preferences)
        mutatePreferences?(&preferences)
        return decision
    }
}

@MainActor
final class ResponsePolicyProbeResponder: NavigationResponder {
    private let name: String
    private let decision: NavigationResponsePolicy?
    private(set) var callCount = 0
    private(set) var observedResponses: [NavigationResponse] = []

    init(name: String, decision: NavigationResponsePolicy?) {
        self.name = name
        self.decision = decision
    }

    func decidePolicy(for navigationResponse: NavigationResponse) async -> NavigationResponsePolicy? {
        callCount += 1
        observedResponses.append(navigationResponse)
        return decision
    }
}

@MainActor
final class SumiNavigationAdapterOrderRecorder {
    private var events: [String] = []

    func append(_ event: String) async {
        events.append(event)
    }

    func snapshot() -> [String] {
        events
    }

    func appendSync(_ event: String) {
        events.append(event)
    }

    func removeAll() {
        events.removeAll()
    }
}

@MainActor
final class SumiScriptAttachmentTimingProbeResponder: SumiNavigationActionResponding {
    private let scriptsProvider: SumiNormalTabUserScripts
    private(set) var observedScriptRevisions: [Int] = []

    init(scriptsProvider: SumiNormalTabUserScripts) {
        self.scriptsProvider = scriptsProvider
    }

    func decidePolicy(
        for _: SumiNavigationAction,
        preferences _: inout SumiNavigationPreferences
    ) async -> SumiNavigationActionPolicy? {
        observedScriptRevisions.append(scriptsProvider.scriptsRevision)
        return .allow
    }
}

@MainActor
final class SumiNavigationAdapterProbeResponder: SumiNavigationActionResponding, SumiNavigationResponseResponding {
    private let name: String
    private let actionDecision: SumiNavigationActionPolicy?
    private let responseDecision: SumiNavigationResponsePolicy?
    private let recorder: SumiNavigationAdapterOrderRecorder?
    private let mutatePreferences: ((inout SumiNavigationPreferences) -> Void)?
    private(set) var actionCallCount = 0
    private(set) var responseCallCount = 0
    private(set) var observedActions: [SumiNavigationAction] = []
    private(set) var observedResponses: [SumiNavigationResponse] = []
    private(set) var observedPreferences: [SumiNavigationPreferences] = []

    init(
        name: String,
        actionDecision: SumiNavigationActionPolicy? = nil,
        responseDecision: SumiNavigationResponsePolicy? = nil,
        recorder: SumiNavigationAdapterOrderRecorder? = nil,
        mutatePreferences: ((inout SumiNavigationPreferences) -> Void)? = nil
    ) {
        self.name = name
        self.actionDecision = actionDecision
        self.responseDecision = responseDecision
        self.recorder = recorder
        self.mutatePreferences = mutatePreferences
    }

    init(
        name: String,
        actionDecision: SumiNavigationActionPolicy?,
        mutatePreferences: @escaping (inout SumiNavigationPreferences) -> Void
    ) {
        self.name = name
        self.actionDecision = actionDecision
        self.responseDecision = nil
        self.recorder = nil
        self.mutatePreferences = mutatePreferences
    }

    func decidePolicy(
        for navigationAction: SumiNavigationAction,
        preferences: inout SumiNavigationPreferences
    ) async -> SumiNavigationActionPolicy? {
        actionCallCount += 1
        observedActions.append(navigationAction)
        observedPreferences.append(preferences)
        await recorder?.append(name)
        mutatePreferences?(&preferences)
        return actionDecision
    }

    func decidePolicy(for navigationResponse: SumiNavigationResponse) async -> SumiNavigationResponsePolicy? {
        responseCallCount += 1
        observedResponses.append(navigationResponse)
        await recorder?.append(name)
        return responseDecision
    }
}

@MainActor
final class SumiNavigationAuthProbeResponder: SumiNavigationAuthChallengeResponding {
    private let decision: SumiAuthChallengeDisposition?
    private(set) var callCount = 0
    private(set) var observedProtectionSpaceHosts: [String] = []
    private(set) var observedContexts: [SumiNavigationContext?] = []

    init(decision: SumiAuthChallengeDisposition?) {
        self.decision = decision
    }

    func didReceive(_ authenticationChallenge: URLAuthenticationChallenge) async -> SumiAuthChallengeDisposition? {
        await didReceive(authenticationChallenge, context: nil)
    }

    func didReceive(
        _ authenticationChallenge: URLAuthenticationChallenge,
        context: SumiNavigationContext?
    ) async -> SumiAuthChallengeDisposition? {
        callCount += 1
        observedProtectionSpaceHosts.append(authenticationChallenge.protectionSpace.host)
        observedContexts.append(context)
        return decision
    }
}

@MainActor
final class SumiSameDocumentNavigationProbeResponder: SumiSameDocumentNavigationResponding {
    private let name: String?
    private let recorder: SumiNavigationAdapterOrderRecorder?
    private(set) var observedTypes: [SumiSameDocumentNavigationType] = []

    init(name: String? = nil, recorder: SumiNavigationAdapterOrderRecorder? = nil) {
        self.name = name
        self.recorder = recorder
    }

    func navigationDidSameDocumentNavigation(type: SumiSameDocumentNavigationType) {
        navigationDidSameDocumentNavigation(type: type, context: nil)
    }

    func navigationDidSameDocumentNavigation(
        type: SumiSameDocumentNavigationType,
        context _: SumiNavigationContext?
    ) {
        observedTypes.append(type)
        if let name {
            recorder?.appendSync("\(name).sameDocument.\(type)")
        }
    }
}

@MainActor
final class SumiNavigationStartProbeResponder: SumiNavigationStartResponding {
    private let name: String?
    private let recorder: SumiNavigationAdapterOrderRecorder?
    private(set) var startCallCount = 0
    private(set) var willStartContexts: [SumiNavigationContext] = []
    private(set) var startContexts: [SumiNavigationContext] = []

    init(name: String? = nil, recorder: SumiNavigationAdapterOrderRecorder? = nil) {
        self.name = name
        self.recorder = recorder
    }

    func navigationWillStart(_ context: SumiNavigationContext) {
        willStartContexts.append(context)
        if let name {
            recorder?.appendSync("\(name).willStart")
        }
    }

    func navigationDidStart() {
        startCallCount += 1
        if let name {
            recorder?.appendSync("\(name).start")
        }
    }

    func navigationDidStart(_ context: SumiNavigationContext) {
        startCallCount += 1
        startContexts.append(context)
        if let name {
            recorder?.appendSync("\(name).start")
        }
    }
}

@MainActor
final class SumiNavigationCompletionProbeResponder: SumiNavigationCompletionResponding {
    private let name: String
    private let recorder: SumiNavigationAdapterOrderRecorder
    private(set) var finishContexts: [SumiNavigationContext] = []
    private(set) var failContexts: [SumiNavigationContext] = []
    private(set) var failErrors: [WKError] = []

    init(name: String, recorder: SumiNavigationAdapterOrderRecorder) {
        self.name = name
        self.recorder = recorder
    }

    func navigationDidFinish() {
        recorder.appendSync("\(name).finish")
    }

    func navigationDidFinish(_ context: SumiNavigationContext?) {
        if let context {
            finishContexts.append(context)
        }
        recorder.appendSync("\(name).finish")
    }

    func navigationDidFail() {
        recorder.appendSync("\(name).fail")
    }

    func navigationDidFail(_ error: WKError, context: SumiNavigationContext?) {
        if let context {
            failContexts.append(context)
        }
        failErrors.append(error)
        recorder.appendSync("\(name).fail")
    }
}

@MainActor
final class SumiNavigationLifecycleContextProbeResponder:
    SumiNavigationStartResponding,
    SumiNavigationCommitResponding,
    SumiNavigationCompletionResponding,
    SumiSameDocumentNavigationResponding {
    private(set) var events: [String] = []
    private(set) var contexts: [SumiNavigationContext] = []
    private(set) var failErrors: [WKError] = []

    func navigationWillStart(_ context: SumiNavigationContext) {
        events.append("willStart")
        contexts.append(context)
    }

    func navigationDidStart() { /* no-op */ }

    func navigationDidStart(_ context: SumiNavigationContext) {
        events.append("didStart")
        contexts.append(context)
    }

    func navigationDidCommit(_ context: SumiNavigationContext) {
        events.append("didCommit")
        contexts.append(context)
    }

    func navigationDidFinish() { /* no-op */ }

    func navigationDidFinish(_ context: SumiNavigationContext?) {
        events.append("finish")
        if let context {
            contexts.append(context)
        }
    }

    func navigationDidFail() { /* no-op */ }

    func navigationDidFail(_ error: WKError, context: SumiNavigationContext?) {
        events.append("fail")
        failErrors.append(error)
        if let context {
            contexts.append(context)
        }
    }

    func navigationDidSameDocumentNavigation(type _: SumiSameDocumentNavigationType) { /* no-op */ }

    func navigationDidSameDocumentNavigation(
        type: SumiSameDocumentNavigationType,
        context: SumiNavigationContext?
    ) {
        events.append("sameDocument.\(type)")
        if let context {
            contexts.append(context)
        }
    }
}

@MainActor
final class SumiNavigationDownloadProbeResponder: SumiNavigationDownloadResponding {
    private(set) var actionDownloads: [(action: SumiNavigationAction, download: SumiNavigationDownload)] = []
    private(set) var responseDownloads: [(response: SumiNavigationResponse, download: SumiNavigationDownload)] = []

    func navigationAction(_ navigationAction: SumiNavigationAction, didBecome download: SumiNavigationDownload) {
        actionDownloads.append((navigationAction, download))
    }

    func navigationResponse(_ navigationResponse: SumiNavigationResponse, didBecome download: SumiNavigationDownload) {
        responseDownloads.append((navigationResponse, download))
    }
}

@MainActor
final class SumiWebKitDownloadMock: NSObject, WebKitDownload {
    let originalRequest: URLRequest?
    let originatingWebView: WKWebView?
    let targetWebView: WKWebView?
    weak var delegate: WKDownloadDelegate?
    private(set) var cancelCount = 0

    init(
        originalRequest: URLRequest?,
        originatingWebView: WKWebView? = nil,
        targetWebView: WKWebView? = nil
    ) {
        self.originalRequest = originalRequest
        self.originatingWebView = originatingWebView
        self.targetWebView = targetWebView
    }

    func cancel(_ completionHandler: (@MainActor @Sendable (Data?) -> Void)?) {
        cancelCount += 1
        completionHandler?(nil)
    }
}

final class SumiURLAuthenticationChallengeSenderMock: NSObject, URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {
        _ = credential
        _ = challenge
    }

    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {
        _ = challenge
    }

    func cancel(_ challenge: URLAuthenticationChallenge) {
        _ = challenge
    }

    func performDefaultHandling(for challenge: URLAuthenticationChallenge) {
        _ = challenge
    }

    func rejectProtectionSpaceAndContinue(with challenge: URLAuthenticationChallenge) {
        _ = challenge
    }
}

@MainActor
final class CountingNavigationDelegateProxy: NSObject, WKNavigationDelegate {
    let distributedNavigationDelegate = DistributedNavigationDelegate()
    var onActionDecision: ((WKNavigationActionPolicy) -> Void)?
    private(set) var actionDecisionCount = 0

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
    ) {
        distributedNavigationDelegate.webView(webView, decidePolicyFor: navigationAction, preferences: preferences) { [weak self] policy, preferences in
            self?.actionDecisionCount += 1
            self?.onActionDecision?(policy)
            decisionHandler(policy, preferences)
        }
    }
}

@MainActor
final class ImmediatePolicyResponder: NavigationResponder {
    private let policy: NavigationActionPolicy
    private(set) var policyCallCount = 0

    init(policy: NavigationActionPolicy) {
        self.policy = policy
    }

    func decidePolicy(
        for _: NavigationAction,
        preferences _: inout NavigationPreferences
    ) async -> NavigationActionPolicy? {
        policyCallCount += 1
        return policy
    }
}

@MainActor
final class SlowLifecycleProbeResponder: NavigationResponder {
    var onWillStart: (() -> Void)?
    private(set) var policyCallCount = 0

    func decidePolicy(
        for _: NavigationAction,
        preferences _: inout NavigationPreferences
    ) async -> NavigationActionPolicy? {
        policyCallCount += 1
        return .allow
    }

    func willStart(_: Navigation) {
        onWillStart?()
    }
}

final class FailingSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "suminavtest"

    func webView(_: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        urlSchemeTask.didFailWithError(NSError(domain: "SumiNavigationResponderTests", code: 1))
    }

    func webView(_: WKWebView, stop _: WKURLSchemeTask) { /* no-op */ }
}

final class SumiNavigationTestUserScript: NSObject, SumiUserScript {
    let source: String
    let injectionTime: WKUserScriptInjectionTime = .atDocumentStart
    let forMainFrameOnly = true
    let requiresRunInPageContentWorld = false
    let messageNames: [String] = []

    init(source: String) {
        self.source = source
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        _ = userContentController
        _ = message
    }
}

@MainActor
final class NavigationExternalSchemeFakeResolver: SumiExternalAppResolving {
    private let handlerSchemes: Set<String>
    private(set) var openedURLs: [URL] = []

    init(handlerSchemes: Set<String>) {
        self.handlerSchemes = Set(handlerSchemes.map(SumiPermissionType.normalizedExternalScheme))
    }

    func appInfo(for url: URL) -> SumiExternalAppInfo? {
        let scheme = SumiExternalSchemePermissionRequest.normalizedScheme(for: url)
        guard handlerSchemes.contains(scheme) else { return nil }
        return SumiExternalAppInfo(
            appDisplayName: "External App"
        )
    }

    func open(_ url: URL) -> Bool {
        openedURLs.append(url)
        return true
    }
}

actor NavigationExternalSchemeFakeCoordinator: SumiPermissionCoordinating {
    private let decision: SumiPermissionCoordinatorDecision

    init(decision: SumiPermissionCoordinatorDecision) {
        self.decision = decision
    }

    func requestPermission(_: SumiPermissionSecurityContext) async -> SumiPermissionCoordinatorDecision {
        decision
    }

    func queryPermissionState(_: SumiPermissionSecurityContext) async -> SumiPermissionCoordinatorDecision {
        decision
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
        navigationExternalCoordinatorDecision(.cancelled, reason: reason)
    }

    @discardableResult
    func cancel(pageId _: String, reason: String) -> SumiPermissionCoordinatorDecision {
        navigationExternalCoordinatorDecision(.cancelled, reason: reason)
    }

    @discardableResult
    func cancelNavigation(pageId _: String, reason: String) -> SumiPermissionCoordinatorDecision {
        navigationExternalCoordinatorDecision(.cancelled, reason: reason)
    }

    @discardableResult
    func cancelTab(tabId _: String, reason: String) -> SumiPermissionCoordinatorDecision {
        navigationExternalCoordinatorDecision(.cancelled, reason: reason)
    }
}

actor NavigationExternalSchemeRecordingCoordinator: SumiPermissionCoordinating {
    private var contexts: [SumiPermissionSecurityContext] = []

    func requestPermission(_ context: SumiPermissionSecurityContext) async -> SumiPermissionCoordinatorDecision {
        contexts.append(context)
        return navigationExternalCoordinatorDecision(.promptRequired, reason: "recorded")
    }

    func queryPermissionState(_ context: SumiPermissionSecurityContext) async -> SumiPermissionCoordinatorDecision {
        contexts.append(context)
        return navigationExternalCoordinatorDecision(.promptRequired, reason: "recorded")
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
        navigationExternalCoordinatorDecision(.cancelled, reason: reason)
    }

    @discardableResult
    func cancel(pageId _: String, reason: String) -> SumiPermissionCoordinatorDecision {
        navigationExternalCoordinatorDecision(.cancelled, reason: reason)
    }

    @discardableResult
    func cancelNavigation(pageId _: String, reason: String) -> SumiPermissionCoordinatorDecision {
        navigationExternalCoordinatorDecision(.cancelled, reason: reason)
    }

    @discardableResult
    func cancelTab(tabId _: String, reason: String) -> SumiPermissionCoordinatorDecision {
        navigationExternalCoordinatorDecision(.cancelled, reason: reason)
    }

    func recordedContexts() -> [SumiPermissionSecurityContext] {
        contexts
    }
}

func navigationExternalTabContext() -> SumiExternalSchemePermissionTabContext {
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

func navigationExternalCoordinatorDecision(
    _ outcome: SumiPermissionCoordinatorOutcome,
    reason: String
) -> SumiPermissionCoordinatorDecision {
    let state: SumiPermissionState? = {
        switch outcome {
        case .granted:
            return .allow
        case .denied:
            return .deny
        case .promptRequired:
            return .ask
        default:
            return nil
        }
    }()
    return SumiPermissionCoordinatorDecision(
        outcome: outcome,
        state: state,
        persistence: outcome == .granted || outcome == .denied ? .persistent : nil,
        source: outcome == .granted || outcome == .denied ? .user : .defaultSetting,
        reason: reason,
        permissionTypes: [.externalScheme("mailto")],
        keys: [
            SumiPermissionKey(
                requestingOrigin: SumiPermissionOrigin(string: "https://request.example"),
                topOrigin: SumiPermissionOrigin(string: "https://top.example"),
                permissionType: .externalScheme("mailto"),
                profilePartitionId: "profile-a",
                transientPageId: "tab-a:1"
            ),
        ]
    )
}
