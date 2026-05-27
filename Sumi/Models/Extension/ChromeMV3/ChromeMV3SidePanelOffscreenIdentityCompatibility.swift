//
//  ChromeMV3SidePanelOffscreenIdentityCompatibility.swift
//  Sumi
//
//  DEBUG/internal Chrome MV3 sidePanel, offscreen, and identity compatibility
//  diagnostics. This layer models manifest/API compatibility, synthetic state,
//  and deterministic bridge responses only. It does not expose product side
//  panel UI, create product hidden offscreen documents, run OAuth UI/network
//  flows, attach to normal tabs, wake service workers, or make runtimeLoadable
//  true.
//

import CryptoKit
import Foundation

enum ChromeMV3SidePanelOffscreenIdentitySupportStatus:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case deferred
    case internalSyntheticOnly
    case productBlocked
    case productUIUnavailable
    case syntheticFixtureOnly
    case unsupported

    static func < (
        lhs: ChromeMV3SidePanelOffscreenIdentitySupportStatus,
        rhs: ChromeMV3SidePanelOffscreenIdentitySupportStatus
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3SidePanelOffscreenIdentityMethodCoverage:
    Codable,
    Equatable,
    Sendable
{
    var namespace: String
    var methodName: String
    var supportStatus:
        ChromeMV3SidePanelOffscreenIdentitySupportStatus
    var modelCoverageAvailable: Bool
    var bridgeCoverageAvailable: Bool
    var availableInInternalFixture: Bool
    var availableInProduct: Bool
    var callbackModeModeled: Bool
    var promiseModeModeled: Bool
    var lastErrorModeled: Bool
    var webKitSyntheticJSCallbackExecuted: Bool
    var webKitSyntheticJSPromiseExecuted: Bool
    var webKitSyntheticJSLastErrorVerified: Bool
    var diagnostics: [String]
}

struct ChromeMV3SidePanelOffscreenIdentityAPIDetectionSummary:
    Codable,
    Equatable,
    Sendable
{
    var sidePanelDeclaredByManifestKey: Bool
    var sidePanelPermissionDeclared: Bool
    var sidePanelDefaultPath: String?
    var sidePanelAPIUsedInSource: Bool
    var sidePanelAPIUsePaths: [String]
    var offscreenPermissionDeclared: Bool
    var offscreenAPIUsedInSource: Bool
    var offscreenAPIUsePaths: [String]
    var identityPermissionDeclared: Bool
    var identityEmailPermissionDeclared: Bool
    var identityOAuth2ManifestDeclared: Bool
    var identityOAuth2Scopes: [String]
    var identityAPIUsedInSource: Bool
    var identityAPIUsePaths: [String]
    var diagnostics: [String]
}

struct ChromeMV3SidePanelSyntheticHostDiagnostics:
    Codable,
    Equatable,
    Sendable
{
    var defaultPathResolved: Bool
    var defaultPathResourceSafe: Bool
    var syntheticHiddenHostAllowedByPolicy: Bool
    var syntheticHiddenHostAttempted: Bool
    var syntheticHiddenHostLoaded: Bool
    var oneShotInspectionAttempted: Bool
    var outcome: String
    var blockingReasons: [String]
    var diagnostics: [String]
}

struct ChromeMV3SidePanelManifestResourceSummary:
    Codable,
    Equatable,
    Sendable
{
    var declaredByManifestKey: Bool
    var permissionDeclared: Bool
    var defaultPath: String?
    var pageDeclaration:
        ChromeMV3ExtensionPageDeclaration?
    var resourceResolution:
        ChromeMV3ExtensionPageResourceResolution?
    var fixturePolicy:
        ChromeMV3ExtensionPageFixturePolicyResult?
    var syntheticHostDiagnostics:
        ChromeMV3SidePanelSyntheticHostDiagnostics
    var missingPageDiagnosed: Bool
    var unsafePathDiagnosed: Bool
    var nonHTMLResourceDiagnosed: Bool
    var remoteResourceDependencyDiagnosed: Bool
    var sidePanelAvailableInInternalFixture: Bool
    var sidePanelAvailableInProduct: Bool
    var productUIBlocked: Bool
    var blockingReasons: [String]
}

enum ChromeMV3OffscreenReason:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case testing = "TESTING"
    case audioPlayback = "AUDIO_PLAYBACK"
    case iframeScripting = "IFRAME_SCRIPTING"
    case domScraping = "DOM_SCRAPING"
    case blobs = "BLOBS"
    case domParser = "DOM_PARSER"
    case userMedia = "USER_MEDIA"
    case displayMedia = "DISPLAY_MEDIA"
    case webRTC = "WEB_RTC"
    case clipboard = "CLIPBOARD"
    case localStorage = "LOCAL_STORAGE"
    case workers = "WORKERS"
    case batteryStatus = "BATTERY_STATUS"
    case matchMedia = "MATCH_MEDIA"
    case geolocation = "GEOLOCATION"

    static func < (
        lhs: ChromeMV3OffscreenReason,
        rhs: ChromeMV3OffscreenReason
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var supportStatus:
        ChromeMV3SidePanelOffscreenIdentitySupportStatus
    {
        switch self {
        case .testing, .blobs, .domParser, .localStorage, .matchMedia:
            return .internalSyntheticOnly
        case .audioPlayback:
            return .deferred
        case .iframeScripting, .domScraping, .userMedia, .displayMedia,
             .webRTC, .clipboard, .workers, .geolocation:
            return .productBlocked
        case .batteryStatus:
            return .unsupported
        }
    }
}

struct ChromeMV3OffscreenReasonSupport:
    Codable,
    Equatable,
    Sendable
{
    var rawReason: String
    var recognizedByChromeDocs: Bool
    var supportStatus:
        ChromeMV3SidePanelOffscreenIdentitySupportStatus
    var canCreateModelOnlyDocument: Bool
    var productOffscreenRuntimeAvailable: Bool
    var diagnostics: [String]
}

enum ChromeMV3OffscreenDocumentLifecycleState:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case absent
    case blocked
    case closed
    case modelOnlyCreated

    static func < (
        lhs: ChromeMV3OffscreenDocumentLifecycleState,
        rhs: ChromeMV3OffscreenDocumentLifecycleState
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3OffscreenDocumentRecord:
    Codable,
    Equatable,
    Sendable
{
    var sequence: Int
    var extensionID: String
    var profileID: String
    var requestedURL: String
    var normalizedPath: String?
    var generatedResourcePath: String?
    var resourceExists: Bool
    var reasons: [ChromeMV3OffscreenReasonSupport]
    var justification: String
    var lifecycleState: ChromeMV3OffscreenDocumentLifecycleState
    var createdAsModelOnly: Bool
    var createdInInternalSyntheticHost: Bool
    var productHiddenWebViewCreated: Bool
    var diagnostics: [String]
}

struct ChromeMV3OffscreenLifecycleSummary:
    Codable,
    Equatable,
    Sendable
{
    var activeDocument:
        ChromeMV3OffscreenDocumentRecord?
    var lastClosedDocument:
        ChromeMV3OffscreenDocumentRecord?
    var requestedDocumentCount: Int
    var modelOnlyCreatedDocumentCount: Int
    var closedDocumentCount: Int
    var hasDocumentResult: Bool
    var productHiddenWebViewRuntimeCreated: Bool
    var serviceWorkerWakeCount: Int
    var recurringWorkCreated: Bool
    var diagnostics: [String]
}

struct ChromeMV3IdentityManifestSummary:
    Codable,
    Equatable,
    Sendable
{
    var identityPermissionDeclared: Bool
    var identityEmailPermissionDeclared: Bool
    var oauth2ManifestDeclared: Bool
    var oauth2ClientIDPresent: Bool
    var oauth2Scopes: [String]
    var identityAvailableInInternalFixture: Bool
    var identityAvailableInProduct: Bool
    var identityExternalAuthNetworkAllowed: Bool
    var diagnostics: [String]
}

struct ChromeMV3IdentitySyntheticFixture:
    Codable,
    Equatable,
    Sendable
{
    var configuredForTestOnly: Bool
    var authFlowRedirectURL: String?
    var authToken: String?
    var grantedScopes: [String]
    var accountID: String?

    static let none = ChromeMV3IdentitySyntheticFixture(
        configuredForTestOnly: false,
        authFlowRedirectURL: nil,
        authToken: nil,
        grantedScopes: [],
        accountID: nil
    )

    static func testOnly(
        authFlowRedirectURL: String? = nil,
        authToken: String? = nil,
        grantedScopes: [String] = [],
        accountID: String? = nil
    ) -> ChromeMV3IdentitySyntheticFixture {
        ChromeMV3IdentitySyntheticFixture(
            configuredForTestOnly: true,
            authFlowRedirectURL: authFlowRedirectURL,
            authToken: authToken,
            grantedScopes: grantedScopes.sorted(),
            accountID: accountID
        )
    }
}

struct ChromeMV3IdentitySyntheticFixtureStatus:
    Codable,
    Equatable,
    Sendable
{
    var configuredForTestOnly: Bool
    var authFlowResponseConfigured: Bool
    var authTokenConfigured: Bool
    var grantedScopes: [String]
    var accountIDConfigured: Bool
    var tokenValueStoredInReport: Bool
    var externalAuthNetworkAllowed: Bool
    var diagnostics: [String]
}

struct ChromeMV3SidePanelOptions:
    Codable,
    Equatable,
    Sendable
{
    var tabID: Int?
    var path: String?
    var enabled: Bool

    var storageValue: ChromeMV3StorageValue {
        var object: [String: ChromeMV3StorageValue] = [
            "enabled": .bool(enabled),
        ]
        if let tabID {
            object["tabId"] = .number(Double(tabID))
        }
        if let path {
            object["path"] = .string(path)
        }
        return .object(object)
    }
}

struct ChromeMV3SidePanelBehavior:
    Codable,
    Equatable,
    Sendable
{
    var openPanelOnActionClick: Bool

    var storageValue: ChromeMV3StorageValue {
        .object([
            "openPanelOnActionClick": .bool(openPanelOnActionClick),
        ])
    }
}

struct ChromeMV3SidePanelOffscreenIdentityConfiguration:
    Codable,
    Equatable,
    Sendable
{
    var extensionID: String
    var profileID: String
    var generatedBundleRootPath: String?
    var defaultSidePanelPath: String?
    var moduleState: ChromeMV3ProfileHostModuleState
    var explicitInternalCompatibilityBridgeAllowed: Bool
    var explicitSyntheticSidePanelHostConfigured: Bool
    var explicitSyntheticOffscreenHostConfigured: Bool
    var sidePanelAvailableInInternalFixture: Bool
    var sidePanelAvailableInProduct: Bool
    var offscreenAvailableInInternalFixture: Bool
    var offscreenAvailableInProduct: Bool
    var identityAvailableInInternalFixture: Bool
    var identityAvailableInProduct: Bool
    var identityExternalAuthNetworkAllowed: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
    var productRuntimeExposed: Bool
    var syntheticIdentityFixture:
        ChromeMV3IdentitySyntheticFixture
    var diagnostics: [String]

    static func syntheticHarness(
        extensionID: String = "sidepanel-offscreen-identity-extension",
        profileID: String = "sidepanel-offscreen-identity-profile",
        generatedBundleRootPath: String? = nil,
        defaultSidePanelPath: String? = nil,
        moduleState: ChromeMV3ProfileHostModuleState = .enabled,
        explicitInternalCompatibilityBridgeAllowed: Bool = true,
        explicitSyntheticSidePanelHostConfigured: Bool = false,
        explicitSyntheticOffscreenHostConfigured: Bool = false,
        syntheticIdentityFixture:
            ChromeMV3IdentitySyntheticFixture = .none
    ) -> ChromeMV3SidePanelOffscreenIdentityConfiguration {
        let enabled = moduleState == .enabled
            && explicitInternalCompatibilityBridgeAllowed
        return ChromeMV3SidePanelOffscreenIdentityConfiguration(
            extensionID: normalizedSOI(
                extensionID,
                fallback: "sidepanel-offscreen-identity-extension"
            ),
            profileID: normalizedSOI(
                profileID,
                fallback: "sidepanel-offscreen-identity-profile"
            ),
            generatedBundleRootPath:
                generatedBundleRootPath.map {
                    URL(fileURLWithPath: $0, isDirectory: true)
                        .standardizedFileURL.path
                },
            defaultSidePanelPath: defaultSidePanelPath,
            moduleState: moduleState,
            explicitInternalCompatibilityBridgeAllowed:
                explicitInternalCompatibilityBridgeAllowed,
            explicitSyntheticSidePanelHostConfigured:
                explicitSyntheticSidePanelHostConfigured,
            explicitSyntheticOffscreenHostConfigured:
                explicitSyntheticOffscreenHostConfigured,
            sidePanelAvailableInInternalFixture: enabled,
            sidePanelAvailableInProduct: false,
            offscreenAvailableInInternalFixture: enabled,
            offscreenAvailableInProduct: false,
            identityAvailableInInternalFixture: enabled,
            identityAvailableInProduct: false,
            identityExternalAuthNetworkAllowed: false,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false,
            productRuntimeExposed: false,
            syntheticIdentityFixture: syntheticIdentityFixture,
            diagnostics: uniqueSortedSOI([
                "sidePanel/offscreen/identity compatibility bridge is DEBUG/internal and synthetic only.",
                "Product side panel UI is unavailable.",
                "Product offscreen hidden document runtime is unavailable.",
                "Identity external auth network and OAuth UI are unavailable.",
                "Product normal-tab runtime bridge remains unavailable.",
                "runtimeLoadable remains false.",
            ])
        )
    }
}

struct ChromeMV3SidePanelOffscreenIdentityBridgeRequest:
    Codable,
    Equatable,
    Sendable
{
    var bridgeCallID: String
    var namespace: String
    var methodName: String
    var invocationMode: ChromeMV3JSBridgeInvocationMode
    var arguments: [ChromeMV3StorageValue]
    var diagnostics: [String]

    init(
        bridgeCallID: String? = nil,
        namespace: String,
        methodName: String,
        invocationMode: ChromeMV3JSBridgeInvocationMode = .promise,
        arguments: [ChromeMV3StorageValue] = [],
        diagnostics: [String] = []
    ) {
        self.namespace = namespace
        self.methodName = methodName
        self.invocationMode = invocationMode
        self.arguments = arguments
        self.bridgeCallID =
            bridgeCallID
            ?? stableIDSOI(
                prefix: "soi-bridge-call",
                parts: [
                    namespace,
                    methodName,
                    invocationMode.rawValue,
                    arguments.map {
                        (try? $0.canonicalJSONString()) ?? "argument"
                    }.joined(separator: "|"),
                ]
            )
        self.diagnostics = uniqueSortedSOI(diagnostics)
    }

    init(envelope: ChromeMV3JSBridgeRequestEnvelope) {
        self.init(
            bridgeCallID: envelope.bridgeCallID,
            namespace: envelope.namespace.rawValue,
            methodName: envelope.methodName,
            invocationMode: envelope.invocationMode,
            arguments: envelope.rawArguments,
            diagnostics: [
                "Request originated from the generic Chrome MV3 JS bridge contract.",
            ]
        )
    }
}

struct ChromeMV3SidePanelOffscreenIdentityBridgeResponse:
    Codable,
    Equatable,
    Sendable
{
    var bridgeCallID: String
    var namespace: String
    var methodName: String
    var invocationMode: ChromeMV3JSBridgeInvocationMode
    var succeeded: Bool
    var resultPayload: ChromeMV3StorageValue?
    var lastErrorMessage: String?
    var lastErrorCode: String?
    var callbackWouldSetLastError: Bool
    var promiseWouldReject: Bool
    var sidePanelAvailableInInternalFixture: Bool
    var sidePanelAvailableInProduct: Bool
    var offscreenAvailableInInternalFixture: Bool
    var offscreenAvailableInProduct: Bool
    var identityAvailableInInternalFixture: Bool
    var identityAvailableInProduct: Bool
    var identityExternalAuthNetworkAllowed: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
    var productRuntimeExposed: Bool
    var diagnostics: [String]

    var foundationObject: [String: Any] {
        [
            "bridgeCallID": bridgeCallID,
            "namespace": namespace,
            "methodName": methodName,
            "invocationMode": invocationMode.rawValue,
            "succeeded": succeeded,
            "resultPayload":
                resultPayload?.sidePanelOffscreenIdentityFoundationObject
                ?? NSNull(),
            "lastErrorMessage": lastErrorMessage ?? NSNull(),
            "lastErrorCode": lastErrorCode ?? NSNull(),
            "callbackWouldSetLastError": callbackWouldSetLastError,
            "promiseWouldReject": promiseWouldReject,
            "sidePanelAvailableInInternalFixture":
                sidePanelAvailableInInternalFixture,
            "sidePanelAvailableInProduct": sidePanelAvailableInProduct,
            "offscreenAvailableInInternalFixture":
                offscreenAvailableInInternalFixture,
            "offscreenAvailableInProduct": offscreenAvailableInProduct,
            "identityAvailableInInternalFixture":
                identityAvailableInInternalFixture,
            "identityAvailableInProduct": identityAvailableInProduct,
            "identityExternalAuthNetworkAllowed":
                identityExternalAuthNetworkAllowed,
            "normalTabRuntimeBridgeAvailable":
                normalTabRuntimeBridgeAvailable,
            "runtimeLoadable": runtimeLoadable,
            "productRuntimeExposed": productRuntimeExposed,
            "diagnostics": diagnostics,
        ]
    }
}

struct ChromeMV3SidePanelOffscreenIdentityRuntimeStateOwner: Sendable {
    let configuration: ChromeMV3SidePanelOffscreenIdentityConfiguration
    private var defaultSidePanelOptions: ChromeMV3SidePanelOptions
    private var tabSidePanelOptions: [Int: ChromeMV3SidePanelOptions] = [:]
    private var panelBehavior =
        ChromeMV3SidePanelBehavior(openPanelOnActionClick: false)
    private(set) var activeOffscreenDocument:
        ChromeMV3OffscreenDocumentRecord?
    private(set) var lastClosedOffscreenDocument:
        ChromeMV3OffscreenDocumentRecord?
    private var requestedOffscreenDocumentCount = 0
    private var modelOnlyOffscreenDocumentCount = 0
    private var closedOffscreenDocumentCount = 0
    private var nextOffscreenSequence = 1
    private var syntheticAuthTokenCache: String?

    init(configuration: ChromeMV3SidePanelOffscreenIdentityConfiguration) {
        self.configuration = configuration
        self.defaultSidePanelOptions = ChromeMV3SidePanelOptions(
            tabID: nil,
            path: configuration.defaultSidePanelPath,
            enabled: true
        )
        self.syntheticAuthTokenCache =
            configuration.syntheticIdentityFixture.configuredForTestOnly
                ? configuration.syntheticIdentityFixture.authToken
                : nil
    }

    var offscreenLifecycleSummary:
        ChromeMV3OffscreenLifecycleSummary
    {
        ChromeMV3OffscreenLifecycleSummary(
            activeDocument: activeOffscreenDocument,
            lastClosedDocument: lastClosedOffscreenDocument,
            requestedDocumentCount: requestedOffscreenDocumentCount,
            modelOnlyCreatedDocumentCount: modelOnlyOffscreenDocumentCount,
            closedDocumentCount: closedOffscreenDocumentCount,
            hasDocumentResult: activeOffscreenDocument != nil,
            productHiddenWebViewRuntimeCreated: false,
            serviceWorkerWakeCount: 0,
            recurringWorkCreated: false,
            diagnostics: [
                "Offscreen lifecycle is model-only.",
                "No product hidden WebView, service-worker wake, or recurring work is created.",
            ]
        )
    }

    var sidePanelBehaviorSummary: ChromeMV3SidePanelBehavior {
        panelBehavior
    }

    mutating func handle(
        _ request: ChromeMV3SidePanelOffscreenIdentityBridgeRequest
    ) -> ChromeMV3SidePanelOffscreenIdentityBridgeResponse {
        guard configuration.moduleState == .enabled,
              configuration.explicitInternalCompatibilityBridgeAllowed
        else {
            return failure(
                request,
                code: .extensionDisabled,
                diagnostics: [
                    "sidePanel/offscreen/identity bridge is blocked because the extensions module or explicit internal gate is disabled.",
                ]
            )
        }

        switch request.namespace {
        case "sidePanel":
            return handleSidePanel(request)
        case "offscreen":
            return handleOffscreen(request)
        case "identity":
            return handleIdentity(request)
        default:
            return failure(
                request,
                code: .namespaceUnsupported,
                diagnostics: [
                    "Unsupported compatibility namespace: \(request.namespace).",
                ]
            )
        }
    }

    private mutating func handleSidePanel(
        _ request: ChromeMV3SidePanelOffscreenIdentityBridgeRequest
    ) -> ChromeMV3SidePanelOffscreenIdentityBridgeResponse {
        guard configuration.sidePanelAvailableInInternalFixture else {
            return failure(
                request,
                code: .productBlocked,
                diagnostics: [
                    "sidePanel compatibility bridge is not available in this internal fixture.",
                ]
            )
        }

        switch request.methodName {
        case "setOptions":
            guard request.arguments.count == 1,
                  let object = request.arguments[0].soiObjectValue
            else {
                return invalidArguments(
                    request,
                    "sidePanel.setOptions requires one options object."
                )
            }
            let tabID = object["tabId"]?.soiIntValue
            if object["tabId"] != nil, tabID == nil {
                return invalidArguments(
                    request,
                    "sidePanel.setOptions tabId must be an integer."
                )
            }
            let path = object["path"]?.soiStringValue
            if object["path"] != nil, path == nil {
                return invalidArguments(
                    request,
                    "sidePanel.setOptions path must be a string."
                )
            }
            if let path,
               let blocker = validateExtensionHTMLPath(path)
            {
                return invalidArguments(request, blocker)
            }
            let enabled = object["enabled"]?.soiBoolValue
                ?? (tabID.flatMap { tabSidePanelOptions[$0]?.enabled }
                    ?? defaultSidePanelOptions.enabled)
            if object["enabled"] != nil,
               object["enabled"]?.soiBoolValue == nil
            {
                return invalidArguments(
                    request,
                    "sidePanel.setOptions enabled must be a boolean."
                )
            }
            let options = ChromeMV3SidePanelOptions(
                tabID: tabID,
                path:
                    path
                    ?? (tabID.flatMap { tabSidePanelOptions[$0]?.path }
                        ?? defaultSidePanelOptions.path),
                enabled: enabled
            )
            if let tabID {
                tabSidePanelOptions[tabID] = options
            } else {
                defaultSidePanelOptions = options
            }
            return success(
                request,
                payload: .null,
                diagnostics: [
                    "sidePanel.setOptions mutated internal synthetic side panel state.",
                    "Product side panel UI remains unavailable.",
                ]
            )
        case "getOptions":
            guard request.arguments.count <= 1 else {
                return invalidArguments(
                    request,
                    "sidePanel.getOptions accepts at most one options object."
                )
            }
            let object = request.arguments.first?.soiObjectValue
            if request.arguments.isEmpty == false, object == nil {
                return invalidArguments(
                    request,
                    "sidePanel.getOptions options must be an object."
                )
            }
            let tabID = object?["tabId"]?.soiIntValue
            if object?["tabId"] != nil, tabID == nil {
                return invalidArguments(
                    request,
                    "sidePanel.getOptions tabId must be an integer."
                )
            }
            let options =
                tabID.flatMap { tabSidePanelOptions[$0] }
                ?? defaultSidePanelOptions
            return success(
                request,
                payload: options.storageValue,
                diagnostics: [
                    "sidePanel.getOptions returned internal synthetic side panel state.",
                ]
            )
        case "setPanelBehavior":
            guard request.arguments.count == 1,
                  let object = request.arguments[0].soiObjectValue
            else {
                return invalidArguments(
                    request,
                    "sidePanel.setPanelBehavior requires one behavior object."
                )
            }
            if object["openPanelOnActionClick"] != nil,
               object["openPanelOnActionClick"]?.soiBoolValue == nil
            {
                return invalidArguments(
                    request,
                    "sidePanel.setPanelBehavior openPanelOnActionClick must be a boolean."
                )
            }
            panelBehavior = ChromeMV3SidePanelBehavior(
                openPanelOnActionClick:
                    object["openPanelOnActionClick"]?.soiBoolValue ?? false
            )
            return success(
                request,
                payload: .null,
                diagnostics: [
                    "sidePanel.setPanelBehavior mutated internal synthetic behavior state.",
                    "Product action-click side panel behavior remains unavailable.",
                ]
            )
        case "open":
            guard request.arguments.count == 1,
                  let object = request.arguments[0].soiObjectValue
            else {
                return invalidArguments(
                    request,
                    "sidePanel.open requires one OpenOptions object."
                )
            }
            let tabID = object["tabId"]?.soiIntValue
            let windowID = object["windowId"]?.soiIntValue
            if object["tabId"] != nil, tabID == nil {
                return invalidArguments(
                    request,
                    "sidePanel.open tabId must be an integer."
                )
            }
            if object["windowId"] != nil, windowID == nil {
                return invalidArguments(
                    request,
                    "sidePanel.open windowId must be an integer."
                )
            }
            guard tabID != nil || windowID != nil else {
                return invalidArguments(
                    request,
                    "sidePanel.open requires tabId or windowId."
                )
            }
            guard configuration.explicitSyntheticSidePanelHostConfigured else {
                return failure(
                    request,
                    code: .productUIUnavailable,
                    payload: .object([
                        "sidePanelAvailableInProduct": .bool(false),
                        "syntheticHostConfigured": .bool(false),
                    ]),
                    diagnostics: [
                        "sidePanel.open requires product side panel UI in Chrome.",
                        "Sumi product side panel UI is blocked.",
                        "No explicit internal synthetic sidePanel host was configured.",
                    ]
                )
            }
            return success(
                request,
                payload: .object([
                    "openedInInternalSyntheticHost": .bool(true),
                    "sidePanelAvailableInProduct": .bool(false),
                ]),
                diagnostics: [
                    "sidePanel.open was satisfied only by an explicit internal synthetic host fixture.",
                    "Product side panel UI remains unavailable.",
                ]
            )
        default:
            return failure(
                request,
                code: .methodUnsupported,
                diagnostics: ["Unsupported sidePanel method."]
            )
        }
    }

    private mutating func handleOffscreen(
        _ request: ChromeMV3SidePanelOffscreenIdentityBridgeRequest
    ) -> ChromeMV3SidePanelOffscreenIdentityBridgeResponse {
        guard configuration.offscreenAvailableInInternalFixture else {
            return failure(
                request,
                code: .offscreenProductRuntimeBlocked,
                diagnostics: [
                    "offscreen compatibility bridge is not available in this internal fixture.",
                ]
            )
        }

        switch request.methodName {
        case "createDocument":
            requestedOffscreenDocumentCount += 1
            guard request.arguments.count == 1,
                  let object = request.arguments[0].soiObjectValue
            else {
                return invalidArguments(
                    request,
                    "offscreen.createDocument requires one parameters object."
                )
            }
            guard let rawURL = object["url"]?.soiStringValue,
                  rawURL.isEmpty == false
            else {
                return invalidArguments(
                    request,
                    "offscreen.createDocument requires a url string."
                )
            }
            if let blocker = validateExtensionHTMLPath(rawURL) {
                return invalidArguments(request, blocker)
            }
            guard case .array(let reasonValues)? = object["reasons"],
                  reasonValues.isEmpty == false
            else {
                return invalidArguments(
                    request,
                    "offscreen.createDocument requires a non-empty reasons array."
                )
            }
            let rawReasons = reasonValues.compactMap(\.soiStringValue)
            guard rawReasons.count == reasonValues.count else {
                return invalidArguments(
                    request,
                    "offscreen.createDocument reasons entries must be strings."
                )
            }
            let reasonSupport = rawReasons.map(Self.reasonSupport)
            if let unsupported = reasonSupport.first(where: {
                $0.supportStatus == .unsupported
            }) {
                activeOffscreenDocument = blockedDocument(
                    rawURL: rawURL,
                    reasons: reasonSupport,
                    justification: object["justification"]?.soiStringValue ?? "",
                    diagnostic:
                        "Unsupported offscreen reason: \(unsupported.rawReason)."
                )
                return invalidArguments(
                    request,
                    "Unsupported offscreen reason: \(unsupported.rawReason)."
                )
            }
            guard let justification = object["justification"]?.soiStringValue,
                  justification.trimmingCharacters(
                    in: .whitespacesAndNewlines
                  ).isEmpty == false
            else {
                return invalidArguments(
                    request,
                    "offscreen.createDocument requires a non-empty justification string."
                )
            }
            if let blocked = reasonSupport.first(where: {
                $0.supportStatus == .productBlocked
                    || $0.supportStatus == .deferred
            }) {
                activeOffscreenDocument = blockedDocument(
                    rawURL: rawURL,
                    reasons: reasonSupport,
                    justification: justification,
                    diagnostic:
                        "offscreen reason \(blocked.rawReason) is \(blocked.supportStatus.rawValue)."
                )
                let code: ChromeMV3JSBridgeErrorCode =
                    blocked.supportStatus == .deferred
                    ? .productBlocked
                    : .offscreenProductRuntimeBlocked
                return failure(
                    request,
                    code: code,
                    diagnostics: [
                        "offscreen.createDocument request was validated but blocked by reason \(blocked.rawReason).",
                        "No product hidden offscreen document runtime was created.",
                    ]
                )
            }
            guard activeOffscreenDocument == nil
                || activeOffscreenDocument?.lifecycleState == .blocked
            else {
                return invalidArguments(
                    request,
                    "Only one offscreen document may be active in this model."
                )
            }

            let record = documentRecord(
                rawURL: rawURL,
                reasons: reasonSupport,
                justification: justification,
                state: .modelOnlyCreated,
                createdAsModelOnly: true
            )
            activeOffscreenDocument = record
            modelOnlyOffscreenDocumentCount += 1
            return success(
                request,
                payload: .null,
                diagnostics: [
                    "offscreen.createDocument created model-only document state.",
                    "No product hidden offscreen WebView was created.",
                ]
            )
        case "hasDocument":
            guard request.arguments.isEmpty else {
                return invalidArguments(
                    request,
                    "offscreen.hasDocument takes no arguments."
                )
            }
            return success(
                request,
                payload: .bool(
                    activeOffscreenDocument?.lifecycleState
                        == .modelOnlyCreated
                ),
                diagnostics: [
                    "offscreen.hasDocument returned model-only lifecycle state.",
                ]
            )
        case "closeDocument":
            guard request.arguments.isEmpty else {
                return invalidArguments(
                    request,
                    "offscreen.closeDocument takes no arguments."
                )
            }
            if var active = activeOffscreenDocument {
                active.lifecycleState = .closed
                lastClosedOffscreenDocument = active
                closedOffscreenDocumentCount += 1
            }
            activeOffscreenDocument = nil
            return success(
                request,
                payload: .null,
                diagnostics: [
                    "offscreen.closeDocument cleared model-only document state.",
                ]
            )
        default:
            return failure(
                request,
                code: .methodUnsupported,
                diagnostics: ["Unsupported offscreen method."]
            )
        }
    }

    private mutating func handleIdentity(
        _ request: ChromeMV3SidePanelOffscreenIdentityBridgeRequest
    ) -> ChromeMV3SidePanelOffscreenIdentityBridgeResponse {
        guard configuration.identityAvailableInInternalFixture else {
            return failure(
                request,
                code: .productBlocked,
                diagnostics: [
                    "identity compatibility bridge is not available in this internal fixture.",
                ]
            )
        }

        switch request.methodName {
        case "getRedirectURL":
            guard request.arguments.count <= 1 else {
                return invalidArguments(
                    request,
                    "identity.getRedirectURL accepts at most one path string."
                )
            }
            let path = request.arguments.first?.soiStringValue
            if request.arguments.isEmpty == false, path == nil {
                return invalidArguments(
                    request,
                    "identity.getRedirectURL path must be a string."
                )
            }
            return success(
                request,
                payload: .string(redirectURL(path: path)),
                diagnostics: [
                    "identity.getRedirectURL returned a deterministic synthetic chromiumapp.org URL.",
                    "No external auth network was used.",
                ]
            )
        case "launchWebAuthFlow":
            guard request.arguments.count == 1,
                  let object = request.arguments[0].soiObjectValue
            else {
                return invalidArguments(
                    request,
                    "identity.launchWebAuthFlow requires one details object."
                )
            }
            guard object["url"]?.soiStringValue?.isEmpty == false else {
                return invalidArguments(
                    request,
                    "identity.launchWebAuthFlow requires a url string."
                )
            }
            guard configuration.syntheticIdentityFixture.configuredForTestOnly,
                  let redirect =
                    configuration.syntheticIdentityFixture.authFlowRedirectURL
            else {
                return failure(
                    request,
                    code: .syntheticFixtureUnavailable,
                    payload: .object([
                        "identityAvailableInProduct": .bool(false),
                        "identityExternalAuthNetworkAllowed": .bool(false),
                    ]),
                    diagnostics: [
                        "identity.launchWebAuthFlow is blocked because no explicit synthetic auth flow response is configured.",
                        "Product OAuth UI and external auth network are unavailable.",
                    ]
                )
            }
            return success(
                request,
                payload: .string(redirect),
                diagnostics: [
                    "identity.launchWebAuthFlow returned an explicit test-only synthetic redirect URL.",
                    "No external auth network was used.",
                ]
            )
        case "getAuthToken":
            guard request.arguments.count <= 1 else {
                return invalidArguments(
                    request,
                    "identity.getAuthToken accepts at most one details object."
                )
            }
            let object = request.arguments.first?.soiObjectValue
            if request.arguments.isEmpty == false, object == nil {
                return invalidArguments(
                    request,
                    "identity.getAuthToken details must be an object."
                )
            }
            guard configuration.syntheticIdentityFixture.configuredForTestOnly,
                  let token = syntheticAuthTokenCache
            else {
                return failure(
                    request,
                    code: .syntheticFixtureUnavailable,
                    payload: .object([
                        "identityAvailableInProduct": .bool(false),
                        "identityExternalAuthNetworkAllowed": .bool(false),
                    ]),
                    diagnostics: [
                        "identity.getAuthToken is blocked because no explicit synthetic token fixture is configured.",
                        "No real token cache, account provider, or external auth network is used.",
                    ]
                )
            }
            let requestedScopes =
                stringArray(object?["scopes"])
            let scopes = requestedScopes.isEmpty
                ? configuration.syntheticIdentityFixture.grantedScopes
                : requestedScopes
            return success(
                request,
                payload: .object([
                    "token": .string(token),
                    "grantedScopes":
                        .array(scopes.map(ChromeMV3StorageValue.string)),
                ]),
                diagnostics: [
                    "identity.getAuthToken returned only an explicit test-only synthetic token fixture.",
                    "No real token was stored by the compatibility layer.",
                ]
            )
        case "removeCachedAuthToken":
            guard request.arguments.count == 1,
                  let object = request.arguments[0].soiObjectValue,
                  let token = object["token"]?.soiStringValue,
                  token.isEmpty == false
            else {
                return invalidArguments(
                    request,
                    "identity.removeCachedAuthToken requires a token string."
                )
            }
            if syntheticAuthTokenCache == token {
                syntheticAuthTokenCache = nil
            }
            return success(
                request,
                payload: .null,
                diagnostics: [
                    "identity.removeCachedAuthToken cleared only matching synthetic in-memory fixture state.",
                ]
            )
        case "clearAllCachedAuthTokens":
            guard request.arguments.isEmpty else {
                return invalidArguments(
                    request,
                    "identity.clearAllCachedAuthTokens takes no arguments."
                )
            }
            syntheticAuthTokenCache = nil
            return success(
                request,
                payload: .null,
                diagnostics: [
                    "identity.clearAllCachedAuthTokens cleared only synthetic in-memory fixture state.",
                ]
            )
        default:
            return failure(
                request,
                code: .methodUnsupported,
                diagnostics: ["Unsupported identity method."]
            )
        }
    }

    static func reasonSupport(
        rawReason: String
    ) -> ChromeMV3OffscreenReasonSupport {
        guard let reason = ChromeMV3OffscreenReason(rawValue: rawReason) else {
            return ChromeMV3OffscreenReasonSupport(
                rawReason: rawReason,
                recognizedByChromeDocs: false,
                supportStatus: .unsupported,
                canCreateModelOnlyDocument: false,
                productOffscreenRuntimeAvailable: false,
                diagnostics: [
                    "Offscreen reason is not recognized by Chrome documentation: \(rawReason).",
                ]
            )
        }
        let status = reason.supportStatus
        return ChromeMV3OffscreenReasonSupport(
            rawReason: rawReason,
            recognizedByChromeDocs: true,
            supportStatus: status,
            canCreateModelOnlyDocument: status == .internalSyntheticOnly,
            productOffscreenRuntimeAvailable: false,
            diagnostics: reasonDiagnostics(reason: reason, status: status)
        )
    }

    private static func reasonDiagnostics(
        reason: ChromeMV3OffscreenReason,
        status: ChromeMV3SidePanelOffscreenIdentitySupportStatus
    ) -> [String] {
        switch status {
        case .internalSyntheticOnly:
            return [
                "Offscreen reason \(reason.rawValue) is recognized and can be modeled without product offscreen runtime.",
            ]
        case .productBlocked:
            return [
                "Offscreen reason \(reason.rawValue) is recognized but requires product browser/runtime capability that is blocked here.",
            ]
        case .deferred:
            return [
                "Offscreen reason \(reason.rawValue) is recognized but deferred because product lifetime behavior is not implemented.",
            ]
        case .unsupported:
            return [
                "Offscreen reason \(reason.rawValue) is recognized but unsupported by this compatibility layer.",
            ]
        case .productUIUnavailable, .syntheticFixtureOnly:
            return [
                "Offscreen reason \(reason.rawValue) has incompatible status \(status.rawValue).",
            ]
        }
    }

    private func validateExtensionHTMLPath(_ rawPath: String) -> String? {
        switch ChromeMV3ExtensionPageResourcePath.normalize(rawPath) {
        case .failure(let reason):
            return reason
        case .success(let path):
            let lower = path.lowercased()
            guard lower.hasSuffix(".html") || lower.hasSuffix(".htm") else {
                return "Extension page resource must be a local HTML file."
            }
            guard let rootPath = configuration.generatedBundleRootPath else {
                return nil
            }
            let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
            guard
                let url = ChromeMV3ExtensionPageResourcePath.resourceURL(
                    normalizedRelativePath: path,
                    rootURL: rootURL
                ),
                FileManager.default.fileExists(atPath: url.path)
            else {
                return "Extension page HTML resource is missing: \(path)."
            }
            return nil
        }
    }

    private mutating func documentRecord(
        rawURL: String,
        reasons: [ChromeMV3OffscreenReasonSupport],
        justification: String,
        state: ChromeMV3OffscreenDocumentLifecycleState,
        createdAsModelOnly: Bool
    ) -> ChromeMV3OffscreenDocumentRecord {
        let normalizedPath: String?
        let generatedPath: String?
        let exists: Bool
        switch ChromeMV3ExtensionPageResourcePath.normalize(rawURL) {
        case .success(let path):
            normalizedPath = path
            if let rootPath = configuration.generatedBundleRootPath {
                let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
                let url = ChromeMV3ExtensionPageResourcePath.resourceURL(
                    normalizedRelativePath: path,
                    rootURL: rootURL
                )
                generatedPath = url?.path
                exists = url.map { FileManager.default.fileExists(atPath: $0.path) }
                    ?? false
            } else {
                generatedPath = nil
                exists = false
            }
        case .failure:
            normalizedPath = nil
            generatedPath = nil
            exists = false
        }
        let record = ChromeMV3OffscreenDocumentRecord(
            sequence: nextOffscreenSequence,
            extensionID: configuration.extensionID,
            profileID: configuration.profileID,
            requestedURL: rawURL,
            normalizedPath: normalizedPath,
            generatedResourcePath: generatedPath,
            resourceExists: exists,
            reasons: reasons,
            justification: justification,
            lifecycleState: state,
            createdAsModelOnly: createdAsModelOnly,
            createdInInternalSyntheticHost: false,
            productHiddenWebViewCreated: false,
            diagnostics: uniqueSortedSOI(
                reasons.flatMap(\.diagnostics)
                    + [
                        createdAsModelOnly
                            ? "Offscreen document exists only as model state."
                            : "Offscreen document request was blocked before model creation.",
                        "No product hidden offscreen WebView was created.",
                    ]
            )
        )
        nextOffscreenSequence += 1
        return record
    }

    private mutating func blockedDocument(
        rawURL: String,
        reasons: [ChromeMV3OffscreenReasonSupport],
        justification: String,
        diagnostic: String
    ) -> ChromeMV3OffscreenDocumentRecord {
        documentRecord(
            rawURL: rawURL,
            reasons: reasons,
            justification: justification,
            state: .blocked,
            createdAsModelOnly: false
        ).withAdditionalDiagnostic(diagnostic)
    }

    private func redirectURL(path: String?) -> String {
        let trimmed = path?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            ?? ""
        let suffix = trimmed.isEmpty ? "" : trimmed
        return "https://\(configuration.extensionID).chromiumapp.org/\(suffix)"
    }

    private func success(
        _ request: ChromeMV3SidePanelOffscreenIdentityBridgeRequest,
        payload: ChromeMV3StorageValue?,
        diagnostics: [String]
    ) -> ChromeMV3SidePanelOffscreenIdentityBridgeResponse {
        response(
            request,
            succeeded: true,
            payload: payload,
            code: nil,
            diagnostics: diagnostics
        )
    }

    private func invalidArguments(
        _ request: ChromeMV3SidePanelOffscreenIdentityBridgeRequest,
        _ message: String
    ) -> ChromeMV3SidePanelOffscreenIdentityBridgeResponse {
        failure(
            request,
            code: .invalidArguments,
            diagnostics: [message]
        )
    }

    private func failure(
        _ request: ChromeMV3SidePanelOffscreenIdentityBridgeRequest,
        code: ChromeMV3JSBridgeErrorCode,
        payload: ChromeMV3StorageValue? = nil,
        diagnostics: [String]
    ) -> ChromeMV3SidePanelOffscreenIdentityBridgeResponse {
        response(
            request,
            succeeded: false,
            payload: payload,
            code: code,
            diagnostics: diagnostics
        )
    }

    private func response(
        _ request: ChromeMV3SidePanelOffscreenIdentityBridgeRequest,
        succeeded: Bool,
        payload: ChromeMV3StorageValue?,
        code: ChromeMV3JSBridgeErrorCode?,
        diagnostics: [String]
    ) -> ChromeMV3SidePanelOffscreenIdentityBridgeResponse {
        ChromeMV3SidePanelOffscreenIdentityBridgeResponse(
            bridgeCallID: request.bridgeCallID,
            namespace: request.namespace,
            methodName: request.methodName,
            invocationMode: request.invocationMode,
            succeeded: succeeded,
            resultPayload: payload,
            lastErrorMessage: succeeded ? nil : code?.lastErrorMessage,
            lastErrorCode: succeeded ? nil : code?.rawValue,
            callbackWouldSetLastError:
                succeeded == false && request.invocationMode == .callback,
            promiseWouldReject:
                succeeded == false && request.invocationMode == .promise,
            sidePanelAvailableInInternalFixture:
                configuration.sidePanelAvailableInInternalFixture,
            sidePanelAvailableInProduct: false,
            offscreenAvailableInInternalFixture:
                configuration.offscreenAvailableInInternalFixture,
            offscreenAvailableInProduct: false,
            identityAvailableInInternalFixture:
                configuration.identityAvailableInInternalFixture,
            identityAvailableInProduct: false,
            identityExternalAuthNetworkAllowed: false,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false,
            productRuntimeExposed: false,
            diagnostics:
                uniqueSortedSOI(
                    request.diagnostics
                        + configuration.diagnostics
                        + diagnostics
                        + [
                            "sidePanel/offscreen/identity response is synthetic compatibility state only.",
                            "Product normal-tab runtime bridge and runtimeLoadable remain false.",
                        ]
                )
        )
    }

    private func stringArray(
        _ value: ChromeMV3StorageValue?
    ) -> [String] {
        guard case .array(let values)? = value else { return [] }
        return values.compactMap(\.soiStringValue).sorted()
    }
}

extension ChromeMV3OffscreenDocumentRecord {
    fileprivate func withAdditionalDiagnostic(
        _ diagnostic: String
    ) -> ChromeMV3OffscreenDocumentRecord {
        var copy = self
        copy.diagnostics = uniqueSortedSOI(copy.diagnostics + [diagnostic])
        return copy
    }
}

private extension ChromeMV3StorageValue {
    init?(sidePanelOffscreenIdentityWebKitValue value: Any) {
        if value is NSNull {
            self = .null
            return
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                let double = number.doubleValue
                guard double.isFinite else { return nil }
                self = .number(double)
            }
            return
        }
        if let string = value as? String {
            self = .string(string)
            return
        }
        if let array = value as? [Any] {
            var values: [ChromeMV3StorageValue] = []
            for item in array {
                guard let converted = ChromeMV3StorageValue(
                    sidePanelOffscreenIdentityWebKitValue: item
                ) else {
                    return nil
                }
                values.append(converted)
            }
            self = .array(values)
            return
        }
        if let object = value as? [String: Any] {
            var values: [String: ChromeMV3StorageValue] = [:]
            for (key, item) in object {
                guard let converted = ChromeMV3StorageValue(
                    sidePanelOffscreenIdentityWebKitValue: item
                ) else {
                    return nil
                }
                values[key] = converted
            }
            self = .object(values)
            return
        }
        return nil
    }

    var soiObjectValue: [String: ChromeMV3StorageValue]? {
        guard case .object(let object) = self else { return nil }
        return object
    }

    var soiStringValue: String? {
        guard case .string(let string) = self else { return nil }
        return string
    }

    var soiBoolValue: Bool? {
        guard case .bool(let bool) = self else { return nil }
        return bool
    }

    var soiIntValue: Int? {
        guard case .number(let number) = self,
              number.rounded(.towardZero) == number
        else { return nil }
        return Int(number)
    }

    var sidePanelOffscreenIdentityFoundationObject: Any {
        switch self {
        case .array(let values):
            return values.map(\.sidePanelOffscreenIdentityFoundationObject)
        case .bool(let value):
            return value
        case .null:
            return NSNull()
        case .number(let value):
            return value
        case .object(let object):
            return object.mapValues(
                \.sidePanelOffscreenIdentityFoundationObject
            )
        case .string(let value):
            return value
        }
    }
}

struct ChromeMV3SidePanelOffscreenIdentityJSShimCoverage:
    Codable,
    Equatable,
    Sendable
{
    var namespaces: [String]
    var sidePanelMethods: [String]
    var offscreenMethods: [String]
    var identityMethods: [String]
    var callbackModeModeled: Bool
    var promiseModeModeled: Bool
    var lastErrorScopedToCallbackTurn: Bool
    var productExposureNow: Bool
}

struct ChromeMV3SidePanelOffscreenIdentityWebKitSyntheticJSExecutionSummary:
    Codable,
    Equatable,
    Sendable
{
    var scriptEvaluationSucceeded: Bool
    var sidePanelJSExecutedInWebKitSyntheticHarness: Bool
    var offscreenJSExecutedInWebKitSyntheticHarness: Bool
    var identityJSExecutedInWebKitSyntheticHarness: Bool
    var sidePanelExecutedMethods: [String]
    var offscreenExecutedMethods: [String]
    var identityExecutedMethods: [String]
    var callbackExecutedMethodKeys: [String]
    var promiseExecutedMethodKeys: [String]
    var lastErrorVerifiedMethodKeys: [String]
    var callbackModeExecutedInWebKitSyntheticHarness: Bool
    var promiseModeExecutedInWebKitSyntheticHarness: Bool
    var lastErrorScopedToCallbackTurnInWebKitSyntheticHarness: Bool
    var deterministicBlockedDiagnosticsVerifiedInWebKitSyntheticHarness: Bool
    var syntheticIdentityFixtureResponseUsed: Bool
    var sidePanelAvailableInProduct: Bool
    var offscreenAvailableInProduct: Bool
    var identityAvailableInProduct: Bool
    var identityExternalAuthNetworkAllowed: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
    var productRuntimeExposed: Bool
    var diagnostics: [String]

    static let notRun =
        ChromeMV3SidePanelOffscreenIdentityWebKitSyntheticJSExecutionSummary(
            scriptEvaluationSucceeded: false,
            sidePanelJSExecutedInWebKitSyntheticHarness: false,
            offscreenJSExecutedInWebKitSyntheticHarness: false,
            identityJSExecutedInWebKitSyntheticHarness: false,
            sidePanelExecutedMethods: [],
            offscreenExecutedMethods: [],
            identityExecutedMethods: [],
            callbackExecutedMethodKeys: [],
            promiseExecutedMethodKeys: [],
            lastErrorVerifiedMethodKeys: [],
            callbackModeExecutedInWebKitSyntheticHarness: false,
            promiseModeExecutedInWebKitSyntheticHarness: false,
            lastErrorScopedToCallbackTurnInWebKitSyntheticHarness: false,
            deterministicBlockedDiagnosticsVerifiedInWebKitSyntheticHarness:
                false,
            syntheticIdentityFixtureResponseUsed: false,
            sidePanelAvailableInProduct: false,
            offscreenAvailableInProduct: false,
            identityAvailableInProduct: false,
            identityExternalAuthNetworkAllowed: false,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false,
            productRuntimeExposed: false,
            diagnostics: [
                "WebKit-executed synthetic JS harness has not run for this report.",
            ]
        )

    static func fromWebKitScriptResult(
        json: String?,
        scriptEvaluationSucceeded: Bool,
        responses: [ChromeMV3SidePanelOffscreenIdentityBridgeResponse],
        syntheticIdentityFixture:
            ChromeMV3IdentitySyntheticFixture,
        diagnostics: [String]
    ) -> ChromeMV3SidePanelOffscreenIdentityWebKitSyntheticJSExecutionSummary {
        let decoded = json.flatMap {
            try? JSONDecoder().decode(
                ChromeMV3StorageValue.self,
                from: Data($0.utf8)
            )
        }
        let object = decoded?.soiObjectValue ?? [:]
        let sidePanelMethods = uniqueSortedSOI(
            responses
                .filter { $0.namespace == "sidePanel" }
                .map(\.methodName)
                + stringArraySOI(object["sidePanelMethodsExecuted"])
        )
        let offscreenMethods = uniqueSortedSOI(
            responses
                .filter { $0.namespace == "offscreen" }
                .map(\.methodName)
                + stringArraySOI(object["offscreenMethodsExecuted"])
        )
        let identityMethods = uniqueSortedSOI(
            responses
                .filter { $0.namespace == "identity" }
                .map(\.methodName)
                + stringArraySOI(object["identityMethodsExecuted"])
        )
        let callbackExecuted =
            responses.contains { $0.invocationMode == .callback }
            || object["callbackModeExecuted"]?.soiBoolValue == true
        let promiseExecuted =
            responses.contains { $0.invocationMode == .promise }
            || object["promiseModeExecuted"]?.soiBoolValue == true
        let callbackMethodKeys = uniqueSortedSOI(
            responses
                .filter { $0.invocationMode == .callback }
                .map { "\($0.namespace).\($0.methodName)" }
                + stringArraySOI(object["callbackExecutedMethodKeys"])
        )
        let promiseMethodKeys = uniqueSortedSOI(
            responses
                .filter { $0.invocationMode == .promise }
                .map { "\($0.namespace).\($0.methodName)" }
                + stringArraySOI(object["promiseExecutedMethodKeys"])
        )
        let lastErrorMethodKeys = uniqueSortedSOI(
            responses
                .filter { $0.succeeded == false }
                .map { "\($0.namespace).\($0.methodName)" }
                + stringArraySOI(object["lastErrorVerifiedMethodKeys"])
        )
        let lastErrorScoped =
            object["lastErrorScopedOK"]?.soiBoolValue == true
        let blockedDiagnostics =
            object["blockedDiagnosticsOK"]?.soiBoolValue == true
        let fixtureUsedByResponse =
            syntheticIdentityFixture.configuredForTestOnly
            && responses.contains {
                $0.namespace == "identity"
                    && $0.succeeded
                    && ($0.methodName == "launchWebAuthFlow"
                        || $0.methodName == "getAuthToken")
            }
        let fixtureUsed =
            object["syntheticIdentityFixtureResponseUsed"]?.soiBoolValue
                == true
            || fixtureUsedByResponse
        let sidePanelComplete =
            ["getOptions", "open", "setOptions", "setPanelBehavior"]
                .allSatisfy { sidePanelMethods.contains($0) }
        let offscreenComplete =
            ["closeDocument", "createDocument", "hasDocument"]
                .allSatisfy { offscreenMethods.contains($0) }
        let identityComplete =
            [
                "clearAllCachedAuthTokens",
                "getAuthToken",
                "getRedirectURL",
                "launchWebAuthFlow",
                "removeCachedAuthToken",
            ].allSatisfy { identityMethods.contains($0) }

        return ChromeMV3SidePanelOffscreenIdentityWebKitSyntheticJSExecutionSummary(
            scriptEvaluationSucceeded: scriptEvaluationSucceeded,
            sidePanelJSExecutedInWebKitSyntheticHarness:
                scriptEvaluationSucceeded && sidePanelComplete,
            offscreenJSExecutedInWebKitSyntheticHarness:
                scriptEvaluationSucceeded && offscreenComplete,
            identityJSExecutedInWebKitSyntheticHarness:
                scriptEvaluationSucceeded && identityComplete,
            sidePanelExecutedMethods: sidePanelMethods,
            offscreenExecutedMethods: offscreenMethods,
            identityExecutedMethods: identityMethods,
            callbackExecutedMethodKeys: callbackMethodKeys,
            promiseExecutedMethodKeys: promiseMethodKeys,
            lastErrorVerifiedMethodKeys: lastErrorMethodKeys,
            callbackModeExecutedInWebKitSyntheticHarness: callbackExecuted,
            promiseModeExecutedInWebKitSyntheticHarness: promiseExecuted,
            lastErrorScopedToCallbackTurnInWebKitSyntheticHarness:
                lastErrorScoped,
            deterministicBlockedDiagnosticsVerifiedInWebKitSyntheticHarness:
                blockedDiagnostics,
            syntheticIdentityFixtureResponseUsed: fixtureUsed,
            sidePanelAvailableInProduct: false,
            offscreenAvailableInProduct: false,
            identityAvailableInProduct: false,
            identityExternalAuthNetworkAllowed: false,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false,
            productRuntimeExposed: false,
            diagnostics: uniqueSortedSOI(
                diagnostics
                    + [
                        "WebKit-executed synthetic JS status is derived from a controlled DEBUG/internal harness result.",
                        "Product sidePanel UI, product offscreen runtime, identity network, normal-tab runtime, and runtimeLoadable remain unavailable.",
                    ]
            )
        )
    }
}

enum ChromeMV3SidePanelOffscreenIdentityJSShimSource {
    static let bridgeMessageHandlerName =
        "sumiChromeMV3SidePanelOffscreenIdentity"

    static var coverage:
        ChromeMV3SidePanelOffscreenIdentityJSShimCoverage
    {
        ChromeMV3SidePanelOffscreenIdentityJSShimCoverage(
            namespaces: ["identity", "offscreen", "sidePanel"],
            sidePanelMethods: [
                "getOptions",
                "open",
                "setOptions",
                "setPanelBehavior",
            ],
            offscreenMethods: [
                "closeDocument",
                "createDocument",
                "hasDocument",
            ],
            identityMethods: [
                "clearAllCachedAuthTokens",
                "getAuthToken",
                "getRedirectURL",
                "launchWebAuthFlow",
                "removeCachedAuthToken",
            ],
            callbackModeModeled: true,
            promiseModeModeled: true,
            lastErrorScopedToCallbackTurn: true,
            productExposureNow: false
        )
    }

    static func source(
        configuration: ChromeMV3SidePanelOffscreenIdentityConfiguration
    ) -> String {
        let configJSON = jsonString([
            "extensionID": configuration.extensionID,
            "profileID": configuration.profileID,
            "bridgeMessageHandlerName": bridgeMessageHandlerName,
        ])
        return """
        (() => {
          "use strict";
          const config = \(configJSON);
          const bridgeName = config.bridgeMessageHandlerName;
          const chromeObject = {};
          const runtime = {};
          const sidePanel = {};
          const offscreen = {};
          const identity = {};
          let lastErrorValue;
          let nextBridgeCallNumber = 0;

          function unavailableResponse(namespace, methodName) {
            return {
              bridgeCallID: "sidepanel-offscreen-identity-js-unavailable",
              namespace,
              methodName,
              invocationMode: "promise",
              succeeded: false,
              resultPayload: null,
              lastErrorMessage:
                "sidePanel/offscreen/identity JS bridge handler is unavailable.",
              lastErrorCode: "jsBridgeUnavailable",
              callbackWouldSetLastError: false,
              promiseWouldReject: false,
              sidePanelAvailableInProduct: false,
              offscreenAvailableInProduct: false,
              identityAvailableInProduct: false,
              identityExternalAuthNetworkAllowed: false,
              normalTabRuntimeBridgeAvailable: false,
              runtimeLoadable: false,
              productRuntimeExposed: false,
              diagnostics: [
                "sidePanel/offscreen/identity JS bridge handler is unavailable."
              ]
            };
          }

          function bridgePost(namespace, methodName, invocationMode, args) {
            const handler = globalThis.webkit
              && globalThis.webkit.messageHandlers
              && globalThis.webkit.messageHandlers[bridgeName];
            if (!handler || typeof handler.postMessage !== "function") {
              return Promise.resolve(unavailableResponse(namespace, methodName));
            }
            nextBridgeCallNumber += 1;
            return handler.postMessage({
              namespace,
              methodName,
              invocationMode,
              extensionID: config.extensionID,
              profileID: config.profileID,
              bridgeCallID: [
                "sidepanel-offscreen-identity-js",
                namespace,
                methodName,
                String(nextBridgeCallNumber)
              ].join("-"),
              arguments: args || []
            });
          }

          function toJSONCompatible(value) {
            if (value === undefined || typeof value === "function") {
              return null;
            }
            return JSON.parse(JSON.stringify(value));
          }

          function splitCallback(argsLike) {
            const args = Array.prototype.slice.call(argsLike);
            const callback =
              typeof args[args.length - 1] === "function" ? args.pop() : null;
            return {
              callback,
              args: args.map(toJSONCompatible)
            };
          }

          function callbackArguments(response) {
            if (!response || !response.succeeded) {
              return [];
            }
            if (
              response.resultPayload === null
              || response.resultPayload === undefined
            ) {
              return [];
            }
            return [response.resultPayload];
          }

          function invokeCallback(callback, response) {
            lastErrorValue = response && response.succeeded === false
              ? { message: response.lastErrorMessage || "Chrome MV3 API failed." }
              : undefined;
            try {
              callback.apply(undefined, callbackArguments(response));
            } finally {
              lastErrorValue = undefined;
            }
          }

          function rejectFromResponse(response) {
            return Promise.reject(
              new Error(
                response.lastErrorMessage
                || "sidePanel/offscreen/identity bridge call failed."
              )
            );
          }

          function invoke(namespace, methodName, argsLike) {
            const parsed = splitCallback(argsLike);
            const invocationMode = parsed.callback ? "callback" : "promise";
            const result = bridgePost(
              namespace,
              methodName,
              invocationMode,
              parsed.args
            ).then((response) => {
              if (parsed.callback) {
                invokeCallback(parsed.callback, response);
                return undefined;
              }
              if (!response || response.succeeded === false) {
                return rejectFromResponse(response || {});
              }
              return response.resultPayload === null
                ? undefined
                : response.resultPayload;
            });
            if (parsed.callback) {
              result.catch((error) => {
                invokeCallback(parsed.callback, {
                  succeeded: false,
                  lastErrorMessage:
                    error && error.message
                      ? error.message
                      : "Chrome MV3 API failed."
                });
              });
              return undefined;
            }
            return result;
          }

          function redirectURL(path) {
            const raw = typeof path === "string" ? path.trim() : "";
            const suffix = raw.replace(/^\\/+|\\/+$/g, "");
            return "https://" + config.extensionID + ".chromiumapp.org/"
              + suffix;
          }

          Object.defineProperty(runtime, "id", {
            value: config.extensionID,
            enumerable: true
          });
          Object.defineProperty(runtime, "lastError", {
            get() {
              return lastErrorValue;
            },
            enumerable: true
          });

          Object.defineProperty(sidePanel, "setOptions", {
            value: function setOptions() {
              return invoke("sidePanel", "setOptions", arguments);
            },
            enumerable: true
          });
          Object.defineProperty(sidePanel, "getOptions", {
            value: function getOptions() {
              return invoke("sidePanel", "getOptions", arguments);
            },
            enumerable: true
          });
          Object.defineProperty(sidePanel, "setPanelBehavior", {
            value: function setPanelBehavior() {
              return invoke("sidePanel", "setPanelBehavior", arguments);
            },
            enumerable: true
          });
          Object.defineProperty(sidePanel, "open", {
            value: function open() {
              return invoke("sidePanel", "open", arguments);
            },
            enumerable: true
          });

          Object.defineProperty(offscreen, "createDocument", {
            value: function createDocument() {
              return invoke("offscreen", "createDocument", arguments);
            },
            enumerable: true
          });
          Object.defineProperty(offscreen, "hasDocument", {
            value: function hasDocument() {
              return invoke("offscreen", "hasDocument", arguments);
            },
            enumerable: true
          });
          Object.defineProperty(offscreen, "closeDocument", {
            value: function closeDocument() {
              return invoke("offscreen", "closeDocument", arguments);
            },
            enumerable: true
          });

          Object.defineProperty(identity, "getRedirectURL", {
            value: function getRedirectURL(path) {
              return redirectURL(path);
            },
            enumerable: true
          });
          Object.defineProperty(identity, "launchWebAuthFlow", {
            value: function launchWebAuthFlow() {
              return invoke("identity", "launchWebAuthFlow", arguments);
            },
            enumerable: true
          });
          Object.defineProperty(identity, "getAuthToken", {
            value: function getAuthToken() {
              return invoke("identity", "getAuthToken", arguments);
            },
            enumerable: true
          });
          Object.defineProperty(identity, "removeCachedAuthToken", {
            value: function removeCachedAuthToken() {
              return invoke("identity", "removeCachedAuthToken", arguments);
            },
            enumerable: true
          });
          Object.defineProperty(identity, "clearAllCachedAuthTokens", {
            value: function clearAllCachedAuthTokens() {
              return invoke("identity", "clearAllCachedAuthTokens", arguments);
            },
            enumerable: true
          });

          Object.defineProperty(chromeObject, "runtime", {
            value: Object.freeze(runtime),
            enumerable: true
          });
          Object.defineProperty(chromeObject, "sidePanel", {
            value: Object.freeze(sidePanel),
            enumerable: true
          });
          Object.defineProperty(chromeObject, "offscreen", {
            value: Object.freeze(offscreen),
            enumerable: true
          });
          Object.defineProperty(chromeObject, "identity", {
            value: Object.freeze(identity),
            enumerable: true
          });
          Object.defineProperty(globalThis, "chrome", {
            value: Object.freeze(chromeObject),
            configurable: true
          });
        })();
        """
    }

    private static func jsonString(_ object: [String: String]) -> String {
        let data = (try? JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )) ?? Data("{}".utf8)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

final class ChromeMV3SidePanelOffscreenIdentityJSBridgeHandler {
    private(set) var runtimeStateOwner:
        ChromeMV3SidePanelOffscreenIdentityRuntimeStateOwner
    private(set) var handledRequestCount = 0
    private(set) var rejectedRequestCount = 0
    private(set) var handledResponses:
        [ChromeMV3SidePanelOffscreenIdentityBridgeResponse] = []

    init(
        runtimeStateOwner:
            ChromeMV3SidePanelOffscreenIdentityRuntimeStateOwner
    ) {
        self.runtimeStateOwner = runtimeStateOwner
    }

    convenience init(
        configuration: ChromeMV3SidePanelOffscreenIdentityConfiguration
    ) {
        self.init(
            runtimeStateOwner:
                ChromeMV3SidePanelOffscreenIdentityRuntimeStateOwner(
                    configuration: configuration
                )
        )
    }

    func handle(
        _ body: Any
    ) -> ChromeMV3SidePanelOffscreenIdentityBridgeResponse {
        handledRequestCount += 1
        let request = makeRequest(from: body)
        let response = runtimeStateOwner.handle(request)
        handledResponses.append(response)
        if response.succeeded == false {
            rejectedRequestCount += 1
        }
        return response
    }

    @discardableResult
    func tearDown() -> ChromeMV3SidePanelOffscreenIdentityBridgeResponse {
        let response = runtimeStateOwner.handle(
            ChromeMV3SidePanelOffscreenIdentityBridgeRequest(
                namespace: "offscreen",
                methodName: "closeDocument",
                invocationMode: .fireAndForget,
                diagnostics: [
                    "Synthetic WebKit harness teardown closes model-only offscreen state.",
                ]
            )
        )
        handledResponses.append(response)
        return response
    }

    private func makeRequest(
        from body: Any
    ) -> ChromeMV3SidePanelOffscreenIdentityBridgeRequest {
        guard let object = body as? [String: Any] else {
            return ChromeMV3SidePanelOffscreenIdentityBridgeRequest(
                namespace: "unsupported",
                methodName: "invalidMessageBody",
                invocationMode: .promise,
                diagnostics: [
                    "Synthetic JS bridge message body was not a dictionary.",
                ]
            )
        }
        let namespace = object["namespace"] as? String ?? "unsupported"
        let methodName = object["methodName"] as? String
            ?? "unsupportedMethod"
        let mode = ChromeMV3JSBridgeInvocationMode(
            rawValue: object["invocationMode"] as? String ?? ""
        ) ?? .promise
        let bridgeCallID = object["bridgeCallID"] as? String
        let rawArguments = object["arguments"] as? [Any] ?? []
        let arguments = rawArguments.compactMap {
            ChromeMV3StorageValue(
                sidePanelOffscreenIdentityWebKitValue: $0
            )
        }
        let allArgumentsConverted = arguments.count == rawArguments.count
        return ChromeMV3SidePanelOffscreenIdentityBridgeRequest(
            bridgeCallID: bridgeCallID,
            namespace: namespace,
            methodName: methodName,
            invocationMode: mode,
            arguments: arguments,
            diagnostics: allArgumentsConverted
                ? ["Request originated from the synthetic WebKit JS shim."]
                : [
                    "Request originated from the synthetic WebKit JS shim.",
                    "One or more JS arguments were not JSON-compatible and were dropped.",
                ]
        )
    }
}

struct ChromeMV3SidePanelOffscreenIdentityReportSummary:
    Codable,
    Equatable,
    Sendable
{
    var reportID: String
    var reportFileName: String
    var sidePanelAvailableInInternalFixture: Bool
    var sidePanelAvailableInProduct: Bool
    var offscreenAvailableInInternalFixture: Bool
    var offscreenAvailableInProduct: Bool
    var identityAvailableInInternalFixture: Bool
    var identityAvailableInProduct: Bool
    var identityExternalAuthNetworkAllowed: Bool
    var sidePanelJSExecutedInWebKitSyntheticHarness: Bool
    var offscreenJSExecutedInWebKitSyntheticHarness: Bool
    var identityJSExecutedInWebKitSyntheticHarness: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
}

struct ChromeMV3SidePanelOffscreenIdentityCompatibilityReport:
    Codable,
    Equatable,
    Sendable
{
    var schemaVersion: Int
    var id: String
    var reportFileName: String
    var extensionID: String
    var profileID: String
    var apiDetection:
        ChromeMV3SidePanelOffscreenIdentityAPIDetectionSummary
    var sidePanelManifestResourceSummary:
        ChromeMV3SidePanelManifestResourceSummary
    var sidePanelJSMethodCoverage:
        [ChromeMV3SidePanelOffscreenIdentityMethodCoverage]
    var offscreenReasonSupportMatrix:
        [ChromeMV3OffscreenReasonSupport]
    var offscreenJSMethodCoverage:
        [ChromeMV3SidePanelOffscreenIdentityMethodCoverage]
    var offscreenLifecycleSummary:
        ChromeMV3OffscreenLifecycleSummary
    var identityManifestSummary:
        ChromeMV3IdentityManifestSummary
    var identityAPISupportMatrix:
        [ChromeMV3SidePanelOffscreenIdentityMethodCoverage]
    var identitySyntheticFixtureStatus:
        ChromeMV3IdentitySyntheticFixtureStatus
    var jsShimCoverage:
        ChromeMV3SidePanelOffscreenIdentityJSShimCoverage
    var webKitSyntheticJSExecutionSummary:
        ChromeMV3SidePanelOffscreenIdentityWebKitSyntheticJSExecutionSummary
    var productBlockers: [String]
    var sidePanelJSExecutedInWebKitSyntheticHarness: Bool
    var sidePanelAvailableInInternalFixture: Bool
    var sidePanelAvailableInProduct: Bool
    var offscreenJSExecutedInWebKitSyntheticHarness: Bool
    var offscreenAvailableInInternalFixture: Bool
    var offscreenAvailableInProduct: Bool
    var identityJSExecutedInWebKitSyntheticHarness: Bool
    var identityAvailableInInternalFixture: Bool
    var identityAvailableInProduct: Bool
    var identityExternalAuthNetworkAllowed: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
    var productRuntimeExposed: Bool
    var documentationSources:
        [ChromeMV3WebKitObjectAcceptanceDocumentationSource]
    var diagnostics: [String]

    var summary: ChromeMV3SidePanelOffscreenIdentityReportSummary {
        ChromeMV3SidePanelOffscreenIdentityReportSummary(
            reportID: id,
            reportFileName: reportFileName,
            sidePanelAvailableInInternalFixture:
                sidePanelAvailableInInternalFixture,
            sidePanelAvailableInProduct: false,
            offscreenAvailableInInternalFixture:
                offscreenAvailableInInternalFixture,
            offscreenAvailableInProduct: false,
            identityAvailableInInternalFixture:
                identityAvailableInInternalFixture,
            identityAvailableInProduct: false,
            identityExternalAuthNetworkAllowed: false,
            sidePanelJSExecutedInWebKitSyntheticHarness:
                sidePanelJSExecutedInWebKitSyntheticHarness,
            offscreenJSExecutedInWebKitSyntheticHarness:
                offscreenJSExecutedInWebKitSyntheticHarness,
            identityJSExecutedInWebKitSyntheticHarness:
                identityJSExecutedInWebKitSyntheticHarness,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false
        )
    }
}

enum ChromeMV3SidePanelOffscreenIdentityCompatibilityReportWriter {
    static let reportFileName =
        "runtime-sidepanel-offscreen-identity-compatibility-report.json"

    @discardableResult
    static func write(
        _ report:
            ChromeMV3SidePanelOffscreenIdentityCompatibilityReport,
        toRewrittenBundleRoot rootURL: URL
    ) throws -> ChromeMV3SidePanelOffscreenIdentityCompatibilityReport {
        guard directoryExists(rootURL.standardizedFileURL) else {
            return report
        }
        try ChromeMV3DeterministicJSON.write(
            report,
            to: rootURL.standardizedFileURL
                .appendingPathComponent(Self.reportFileName)
        )
        return report
    }

    private static func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
    }
}

enum ChromeMV3SidePanelOffscreenIdentityCompatibilityReportGenerator {
    static func makeReport(
        manifest: ChromeMV3Manifest?,
        generatedBundleRootURL rootURL: URL,
        extensionID: String = "sidepanel-offscreen-identity-extension",
        profileID: String = "sidepanel-offscreen-identity-profile",
        moduleState: ChromeMV3ProfileHostModuleState = .enabled,
        syntheticIdentityFixture:
            ChromeMV3IdentitySyntheticFixture = .none,
        webKitSyntheticJSExecutionSummary:
            ChromeMV3SidePanelOffscreenIdentityWebKitSyntheticJSExecutionSummary
            = .notRun
    ) -> ChromeMV3SidePanelOffscreenIdentityCompatibilityReport {
        let rootURL = rootURL.standardizedFileURL
        let apiDetection = apiDetectionSummary(
            manifest: manifest,
            rootURL: rootURL
        )
        let sidePanelSummary = sidePanelSummary(
            manifest: manifest,
            rootURL: rootURL,
            apiDetection: apiDetection,
            moduleState: moduleState
        )
        let configuration =
            ChromeMV3SidePanelOffscreenIdentityConfiguration
            .syntheticHarness(
                extensionID: extensionID,
                profileID: profileID,
                generatedBundleRootPath: rootURL.path,
                defaultSidePanelPath: manifest?.sidePanel?.defaultPath,
                moduleState: moduleState,
                syntheticIdentityFixture: syntheticIdentityFixture
            )
        let stateOwner =
            ChromeMV3SidePanelOffscreenIdentityRuntimeStateOwner(
                configuration: configuration
            )
        let identitySummary = identityManifestSummary(
            manifest: manifest,
            apiDetection: apiDetection,
            moduleState: moduleState
        )
        let fixtureStatus = identityFixtureStatus(
            syntheticIdentityFixture
        )
        let productBlockers = [
            "sidePanel product UI blocked",
            "offscreen product runtime blocked",
            "identity OAuth blocked",
            "identity external auth network blocked",
            "normal-tab runtime bridge unavailable",
            "runtimeLoadable remains false",
        ].sorted()
        let reportID = stableIDSOI(
            prefix: "runtime-sidepanel-offscreen-identity",
            parts: [
                extensionID,
                profileID,
                rootURL.path,
                apiDetection.sidePanelDefaultPath ?? "",
                String(apiDetection.offscreenPermissionDeclared),
            String(apiDetection.identityPermissionDeclared),
            String(fixtureStatus.authFlowResponseConfigured),
            String(fixtureStatus.authTokenConfigured),
            String(
                webKitSyntheticJSExecutionSummary
                    .sidePanelJSExecutedInWebKitSyntheticHarness
            ),
            String(
                webKitSyntheticJSExecutionSummary
                    .offscreenJSExecutedInWebKitSyntheticHarness
            ),
            String(
                webKitSyntheticJSExecutionSummary
                    .identityJSExecutedInWebKitSyntheticHarness
            ),
        ]
    )
        let sidePanelInternal =
            moduleState == .enabled
            && (apiDetection.sidePanelDeclaredByManifestKey
                || apiDetection.sidePanelPermissionDeclared
                || apiDetection.sidePanelAPIUsedInSource)
        let offscreenInternal =
            moduleState == .enabled
            && (apiDetection.offscreenPermissionDeclared
                || apiDetection.offscreenAPIUsedInSource)
        let identityInternal =
            moduleState == .enabled
            && (apiDetection.identityPermissionDeclared
                || apiDetection.identityEmailPermissionDeclared
                || apiDetection.identityOAuth2ManifestDeclared
                || apiDetection.identityAPIUsedInSource)

        return ChromeMV3SidePanelOffscreenIdentityCompatibilityReport(
            schemaVersion: 2,
            id: reportID,
            reportFileName:
                ChromeMV3SidePanelOffscreenIdentityCompatibilityReportWriter
                .reportFileName,
            extensionID: extensionID,
            profileID: profileID,
            apiDetection: apiDetection,
            sidePanelManifestResourceSummary: sidePanelSummary,
            sidePanelJSMethodCoverage:
                sidePanelMethodCoverage(
                    internalAvailable: sidePanelInternal,
                    webKitSummary: webKitSyntheticJSExecutionSummary
                ),
            offscreenReasonSupportMatrix:
                ChromeMV3OffscreenReason.allCases.map {
                    ChromeMV3SidePanelOffscreenIdentityRuntimeStateOwner
                        .reasonSupport(rawReason: $0.rawValue)
                }.sorted { $0.rawReason < $1.rawReason },
            offscreenJSMethodCoverage:
                offscreenMethodCoverage(
                    internalAvailable: offscreenInternal,
                    webKitSummary: webKitSyntheticJSExecutionSummary
                ),
            offscreenLifecycleSummary:
                stateOwner.offscreenLifecycleSummary,
            identityManifestSummary: identitySummary,
            identityAPISupportMatrix:
                identityMethodCoverage(
                    internalAvailable: identityInternal,
                    fixture: syntheticIdentityFixture,
                    webKitSummary: webKitSyntheticJSExecutionSummary
                ),
            identitySyntheticFixtureStatus: fixtureStatus,
            jsShimCoverage:
                ChromeMV3SidePanelOffscreenIdentityJSShimSource.coverage,
            webKitSyntheticJSExecutionSummary:
                webKitSyntheticJSExecutionSummary,
            productBlockers: productBlockers,
            sidePanelJSExecutedInWebKitSyntheticHarness:
                webKitSyntheticJSExecutionSummary
                .sidePanelJSExecutedInWebKitSyntheticHarness,
            sidePanelAvailableInInternalFixture: sidePanelInternal,
            sidePanelAvailableInProduct: false,
            offscreenJSExecutedInWebKitSyntheticHarness:
                webKitSyntheticJSExecutionSummary
                .offscreenJSExecutedInWebKitSyntheticHarness,
            offscreenAvailableInInternalFixture: offscreenInternal,
            offscreenAvailableInProduct: false,
            identityJSExecutedInWebKitSyntheticHarness:
                webKitSyntheticJSExecutionSummary
                .identityJSExecutedInWebKitSyntheticHarness,
            identityAvailableInInternalFixture: identityInternal,
            identityAvailableInProduct: false,
            identityExternalAuthNetworkAllowed: false,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false,
            productRuntimeExposed: false,
            documentationSources: documentationSources(),
            diagnostics: uniqueSortedSOI(
                configuration.diagnostics
                    + apiDetection.diagnostics
                    + sidePanelSummary.blockingReasons
                    + productBlockers
                    + [
                        "Compatibility model and product blockers remain deterministic.",
                        webKitSyntheticJSExecutionSummary
                            .scriptEvaluationSucceeded
                            ? "A controlled DEBUG/internal WebKit synthetic JS harness result is attached."
                            : "No WebKit synthetic JS harness result is attached.",
                        "No product sidePanel, offscreen, identity, normal-tab runtime, or external auth path was added.",
                    ]
            )
        )
    }

    private static func apiDetectionSummary(
        manifest: ChromeMV3Manifest?,
        rootURL: URL
    ) -> ChromeMV3SidePanelOffscreenIdentityAPIDetectionSummary {
        let sourceMatches = sourceAPIMatches(rootURL: rootURL)
        let identityPermission =
            manifest?.declaresPermission("identity") ?? false
        let identityEmail =
            manifest?.declaresPermission("identity.email") ?? false
        return ChromeMV3SidePanelOffscreenIdentityAPIDetectionSummary(
            sidePanelDeclaredByManifestKey: manifest?.sidePanel != nil,
            sidePanelPermissionDeclared:
                manifest?.declaresPermission("sidePanel") ?? false,
            sidePanelDefaultPath: manifest?.sidePanel?.defaultPath,
            sidePanelAPIUsedInSource:
                sourceMatches["sidePanel"]?.isEmpty == false,
            sidePanelAPIUsePaths: sourceMatches["sidePanel"] ?? [],
            offscreenPermissionDeclared:
                manifest?.declaresPermission("offscreen") ?? false,
            offscreenAPIUsedInSource:
                sourceMatches["offscreen"]?.isEmpty == false,
            offscreenAPIUsePaths: sourceMatches["offscreen"] ?? [],
            identityPermissionDeclared: identityPermission,
            identityEmailPermissionDeclared: identityEmail,
            identityOAuth2ManifestDeclared: manifest?.oauth2 != nil,
            identityOAuth2Scopes: manifest?.oauth2?.scopes ?? [],
            identityAPIUsedInSource:
                sourceMatches["identity"]?.isEmpty == false,
            identityAPIUsePaths: sourceMatches["identity"] ?? [],
            diagnostics: [
                "API usage detection scans extension-local JS/HTML source for chrome.* and browser.* namespace references.",
                "Manifest detection uses side_panel, permissions, identity.email, and oauth2 metadata.",
            ]
        )
    }

    private static func sidePanelSummary(
        manifest: ChromeMV3Manifest?,
        rootURL: URL,
        apiDetection:
            ChromeMV3SidePanelOffscreenIdentityAPIDetectionSummary,
        moduleState: ChromeMV3ProfileHostModuleState
    ) -> ChromeMV3SidePanelManifestResourceSummary {
        let declarationModel = ChromeMV3ExtensionPageDeclarationReader.read(
            generatedRewrittenRootPath: rootURL.path
        )
        let declaration = declarationModel.declarations.first {
            $0.kind == .sidePanel
        }
        let resolution = declaration.map {
            ChromeMV3ExtensionPageResourceResolver.resolve(declaration: $0)
        }
        let policy = declaration.map { _ in
            ChromeMV3ExtensionPageFixturePolicy.evaluate(
                declarationModel: declarationModel,
                selectedKind: .sidePanel
            )
        }
        let missing = declaration?.pathSafety == .missing
            || declaration?.resourceExists == false
        let unsafe = declaration?.pathSafety == .unsafe
        let nonHTML =
            resolution?.blockingReasons.contains {
                $0.contains("only accepts HTML")
                    || $0.contains("local HTML")
            } ?? false
        let remote =
            resolution?.remoteResourceReferences.isEmpty == false
        let blockers = uniqueSortedSOI(
            (declaration?.safetyDiagnostics ?? [])
                + (resolution?.blockingReasons ?? [])
                + (policy?.blockingReasons ?? [])
                + [
                    "sidePanel product UI blocked.",
                    "sidePanel is not attached to toolbar, sidebar, settings, or normal tabs.",
                ]
        )
        let hostAllowed = policy?.fixturePagePolicyPassed == true
        let detected =
            apiDetection.sidePanelDeclaredByManifestKey
                || apiDetection.sidePanelPermissionDeclared
                || apiDetection.sidePanelAPIUsedInSource
        return ChromeMV3SidePanelManifestResourceSummary(
            declaredByManifestKey: apiDetection.sidePanelDeclaredByManifestKey,
            permissionDeclared: apiDetection.sidePanelPermissionDeclared,
            defaultPath: manifest?.sidePanel?.defaultPath,
            pageDeclaration: declaration,
            resourceResolution: resolution,
            fixturePolicy: policy,
            syntheticHostDiagnostics:
                ChromeMV3SidePanelSyntheticHostDiagnostics(
                    defaultPathResolved:
                        declaration?.normalizedPath != nil,
                    defaultPathResourceSafe:
                        resolution?.resourceSafeForExtensionPageHost
                            ?? false,
                    syntheticHiddenHostAllowedByPolicy: hostAllowed,
                    syntheticHiddenHostAttempted: false,
                    syntheticHiddenHostLoaded: false,
                    oneShotInspectionAttempted: false,
                    outcome:
                        hostAllowed
                            ? "availableForExplicitInternalHarness"
                            : (declaration == nil
                                ? "notDeclared"
                                : "blocked"),
                    blockingReasons:
                        hostAllowed ? [] : blockers,
                    diagnostics: [
                        hostAllowed
                            ? "sidePanel page is safe for a future explicit hidden internal harness attempt."
                            : "sidePanel synthetic host was not attempted; report records deterministic blockers.",
                        "No product side panel UI was exposed.",
                    ]
                ),
            missingPageDiagnosed: missing,
            unsafePathDiagnosed: unsafe,
            nonHTMLResourceDiagnosed: nonHTML,
            remoteResourceDependencyDiagnosed: remote,
            sidePanelAvailableInInternalFixture:
                moduleState == .enabled && detected,
            sidePanelAvailableInProduct: false,
            productUIBlocked: true,
            blockingReasons: blockers
        )
    }

    private static func identityManifestSummary(
        manifest: ChromeMV3Manifest?,
        apiDetection:
            ChromeMV3SidePanelOffscreenIdentityAPIDetectionSummary,
        moduleState: ChromeMV3ProfileHostModuleState
    ) -> ChromeMV3IdentityManifestSummary {
        let detected =
            apiDetection.identityPermissionDeclared
                || apiDetection.identityEmailPermissionDeclared
                || apiDetection.identityOAuth2ManifestDeclared
                || apiDetection.identityAPIUsedInSource
        return ChromeMV3IdentityManifestSummary(
            identityPermissionDeclared:
                apiDetection.identityPermissionDeclared,
            identityEmailPermissionDeclared:
                apiDetection.identityEmailPermissionDeclared,
            oauth2ManifestDeclared:
                apiDetection.identityOAuth2ManifestDeclared,
            oauth2ClientIDPresent:
                manifest?.oauth2?.clientID?.isEmpty == false,
            oauth2Scopes: apiDetection.identityOAuth2Scopes,
            identityAvailableInInternalFixture:
                moduleState == .enabled && detected,
            identityAvailableInProduct: false,
            identityExternalAuthNetworkAllowed: false,
            diagnostics: [
                "identity manifest metadata is retained for compatibility diagnostics only.",
                "Product identity OAuth UI, account provider, token cache, and external auth network are unavailable.",
            ]
        )
    }

    private static func identityFixtureStatus(
        _ fixture: ChromeMV3IdentitySyntheticFixture
    ) -> ChromeMV3IdentitySyntheticFixtureStatus {
        ChromeMV3IdentitySyntheticFixtureStatus(
            configuredForTestOnly: fixture.configuredForTestOnly,
            authFlowResponseConfigured:
                fixture.configuredForTestOnly
                    && fixture.authFlowRedirectURL != nil,
            authTokenConfigured:
                fixture.configuredForTestOnly && fixture.authToken != nil,
            grantedScopes: fixture.grantedScopes,
            accountIDConfigured: fixture.accountID != nil,
            tokenValueStoredInReport: false,
            externalAuthNetworkAllowed: false,
            diagnostics: [
                fixture.configuredForTestOnly
                    ? "Synthetic identity fixture is explicit and test-only."
                    : "No synthetic identity fixture response is configured.",
                "Report records fixture presence only; token values are not serialized into the report.",
            ]
        )
    }

    private static func sidePanelMethodCoverage(
        internalAvailable: Bool,
        webKitSummary:
            ChromeMV3SidePanelOffscreenIdentityWebKitSyntheticJSExecutionSummary
    ) -> [ChromeMV3SidePanelOffscreenIdentityMethodCoverage] {
        [
            method(
                namespace: "sidePanel",
                methodName: "getOptions",
                status: .internalSyntheticOnly,
                internalAvailable: internalAvailable,
                webKitSummary: webKitSummary,
                diagnostics: ["Reads internal synthetic sidePanel state."]
            ),
            method(
                namespace: "sidePanel",
                methodName: "setOptions",
                status: .internalSyntheticOnly,
                internalAvailable: internalAvailable,
                webKitSummary: webKitSummary,
                diagnostics: ["Mutates internal synthetic sidePanel state."]
            ),
            method(
                namespace: "sidePanel",
                methodName: "setPanelBehavior",
                status: .internalSyntheticOnly,
                internalAvailable: internalAvailable,
                webKitSummary: webKitSummary,
                diagnostics: ["Mutates internal synthetic panel behavior state."]
            ),
            method(
                namespace: "sidePanel",
                methodName: "open",
                status: .productUIUnavailable,
                internalAvailable: internalAvailable,
                webKitSummary: webKitSummary,
                diagnostics: [
                    "Returns product UI unavailable unless an explicit internal sidePanel host fixture is configured.",
                ]
            ),
        ].sorted { $0.methodName < $1.methodName }
    }

    private static func offscreenMethodCoverage(
        internalAvailable: Bool,
        webKitSummary:
            ChromeMV3SidePanelOffscreenIdentityWebKitSyntheticJSExecutionSummary
    ) -> [ChromeMV3SidePanelOffscreenIdentityMethodCoverage] {
        [
            method(
                namespace: "offscreen",
                methodName: "createDocument",
                status: .internalSyntheticOnly,
                internalAvailable: internalAvailable,
                webKitSummary: webKitSummary,
                diagnostics: ["Validates URL, reasons, and justification before model-only creation."]
            ),
            method(
                namespace: "offscreen",
                methodName: "hasDocument",
                status: .internalSyntheticOnly,
                internalAvailable: internalAvailable,
                webKitSummary: webKitSummary,
                diagnostics: ["Reads model-only offscreen document state."]
            ),
            method(
                namespace: "offscreen",
                methodName: "closeDocument",
                status: .internalSyntheticOnly,
                internalAvailable: internalAvailable,
                webKitSummary: webKitSummary,
                diagnostics: ["Clears model-only offscreen document state."]
            ),
        ].sorted { $0.methodName < $1.methodName }
    }

    private static func identityMethodCoverage(
        internalAvailable: Bool,
        fixture: ChromeMV3IdentitySyntheticFixture,
        webKitSummary:
            ChromeMV3SidePanelOffscreenIdentityWebKitSyntheticJSExecutionSummary
    ) -> [ChromeMV3SidePanelOffscreenIdentityMethodCoverage] {
        [
            method(
                namespace: "identity",
                methodName: "getRedirectURL",
                status: .internalSyntheticOnly,
                internalAvailable: internalAvailable,
                webKitSummary: webKitSummary,
                diagnostics: ["Returns deterministic synthetic chromiumapp.org redirect URLs."]
            ),
            method(
                namespace: "identity",
                methodName: "launchWebAuthFlow",
                status:
                    fixture.configuredForTestOnly
                    && fixture.authFlowRedirectURL != nil
                        ? .syntheticFixtureOnly
                        : .productBlocked,
                internalAvailable: internalAvailable,
                webKitSummary: webKitSummary,
                diagnostics: [
                    "Blocked unless an explicit test-only synthetic auth flow response is configured.",
                    "External auth network is unavailable.",
                ]
            ),
            method(
                namespace: "identity",
                methodName: "getAuthToken",
                status:
                    fixture.configuredForTestOnly
                    && fixture.authToken != nil
                        ? .syntheticFixtureOnly
                        : .productBlocked,
                internalAvailable: internalAvailable,
                webKitSummary: webKitSummary,
                diagnostics: [
                    "Blocked unless an explicit test-only synthetic token is configured.",
                    "No real token storage is used.",
                ]
            ),
            method(
                namespace: "identity",
                methodName: "removeCachedAuthToken",
                status: .internalSyntheticOnly,
                internalAvailable: internalAvailable,
                webKitSummary: webKitSummary,
                diagnostics: ["Clears only synthetic in-memory fixture token state."]
            ),
            method(
                namespace: "identity",
                methodName: "clearAllCachedAuthTokens",
                status: .internalSyntheticOnly,
                internalAvailable: internalAvailable,
                webKitSummary: webKitSummary,
                diagnostics: ["Clears only synthetic in-memory fixture token state."]
            ),
        ].sorted { $0.methodName < $1.methodName }
    }

    private static func method(
        namespace: String,
        methodName: String,
        status: ChromeMV3SidePanelOffscreenIdentitySupportStatus,
        internalAvailable: Bool,
        webKitSummary:
            ChromeMV3SidePanelOffscreenIdentityWebKitSyntheticJSExecutionSummary,
        diagnostics: [String]
    ) -> ChromeMV3SidePanelOffscreenIdentityMethodCoverage {
        let executedMethods: [String]
        switch namespace {
        case "sidePanel":
            executedMethods = webKitSummary.sidePanelExecutedMethods
        case "offscreen":
            executedMethods = webKitSummary.offscreenExecutedMethods
        case "identity":
            executedMethods = webKitSummary.identityExecutedMethods
        default:
            executedMethods = []
        }
        let methodExecuted = executedMethods.contains(methodName)
        let methodKey = "\(namespace).\(methodName)"
        return ChromeMV3SidePanelOffscreenIdentityMethodCoverage(
            namespace: namespace,
            methodName: methodName,
            supportStatus: status,
            modelCoverageAvailable: true,
            bridgeCoverageAvailable: internalAvailable,
            availableInInternalFixture: internalAvailable,
            availableInProduct: false,
            callbackModeModeled: true,
            promiseModeModeled: true,
            lastErrorModeled: true,
            webKitSyntheticJSCallbackExecuted:
                webKitSummary.callbackExecutedMethodKeys.contains(methodKey),
            webKitSyntheticJSPromiseExecuted:
                webKitSummary.promiseExecutedMethodKeys.contains(methodKey),
            webKitSyntheticJSLastErrorVerified:
                webKitSummary.lastErrorVerifiedMethodKeys.contains(methodKey)
                && webKitSummary
                    .lastErrorScopedToCallbackTurnInWebKitSyntheticHarness,
            diagnostics:
                uniqueSortedSOI(
                    diagnostics
                        + [
                            "Product availability remains false.",
                            "Callback, Promise, and runtime.lastError behavior are modeled deterministically.",
                            methodExecuted
                                ? "Method was executed by a controlled WebKit synthetic JS harness."
                                : "Method has not been executed by a WebKit synthetic JS harness in this report.",
                        ]
                )
        )
    }

    private static func sourceAPIMatches(
        rootURL: URL
    ) -> [String: [String]] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: rootURL,
                includingPropertiesForKeys: nil
            )
        else { return [:] }
        var matches: [String: [String]] = [
            "identity": [],
            "offscreen": [],
            "sidePanel": [],
        ]
        for case let fileURL as URL in enumerator {
            guard sourceFileExtensions.contains(fileURL.pathExtension.lowercased())
            else { continue }
            guard let source = try? String(contentsOf: fileURL, encoding: .utf8)
            else { continue }
            let relative = relativePath(fileURL: fileURL, rootURL: rootURL)
            if source.contains("chrome.sidePanel")
                || source.contains("browser.sidePanel")
            {
                matches["sidePanel", default: []].append(relative)
            }
            if source.contains("chrome.offscreen")
                || source.contains("browser.offscreen")
            {
                matches["offscreen", default: []].append(relative)
            }
            if source.contains("chrome.identity")
                || source.contains("browser.identity")
            {
                matches["identity", default: []].append(relative)
            }
        }
        return matches.mapValues { uniqueSortedSOI($0) }
    }

    private static var sourceFileExtensions: Set<String> {
        ["js", "mjs", "cjs", "html", "htm"]
    }

    private static func relativePath(
        fileURL: URL,
        rootURL: URL
    ) -> String {
        let root = rootURL.standardizedFileURL.path
        let file = fileURL.standardizedFileURL.path
        guard file.hasPrefix(root + "/") else {
            return fileURL.lastPathComponent
        }
        return String(file.dropFirst(root.count + 1))
    }

    private static func documentationSources()
        -> [ChromeMV3WebKitObjectAcceptanceDocumentationSource]
    {
        [
            source(
                title: "chrome.sidePanel",
                url: "https://developer.chrome.com/docs/extensions/reference/api/sidePanel",
                note: "Defines side_panel.default_path, setOptions, getOptions, setPanelBehavior, open, local page resources, and product side panel UI behavior."
            ),
            source(
                title: "chrome.offscreen",
                url: "https://developer.chrome.com/docs/extensions/reference/api/offscreen",
                note: "Defines createDocument, closeDocument, hasDocument, local static HTML URL, reasons, justification, and one-open-document lifecycle."
            ),
            source(
                title: "chrome.identity",
                url: "https://developer.chrome.com/docs/extensions/reference/api/identity",
                note: "Defines getRedirectURL, launchWebAuthFlow, getAuthToken, removeCachedAuthToken, clearAllCachedAuthTokens, redirect URL format, and token-cache semantics."
            ),
            source(
                title: "chrome.runtime.lastError",
                url: "https://developer.chrome.com/docs/extensions/reference/api/runtime#property-lastError",
                note: "Defines callback-scoped lastError behavior and Promise error separation used by the synthetic shim diagnostics."
            ),
            source(
                title: "Apple WebKit synthetic script APIs",
                url: "https://developer.apple.com/documentation/webkit/wkscriptmessagehandlerwithreply",
                note: "Local Apple WebKit SDK headers checked for user-script injection, content worlds, script-message reply handlers, async JS evaluation, and handler teardown boundaries."
            ),
            source(
                title: "Current Sumi extension page host harness",
                url: nil,
                note: "The existing DEBUG/internal extension page resolver and host policy are reused for sidePanel.default_path diagnostics only."
            ),
        ]
    }

    private static func source(
        title: String,
        url: String?,
        note: String
    ) -> ChromeMV3WebKitObjectAcceptanceDocumentationSource {
        let kind: String
        if let url, url.contains("developer.apple.com") {
            kind = "appleDocumentation"
        } else {
            kind = url == nil ? "currentSumiCode" : "chromeDocumentation"
        }
        return ChromeMV3WebKitObjectAcceptanceDocumentationSource(
            kind: kind,
            title: title,
            url: url,
            note: note
        )
    }
}

private func stableIDSOI(prefix: String, parts: [String]) -> String {
    let seed = ([prefix] + parts).joined(separator: "|")
    return "\(prefix)-\(sha256SOI(Data(seed.utf8)).prefix(32))"
}

private func sha256SOI(_ data: Data) -> String {
    SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }
        .joined()
}

private func uniqueSortedSOI<T: Hashable & Comparable>(
    _ values: [T]
) -> [T] {
    Array(Set(values)).sorted()
}

private func stringArraySOI(
    _ value: ChromeMV3StorageValue?
) -> [String] {
    guard case .array(let values)? = value else { return [] }
    return values.compactMap(\.soiStringValue).sorted()
}

private func normalizedSOI(
    _ value: String,
    fallback: String
) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? fallback : trimmed
}
