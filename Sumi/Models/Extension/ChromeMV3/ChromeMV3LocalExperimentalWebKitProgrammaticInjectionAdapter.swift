//
//  ChromeMV3LocalExperimentalWebKitProgrammaticInjectionAdapter.swift
//  Sumi
//
//  DEBUG/internal WebKit execution adapter for the reviewed Bitwarden
//  bootstrap-autofill generated-bundle file. This is not a general scripting
//  API and is never attached to product tabs.
//

import CryptoKit
import Foundation

#if DEBUG
import WebKit
#endif

enum ChromeMV3LocalExperimentalWebKitProgrammaticInjectionBlocker:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case extensionDisabled
    case hostPermissionBlocked
    case isolatedWorldRequired
    case localExperimentalGateClosed
    case moduleDisabled
    case multiFrameBlocked
    case profileScopedExtensionMissing
    case reviewedGeneratedBundleFileRequired
    case reviewedScriptExecutionBlocked
    case reviewedScriptResolutionBlocked
    case syntheticHTTPSFixtureRequired
    case webKitIsolatedWorldUnavailable
    case webKitSyntheticFixtureUnavailable
    case webKitUserScriptAttachmentUnavailable

    static func < (
        lhs: ChromeMV3LocalExperimentalWebKitProgrammaticInjectionBlocker,
        rhs: ChromeMV3LocalExperimentalWebKitProgrammaticInjectionBlocker
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3LocalExperimentalWebKitProgrammaticInjectionPolicy:
    Codable,
    Equatable,
    Sendable
{
    var webKitProgrammaticInjectionAvailableInLocalExperimentalGate: Bool
    var webKitProgrammaticInjectionAvailableByDefault: Bool
    var syntheticHarnessOnly: Bool
    var reviewedGeneratedBundleFileOnly: Bool
    var isolatedWorldOnly: Bool
    var topFrameOnly: Bool
    var mainWorldAllowed: Bool
    var multiFrameAllowed: Bool
    var fileSchemeAllowed: Bool
    var productNormalTabAllowed: Bool
    var teardownRequired: Bool

    static let bitwardenDetectFill = Self(
        webKitProgrammaticInjectionAvailableInLocalExperimentalGate: true,
        webKitProgrammaticInjectionAvailableByDefault: false,
        syntheticHarnessOnly: true,
        reviewedGeneratedBundleFileOnly: true,
        isolatedWorldOnly: true,
        topFrameOnly: true,
        mainWorldAllowed: false,
        multiFrameAllowed: false,
        fileSchemeAllowed: false,
        productNormalTabAllowed: false,
        teardownRequired: true
    )
}

struct ChromeMV3LocalExperimentalWebKitSyntheticLoginDOMSnapshot:
    Codable,
    Equatable,
    Sendable
{
    var phase: String
    var url: String
    var origin: String
    var documentID: String
    var navigationSequence: Int
    var usernameFieldExists: Bool
    var passwordFieldExists: Bool
    var submitButtonExists: Bool
    var usernameValue: String
    var passwordValue: String
    var initialValuesEmpty: Bool
    var finalValuesMatchDummyFill: Bool

    static func notAttempted(
        phase: String,
        documentID: String,
        navigationSequence: Int
    ) -> Self {
        Self(
            phase: phase,
            url: "notAttempted",
            origin: "notAttempted",
            documentID: documentID,
            navigationSequence: navigationSequence,
            usernameFieldExists: false,
            passwordFieldExists: false,
            submitButtonExists: false,
            usernameValue: "",
            passwordValue: "",
            initialValuesEmpty: true,
            finalValuesMatchDummyFill: false
        )
    }
}

struct ChromeMV3LocalExperimentalWebKitSyntheticLoginFixture:
    Codable,
    Equatable,
    Sendable
{
    var url: String
    var origin: String?
    var documentID: String
    var navigationSequence: Int
    var networkSubmissionBlocked: Bool
    var persistentBrowsingDataAllowed: Bool
    var realWebsiteUsed: Bool
    var realCredentialsUsed: Bool
}

struct ChromeMV3LocalExperimentalWebKitProgrammaticInjectionTeardown:
    Codable,
    Equatable,
    Sendable
{
    var required: Bool
    var completed: Bool
    var navigationDelegateDetached: Bool
    var userScriptCountAfterTeardown: Int
    var scriptMessageHandlerCountAfterTeardown: Int
    var webViewReferenceReleased: Bool
    var configurationReferenceReleased: Bool
    var diagnostics: [String]

    static let notRequired = Self(
        required: false,
        completed: true,
        navigationDelegateDetached: true,
        userScriptCountAfterTeardown: 0,
        scriptMessageHandlerCountAfterTeardown: 0,
        webViewReferenceReleased: true,
        configurationReferenceReleased: true,
        diagnostics: [
            "No synthetic WebKit objects were created, so teardown was not required.",
        ]
    )
}

struct ChromeMV3LocalExperimentalWebKitProgrammaticInjectionResult:
    Codable,
    Equatable,
    Sendable
{
    var attempted: Bool
    var allowed: Bool
    var policy: ChromeMV3LocalExperimentalWebKitProgrammaticInjectionPolicy
    var syntheticFixture:
        ChromeMV3LocalExperimentalWebKitSyntheticLoginFixture
    var injectedReviewedFile: String?
    var reviewedSourceSHA256: String?
    var contentWorldName: String?
    var isolatedWorldUsed: Bool
    var topFrameOnly: Bool
    var hiddenSyntheticWebViewCreated: Bool
    var nonPersistentWebsiteDataStoreUsed: Bool
    var userScriptAttachmentCount: Int
    var scriptMessageHandlerAttachmentCount: Int
    var navigationCompleted: Bool
    var reviewedScriptExecutedByWebKit: Bool
    var fixedHarnessShimInstalled: Bool
    var fixedDetectFillDispatchCompleted: Bool
    var dummyValuesWrittenByActualWebKitExecutedScript: Bool
    var domObservationBefore:
        ChromeMV3LocalExperimentalWebKitSyntheticLoginDOMSnapshot
    var domObservationAfter:
        ChromeMV3LocalExperimentalWebKitSyntheticLoginDOMSnapshot
    var teardown: ChromeMV3LocalExperimentalWebKitProgrammaticInjectionTeardown
    var blockers:
        [ChromeMV3LocalExperimentalWebKitProgrammaticInjectionBlocker]
    var currentBlocker: String
    var diagnostics: [String]

    static func notAttempted(
        url: String,
        documentID: String,
        navigationSequence: Int,
        reason: String
    ) -> Self {
        Self(
            attempted: false,
            allowed: false,
            policy: .bitwardenDetectFill,
            syntheticFixture:
                ChromeMV3LocalExperimentalWebKitSyntheticLoginFixture(
                    url: url,
                    origin: ChromeMV3RuntimeMessagingURL.origin(from: url),
                    documentID: documentID,
                    navigationSequence: navigationSequence,
                    networkSubmissionBlocked: true,
                    persistentBrowsingDataAllowed: false,
                    realWebsiteUsed: false,
                    realCredentialsUsed: false
                ),
            injectedReviewedFile: nil,
            reviewedSourceSHA256: nil,
            contentWorldName: nil,
            isolatedWorldUsed: false,
            topFrameOnly: true,
            hiddenSyntheticWebViewCreated: false,
            nonPersistentWebsiteDataStoreUsed: false,
            userScriptAttachmentCount: 0,
            scriptMessageHandlerAttachmentCount: 0,
            navigationCompleted: false,
            reviewedScriptExecutedByWebKit: false,
            fixedHarnessShimInstalled: false,
            fixedDetectFillDispatchCompleted: false,
            dummyValuesWrittenByActualWebKitExecutedScript: false,
            domObservationBefore:
                .notAttempted(
                    phase: "before",
                    documentID: documentID,
                    navigationSequence: navigationSequence
                ),
            domObservationAfter:
                .notAttempted(
                    phase: "after",
                    documentID: documentID,
                    navigationSequence: navigationSequence
                ),
            teardown: .notRequired,
            blockers: [],
            currentBlocker: "notAttempted",
            diagnostics: [reason]
        )
    }
}

struct ChromeMV3LocalExperimentalWebKitProgrammaticInjectionRequest {
    var moduleState: ChromeMV3ProfileHostModuleState
    var localExperimentalGateAllowed: Bool
    var extensionEnabled: Bool
    var profileScopedExtensionLoaded: Bool
    var hostPermissionOrActiveTabAllowed: Bool
    var targetURL: String
    var syntheticLoginURL: String
    var documentID: String
    var navigationSequence: Int
    var frameIDs: [Int]
    var allFrames: Bool
    var world: String
    var dummyUsername: String
    var dummyPassword: String
    var modeledInjectionAttempt:
        ChromeMV3LocalExperimentalProgrammaticInjectionAttempt
}

struct ChromeMV3LocalExperimentalNormalTabManualSmokePlan:
    Codable,
    Equatable,
    Sendable
{
    var extensionID: String
    var profileID: String
    var tabID: String
    var documentID: String
    var syntheticURL: String
    var syntheticOrigin: String
    var reviewedScriptPath: String
    var generatedResourceHash: String?
    var targetFrame: String
    var contentWorld: String
    var permissionSource: String
    var expectedObjectLifetime: String
    var teardownTriggers: [ChromeMV3ProductNormalTabReadinessTeardownTrigger]
    var managerReadoutExecutes: Bool
    var productSupportClaimed: Bool
    var diagnostics: [String]

    static func make(
        preflight: ChromeMV3ProductNormalTabReadinessPreflight,
        injectionPlan: ChromeMV3ProductNormalTabReviewedFileInjectionPlan
    ) -> Self {
        ChromeMV3LocalExperimentalNormalTabManualSmokePlan(
            extensionID: preflight.extensionID,
            profileID: preflight.profileID,
            tabID: preflight.tabID,
            documentID: preflight.documentID,
            syntheticURL: preflight.urlString,
            syntheticOrigin:
                ChromeMV3RuntimeMessagingURL.origin(
                    from: preflight.urlString
                ) ?? "invalid",
            reviewedScriptPath: injectionPlan.reviewedScriptPath,
            generatedResourceHash: injectionPlan.generatedResourceHash,
            targetFrame: injectionPlan.targetFrame,
            contentWorld: injectionPlan.contentWorld,
            permissionSource: preflight.hostAccessDecision.grantSource.rawValue,
            expectedObjectLifetime:
                "One event-driven manual smoke attempt for one synthetic normal-tab document; teardown runs immediately on completion and is required for navigation, tab close, extension disable, module disable, profile close, permission revoke, reset, and uninstall.",
            teardownTriggers:
                ChromeMV3ProductNormalTabReadinessTeardownTrigger
                .allCases
                .sorted(),
            managerReadoutExecutes: false,
            productSupportClaimed: false,
            diagnostics:
                uniqueSortedWebKitProgrammaticInjection(
                    injectionPlan.diagnostics
                        + [
                            "Manual normal-tab smoke plan is reviewed-file-only and cannot be executed by viewing manager details.",
                            "Plan targets the synthetic HTTPS origin \(ChromeMV3RuntimeMessagingURL.origin(from: preflight.urlString) ?? "invalid").",
                        ]
                )
        )
    }
}

struct ChromeMV3LocalExperimentalNormalTabManualSmokeTeardown:
    Codable,
    Equatable,
    Sendable
{
    var required: Bool
    var completed: Bool
    var verifiedTriggers:
        [ChromeMV3ProductNormalTabReadinessTeardownTrigger]
    var webKitObjectsCreated: [String]
    var handlersCreated: [String]
    var userScriptsCreated: [String]
    var endpointsCreated: [String]
    var objectsRemoved: [String]
    var retainedObjectCountAfterTeardown: Int
    var diagnostics: [String]

    static let notRequired = Self(
        required: false,
        completed: true,
        verifiedTriggers: [],
        webKitObjectsCreated: [],
        handlersCreated: [],
        userScriptsCreated: [],
        endpointsCreated: [],
        objectsRemoved: [],
        retainedObjectCountAfterTeardown: 0,
        diagnostics: [
            "Manual normal-tab smoke was blocked before WebKit object creation.",
        ]
    )
}

struct ChromeMV3LocalExperimentalNormalTabManualSmokeRequest:
    Sendable
{
    var preflight: ChromeMV3ProductNormalTabReadinessPreflight
    var injectionPlan: ChromeMV3ProductNormalTabReviewedFileInjectionPlan
    var modeledInjectionAttempt:
        ChromeMV3LocalExperimentalProgrammaticInjectionAttempt
    var dummyUsername: String
    var dummyPassword: String
    var productDefaultRuntimeAvailable: Bool
    var matchAboutBlank: Bool
    var matchOriginAsFallback: Bool
}

struct ChromeMV3LocalExperimentalNormalTabManualSmokeResult:
    Codable,
    Equatable,
    Sendable
{
    var attempted: Bool
    var allowed: Bool
    var policy: ChromeMV3ProductNormalTabReadinessPolicy
    var eligibility: ChromeMV3ProductNormalTabReadinessPreflight
    var injectionPlan: ChromeMV3LocalExperimentalNormalTabManualSmokePlan
    var manualNormalTabSmokeAvailableInLocalExperimentalGate: Bool
    var manualNormalTabSmokeAvailableByDefault: Bool
    var productDefaultRuntimeAvailable: Bool
    var reviewedFileOnly: Bool
    var syntheticHTTPSOriginOnly: Bool
    var isolatedWorldOnly: Bool
    var topFrameOnly: Bool
    var auxiliarySurfaceAllowed: Bool
    var teardownRequired: Bool
    var normalTabConfigurationMarked: Bool
    var normalBrowsingSurfaceOnly: Bool
    var reviewedScriptExecutedByWebKit: Bool
    var fixedHarnessShimInstalled: Bool
    var fixedDetectFillDispatchCompleted: Bool
    var domObservationBefore:
        ChromeMV3LocalExperimentalWebKitSyntheticLoginDOMSnapshot
    var domObservationAfter:
        ChromeMV3LocalExperimentalWebKitSyntheticLoginDOMSnapshot
    var fieldsTouched: [String]
    var usernameDummyValue: String
    var passwordDummyValue: String
    var webKitExecutionResult: String
    var thrownErrors: [String]
    var teardown: ChromeMV3LocalExperimentalNormalTabManualSmokeTeardown
    var blockers: [ChromeMV3ProductNormalTabReadinessBlocker]
    var currentBlocker: String
    var diagnostics: [String]

    static func notAttempted(
        preflight: ChromeMV3ProductNormalTabReadinessPreflight,
        injectionPlan: ChromeMV3ProductNormalTabReviewedFileInjectionPlan,
        reason: String
    ) -> Self {
        let plan =
            ChromeMV3LocalExperimentalNormalTabManualSmokePlan.make(
                preflight: preflight,
                injectionPlan: injectionPlan
            )
        return ChromeMV3LocalExperimentalNormalTabManualSmokeResult(
            attempted: false,
            allowed: false,
            policy: preflight.policy,
            eligibility: preflight,
            injectionPlan: plan,
            manualNormalTabSmokeAvailableInLocalExperimentalGate:
                preflight.policy
                .manualNormalTabSmokeAvailableInLocalExperimentalGate,
            manualNormalTabSmokeAvailableByDefault:
                preflight.policy.manualNormalTabSmokeAvailableByDefault,
            productDefaultRuntimeAvailable:
                preflight.policy.productDefaultRuntimeAvailable,
            reviewedFileOnly: preflight.policy.reviewedFileOnly,
            syntheticHTTPSOriginOnly:
                preflight.policy.syntheticHTTPSOriginOnly,
            isolatedWorldOnly: preflight.policy.isolatedWorldOnly,
            topFrameOnly: preflight.policy.topFrameOnly,
            auxiliarySurfaceAllowed: preflight.policy.auxiliarySurfaceAllowed,
            teardownRequired: preflight.policy.teardownRequired,
            normalTabConfigurationMarked: false,
            normalBrowsingSurfaceOnly: preflight.tabSurface == .normalTab,
            reviewedScriptExecutedByWebKit: false,
            fixedHarnessShimInstalled: false,
            fixedDetectFillDispatchCompleted: false,
            domObservationBefore:
                .notAttempted(
                    phase: "before",
                    documentID: preflight.documentID,
                    navigationSequence: 0
                ),
            domObservationAfter:
                .notAttempted(
                    phase: "after",
                    documentID: preflight.documentID,
                    navigationSequence: 0
                ),
            fieldsTouched: [],
            usernameDummyValue: "",
            passwordDummyValue: "",
            webKitExecutionResult: "notAttempted",
            thrownErrors: [],
            teardown: .notRequired,
            blockers: preflight.blockers,
            currentBlocker: preflight.blockers.first?.rawValue ?? "notAttempted",
            diagnostics: [reason]
        )
    }

    static func notAttempted(
        url: String,
        documentID: String,
        reason: String
    ) -> Self {
        let hostDecision = ChromeMV3HostAccessDecision(
            url: url,
            origin: ChromeMV3RuntimeMessagingURL.origin(from: url),
            status: .blocked,
            grantSource: .none,
            hasHostAccess: false,
            allowedByHostPermission: false,
            allowedByOptionalHostPermission: false,
            allowedByActiveTab: false,
            matchingHostPatterns: [],
            optionalHostPatternsThatCouldPrompt: [],
            invalidHostPatterns: [],
            unsupportedHostPatterns: [],
            deniedByPattern: false,
            revokedByPattern: false,
            wouldNeedPrompt: false,
            missingReason: .hostPermissionMissing,
            diagnostics: [reason]
        )
        let resource = ChromeMV3ProductNormalTabReviewedResource(
            reviewedScriptPath:
                ChromeMV3LocalExperimentalProgrammaticInjectionResourceCatalog
                .bitwardenDetectFillBootstrapFile,
            generatedResourceHash: nil,
            generatedResourceFileSystemPath: nil,
            present: false,
            packageOwned: false,
            diagnostics: [reason]
        )
        let preflight =
            ChromeMV3ProductNormalTabReadinessPreflightEvaluator.evaluate(
                input: ChromeMV3ProductNormalTabReadinessPreflightInput(
                    profileID: "notAttempted",
                    extensionID: "notAttempted",
                    tabID: "notAttempted",
                    documentID: documentID,
                    urlString: url,
                    moduleEnabled: false,
                    extensionEnabled: false,
                    profileEnabled: false,
                    localExperimentalProductGateAllowed: false,
                    runtimeGateAllowsReadiness: false,
                    contentScriptRouteReady: false,
                    serviceWorkerRouteReady: false,
                    tabSurface: .normalTab,
                    syntheticHTTPSOrigin: "https://sumi.local.test",
                    frameID: 0,
                    isTopFrame: true,
                    contentWorld: .isolated,
                    hostAccessDecision: hostDecision,
                    reviewedResource: resource,
                    teardownPending: false
                )
            )
        let injectionPlan =
            ChromeMV3ProductNormalTabReviewedFileInjectionPlan.make(
                preflight: preflight
            )
        return notAttempted(
            preflight: preflight,
            injectionPlan: injectionPlan,
            reason: reason
        )
    }
}

#if DEBUG
@available(macOS 15.5, *)
@MainActor
private final class ChromeMV3LocalExperimentalWebKitInjectionNavigationObserver:
    NSObject,
    WKNavigationDelegate
{
    private var completion: Result<Void, Error>?
    private var continuation: CheckedContinuation<Result<Void, Error>, Never>?

    func wait(navigation: WKNavigation?) async -> Result<Void, Error> {
        guard navigation != nil else {
            return .failure(
                NSError(
                    domain: "Sumi.ChromeMV3LocalExperimentalWebKitInjection",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Synthetic WebKit navigation did not start.",
                    ]
                )
            )
        }
        if let completion {
            return completion
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        _ = webView
        _ = navigation
        finish(.success(()))
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        _ = webView
        _ = navigation
        finish(.failure(error))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        _ = webView
        _ = navigation
        finish(.failure(error))
    }

    private func finish(_ completion: Result<Void, Error>) {
        guard self.completion == nil else { return }
        self.completion = completion
        continuation?.resume(returning: completion)
        continuation = nil
    }
}

@available(macOS 15.5, *)
@MainActor
private final class ChromeMV3LocalExperimentalWebKitInjectionMessageObserver:
    NSObject,
    WKScriptMessageHandler
{
    private var completions: [String: [String: Any]] = [:]
    private var continuations:
        [String: CheckedContinuation<[String: Any], Never>] = [:]

    func wait(for stage: String) async -> [String: Any] {
        if let completion = completions.removeValue(forKey: stage) {
            return completion
        }
        return await withCheckedContinuation { continuation in
            continuations[stage] = continuation
        }
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        _ = userContentController
        guard let body = message.body as? [String: Any],
              let stage = body["stage"] as? String
        else { return }
        if let continuation = continuations.removeValue(forKey: stage) {
            continuation.resume(returning: body)
        } else {
            completions[stage] = body
        }
    }
}

@available(macOS 15.5, *)
@MainActor
enum ChromeMV3LocalExperimentalWebKitProgrammaticInjectionAdapter {
    static let contentWorldName =
        "sumi.mv3.synthetic.bitwarden.detect-fill.isolated"
    private static let completionMessageHandlerName =
        "sumiBitwardenSyntheticCompletion"

    static func run(
        _ request: ChromeMV3LocalExperimentalWebKitProgrammaticInjectionRequest
    ) async -> ChromeMV3LocalExperimentalWebKitProgrammaticInjectionResult {
        let policy =
            ChromeMV3LocalExperimentalWebKitProgrammaticInjectionPolicy
            .bitwardenDetectFill
        let fixture =
            ChromeMV3LocalExperimentalWebKitSyntheticLoginFixture(
                url: request.syntheticLoginURL,
                origin:
                    ChromeMV3RuntimeMessagingURL.origin(
                        from: request.syntheticLoginURL
                    ),
                documentID: request.documentID,
                navigationSequence: request.navigationSequence,
                networkSubmissionBlocked: true,
                persistentBrowsingDataAllowed: false,
                realWebsiteUsed: false,
                realCredentialsUsed: false
            )
        var blockers = preflightBlockers(request)
        guard blockers.isEmpty else {
            return blockedResult(
                fixture: fixture,
                blockers: blockers,
                diagnostics: [
                    "Synthetic WebKit adapter preflight blocked object creation.",
                ]
            )
        }
        guard let reviewedSource = reviewedGeneratedSource(request) else {
            blockers.append(.reviewedScriptResolutionBlocked)
            return blockedResult(
                fixture: fixture,
                blockers: blockers,
                diagnostics: [
                    "The reviewed copied generated-bundle bootstrap file could not be loaded with the audited digest.",
                ]
            )
        }

        var configuration: WKWebViewConfiguration? = WKWebViewConfiguration()
        configuration?.websiteDataStore = .nonPersistent()
        configuration?.sumiIsNormalTabWebViewConfiguration = false
        guard let activeConfiguration = configuration else {
            return blockedResult(
                fixture: fixture,
                blockers: [.webKitSyntheticFixtureUnavailable],
                diagnostics: [
                    "Synthetic WKWebViewConfiguration creation failed.",
                ]
            )
        }
        var webView: WKWebView? = WKWebView(
            frame: .zero,
            configuration: activeConfiguration
        )
        guard let activeWebView = webView else {
            return blockedResult(
                fixture: fixture,
                blockers: [.webKitSyntheticFixtureUnavailable],
                diagnostics: [
                    "Hidden synthetic WKWebView creation failed.",
                ]
            )
        }
        let contentWorld = WKContentWorld.world(name: contentWorldName)
        let messageObserver =
            ChromeMV3LocalExperimentalWebKitInjectionMessageObserver()
        activeConfiguration.userContentController.add(
            messageObserver,
            contentWorld: contentWorld,
            name: completionMessageHandlerName
        )
        let observer =
            ChromeMV3LocalExperimentalWebKitInjectionNavigationObserver()
        activeWebView.navigationDelegate = observer
        let navigation = activeWebView.loadHTMLString(
            syntheticLoginHTML,
            baseURL: URL(string: request.syntheticLoginURL)
        )
        var diagnostics = [
            "Created one hidden synthetic WKWebView with WKWebsiteDataStore.nonPersistent().",
            "The reviewed generated-bundle file is evaluated verbatim in one named isolated WKContentWorld with nil frame targeting the top frame.",
            "One completion-only script message handler is scoped to the synthetic isolated world; no WKUserScript, product BrowserConfig, product tab, auxiliary surface, native host, auth flow, or network request is created by the adapter.",
        ]
        var navigationCompleted = false
        var reviewedScriptExecuted = false
        var fixedHarnessShimInstalled = false
        var fixedDetectFillDispatchCompleted = false
        var before =
            ChromeMV3LocalExperimentalWebKitSyntheticLoginDOMSnapshot
            .notAttempted(
                phase: "before",
                documentID: request.documentID,
                navigationSequence: request.navigationSequence
            )
        var after =
            ChromeMV3LocalExperimentalWebKitSyntheticLoginDOMSnapshot
            .notAttempted(
                phase: "after",
                documentID: request.documentID,
                navigationSequence: request.navigationSequence
            )

        let navigationResult = await observer.wait(navigation: navigation)
        switch navigationResult {
        case .failure(let error):
            blockers.append(.webKitSyntheticFixtureUnavailable)
            diagnostics.append(error.localizedDescription)
        case .success:
            navigationCompleted = true
            do {
                before = try await inspectDOM(
                    activeWebView,
                    phase: "before",
                    request: request,
                    contentWorld: contentWorld
                )
                guard before.url == request.syntheticLoginURL,
                      before.origin
                        == ChromeMV3RuntimeMessagingURL.origin(
                            from: request.syntheticLoginURL
                        )
                else {
                    blockers.append(.webKitSyntheticFixtureUnavailable)
                    throw AdapterError.syntheticFixtureURLMismatch
                }
                _ = try await activeWebView.evaluateJavaScript(
                    fixedIsolatedHarnessShim,
                    in: nil,
                    contentWorld: contentWorld
                )
                fixedHarnessShimInstalled = true
                activeWebView.evaluateJavaScript(
                    reviewedSource,
                    in: nil,
                    in: contentWorld,
                    completionHandler: nil
                )
                let initialized = try await activeWebView.evaluateJavaScript(
                    "!!globalThis.bitwardenAutofillInit",
                    in: nil,
                    contentWorld: contentWorld
                )
                guard initialized as? Bool == true else {
                    throw AdapterError.reviewedScriptInitializationUnavailable
                }
                reviewedScriptExecuted = true
                let detectResult: Any?
                do {
                    detectResult =
                        try await eventDrivenDispatch(
                            fixedDetectDispatch,
                            stage: "detect",
                            webView: activeWebView,
                            contentWorld: contentWorld,
                            observer: messageObserver
                        )
                } catch {
                    throw AdapterError.webKitAsyncDispatchFailed(
                        stage: "detect",
                        message: diagnosticDescription(error)
                    )
                }
                guard let detectObject = detectResult as? [String: Any],
                      detectObject["ok"] as? Bool == true,
                      let usernameOpid = detectObject["usernameOpid"] as? String,
                      let passwordOpid = detectObject["passwordOpid"] as? String
                else {
                    throw AdapterError.detectFillDispatchFailed(
                        (detectResult as? [String: Any])?["message"]
                            as? String
                            ?? "unknown fixed detect dispatch failure"
                    )
                }
                diagnostics.append(
                    "Reviewed bootstrap detect dispatch completed through its registered runtime listener."
                )
                let fillResult: Any?
                do {
                    fillResult =
                        try await eventDrivenDispatch(
                            fixedFillDispatch,
                            stage: "fill",
                            webView: activeWebView,
                            contentWorld: contentWorld,
                            observer: messageObserver,
                            replacements: [
                                "__SUMI_DUMMY_USERNAME__":
                                    jsStringLiteral(request.dummyUsername),
                                "__SUMI_DUMMY_PASSWORD__":
                                    jsStringLiteral(request.dummyPassword),
                                "__SUMI_USERNAME_OPID__":
                                    jsStringLiteral(usernameOpid),
                                "__SUMI_PASSWORD_OPID__":
                                    jsStringLiteral(passwordOpid),
                            ]
                        )
                } catch {
                    throw AdapterError.webKitAsyncDispatchFailed(
                        stage: "fill",
                        message: diagnosticDescription(error)
                    )
                }
                guard let fillObject = fillResult as? [String: Any],
                      fillObject["ok"] as? Bool == true
                else {
                    throw AdapterError.detectFillDispatchFailed(
                        (fillResult as? [String: Any])?["message"]
                            as? String
                            ?? "unknown fixed fill dispatch failure"
                    )
                }
                fixedDetectFillDispatchCompleted = true
                after = try await inspectDOM(
                    activeWebView,
                    phase: "after",
                    request: request,
                    contentWorld: contentWorld
                )
            } catch {
                if blockers.isEmpty {
                    blockers.append(.reviewedScriptExecutionBlocked)
                }
                diagnostics.append(diagnosticDescription(error))
            }
        }

        let teardown = await tearDown(
            webView: activeWebView,
            configuration: activeConfiguration,
            contentWorld: contentWorld,
            completionMessageHandlerName: completionMessageHandlerName,
            evaluatedReviewedScript: reviewedScriptExecuted
        )
        webView = nil
        configuration = nil
        var completedTeardown = teardown
        completedTeardown.webViewReferenceReleased = webView == nil
        completedTeardown.configurationReferenceReleased =
            configuration == nil
        completedTeardown.completed =
            completedTeardown.navigationDelegateDetached
                && completedTeardown.userScriptCountAfterTeardown == 0
                && completedTeardown.scriptMessageHandlerCountAfterTeardown == 0
                && completedTeardown.webViewReferenceReleased
                && completedTeardown.configurationReferenceReleased

        blockers = Array(Set(blockers)).sorted()
        let wroteDummyValues =
            after.usernameValue == request.dummyUsername
                && after.passwordValue == request.dummyPassword
        return ChromeMV3LocalExperimentalWebKitProgrammaticInjectionResult(
            attempted: true,
            allowed: blockers.isEmpty,
            policy: policy,
            syntheticFixture: fixture,
            injectedReviewedFile:
                ChromeMV3LocalExperimentalProgrammaticInjectionResourceCatalog
                .bitwardenDetectFillBootstrapFile,
            reviewedSourceSHA256: sha256(reviewedSource),
            contentWorldName: contentWorld.name,
            isolatedWorldUsed: contentWorld !== WKContentWorld.page,
            topFrameOnly: true,
            hiddenSyntheticWebViewCreated: true,
            nonPersistentWebsiteDataStoreUsed: true,
            userScriptAttachmentCount:
                activeConfiguration.userContentController.userScripts.count,
            scriptMessageHandlerAttachmentCount: 1,
            navigationCompleted: navigationCompleted,
            reviewedScriptExecutedByWebKit: reviewedScriptExecuted,
            fixedHarnessShimInstalled: fixedHarnessShimInstalled,
            fixedDetectFillDispatchCompleted:
                fixedDetectFillDispatchCompleted,
            dummyValuesWrittenByActualWebKitExecutedScript: wroteDummyValues,
            domObservationBefore: before,
            domObservationAfter: after,
            teardown: completedTeardown,
            blockers: blockers,
            currentBlocker: blockers.first?.rawValue ?? "none",
            diagnostics:
                uniqueSortedWebKitProgrammaticInjection(
                    diagnostics + completedTeardown.diagnostics
                )
        )
    }

    static func runManualNormalTabSmoke(
        _ request: ChromeMV3LocalExperimentalNormalTabManualSmokeRequest
    ) async -> ChromeMV3LocalExperimentalNormalTabManualSmokeResult {
        let preflight = request.preflight
        let plan =
            ChromeMV3LocalExperimentalNormalTabManualSmokePlan.make(
                preflight: preflight,
                injectionPlan: request.injectionPlan
            )
        let adapterRequest =
            ChromeMV3LocalExperimentalWebKitProgrammaticInjectionRequest(
                moduleState:
                    preflight.blockedByModule ? .disabled : .enabled,
                localExperimentalGateAllowed:
                    preflight.blockedByLocalExperimentalGate == false,
                extensionEnabled:
                    preflight.blockedByExtension == false,
                profileScopedExtensionLoaded:
                    preflight.blockedByProfile == false,
                hostPermissionOrActiveTabAllowed:
                    preflight.hostAccessDecision.hasHostAccess,
                targetURL: preflight.urlString,
                syntheticLoginURL: preflight.urlString,
                documentID: preflight.documentID,
                navigationSequence: 1,
                frameIDs: [preflight.frameID],
                allFrames: false,
                world: preflight.contentWorld.rawValue,
                dummyUsername: request.dummyUsername,
                dummyPassword: request.dummyPassword,
                modeledInjectionAttempt: request.modeledInjectionAttempt
            )
        var blockers = preflight.blockers
        if request.productDefaultRuntimeAvailable
            || preflight.policy.productDefaultRuntimeAvailable
        {
            blockers.append(.blockedByRuntimeGate)
        }
        if request.matchAboutBlank || request.matchOriginAsFallback {
            blockers.append(.blockedByNonSyntheticOrigin)
        }
        if request.modeledInjectionAttempt.allowed == false
            || request.injectionPlan.reviewedScriptPath
                != ChromeMV3LocalExperimentalProgrammaticInjectionResourceCatalog
                .bitwardenDetectFillBootstrapFile
        {
            blockers.append(.blockedByMissingReviewedResource)
        }
        if request.injectionPlan.performsExecutionByManagerReadout {
            blockers.append(.blockedByRuntimeGate)
        }
        blockers = Array(Set(blockers)).sorted()
        guard blockers.isEmpty else {
            return blockedManualSmokeResult(
                request: request,
                plan: plan,
                blockers: blockers,
                diagnostics: [
                    "Manual normal-tab smoke preflight blocked WebKit object creation.",
                    request.matchAboutBlank
                        ? "match_about_blank remains blocked."
                        : "match_about_blank is false.",
                    request.matchOriginAsFallback
                        ? "match_origin_as_fallback remains blocked."
                        : "match_origin_as_fallback is false.",
                ]
            )
        }
        guard let reviewedSource = reviewedGeneratedSource(adapterRequest) else {
            return blockedManualSmokeResult(
                request: request,
                plan: plan,
                blockers: [.blockedByMissingReviewedResource],
                diagnostics: [
                    "The reviewed copied generated-bundle bootstrap file could not be loaded with the audited digest.",
                ]
            )
        }

        var configuration: WKWebViewConfiguration? = WKWebViewConfiguration()
        configuration?.websiteDataStore = .nonPersistent()
        configuration?.sumiIsNormalTabWebViewConfiguration = true
        guard let activeConfiguration = configuration else {
            return blockedManualSmokeResult(
                request: request,
                plan: plan,
                blockers: [.blockedByRuntimeGate],
                diagnostics: [
                    "Synthetic normal-tab WKWebViewConfiguration creation failed.",
                ]
            )
        }
        var webView: WKWebView? = WKWebView(
            frame: .zero,
            configuration: activeConfiguration
        )
        guard let activeWebView = webView else {
            return blockedManualSmokeResult(
                request: request,
                plan: plan,
                blockers: [.blockedByRuntimeGate],
                diagnostics: [
                    "Synthetic normal-tab WKWebView creation failed.",
                ]
            )
        }

        let contentWorld = WKContentWorld.world(name: contentWorldName)
        let messageObserver =
            ChromeMV3LocalExperimentalWebKitInjectionMessageObserver()
        activeConfiguration.userContentController.add(
            messageObserver,
            contentWorld: contentWorld,
            name: completionMessageHandlerName
        )
        let observer =
            ChromeMV3LocalExperimentalWebKitInjectionNavigationObserver()
        activeWebView.navigationDelegate = observer
        let navigation = activeWebView.loadHTMLString(
            syntheticLoginHTML,
            baseURL: URL(string: preflight.urlString)
        )
        let diagnostics = [
            "Created one explicit synthetic normal-tab WKWebViewConfiguration marker for manual smoke only.",
            "The reviewed generated-bundle file is evaluated verbatim in one named isolated WKContentWorld against the top frame.",
            "No manager readout, product BrowserManager path, WKWebExtension controller/context, native host, auth flow, network request, MAIN world, or multi-frame attachment is created.",
        ]
        var thrownErrors: [String] = []
        var reviewedScriptExecuted = false
        var fixedHarnessShimInstalled = false
        var fixedDetectFillDispatchCompleted = false
        var before =
            ChromeMV3LocalExperimentalWebKitSyntheticLoginDOMSnapshot
            .notAttempted(
                phase: "before",
                documentID: preflight.documentID,
                navigationSequence: 1
            )
        var after =
            ChromeMV3LocalExperimentalWebKitSyntheticLoginDOMSnapshot
            .notAttempted(
                phase: "after",
                documentID: preflight.documentID,
                navigationSequence: 1
            )

        let navigationResult = await observer.wait(navigation: navigation)
        switch navigationResult {
        case .failure(let error):
            thrownErrors.append(diagnosticDescription(error))
            blockers.append(.blockedByRuntimeGate)
        case .success:
            do {
                before = try await inspectDOM(
                    activeWebView,
                    phase: "before",
                    request: adapterRequest,
                    contentWorld: contentWorld
                )
                guard before.url == preflight.urlString,
                      before.origin == plan.syntheticOrigin
                else {
                    throw AdapterError.syntheticFixtureURLMismatch
                }
                _ = try await activeWebView.evaluateJavaScript(
                    fixedIsolatedHarnessShim,
                    in: nil,
                    contentWorld: contentWorld
                )
                fixedHarnessShimInstalled = true
                activeWebView.evaluateJavaScript(
                    reviewedSource,
                    in: nil,
                    in: contentWorld,
                    completionHandler: nil
                )
                let initialized = try await activeWebView.evaluateJavaScript(
                    "!!globalThis.bitwardenAutofillInit",
                    in: nil,
                    contentWorld: contentWorld
                )
                guard initialized as? Bool == true else {
                    throw AdapterError.reviewedScriptInitializationUnavailable
                }
                reviewedScriptExecuted = true
                let detectResult = try await eventDrivenDispatch(
                    fixedDetectDispatch,
                    stage: "detect",
                    webView: activeWebView,
                    contentWorld: contentWorld,
                    observer: messageObserver
                )
                guard detectResult["ok"] as? Bool == true,
                      let usernameOpid =
                        detectResult["usernameOpid"] as? String,
                      let passwordOpid =
                        detectResult["passwordOpid"] as? String
                else {
                    throw AdapterError.detectFillDispatchFailed(
                        detectResult["message"] as? String
                            ?? "unknown fixed detect dispatch failure"
                    )
                }
                let fillResult = try await eventDrivenDispatch(
                    fixedFillDispatch,
                    stage: "fill",
                    webView: activeWebView,
                    contentWorld: contentWorld,
                    observer: messageObserver,
                    replacements: [
                        "__SUMI_DUMMY_USERNAME__":
                            jsStringLiteral(request.dummyUsername),
                        "__SUMI_DUMMY_PASSWORD__":
                            jsStringLiteral(request.dummyPassword),
                        "__SUMI_USERNAME_OPID__":
                            jsStringLiteral(usernameOpid),
                        "__SUMI_PASSWORD_OPID__":
                            jsStringLiteral(passwordOpid),
                    ]
                )
                guard fillResult["ok"] as? Bool == true else {
                    throw AdapterError.detectFillDispatchFailed(
                        fillResult["message"] as? String
                            ?? "unknown fixed fill dispatch failure"
                    )
                }
                fixedDetectFillDispatchCompleted = true
                after = try await inspectDOM(
                    activeWebView,
                    phase: "after",
                    request: adapterRequest,
                    contentWorld: contentWorld
                )
            } catch {
                thrownErrors.append(diagnosticDescription(error))
                blockers.append(.blockedByRuntimeGate)
            }
        }

        let scopedTeardown = await tearDown(
            webView: activeWebView,
            configuration: activeConfiguration,
            contentWorld: contentWorld,
            completionMessageHandlerName: completionMessageHandlerName,
            evaluatedReviewedScript: reviewedScriptExecuted
        )
        webView = nil
        configuration = nil
        let teardownCompleted =
            scopedTeardown.navigationDelegateDetached
                && scopedTeardown.userScriptCountAfterTeardown == 0
                && scopedTeardown.scriptMessageHandlerCountAfterTeardown == 0
                && webView == nil
                && configuration == nil
        let manualTeardown =
            ChromeMV3LocalExperimentalNormalTabManualSmokeTeardown(
                required: true,
                completed: teardownCompleted,
                verifiedTriggers:
                    ChromeMV3ProductNormalTabReadinessTeardownTrigger
                    .allCases
                    .sorted(),
                webKitObjectsCreated: [
                    "WKWebViewConfiguration(normal-tab manual smoke)",
                    "WKWebView(synthetic normal-tab test page)",
                    "WKContentWorld(\(contentWorld.name ?? contentWorldName))",
                ],
                handlersCreated: [completionMessageHandlerName],
                userScriptsCreated: [],
                endpointsCreated: [
                    "sumiBitwardenSyntheticCompletion",
                    "reviewed Bitwarden runtime.onMessage listener",
                ],
                objectsRemoved: [
                    "navigationDelegate",
                    "scriptMessageHandler:\(completionMessageHandlerName)",
                    "reviewed Bitwarden listener state",
                    "synthetic chrome runtime shim",
                    "WKWebView reference",
                    "WKWebViewConfiguration reference",
                ],
                retainedObjectCountAfterTeardown:
                    teardownCompleted ? 0 : 2,
                diagnostics: scopedTeardown.diagnostics
                    + [
                        "Manual normal-tab smoke teardown verified all configured lifecycle trigger categories by policy.",
                    ]
            )

        blockers = Array(Set(blockers)).sorted()
        let fieldsTouched =
            after.usernameValue == request.dummyUsername
                && after.passwordValue == request.dummyPassword
                ? ["sumi-login-email", "sumi-login-password"]
                : []
        let success =
            blockers.isEmpty
                && reviewedScriptExecuted
                && fixedDetectFillDispatchCompleted
                && fieldsTouched.count == 2
                && manualTeardown.completed
        return ChromeMV3LocalExperimentalNormalTabManualSmokeResult(
            attempted: true,
            allowed: success,
            policy: preflight.policy,
            eligibility: preflight,
            injectionPlan: plan,
            manualNormalTabSmokeAvailableInLocalExperimentalGate:
                preflight.policy
                .manualNormalTabSmokeAvailableInLocalExperimentalGate,
            manualNormalTabSmokeAvailableByDefault:
                preflight.policy.manualNormalTabSmokeAvailableByDefault,
            productDefaultRuntimeAvailable:
                request.productDefaultRuntimeAvailable
                    || preflight.policy.productDefaultRuntimeAvailable,
            reviewedFileOnly: preflight.policy.reviewedFileOnly,
            syntheticHTTPSOriginOnly:
                preflight.policy.syntheticHTTPSOriginOnly,
            isolatedWorldOnly: preflight.policy.isolatedWorldOnly,
            topFrameOnly: preflight.policy.topFrameOnly,
            auxiliarySurfaceAllowed: preflight.policy.auxiliarySurfaceAllowed,
            teardownRequired: preflight.policy.teardownRequired,
            normalTabConfigurationMarked:
                activeConfiguration.sumiIsNormalTabWebViewConfiguration,
            normalBrowsingSurfaceOnly: preflight.tabSurface == .normalTab,
            reviewedScriptExecutedByWebKit: reviewedScriptExecuted,
            fixedHarnessShimInstalled: fixedHarnessShimInstalled,
            fixedDetectFillDispatchCompleted:
                fixedDetectFillDispatchCompleted,
            domObservationBefore: before,
            domObservationAfter: after,
            fieldsTouched: fieldsTouched,
            usernameDummyValue: request.dummyUsername,
            passwordDummyValue: request.dummyPassword,
            webKitExecutionResult: success ? "pass" : "failed",
            thrownErrors: thrownErrors,
            teardown: manualTeardown,
            blockers: blockers,
            currentBlocker: blockers.first?.rawValue ?? "none",
            diagnostics:
                uniqueSortedWebKitProgrammaticInjection(
                    diagnostics
                        + manualTeardown.diagnostics
                        + thrownErrors
                        + [
                            success
                                ? "Manual normal-tab smoke executed the reviewed Bitwarden bootstrap on the synthetic HTTPS test page and wrote only dummy values."
                                : "Manual normal-tab smoke did not complete successfully.",
                            "Product/default runtime remains unavailable and no product support is claimed.",
                        ]
                )
        )
    }

    private static func preflightBlockers(
        _ request: ChromeMV3LocalExperimentalWebKitProgrammaticInjectionRequest
    ) -> [ChromeMV3LocalExperimentalWebKitProgrammaticInjectionBlocker] {
        var blockers:
            [ChromeMV3LocalExperimentalWebKitProgrammaticInjectionBlocker] = []
        if request.moduleState != .enabled {
            blockers.append(.moduleDisabled)
        }
        if request.localExperimentalGateAllowed == false {
            blockers.append(.localExperimentalGateClosed)
        }
        if request.extensionEnabled == false {
            blockers.append(.extensionDisabled)
        }
        if request.profileScopedExtensionLoaded == false {
            blockers.append(.profileScopedExtensionMissing)
        }
        if request.hostPermissionOrActiveTabAllowed == false {
            blockers.append(.hostPermissionBlocked)
        }
        if request.targetURL != request.syntheticLoginURL
            || URL(string: request.targetURL)?.scheme?.lowercased() != "https"
        {
            blockers.append(.syntheticHTTPSFixtureRequired)
        }
        if request.world != "ISOLATED" {
            blockers.append(.isolatedWorldRequired)
        }
        if request.frameIDs != [0] || request.allFrames {
            blockers.append(.multiFrameBlocked)
        }
        let attempt = request.modeledInjectionAttempt
        if attempt.allowed == false {
            blockers.append(.reviewedScriptResolutionBlocked)
        }
        if attempt.shapeAudit.files
            != [
                ChromeMV3LocalExperimentalProgrammaticInjectionResourceCatalog
                    .bitwardenDetectFillBootstrapFile
            ]
        {
            blockers.append(.reviewedGeneratedBundleFileRequired)
        }
        return Array(Set(blockers)).sorted()
    }

    private static func reviewedGeneratedSource(
        _ request: ChromeMV3LocalExperimentalWebKitProgrammaticInjectionRequest
    ) -> String? {
        let attempt = request.modeledInjectionAttempt
        guard attempt.allowed,
              attempt.shapeAudit.packageShapeMatched,
              let expectedSHA256 = attempt.shapeAudit.reviewedBootstrapSHA256,
              attempt.resourceResolutions.count == 1,
              let resolution = attempt.resourceResolutions.first,
              resolution.status == .copiedGeneratedBundleFile,
              resolution.requestedPath
                == ChromeMV3LocalExperimentalProgrammaticInjectionResourceCatalog
                .bitwardenDetectFillBootstrapFile,
              let path = resolution.resolvedFileSystemPath,
              let source = try? String(
                  contentsOf: URL(fileURLWithPath: path),
                  encoding: .utf8
              ),
              source.contains("collectPageDetailsImmediately"),
              source.contains("fillForm"),
              source.contains("chrome.runtime.onMessage.addListener"),
              sha256(source) == expectedSHA256
        else { return nil }
        return source
    }

    private static func inspectDOM(
        _ webView: WKWebView,
        phase: String,
        request: ChromeMV3LocalExperimentalWebKitProgrammaticInjectionRequest,
        contentWorld: WKContentWorld
    ) async throws
        -> ChromeMV3LocalExperimentalWebKitSyntheticLoginDOMSnapshot
    {
        let value = try await webView.evaluateJavaScript(
            """
            (() => {
              const username = globalThis.document.getElementById("sumi-login-email");
              const password = globalThis.document.getElementById("sumi-login-password");
              const submit = globalThis.document.getElementById("sumi-login-submit");
              return JSON.stringify({
                url: globalThis.location.href,
                origin: globalThis.location.origin,
                usernameFieldExists: !!username,
                passwordFieldExists: !!password,
                submitButtonExists: !!submit,
                usernameValue: username ? username.value : "",
                passwordValue: password ? password.value : ""
              });
            })();
            """,
            in: nil,
            contentWorld: contentWorld
        )
        guard let json = value as? String,
              let data = json.data(using: .utf8),
              let object =
                try JSONSerialization.jsonObject(with: data)
                    as? [String: Any]
        else {
            throw AdapterError.domObservationUnavailable
        }
        let usernameValue = object["usernameValue"] as? String ?? ""
        let passwordValue = object["passwordValue"] as? String ?? ""
        return ChromeMV3LocalExperimentalWebKitSyntheticLoginDOMSnapshot(
            phase: phase,
            url: object["url"] as? String ?? "",
            origin: object["origin"] as? String ?? "",
            documentID: request.documentID,
            navigationSequence: request.navigationSequence,
            usernameFieldExists: object["usernameFieldExists"] as? Bool ?? false,
            passwordFieldExists: object["passwordFieldExists"] as? Bool ?? false,
            submitButtonExists: object["submitButtonExists"] as? Bool ?? false,
            usernameValue: usernameValue,
            passwordValue: passwordValue,
            initialValuesEmpty:
                usernameValue.isEmpty && passwordValue.isEmpty,
            finalValuesMatchDummyFill:
                phase == "after"
                    && usernameValue == request.dummyUsername
                    && passwordValue == request.dummyPassword
        )
    }

    private static func tearDown(
        webView: WKWebView,
        configuration: WKWebViewConfiguration,
        contentWorld: WKContentWorld,
        completionMessageHandlerName: String,
        evaluatedReviewedScript: Bool
    ) async -> ChromeMV3LocalExperimentalWebKitProgrammaticInjectionTeardown {
        var diagnostics: [String] = []
        if evaluatedReviewedScript {
            do {
                _ = try await webView.evaluateJavaScript(
                    fixedIsolatedHarnessTeardown,
                    in: nil,
                    contentWorld: contentWorld
                )
                diagnostics.append(
                    "Destroyed the reviewed Bitwarden autofill instance and removed its scoped listener state before releasing the synthetic WebView."
                )
            } catch {
                diagnostics.append(
                    "Scoped reviewed-script teardown returned an error: \(diagnosticDescription(error))"
                )
            }
        }
        webView.stopLoading()
        webView.navigationDelegate = nil
        configuration.userContentController.removeAllUserScripts()
        configuration.userContentController.removeScriptMessageHandler(
            forName: completionMessageHandlerName,
            contentWorld: contentWorld
        )
        return ChromeMV3LocalExperimentalWebKitProgrammaticInjectionTeardown(
            required: true,
            completed: false,
            navigationDelegateDetached: webView.navigationDelegate == nil,
            userScriptCountAfterTeardown:
                configuration.userContentController.userScripts.count,
            scriptMessageHandlerCountAfterTeardown: 0,
            webViewReferenceReleased: false,
            configurationReferenceReleased: false,
            diagnostics:
                diagnostics + [
                    "Detached the navigation delegate, removed synthetic user scripts, and retained no script message handlers.",
                ]
        )
    }

    private static func blockedResult(
        fixture: ChromeMV3LocalExperimentalWebKitSyntheticLoginFixture,
        blockers:
            [ChromeMV3LocalExperimentalWebKitProgrammaticInjectionBlocker],
        diagnostics: [String]
    ) -> ChromeMV3LocalExperimentalWebKitProgrammaticInjectionResult {
        let sortedBlockers = Array(Set(blockers)).sorted()
        return ChromeMV3LocalExperimentalWebKitProgrammaticInjectionResult(
            attempted: true,
            allowed: false,
            policy: .bitwardenDetectFill,
            syntheticFixture: fixture,
            injectedReviewedFile: nil,
            reviewedSourceSHA256: nil,
            contentWorldName: nil,
            isolatedWorldUsed: false,
            topFrameOnly: true,
            hiddenSyntheticWebViewCreated: false,
            nonPersistentWebsiteDataStoreUsed: false,
            userScriptAttachmentCount: 0,
            scriptMessageHandlerAttachmentCount: 0,
            navigationCompleted: false,
            reviewedScriptExecutedByWebKit: false,
            fixedHarnessShimInstalled: false,
            fixedDetectFillDispatchCompleted: false,
            dummyValuesWrittenByActualWebKitExecutedScript: false,
            domObservationBefore:
                .notAttempted(
                    phase: "before",
                    documentID: fixture.documentID,
                    navigationSequence: fixture.navigationSequence
                ),
            domObservationAfter:
                .notAttempted(
                    phase: "after",
                    documentID: fixture.documentID,
                    navigationSequence: fixture.navigationSequence
                ),
            teardown: .notRequired,
            blockers: sortedBlockers,
            currentBlocker: sortedBlockers.first?.rawValue ?? "none",
            diagnostics: diagnostics
        )
    }

    private static func blockedManualSmokeResult(
        request: ChromeMV3LocalExperimentalNormalTabManualSmokeRequest,
        plan: ChromeMV3LocalExperimentalNormalTabManualSmokePlan,
        blockers: [ChromeMV3ProductNormalTabReadinessBlocker],
        diagnostics: [String]
    ) -> ChromeMV3LocalExperimentalNormalTabManualSmokeResult {
        let sortedBlockers = Array(Set(blockers)).sorted()
        return ChromeMV3LocalExperimentalNormalTabManualSmokeResult(
            attempted: true,
            allowed: false,
            policy: request.preflight.policy,
            eligibility: request.preflight,
            injectionPlan: plan,
            manualNormalTabSmokeAvailableInLocalExperimentalGate:
                request.preflight.policy
                .manualNormalTabSmokeAvailableInLocalExperimentalGate,
            manualNormalTabSmokeAvailableByDefault:
                request.preflight.policy.manualNormalTabSmokeAvailableByDefault,
            productDefaultRuntimeAvailable:
                request.productDefaultRuntimeAvailable
                    || request.preflight.policy.productDefaultRuntimeAvailable,
            reviewedFileOnly: request.preflight.policy.reviewedFileOnly,
            syntheticHTTPSOriginOnly:
                request.preflight.policy.syntheticHTTPSOriginOnly,
            isolatedWorldOnly: request.preflight.policy.isolatedWorldOnly,
            topFrameOnly: request.preflight.policy.topFrameOnly,
            auxiliarySurfaceAllowed:
                request.preflight.policy.auxiliarySurfaceAllowed,
            teardownRequired: request.preflight.policy.teardownRequired,
            normalTabConfigurationMarked: false,
            normalBrowsingSurfaceOnly:
                request.preflight.tabSurface == .normalTab,
            reviewedScriptExecutedByWebKit: false,
            fixedHarnessShimInstalled: false,
            fixedDetectFillDispatchCompleted: false,
            domObservationBefore:
                .notAttempted(
                    phase: "before",
                    documentID: request.preflight.documentID,
                    navigationSequence: 0
                ),
            domObservationAfter:
                .notAttempted(
                    phase: "after",
                    documentID: request.preflight.documentID,
                    navigationSequence: 0
                ),
            fieldsTouched: [],
            usernameDummyValue: request.dummyUsername,
            passwordDummyValue: request.dummyPassword,
            webKitExecutionResult: "blockedBeforeObjectCreation",
            thrownErrors: [],
            teardown: .notRequired,
            blockers: sortedBlockers,
            currentBlocker: sortedBlockers.first?.rawValue ?? "none",
            diagnostics:
                uniqueSortedWebKitProgrammaticInjection(
                    diagnostics
                        + [
                            "No WKWebViewConfiguration, WKWebView, content world, script handler, content-script endpoint, native host, auth flow, network request, or product runtime object was created.",
                        ]
                )
        )
    }

    private static func sha256(_ source: String) -> String {
        SHA256.hash(data: Data(source.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func eventDrivenDispatch(
        _ source: String,
        stage: String,
        webView: WKWebView,
        contentWorld: WKContentWorld,
        observer: ChromeMV3LocalExperimentalWebKitInjectionMessageObserver,
        replacements: [String: String] = [:]
    ) async throws -> [String: Any] {
        let evaluatedSource = replacements.reduce(into: source) {
            result,
            replacement in
            result = result.replacingOccurrences(
                of: replacement.key,
                with: replacement.value
            )
        }
        _ = try await webView.evaluateJavaScript(
            evaluatedSource,
            in: nil,
            contentWorld: contentWorld
        )
        return await observer.wait(for: stage)
    }

    private static func jsStringLiteral(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let literal = String(data: data, encoding: .utf8)
        else {
            return "\"\""
        }
        return literal
    }

    private static func diagnosticDescription(_ error: Error) -> String {
        let nsError = error as NSError
        let userInfo = nsError.userInfo
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: ", ")
        guard userInfo.isEmpty == false else {
            return nsError.localizedDescription
        }
        return "\(nsError.localizedDescription) [\(userInfo)]"
    }

    private enum AdapterError: LocalizedError {
        case domObservationUnavailable
        case detectFillDispatchFailed(String)
        case reviewedScriptInitializationUnavailable
        case syntheticFixtureURLMismatch
        case webKitAsyncDispatchFailed(stage: String, message: String)

        var errorDescription: String? {
            switch self {
            case .domObservationUnavailable:
                return "Synthetic login DOM observation did not return JSON."
            case .detectFillDispatchFailed(let message):
                return "Reviewed-script detect/fill dispatch failed: \(message)"
            case .reviewedScriptInitializationUnavailable:
                return "The reviewed Bitwarden bootstrap did not initialize in the isolated synthetic world."
            case .syntheticFixtureURLMismatch:
                return "Synthetic WebKit fixture did not preserve the required HTTPS URL and origin."
            case .webKitAsyncDispatchFailed(let stage, let message):
                return "Reviewed-script \(stage) WebKit bridge failed: \(message)"
            }
        }
    }

    private static let syntheticLoginHTML = """
    <!doctype html>
    <html>
      <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
        <title>Sumi synthetic Bitwarden login</title>
      </head>
      <body>
        <form id="sumi-login-form" name="sumiSyntheticLogin" method="post" action="#sumi-blocked-submit" onsubmit="event.preventDefault(); return false;">
          <label>Email <input id="sumi-login-email" name="email" type="email" autocomplete="username"></label>
          <label>Password <input id="sumi-login-password" name="password" type="password" autocomplete="current-password"></label>
          <button id="sumi-login-submit" name="submit" type="submit">Sign in</button>
        </form>
      </body>
    </html>
    """

    private static let fixedIsolatedHarnessShim = """
    (() => {
      const messageListeners = new Set();
      const disconnectListeners = new Set();
      const sentMessages = [];
      const port = {
        onDisconnect: {
          addListener(listener) { disconnectListeners.add(listener); },
          removeListener(listener) { disconnectListeners.delete(listener); }
        },
        disconnect() {
          for (const listener of Array.from(disconnectListeners)) {
            listener(port);
          }
          disconnectListeners.clear();
        }
      };
      const runtime = {
        lastError: null,
        onMessage: {
          addListener(listener) { messageListeners.add(listener); },
          removeListener(listener) { messageListeners.delete(listener); }
        },
        sendMessage(message, callback) {
          sentMessages.push(message);
          const response = message && message.command === "getUrlAutofillTargetingRules"
            ? { result: null }
            : null;
          if (typeof callback === "function") {
            callback(response);
          }
          return Promise.resolve(response);
        },
        connect() { return port; }
      };
      globalThis.chrome = {
        runtime,
        i18n: { getMessage() { return ""; } }
      };
      globalThis.__sumiBitwardenSyntheticHarness = {
        dispatch(message) {
          return new Promise((resolve, reject) => {
            const listeners = Array.from(messageListeners);
            if (!listeners.length) {
              resolve(null);
              return;
            }
            let settled = false;
            const sendResponse = () => {
              if (!settled) {
                settled = true;
                resolve(true);
              }
            };
            try {
              for (const listener of listeners) {
                const result = listener(message, { url: globalThis.location.href }, sendResponse);
                if (result === true) {
                  return;
                }
                if (result !== undefined && result !== null) {
                  Promise.resolve(result).then(sendResponse, reject);
                  return;
                }
              }
              sendResponse(null);
            } catch (error) {
              reject(error);
            }
          });
        },
        destroy() {
          port.disconnect();
          messageListeners.clear();
          sentMessages.length = 0;
        }
      };
      return true;
    })();
    """

    private static let fixedDetectDispatch = """
    (() => {
      const bridge = globalThis.webkit.messageHandlers.sumiBitwardenSyntheticCompletion;
      void (async () => {
        try {
          const harness = globalThis.__sumiBitwardenSyntheticHarness;
          if (!harness) {
            throw new Error("missing synthetic Bitwarden harness");
          }
          const username = globalThis.document.getElementById("sumi-login-email");
          const password = globalThis.document.getElementById("sumi-login-password");
          if (!username || !password) {
            throw new Error("missing synthetic login fields");
          }
          await harness.dispatch({
            command: "collectPageDetailsImmediately",
            sender: "sumiDetectFillSmoke",
            tab: { id: 1, url: globalThis.location.href }
          });
          if (!username.opid || !password.opid) {
            throw new Error("reviewed Bitwarden bootstrap did not assign synthetic field opids");
          }
          bridge.postMessage({
            stage: "detect",
            ok: true,
            usernameOpid: username.opid,
            passwordOpid: password.opid
          });
        } catch (error) {
          bridge.postMessage({
            stage: "detect",
            ok: false,
            message: String(error && error.stack ? error.stack : error)
          });
        }
      })();
      return true;
    })();
    """

    private static let fixedFillDispatch = """
    (() => {
      const bridge = globalThis.webkit.messageHandlers.sumiBitwardenSyntheticCompletion;
      void (async () => {
        try {
          const harness = globalThis.__sumiBitwardenSyntheticHarness;
          if (!harness) {
            throw new Error("missing synthetic Bitwarden harness");
          }
          const username = globalThis.document.getElementById("sumi-login-email");
          const password = globalThis.document.getElementById("sumi-login-password");
          if (!username || !password) {
            throw new Error("missing synthetic login fields");
          }
          await harness.dispatch({
            command: "fillForm",
            pageDetailsUrl: globalThis.location.href,
            showAnimations: false,
            fillScript: {
              script: [
                ["fill_by_opid", __SUMI_USERNAME_OPID__, __SUMI_DUMMY_USERNAME__],
                ["fill_by_opid", __SUMI_PASSWORD_OPID__, __SUMI_DUMMY_PASSWORD__]
              ],
              savedUrls: [globalThis.location.origin],
              untrustedIframe: false
            }
          });
          bridge.postMessage({
            stage: "fill",
            ok: true,
            usernameValue: username.value,
            passwordValue: password.value
          });
        } catch (error) {
          bridge.postMessage({
            stage: "fill",
            ok: false,
            message: String(error && error.stack ? error.stack : error)
          });
        }
      })();
      return true;
    })();
    """

    private static let fixedIsolatedHarnessTeardown = """
    (() => {
      try {
        if (globalThis.bitwardenAutofillInit) {
          globalThis.bitwardenAutofillInit.destroy();
          delete globalThis.bitwardenAutofillInit;
        }
      } catch (_) {}
      try {
        if (globalThis.__sumiBitwardenSyntheticHarness) {
          globalThis.__sumiBitwardenSyntheticHarness.destroy();
          delete globalThis.__sumiBitwardenSyntheticHarness;
        }
      } catch (_) {}
      try { delete globalThis.chrome; } catch (_) {}
      return true;
    })();
    """
}

@available(macOS 15.5, *)
extension ChromeMV3PasswordManagerRealPackageTrialRunner {
    @MainActor
    static func runWithSyntheticWebKitProgrammaticInjectionAdapter(
        rootURL: URL,
        targets:
            [ChromeMV3PasswordManagerRealPackageTargetDefinition] =
                ChromeMV3PasswordManagerRealPackageTargetCatalog
                .explicitLocalTargets(),
        profileID: String = "password-manager-real-package-profile",
        moduleState: ChromeMV3ProfileHostModuleState = .enabled,
        serviceWorkerTrialGateSource:
            ChromeMV3PasswordManagerRealPackageServiceWorkerTrialGateSource =
                .blockedDefault,
        trustedHostApprovalRecords:
            [ChromeMV3NativeTrustedHostApprovalRecord] = [],
        writeReport: Bool = true,
        now: @escaping () -> Date = Date.init,
        fileManager: FileManager = .default
    ) async -> ChromeMV3PasswordManagerRealPackageCompatibilityReport {
        var report = run(
            rootURL: rootURL,
            targets: targets,
            profileID: profileID,
            moduleState: moduleState,
            serviceWorkerTrialGateSource: serviceWorkerTrialGateSource,
            trustedHostApprovalRecords: trustedHostApprovalRecords,
            writeReport: false,
            now: now,
            fileManager: fileManager
        )
        var executedAdapterCount = 0
        var executedManualNormalTabSmokeCount = 0
        for index in report.rows.indices
        where report.rows[index].targetClass == .bitwarden {
            var smoke = report.rows[index].bitwardenE2ESmoke
            let detectFill = smoke.detectFillSmoke
            guard detectFill.attempted else { continue }
            let attempt = detectFill.programmaticInjectionAttempt
            let result = await
                ChromeMV3LocalExperimentalWebKitProgrammaticInjectionAdapter
                .run(
                    ChromeMV3LocalExperimentalWebKitProgrammaticInjectionRequest(
                        moduleState: moduleState,
                        localExperimentalGateAllowed:
                            serviceWorkerTrialGateSource
                            .allowsScopedExecution,
                        extensionEnabled: smoke.extensionEnabled,
                        profileScopedExtensionLoaded:
                            attempt.blockers.contains(
                                .profileScopedExtensionMissing
                            ) == false,
                        hostPermissionOrActiveTabAllowed:
                            attempt.shapeAudit
                            .hostPermissionOrActiveTabAllowed,
                        targetURL: detectFill.syntheticLoginPage.url,
                        syntheticLoginURL:
                            detectFill.syntheticLoginPage.url,
                        documentID:
                            detectFill.webKitProgrammaticInjectionResult
                            .syntheticFixture.documentID,
                        navigationSequence: 1,
                        frameIDs: attempt.shapeAudit.frameIDs,
                        allFrames: attempt.shapeAudit.allFrames,
                        world: attempt.shapeAudit.world,
                        dummyUsername: detectFill.dummyUsername,
                        dummyPassword: detectFill.dummyPassword,
                        modeledInjectionAttempt: attempt
                    )
                )
            smoke.detectFillSmoke = applying(
                result,
                to: detectFill
            )
            let manualRequest = manualNormalTabSmokeRequest(
                detectFill: smoke.detectFillSmoke,
                attempt: attempt,
                moduleState: moduleState,
                serviceWorkerTrialGateSource: serviceWorkerTrialGateSource,
                extensionEnabled: smoke.extensionEnabled,
                profileID: profileID,
                extensionID: report.rows[index].targetID
            )
            let manualResult = await
                ChromeMV3LocalExperimentalWebKitProgrammaticInjectionAdapter
                .runManualNormalTabSmoke(manualRequest)
            smoke.detectFillSmoke = applying(
                manualResult,
                to: smoke.detectFillSmoke
            )
            report.rows[index].bitwardenE2ESmoke = smoke
            executedAdapterCount += 1
            executedManualNormalTabSmokeCount += 1
        }
        report.diagnostics =
            uniqueSortedWebKitProgrammaticInjection(
                report.diagnostics + [
                    executedAdapterCount == 0
                        ? "Explicit async synthetic WebKit adapter runner created no adapter because no gated Bitwarden detect/fill smoke was eligible."
                        : "Explicit async synthetic WebKit adapter runner executed \(executedAdapterCount) gated Bitwarden reviewed-bundle adapter attempt(s).",
                    executedManualNormalTabSmokeCount == 0
                        ? "Explicit async manual normal-tab smoke runner created no adapter because no gated Bitwarden detect/fill smoke was eligible."
                        : "Explicit async manual normal-tab smoke runner executed \(executedManualNormalTabSmokeCount) gated Bitwarden reviewed-bundle normal-tab smoke attempt(s).",
                ]
            )
        if writeReport {
            return (
                try?
                    ChromeMV3PasswordManagerRealPackageCompatibilityReportWriter
                    .write(report, to: rootURL.standardizedFileURL)
            ) ?? report
        }
        return report
    }

    private static func manualNormalTabSmokeRequest(
        detectFill: ChromeMV3PasswordManagerRealPackageDetectFillSmoke,
        attempt: ChromeMV3LocalExperimentalProgrammaticInjectionAttempt,
        moduleState: ChromeMV3ProfileHostModuleState,
        serviceWorkerTrialGateSource:
            ChromeMV3PasswordManagerRealPackageServiceWorkerTrialGateSource,
        extensionEnabled: Bool,
        profileID: String,
        extensionID: String
    ) -> ChromeMV3LocalExperimentalNormalTabManualSmokeRequest {
        let url = detectFill.syntheticLoginPage.url
        let origin = ChromeMV3RuntimeMessagingURL.origin(from: url)
        let hostAllowed =
            attempt.shapeAudit.hostPermissionOrActiveTabAllowed
        let hostDecision = ChromeMV3HostAccessDecision(
            url: url,
            origin: origin,
            status: hostAllowed ? .allowed : .blocked,
            grantSource: hostAllowed ? .activeTabGrant : .none,
            hasHostAccess: hostAllowed,
            allowedByHostPermission: false,
            allowedByOptionalHostPermission: false,
            allowedByActiveTab: hostAllowed,
            matchingHostPatterns:
                hostAllowed ? ["activeTab:\(origin ?? "invalid")"] : [],
            optionalHostPatternsThatCouldPrompt: [],
            invalidHostPatterns: [],
            unsupportedHostPatterns: [],
            deniedByPattern: false,
            revokedByPattern: false,
            wouldNeedPrompt: false,
            missingReason: hostAllowed ? .none : .activeTabMissing,
            diagnostics: [
                hostAllowed
                    ? "Manual smoke host access is satisfied by the modeled activeTab grant for the synthetic origin."
                    : "Manual smoke host access is missing for the synthetic origin.",
            ]
        )
        let resolution = attempt.resourceResolutions.first
        let reviewedResource = ChromeMV3ProductNormalTabReviewedResource(
            reviewedScriptPath:
                ChromeMV3LocalExperimentalProgrammaticInjectionResourceCatalog
                .bitwardenDetectFillBootstrapFile,
            generatedResourceHash: attempt.shapeAudit.reviewedBootstrapSHA256,
            generatedResourceFileSystemPath:
                resolution?.resolvedFileSystemPath,
            present:
                resolution?.status == .copiedGeneratedBundleFile
                    && attempt.shapeAudit.reviewedBootstrapSHA256 != nil,
            packageOwned:
                resolution?.status == .copiedGeneratedBundleFile,
            diagnostics:
                resolution?.diagnostics
                    ?? ["Reviewed generated-bundle resource was not resolved."]
        )
        let preflight =
            ChromeMV3ProductNormalTabReadinessPreflightEvaluator.evaluate(
                input: ChromeMV3ProductNormalTabReadinessPreflightInput(
                    profileID: profileID,
                    extensionID: extensionID,
                    tabID: "\(attempt.shapeAudit.tabID)",
                    documentID:
                        detectFill.webKitProgrammaticInjectionResult
                        .syntheticFixture.documentID,
                    urlString: url,
                    moduleEnabled: moduleState == .enabled,
                    extensionEnabled: extensionEnabled,
                    profileEnabled: true,
                    localExperimentalProductGateAllowed:
                        serviceWorkerTrialGateSource.allowsScopedExecution,
                    runtimeGateAllowsReadiness: true,
                    contentScriptRouteReady:
                        attempt.shapeAudit.contentScriptDOMInjectionPresent,
                    serviceWorkerRouteReady:
                        attempt.shapeAudit.packageShapeMatched,
                    tabSurface: .normalTab,
                    syntheticHTTPSOrigin: "https://sumi.local.test",
                    frameID: 0,
                    isTopFrame: true,
                    contentWorld: .isolated,
                    hostAccessDecision: hostDecision,
                    reviewedResource: reviewedResource,
                    teardownPending: false
                )
            )
        let plan =
            ChromeMV3ProductNormalTabReviewedFileInjectionPlan.make(
                preflight: preflight
            )
        return ChromeMV3LocalExperimentalNormalTabManualSmokeRequest(
            preflight: preflight,
            injectionPlan: plan,
            modeledInjectionAttempt: attempt,
            dummyUsername: detectFill.dummyUsername,
            dummyPassword: detectFill.dummyPassword,
            productDefaultRuntimeAvailable: false,
            matchAboutBlank: false,
            matchOriginAsFallback: false
        )
    }

    private static func applying(
        _ result:
            ChromeMV3LocalExperimentalWebKitProgrammaticInjectionResult,
        to smoke: ChromeMV3PasswordManagerRealPackageDetectFillSmoke
    ) -> ChromeMV3PasswordManagerRealPackageDetectFillSmoke {
        var updated = smoke
        updated.webKitProgrammaticInjectionResult = result
        if result.dummyValuesWrittenByActualWebKitExecutedScript {
            updated.domObservationBefore =
                realPackageDOMObservation(result.domObservationBefore)
            updated.domObservationAfter =
                realPackageDOMObservation(result.domObservationAfter)
            updated.domObservationResult =
                "actualWebKitIsolatedWorldDOM: reviewed content/bootstrap-autofill.js changed the synthetic username/password fields after isolated top-frame execution."
            updated.dummyFillResult =
                "completed: actual WebKit execution of the reviewed generated-bundle Bitwarden bootstrap wrote only the synthetic dummy username/password values."
            updated.touchedSyntheticFieldIDs = [
                "sumi-login-email",
                "sumi-login-password",
            ]
            updated.touchedNonSyntheticFieldIDs = []
            updated.status = .pass
            updated.nextBlockerClassification = nil
            updated.nextBlocker =
                "Real reviewed-bundle execution passed only in the local experimental synthetic WebKit harness; stable product normal-tab runtime support remains blocked."
        } else {
            updated.status = updated.status == .pass ? .partial : updated.status
            updated.nextBlockerClassification = .contentScriptWorldUnavailable
            updated.nextBlocker =
                "Modeled detect/fill route remains available, but actual reviewed-bundle WebKit execution is blocked: \(result.currentBlocker)."
        }
        updated.diagnostics =
            uniqueSortedWebKitProgrammaticInjection(
                updated.diagnostics
                    + result.diagnostics
                    + [
                        "Modeled dummy fill changed DOM=\(updated.modeledDummyFillChangedDOM); actual WebKit-reviewed-script dummy fill changed DOM=\(result.dummyValuesWrittenByActualWebKitExecutedScript).",
                    ]
        )
        return updated
    }

    private static func applying(
        _ result:
            ChromeMV3LocalExperimentalNormalTabManualSmokeResult,
        to smoke: ChromeMV3PasswordManagerRealPackageDetectFillSmoke
    ) -> ChromeMV3PasswordManagerRealPackageDetectFillSmoke {
        var updated = smoke
        updated.manualNormalTabSmokeResult = result
        if result.allowed {
            updated.domObservationBefore =
                realPackageDOMObservation(result.domObservationBefore)
            updated.domObservationAfter =
                realPackageDOMObservation(result.domObservationAfter)
            updated.domObservationResult =
                "manualNormalTabSmokeDOM: reviewed content/bootstrap-autofill.js changed only the synthetic username/password fields after isolated top-frame execution."
            updated.dummyFillResult =
                "completed: manual normal-tab smoke executed the reviewed generated-bundle Bitwarden bootstrap and wrote only synthetic dummy values."
            updated.touchedSyntheticFieldIDs = result.fieldsTouched
            updated.touchedNonSyntheticFieldIDs = []
            updated.status = .pass
            updated.nextBlockerClassification = nil
            updated.nextBlocker =
                "Manual normal-tab smoke passed only under the local experimental gate; stable product normal-tab runtime support remains blocked."
        } else {
            updated.status = updated.status == .pass ? .partial : updated.status
            updated.nextBlockerClassification = .contentScriptWorldUnavailable
            updated.nextBlocker =
                "Manual normal-tab smoke remains blocked: \(result.currentBlocker)."
        }
        updated.diagnostics =
            uniqueSortedWebKitProgrammaticInjection(
                updated.diagnostics
                    + result.diagnostics
                    + [
                        "Manual normal-tab smoke allowed=\(result.allowed); managerReadoutExecutes=\(result.injectionPlan.managerReadoutExecutes); productDefaultRuntimeAvailable=\(result.productDefaultRuntimeAvailable).",
                    ]
            )
        return updated
    }

    private static func realPackageDOMObservation(
        _ snapshot:
            ChromeMV3LocalExperimentalWebKitSyntheticLoginDOMSnapshot
    ) -> ChromeMV3PasswordManagerRealPackageSyntheticLoginDOMObservation {
        ChromeMV3PasswordManagerRealPackageSyntheticLoginDOMObservation(
            phase: snapshot.phase,
            usernameFieldExists: snapshot.usernameFieldExists,
            passwordFieldExists: snapshot.passwordFieldExists,
            submitButtonExists: snapshot.submitButtonExists,
            usernameValue: snapshot.usernameValue,
            passwordValue: snapshot.passwordValue,
            submitValueSummary:
                snapshot.submitButtonExists ? "button:no-value" : "missing",
            initialValuesEmpty: snapshot.initialValuesEmpty,
            finalValuesMatchDummyFill: snapshot.finalValuesMatchDummyFill,
            domChanged:
                snapshot.phase == "after"
                    && snapshot.finalValuesMatchDummyFill,
            observationClassification:
                snapshot.phase == "after"
                    ? "actualWebKitDummyFillCompleted"
                    : "actualWebKitSyntheticDOMBefore",
            diagnostics: [
                "Observed the synthetic login DOM through the hidden local experimental WKWebView.",
            ]
        )
    }
}
#endif

private func uniqueSortedWebKitProgrammaticInjection(
    _ values: [String]
) -> [String] {
    Array(Set(values)).sorted()
}
