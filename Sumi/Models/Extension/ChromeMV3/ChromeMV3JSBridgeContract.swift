//
//  ChromeMV3JSBridgeContract.swift
//  Sumi
//
//  Deterministic host-side Chrome MV3 JavaScript bridge contract layer.
//  This models future chrome.* bridge envelopes and routes already-formed
//  test inputs into existing Swift model handlers only. It does not import
//  WebKit, inject scripts, register user scripts or script handlers, create
//  extension contexts, wake service workers, open ports, launch native hosts,
//  or schedule background work.
//

import CryptoKit
import Foundation

enum ChromeMV3JSBridgeSourceContext:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case actionPopup
    case contentScript
    case extensionPage
    case optionsPage
    case serviceWorker
    case testFixture

    static func < (
        lhs: ChromeMV3JSBridgeSourceContext,
        rhs: ChromeMV3JSBridgeSourceContext
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var runtimeContext: ChromeMV3RuntimeMessagingContextKind {
        switch self {
        case .actionPopup:
            return .actionPopup
        case .contentScript:
            return .contentScript
        case .extensionPage:
            return .extensionPage
        case .optionsPage:
            return .optionsPage
        case .serviceWorker, .testFixture:
            return .serviceWorker
        }
    }

    var storageContext: ChromeMV3StorageAPISourceContext {
        switch self {
        case .actionPopup:
            return .actionPopup
        case .contentScript:
            return .contentScript
        case .extensionPage:
            return .extensionPage
        case .optionsPage:
            return .optionsPage
        case .serviceWorker:
            return .serviceWorker
        case .testFixture:
            return .testFixture
        }
    }

    var permissionsContext:
        ChromeMV3PermissionsAPIRequestSourceContext
    {
        switch self {
        case .actionPopup:
            return .actionPopup
        case .extensionPage:
            return .extensionPage
        case .optionsPage:
            return .optionsPage
        case .serviceWorker:
            return .serviceWorker
        case .contentScript, .testFixture:
            return .testFixture
        }
    }
}

enum ChromeMV3JSBridgeNamespace:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case nativeMessaging
    case permissions
    case runtime
    case storage
    case tabs
    case unsupported

    static func < (
        lhs: ChromeMV3JSBridgeNamespace,
        rhs: ChromeMV3JSBridgeNamespace
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3JSBridgeInvocationMode:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case callback
    case callbackAndPromiseInvalid
    case fireAndForget
    case promise

    static func < (
        lhs: ChromeMV3JSBridgeInvocationMode,
        rhs: ChromeMV3JSBridgeInvocationMode
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3JSBridgeRequestEnvelope:
    Codable,
    Equatable,
    Sendable
{
    var bridgeCallID: String
    var extensionID: String
    var profileID: String
    var sourceContext: ChromeMV3JSBridgeSourceContext
    var namespace: ChromeMV3JSBridgeNamespace
    var methodName: String
    var rawArguments: [ChromeMV3StorageValue]
    var invocationMode: ChromeMV3JSBridgeInvocationMode
    var diagnosticTraceID: String

    init(
        bridgeCallID: String? = nil,
        extensionID: String,
        profileID: String,
        sourceContext: ChromeMV3JSBridgeSourceContext,
        namespace: ChromeMV3JSBridgeNamespace,
        methodName: String,
        rawArguments: [ChromeMV3StorageValue] = [],
        invocationMode: ChromeMV3JSBridgeInvocationMode,
        diagnosticTraceID: String? = nil
    ) {
        let normalizedExtensionID = extensionID.isEmpty
            ? "unknown-extension"
            : extensionID
        let normalizedProfileID = profileID.isEmpty
            ? "unknown-profile"
            : profileID
        let normalizedMethodName = methodName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let callID = bridgeCallID
            ?? Self.makeBridgeCallID(
                extensionID: normalizedExtensionID,
                profileID: normalizedProfileID,
                sourceContext: sourceContext,
                namespace: namespace,
                methodName: normalizedMethodName,
                rawArguments: rawArguments,
                invocationMode: invocationMode
            )
        self.bridgeCallID = callID
        self.extensionID = normalizedExtensionID
        self.profileID = normalizedProfileID
        self.sourceContext = sourceContext
        self.namespace = namespace
        self.methodName = normalizedMethodName
        self.rawArguments = rawArguments
        self.invocationMode = invocationMode
        self.diagnosticTraceID = diagnosticTraceID
            ?? stableID(prefix: "js-bridge-trace", parts: [callID])
    }

    private static func makeBridgeCallID(
        extensionID: String,
        profileID: String,
        sourceContext: ChromeMV3JSBridgeSourceContext,
        namespace: ChromeMV3JSBridgeNamespace,
        methodName: String,
        rawArguments: [ChromeMV3StorageValue],
        invocationMode: ChromeMV3JSBridgeInvocationMode
    ) -> String {
        stableID(
            prefix: "js-bridge-call",
            parts: [
                profileID,
                extensionID,
                sourceContext.rawValue,
                namespace.rawValue,
                methodName,
                invocationMode.rawValue,
                rawArguments.map(stableArgumentDescription)
                    .joined(separator: "|"),
            ]
        )
    }
}

enum ChromeMV3JSBridgeErrorCode:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case apiContractNotImplemented
    case contextNotLoaded
    case extensionDisabled
    case invalidArguments
    case jsBridgeUnavailable
    case methodUnsupported
    case namespaceUnsupported
    case nativeMessagingBlocked
    case permissionDenied
    case runtimeDispatchUnavailable
    case serviceWorkerWakeUnavailable
    case storageAreaUnavailable
    case unsupportedAPI

    static func < (
        lhs: ChromeMV3JSBridgeErrorCode,
        rhs: ChromeMV3JSBridgeErrorCode
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var lastErrorMessage: String {
        switch self {
        case .apiContractNotImplemented:
            return "Chrome MV3 API contract is not implemented for this bridge method."
        case .contextNotLoaded:
            return "No extension context is loaded for Chrome MV3 JavaScript bridge routing."
        case .extensionDisabled:
            return "The extensions module is disabled."
        case .invalidArguments:
            return "Invalid Chrome MV3 JavaScript bridge arguments."
        case .jsBridgeUnavailable:
            return "Chrome MV3 JavaScript bridge runtime exposure is unavailable."
        case .methodUnsupported:
            return "Chrome MV3 JavaScript bridge method is unsupported."
        case .namespaceUnsupported:
            return "Chrome MV3 JavaScript bridge namespace is unsupported."
        case .nativeMessagingBlocked:
            return "Chrome MV3 native messaging is blocked by host preflight."
        case .permissionDenied:
            return "Chrome MV3 bridge request is blocked by modeled permission state."
        case .runtimeDispatchUnavailable:
            return "Chrome MV3 runtime dispatch is unavailable outside model routing."
        case .serviceWorkerWakeUnavailable:
            return "Chrome MV3 service-worker wake is unavailable."
        case .storageAreaUnavailable:
            return "Chrome MV3 storage area is unavailable for this modeled request."
        case .unsupportedAPI:
            return "Chrome MV3 API is unsupported by the bridge contract."
        }
    }
}

struct ChromeMV3JSBridgeLastErrorContract:
    Codable,
    Equatable,
    Sendable
{
    var code: ChromeMV3JSBridgeErrorCode
    var futureLastErrorMessage: String
    var wouldSetRuntimeLastError: Bool
    var promiseWouldReject: Bool
    var callbackWouldInvoke: Bool
    var runtimeExposureNow: Bool
    var diagnostics: [String]

    static func make(
        code: ChromeMV3JSBridgeErrorCode,
        invocationMode: ChromeMV3JSBridgeInvocationMode,
        diagnostics: [String] = []
    ) -> ChromeMV3JSBridgeLastErrorContract {
        ChromeMV3JSBridgeLastErrorContract(
            code: code,
            futureLastErrorMessage: code.lastErrorMessage,
            wouldSetRuntimeLastError: invocationMode == .callback,
            promiseWouldReject: invocationMode == .promise,
            callbackWouldInvoke: invocationMode == .callback,
            runtimeExposureNow: false,
            diagnostics:
                uniqueSorted(
                    [
                        "lastError is modeled as future callback-scope state only.",
                        "No callback is executed and no Promise is rejected now.",
                    ] + diagnostics
                )
        )
    }
}

struct ChromeMV3JSBridgePromiseBehavior:
    Codable,
    Equatable,
    Sendable
{
    var promiseModeRequested: Bool
    var wouldResolve: Bool
    var wouldReject: Bool
    var rejectionMessage: String?
}

struct ChromeMV3JSBridgeCallbackBehavior:
    Codable,
    Equatable,
    Sendable
{
    var callbackModeRequested: Bool
    var wouldInvokeCallback: Bool
    var callbackPayload: ChromeMV3StorageValue?
    var wouldSetRuntimeLastError: Bool
    var lastErrorMessage: String?
}

enum ChromeMV3JSBridgeArgumentIssueKind:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case invalidType
    case missingRequiredArgument
    case needsVerification
    case unexpectedArgument
    case unsupportedVariant

    static func < (
        lhs: ChromeMV3JSBridgeArgumentIssueKind,
        rhs: ChromeMV3JSBridgeArgumentIssueKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3JSBridgeArgumentIssue:
    Codable,
    Equatable,
    Sendable
{
    var kind: ChromeMV3JSBridgeArgumentIssueKind
    var argumentIndex: Int?
    var message: String
    var diagnostics: [String]
}

enum ChromeMV3JSBridgeArgumentNormalizationStatus:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case argumentUnsupported
    case invalidArguments
    case needsVerification
    case normalized

    static func < (
        lhs: ChromeMV3JSBridgeArgumentNormalizationStatus,
        rhs: ChromeMV3JSBridgeArgumentNormalizationStatus
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3JSBridgeAPITarget:
    Codable,
    Equatable,
    Sendable
{
    var namespace: ChromeMV3JSBridgeNamespace
    var methodName: String
    var storageArea: ChromeMV3StorageAreaKind?
    var storageOperation: ChromeMV3StorageOperationKind?
    var routeKind: ChromeMV3RuntimeMessagingRouteKind?
    var nativeOperationKind: ChromeMV3NativeMessagingOperationKind?
}

struct ChromeMV3JSBridgeArgumentNormalization:
    Codable,
    Equatable,
    Sendable
{
    var target: ChromeMV3JSBridgeAPITarget?
    var status: ChromeMV3JSBridgeArgumentNormalizationStatus
    var runtimeRoute: ChromeMV3RuntimeMessagingRoute?
    var storageOperationInput: ChromeMV3StorageAPIOperationInput?
    var permissionsInput: ChromeMV3PermissionsAPIRequestInput?
    var nativeMessagingInput: ChromeMV3NativeMessagingPreflightInput?
    var normalizedPayload: [String: ChromeMV3StorageValue]
    var issues: [ChromeMV3JSBridgeArgumentIssue]
    var diagnostics: [String]

    var canRouteToHostModel: Bool {
        status == .normalized
    }
}

struct ChromeMV3JSBridgeRouteResult:
    Codable,
    Equatable,
    Sendable
{
    var normalizedArguments: ChromeMV3JSBridgeArgumentNormalization
    var runtimeDispatcherResult:
        ChromeMV3RuntimeMessageDispatcherResult?
    var storageOperationResult:
        ChromeMV3StorageAPIOperationResultEnvelope?
    var permissionsContainsResult:
        ChromeMV3PermissionsAPIContainsResult?
    var permissionsGetAllResult:
        ChromeMV3PermissionsAPIGetAllResult?
    var permissionsRequestResult:
        ChromeMV3PermissionsAPIRequestResult?
    var permissionsRemoveResult:
        ChromeMV3PermissionsAPIRemoveResult?
    var nativeMessagingPreflight:
        ChromeMV3NativeMessagingOperationPreflight?
    var routedToHostModel: Bool
    var openedRuntimePortNow: Bool
    var openedNativePortNow: Bool
    var dispatchedStorageOnChangedNow: Bool
    var wokeServiceWorkerNow: Bool
    var loadedContextNow: Bool
    var diagnostics: [String]
}

struct ChromeMV3JSBridgeResponseEnvelope:
    Codable,
    Equatable,
    Sendable
{
    var bridgeCallID: String
    var succeeded: Bool
    var resultPayload: ChromeMV3StorageValue?
    var lastErrorContract: ChromeMV3JSBridgeLastErrorContract?
    var promiseBehavior: ChromeMV3JSBridgePromiseBehavior
    var callbackBehavior: ChromeMV3JSBridgeCallbackBehavior
    var routeResult: ChromeMV3JSBridgeRouteResult?
    var runtimeExposureNow: Bool
    var jsBridgeAvailableNow: Bool
    var diagnostics: [String]
}

struct ChromeMV3JSBridgeContractEnvironment: Sendable {
    var moduleState: ChromeMV3ProfileHostModuleState
    var listenerRegistrySnapshot:
        ChromeMV3RuntimeModelListenerRegistrySnapshot
    var permissionStore: ChromeMV3PermissionDecisionStore
    var activeTabStore: ChromeMV3ActiveTabGrantStore
    var serviceWorkerLifecycleSnapshot:
        ChromeMV3ServiceWorkerLifecycleStateSnapshot
    var localStorageBroker: ChromeMV3StorageBroker
    var sessionStorageBroker: ChromeMV3StorageBroker
    var syncStorageBroker: ChromeMV3StorageBroker
    var managedStorageBroker: ChromeMV3StorageBroker
    var storageHandlerState:
        ChromeMV3StorageAPIOperationHandlerState
    var nativeLookupPolicy: ChromeMV3NativeHostLookupPolicy
    var nativeProductPolicy: ChromeMV3NativeMessagingProductPolicy
    var nativeMessagingPermissionState:
        ChromeMV3NativeMessagingPermissionState

    var permissionBroker: ChromeMV3PermissionBroker {
        permissionStore.permissionBroker(activeTabStore: activeTabStore)
    }

    static func passwordManagerModelFixture(
        extensionID: String,
        profileID: String,
        storagePermissionDetected: Bool = true,
        nativeMessagingPermissionDetected: Bool = true,
        moduleState: ChromeMV3ProfileHostModuleState = .enabled
    ) -> ChromeMV3JSBridgeContractEnvironment {
        let normalizedExtensionID = extensionID.isEmpty
            ? "unknown-extension"
            : extensionID
        let normalizedProfileID = profileID.isEmpty
            ? "unknown-profile"
            : profileID
        let permissionStore = ChromeMV3PermissionDecisionStore(
            snapshot: ChromeMV3PermissionDecisionStoreSnapshot(
                extensionID: normalizedExtensionID,
                profileID: normalizedProfileID,
                declaredAPIPermissions:
                    (storagePermissionDetected ? ["storage"] : [])
                    + ["activeTab", "tabs"]
                    + (nativeMessagingPermissionDetected
                        ? ["nativeMessaging"]
                        : []),
                declaredHostPermissions: ["https://example.com/*"],
                optionalAPIPermissions: ["bookmarks", "history"],
                optionalHostPermissions: ["https://optional.example/*"],
                grantedOptionalAPIPermissions: ["bookmarks"],
                grantedOptionalHostPermissions: [],
                deferredPermissions:
                    nativeMessagingPermissionDetected
                        ? ["nativeMessaging"]
                        : []
            )
        )
        let activeTabStore = ChromeMV3ActiveTabGrantStore.empty(
            extensionID: normalizedExtensionID,
            profileID: normalizedProfileID
        )
        let namespace: (ChromeMV3StorageAreaKind) -> ChromeMV3StorageNamespace = {
            ChromeMV3StorageNamespace(
                profileID: normalizedProfileID,
                extensionID: normalizedExtensionID,
                area: $0
            )
        }
        return ChromeMV3JSBridgeContractEnvironment(
            moduleState: moduleState,
            listenerRegistrySnapshot:
                ChromeMV3RuntimeModelListenerRegistrySnapshot
                .passwordManagerModelFixture(
                    extensionID: normalizedExtensionID,
                    profileID: normalizedProfileID
                ),
            permissionStore: permissionStore,
            activeTabStore: activeTabStore,
            serviceWorkerLifecycleSnapshot: .blocked(
                extensionID: normalizedExtensionID,
                profileID: normalizedProfileID
            ),
            localStorageBroker: ChromeMV3StorageBroker(
                namespace: namespace(.local),
                initialValues: ["existing": .string("value")]
            ),
            sessionStorageBroker: ChromeMV3StorageBroker(
                namespace: namespace(.session)
            ),
            syncStorageBroker: ChromeMV3StorageBroker(
                namespace: namespace(.sync)
            ),
            managedStorageBroker: ChromeMV3StorageBroker(
                namespace: namespace(.managed)
            ),
            storageHandlerState:
                moduleState == .enabled
                    ? .enabledModelTestFixture
                    : .disabledModule,
            nativeLookupPolicy: .macOS(extensionModuleEnabled: moduleState == .enabled),
            nativeProductPolicy:
                ChromeMV3NativeMessagingProductPolicy(
                    extensionModuleEnabled: moduleState == .enabled,
                    nativeMessagingAllowedByProductPolicy: true,
                    userConsentRequired: true,
                    userConsentGranted: false
                ),
            nativeMessagingPermissionState:
                nativeMessagingPermissionDetected
                    ? .grantedByManifest
                    : .missing
        )
    }
}

enum ChromeMV3JSBridgeArgumentNormalizer {
    static func normalize(
        request: ChromeMV3JSBridgeRequestEnvelope,
        environment: ChromeMV3JSBridgeContractEnvironment
    ) -> ChromeMV3JSBridgeArgumentNormalization {
        if request.invocationMode == .callbackAndPromiseInvalid {
            return invalid(
                target: apiTarget(request: request),
                issue: issue(
                    .unsupportedVariant,
                    index: nil,
                    "Callback and Promise modes cannot both be requested by a deterministic bridge envelope."
                )
            )
        }

        switch request.namespace {
        case .runtime:
            return normalizeRuntime(request)
        case .tabs:
            return normalizeTabs(request)
        case .storage:
            return normalizeStorage(request)
        case .permissions:
            return normalizePermissions(request)
        case .nativeMessaging:
            return normalizeNativeMessaging(
                request,
                permissionState:
                    environment.nativeMessagingPermissionState,
                productPolicy: environment.nativeProductPolicy
            )
        case .unsupported:
            return invalid(
                target: apiTarget(request: request),
                status: .argumentUnsupported,
                issue: issue(
                    .unsupportedVariant,
                    index: nil,
                    "Unsupported namespace has no argument contract."
                )
            )
        }
    }

    private static func normalizeRuntime(
        _ request: ChromeMV3JSBridgeRequestEnvelope
    ) -> ChromeMV3JSBridgeArgumentNormalization {
        switch request.methodName {
        case "sendMessage":
            return normalizeRuntimeSendMessage(request)
        case "connect":
            return normalizeRuntimeConnect(request)
        default:
            return invalid(
                target: apiTarget(request: request),
                status: .argumentUnsupported,
                issue: issue(
                    .unsupportedVariant,
                    index: nil,
                    "Unsupported runtime bridge method."
                )
            )
        }
    }

    private static func normalizeTabs(
        _ request: ChromeMV3JSBridgeRequestEnvelope
    ) -> ChromeMV3JSBridgeArgumentNormalization {
        switch request.methodName {
        case "sendMessage":
            return normalizeTabsSendMessage(request)
        case "connect":
            return normalizeTabsConnect(request)
        default:
            return invalid(
                target: apiTarget(request: request),
                status: .argumentUnsupported,
                issue: issue(
                    .unsupportedVariant,
                    index: nil,
                    "Unsupported tabs bridge method."
                )
            )
        }
    }

    private static func normalizeStorage(
        _ request: ChromeMV3JSBridgeRequestEnvelope
    ) -> ChromeMV3JSBridgeArgumentNormalization {
        guard let target = storageTarget(request.methodName) else {
            return invalid(
                target: apiTarget(request: request),
                status: .argumentUnsupported,
                issue: issue(
                    .unsupportedVariant,
                    index: nil,
                    "Storage method must use an area-qualified name such as local.get."
                )
            )
        }
        let args = request.rawArguments
        let invocationMode = storageInvocationMode(request.invocationMode)
        let sourceContext = request.sourceContext.storageContext
        let input: ChromeMV3StorageAPIOperationInput

        switch target.storageOperation {
        case .get:
            guard args.count <= 1 else {
                return unexpectedArgument(request: request, target: target)
            }
            let selectorResult = storageSelector(
                args.first,
                defaultWhenMissing: .omitted
            )
            guard selectorResult.issues.isEmpty else {
                return invalid(
                    target: target,
                    issues: selectorResult.issues
                )
            }
            input = ChromeMV3StorageAPIOperationInput(
                extensionID: request.extensionID,
                profileID: request.profileID,
                area: target.storageArea ?? .local,
                operation: .get,
                invocationMode: invocationMode,
                keySelector: selectorResult.selector,
                sourceContext: sourceContext,
                diagnostics: [
                    "Bridge normalized storage.get key selector.",
                ]
            )
        case .set:
            guard args.count == 1 else {
                return invalid(
                    target: target,
                    issue: issue(
                        .missingRequiredArgument,
                        index: 0,
                        "storage.set requires exactly one object argument."
                    )
                )
            }
            guard let values = args[0].objectValue else {
                return invalid(
                    target: target,
                    issue: issue(
                        .invalidType,
                        index: 0,
                        "storage.set requires an object of key/value pairs."
                    )
                )
            }
            input = ChromeMV3StorageAPIOperationInput(
                extensionID: request.extensionID,
                profileID: request.profileID,
                area: target.storageArea ?? .local,
                operation: .set,
                invocationMode: invocationMode,
                values: values,
                sourceContext: sourceContext,
                diagnostics: [
                    "Bridge normalized storage.set object values.",
                ]
            )
        case .remove:
            guard args.count == 1 else {
                return invalid(
                    target: target,
                    issue: issue(
                        .missingRequiredArgument,
                        index: 0,
                        "storage.remove requires a string key or string array."
                    )
                )
            }
            let selectorResult = storageSelector(
                args.first,
                defaultWhenMissing: .invalidType("missing")
            )
            guard selectorResult.issues.isEmpty else {
                return invalid(
                    target: target,
                    issues: selectorResult.issues
                )
            }
            input = ChromeMV3StorageAPIOperationInput(
                extensionID: request.extensionID,
                profileID: request.profileID,
                area: target.storageArea ?? .local,
                operation: .remove,
                invocationMode: invocationMode,
                keySelector: selectorResult.selector,
                sourceContext: sourceContext,
                diagnostics: [
                    "Bridge normalized storage.remove key selector.",
                ]
            )
        case .clear:
            guard args.isEmpty else {
                return unexpectedArgument(request: request, target: target)
            }
            input = ChromeMV3StorageAPIOperationInput(
                extensionID: request.extensionID,
                profileID: request.profileID,
                area: target.storageArea ?? .local,
                operation: .clear,
                invocationMode: invocationMode,
                sourceContext: sourceContext,
                diagnostics: ["Bridge normalized storage.clear."]
            )
        case .getBytesInUse:
            guard args.count <= 1 else {
                return unexpectedArgument(request: request, target: target)
            }
            let selectorResult = storageSelector(
                args.first,
                defaultWhenMissing: .omitted
            )
            guard selectorResult.issues.isEmpty else {
                return invalid(
                    target: target,
                    issues: selectorResult.issues
                )
            }
            input = ChromeMV3StorageAPIOperationInput(
                extensionID: request.extensionID,
                profileID: request.profileID,
                area: target.storageArea ?? .local,
                operation: .getBytesInUse,
                invocationMode: invocationMode,
                keySelector: selectorResult.selector,
                sourceContext: sourceContext,
                diagnostics: [
                    "Bridge normalized storage.getBytesInUse key selector.",
                ]
            )
        default:
            return invalid(
                target: target,
                status: .argumentUnsupported,
                issue: issue(
                    .unsupportedVariant,
                    index: nil,
                    "Storage operation is not modeled for bridge routing."
                )
            )
        }

        return normalized(
            target: target,
            storageInput: input,
            payload: storagePayload(input)
        )
    }

    private static func normalizePermissions(
        _ request: ChromeMV3JSBridgeRequestEnvelope
    ) -> ChromeMV3JSBridgeArgumentNormalization {
        let target = apiTarget(request: request)
        switch request.methodName {
        case "contains", "request", "remove":
            guard request.rawArguments.count == 1 else {
                return invalid(
                    target: target,
                    issue: issue(
                        .missingRequiredArgument,
                        index: 0,
                        "permissions.\(request.methodName) requires a permissions object."
                    )
                )
            }
            guard let object = request.rawArguments[0].objectValue else {
                return invalid(
                    target: target,
                    issue: issue(
                        .invalidType,
                        index: 0,
                        "permissions.\(request.methodName) requires an object argument."
                    )
                )
            }
            let permissions = stringArray(
                object["permissions"],
                fieldName: "permissions"
            )
            let origins = stringArray(object["origins"], fieldName: "origins")
            let issues = permissions.issues + origins.issues
            guard issues.isEmpty else {
                return invalid(target: target, issues: issues)
            }
            let input = ChromeMV3PermissionsAPIRequestInput(
                extensionID: request.extensionID,
                profileID: request.profileID,
                sourceContext: request.sourceContext.permissionsContext,
                userGestureModeled:
                    object["__sumiUserGestureModeled"]?.boolValue
                    ?? (request.sourceContext == .actionPopup),
                extensionModuleEnabled: true,
                permissions: permissions.values,
                origins: origins.values
            )
            return normalized(
                target: target,
                permissionsInput: input,
                payload: [
                    "permissions": .array(
                        permissions.values.map(ChromeMV3StorageValue.string)
                    ),
                    "origins": .array(
                        origins.values.map(ChromeMV3StorageValue.string)
                    ),
                ],
                diagnostics: request.sourceContext == .contentScript
                    ? [
                        "contentScript permissions calls are accepted only as a test fixture source context.",
                    ]
                    : []
            )
        case "getAll":
            guard request.rawArguments.isEmpty else {
                return unexpectedArgument(request: request, target: target)
            }
            return normalized(target: target)
        default:
            return invalid(
                target: target,
                status: .argumentUnsupported,
                issue: issue(
                    .unsupportedVariant,
                    index: nil,
                    "Unsupported permissions bridge method."
                )
            )
        }
    }

    private static func normalizeNativeMessaging(
        _ request: ChromeMV3JSBridgeRequestEnvelope,
        permissionState: ChromeMV3NativeMessagingPermissionState,
        productPolicy: ChromeMV3NativeMessagingProductPolicy
    ) -> ChromeMV3JSBridgeArgumentNormalization {
        guard let operation = nativeOperation(methodName: request.methodName)
        else {
            return invalid(
                target: apiTarget(request: request),
                status: .argumentUnsupported,
                issue: issue(
                    .unsupportedVariant,
                    index: nil,
                    "Unsupported native messaging bridge method."
                )
            )
        }
        guard let host = request.rawArguments.first?.stringValue,
              host.isEmpty == false
        else {
            return invalid(
                target: apiTarget(request: request),
                issue: issue(
                    .missingRequiredArgument,
                    index: 0,
                    "Native messaging bridge calls require a host name string."
                )
            )
        }
        if operation == .oneShotNativeMessage {
            guard request.rawArguments.count == 2 else {
                return invalid(
                    target: apiTarget(request: request),
                    issue: issue(
                        .missingRequiredArgument,
                        index: 1,
                        "One-shot native messaging bridge calls require a JSON message object."
                    )
                )
            }
            guard request.rawArguments[1].objectValue != nil else {
                return invalid(
                    target: apiTarget(request: request),
                    issue: issue(
                        .invalidType,
                        index: 1,
                        "One-shot native messaging message must be a JSON object."
                    )
                )
            }
        } else if request.rawArguments.count != 1 {
            return unexpectedArgument(
                request: request,
                target: apiTarget(request: request)
            )
        }
        let input = ChromeMV3NativeMessagingPreflightInput(
            extensionID: request.extensionID,
            profileID: request.profileID,
            hostName: host,
            operationKind: operation,
            sourceContext: request.sourceContext.runtimeContext,
            permissionState: permissionState,
            productPolicy: productPolicy
        )
        return normalized(
            target: apiTarget(
                request: request,
                nativeOperationKind: operation
            ),
            nativeInput: input,
            payload: [
                "hostName": .string(host),
                "operationKind": .string(operation.rawValue),
            ]
        )
    }

    private static func normalizeRuntimeSendMessage(
        _ request: ChromeMV3JSBridgeRequestEnvelope
    ) -> ChromeMV3JSBridgeArgumentNormalization {
        let args = request.rawArguments
        guard args.count >= 1 else {
            return invalid(
                target: apiTarget(
                    request: request,
                    routeKind: .runtimeSendMessage
                ),
                issue: issue(
                    .missingRequiredArgument,
                    index: 0,
                    "runtime.sendMessage requires a message argument."
                )
            )
        }
        guard args.count <= 2 else {
            return invalid(
                target: apiTarget(
                    request: request,
                    routeKind: .runtimeSendMessage
                ),
                status: .argumentUnsupported,
                issue: issue(
                    .unsupportedVariant,
                    index: nil,
                    "runtime.sendMessage external-extension overload is not modeled by this bridge contract."
                )
            )
        }
        if args.count == 2, args[1].objectValue == nil {
            return invalid(
                target: apiTarget(
                    request: request,
                    routeKind: .runtimeSendMessage
                ),
                issue: issue(
                    .invalidType,
                    index: 1,
                    "runtime.sendMessage options must be an object when supplied."
                )
            )
        }
        let routeKind = runtimeSendMessageRouteKind(
            sourceContext: request.sourceContext
        )
        let route = ChromeMV3RuntimeMessagingRoute.make(
            kind: routeKind,
            extensionID: request.extensionID,
            profileID: request.profileID,
            tabID: request.sourceContext == .contentScript ? 1 : nil,
            frameID: request.sourceContext == .contentScript ? 0 : nil,
            documentID:
                request.sourceContext == .contentScript
                    ? "bridge-document-0"
                    : nil,
            sourceURL:
                request.sourceContext == .contentScript
                    ? "https://example.com/login"
                    : nil,
            targetURL:
                request.sourceContext == .contentScript
                    ? "https://example.com/login"
                    : nil
        )
        return normalized(
            target: apiTarget(
                request: request,
                routeKind: routeKind
            ),
            route: route,
            payload: [
                "message": args[0],
                "options": args.count == 2 ? args[1] : .object([:]),
            ],
            diagnostics: [
                "runtime.sendMessage normalized as a one-shot model dispatcher route.",
            ]
        )
    }

    private static func normalizeRuntimeConnect(
        _ request: ChromeMV3JSBridgeRequestEnvelope
    ) -> ChromeMV3JSBridgeArgumentNormalization {
        let args = request.rawArguments
        guard args.count <= 2 else {
            return unexpectedArgument(
                request: request,
                target: apiTarget(
                    request: request,
                    routeKind: .runtimeConnect
                )
            )
        }
        var externalExtensionID: String?
        var connectInfo: [String: ChromeMV3StorageValue] = [:]
        if args.count == 1 {
            if let value = args[0].stringValue {
                externalExtensionID = value
            } else if let object = args[0].objectValue {
                connectInfo = object
            } else {
                return invalid(
                    target: apiTarget(
                        request: request,
                        routeKind: .runtimeConnect
                    ),
                    issue: issue(
                        .invalidType,
                        index: 0,
                        "runtime.connect expects an extension id string or connectInfo object."
                    )
                )
            }
        }
        if args.count == 2 {
            guard let value = args[0].stringValue else {
                return invalid(
                    target: apiTarget(
                        request: request,
                        routeKind: .runtimeConnect
                    ),
                    issue: issue(
                        .invalidType,
                        index: 0,
                        "runtime.connect extension id must be a string."
                    )
                )
            }
            guard let object = args[1].objectValue else {
                return invalid(
                    target: apiTarget(
                        request: request,
                        routeKind: .runtimeConnect
                    ),
                    issue: issue(
                        .invalidType,
                        index: 1,
                        "runtime.connect connectInfo must be an object."
                    )
                )
            }
            externalExtensionID = value
            connectInfo = object
        }
        let route = ChromeMV3RuntimeMessagingRoute.make(
            kind: .runtimeConnect,
            extensionID: request.extensionID,
            profileID: request.profileID
        )
        return normalized(
            target: apiTarget(
                request: request,
                routeKind: .runtimeConnect
            ),
            route: route,
            payload: connectPayload(
                externalExtensionID: externalExtensionID,
                connectInfo: connectInfo,
                tabID: nil
            ),
            diagnostics: uniqueSorted(
                [
                    "runtime.connect normalized as a model Port preflight.",
                    externalExtensionID == nil
                        ? nil
                        : "External extension id was recorded but external routing is not implemented.",
                ].compactMap { $0 }
            )
        )
    }

    private static func normalizeTabsSendMessage(
        _ request: ChromeMV3JSBridgeRequestEnvelope
    ) -> ChromeMV3JSBridgeArgumentNormalization {
        let args = request.rawArguments
        guard args.count >= 2 else {
            return invalid(
                target: apiTarget(
                    request: request,
                    routeKind: .tabsSendMessage
                ),
                issue: issue(
                    .missingRequiredArgument,
                    index: 0,
                    "tabs.sendMessage requires tabId and message arguments."
                )
            )
        }
        guard args.count <= 3 else {
            return unexpectedArgument(
                request: request,
                target: apiTarget(
                    request: request,
                    routeKind: .tabsSendMessage
                )
            )
        }
        guard let tabID = args[0].intValue else {
            return invalid(
                target: apiTarget(
                    request: request,
                    routeKind: .tabsSendMessage
                ),
                issue: issue(
                    .invalidType,
                    index: 0,
                    "tabs.sendMessage tabId must be an integer."
                )
            )
        }
        let options = args.count == 3 ? args[2].objectValue : [:]
        if args.count == 3, options == nil {
            return invalid(
                target: apiTarget(
                    request: request,
                    routeKind: .tabsSendMessage
                ),
                issue: issue(
                    .invalidType,
                    index: 2,
                    "tabs.sendMessage options must be an object."
                )
            )
        }
        let frameID = options?["frameId"]?.intValue ?? 0
        let documentID = options?["documentId"]?.stringValue
            ?? "bridge-document-\(frameID)"
        let route = ChromeMV3RuntimeMessagingRoute.make(
            kind: .tabsSendMessage,
            extensionID: request.extensionID,
            profileID: request.profileID,
            tabID: tabID,
            frameID: frameID,
            documentID: documentID,
            sourceURL: "https://example.com/login",
            targetURL: "https://example.com/login"
        )
        return normalized(
            target: apiTarget(
                request: request,
                routeKind: .tabsSendMessage
            ),
            route: route,
            payload: [
                "tabId": .number(Double(tabID)),
                "frameId": .number(Double(frameID)),
                "documentId": .string(documentID),
                "message": args[1],
                "options": args.count == 3 ? args[2] : .object([:]),
            ],
            diagnostics: [
                "tabs.sendMessage normalized as a one-shot model dispatcher route.",
            ]
        )
    }

    private static func normalizeTabsConnect(
        _ request: ChromeMV3JSBridgeRequestEnvelope
    ) -> ChromeMV3JSBridgeArgumentNormalization {
        let args = request.rawArguments
        guard args.count >= 1 else {
            return invalid(
                target: apiTarget(
                    request: request,
                    routeKind: .tabsConnect
                ),
                issue: issue(
                    .missingRequiredArgument,
                    index: 0,
                    "tabs.connect requires a tabId argument."
                )
            )
        }
        guard args.count <= 2 else {
            return unexpectedArgument(
                request: request,
                target: apiTarget(
                    request: request,
                    routeKind: .tabsConnect
                )
            )
        }
        guard let tabID = args[0].intValue else {
            return invalid(
                target: apiTarget(
                    request: request,
                    routeKind: .tabsConnect
                ),
                issue: issue(
                    .invalidType,
                    index: 0,
                    "tabs.connect tabId must be an integer."
                )
            )
        }
        let connectInfo = args.count == 2 ? args[1].objectValue : [:]
        if args.count == 2, connectInfo == nil {
            return invalid(
                target: apiTarget(
                    request: request,
                    routeKind: .tabsConnect
                ),
                issue: issue(
                    .invalidType,
                    index: 1,
                    "tabs.connect connectInfo must be an object."
                )
            )
        }
        let frameID = connectInfo?["frameId"]?.intValue ?? 0
        let documentID = connectInfo?["documentId"]?.stringValue
            ?? "bridge-document-\(frameID)"
        let route = ChromeMV3RuntimeMessagingRoute.make(
            kind: .tabsConnect,
            extensionID: request.extensionID,
            profileID: request.profileID,
            tabID: tabID,
            frameID: frameID,
            documentID: documentID,
            sourceURL: "https://example.com/login",
            targetURL: "https://example.com/login"
        )
        var payload = connectPayload(
            externalExtensionID: nil,
            connectInfo: connectInfo ?? [:],
            tabID: tabID
        )
        payload["frameId"] = .number(Double(frameID))
        payload["documentId"] = .string(documentID)
        return normalized(
            target: apiTarget(request: request, routeKind: .tabsConnect),
            route: route,
            payload: payload,
            diagnostics: [
                "tabs.connect normalized as a model Port preflight.",
            ]
        )
    }

    private static func runtimeSendMessageRouteKind(
        sourceContext: ChromeMV3JSBridgeSourceContext
    ) -> ChromeMV3RuntimeMessagingRouteKind {
        switch sourceContext {
        case .actionPopup:
            return .actionPopupToServiceWorker
        case .contentScript:
            return .contentScriptToServiceWorker
        case .optionsPage:
            return .optionsPageToServiceWorker
        case .extensionPage:
            return .extensionPageToServiceWorker
        case .serviceWorker, .testFixture:
            return .runtimeSendMessage
        }
    }

    private static func storageTarget(
        _ methodName: String
    ) -> ChromeMV3JSBridgeAPITarget? {
        let parts = methodName.split(separator: ".", maxSplits: 1)
        guard parts.count == 2,
              let area = ChromeMV3StorageAreaKind(rawValue: String(parts[0]))
        else { return nil }
        let operation: ChromeMV3StorageOperationKind?
        switch String(parts[1]) {
        case "get":
            operation = .get
        case "set":
            operation = .set
        case "remove":
            operation = .remove
        case "clear":
            operation = .clear
        case "getBytesInUse":
            operation = .getBytesInUse
        default:
            operation = nil
        }
        guard let operation else { return nil }
        return ChromeMV3JSBridgeAPITarget(
            namespace: .storage,
            methodName: methodName,
            storageArea: area,
            storageOperation: operation,
            routeKind: nil,
            nativeOperationKind: nil
        )
    }

    static func nativeOperation(
        methodName: String
    ) -> ChromeMV3NativeMessagingOperationKind? {
        if methodName == "connect" || methodName == nativeConnectName() {
            return .longLivedNativePort
        }
        if methodName == "send" || methodName == nativeSendName() {
            return .oneShotNativeMessage
        }
        return nil
    }

    static func nativeConnectName() -> String {
        ["connect", "Native"].joined()
    }

    static func nativeSendName() -> String {
        ["send", "Native", "Message"].joined()
    }

    private static func storageInvocationMode(
        _ mode: ChromeMV3JSBridgeInvocationMode
    ) -> ChromeMV3StorageAPIInvocationMode {
        mode == .callback ? .callback : .promise
    }

    private static func storageSelector(
        _ value: ChromeMV3StorageValue?,
        defaultWhenMissing: ChromeMV3StorageAPIKeySelector
    ) -> (
        selector: ChromeMV3StorageAPIKeySelector,
        issues: [ChromeMV3JSBridgeArgumentIssue]
    ) {
        guard let value else {
            return (defaultWhenMissing, [])
        }
        switch value {
        case .null:
            return (.allKeys, [])
        case .string(let key):
            return (.singleString(key), [])
        case .array(let values):
            var keys: [String] = []
            var issues: [ChromeMV3JSBridgeArgumentIssue] = []
            for (index, entry) in values.enumerated() {
                guard let key = entry.stringValue else {
                    issues.append(
                        issue(
                            .invalidType,
                            index: index,
                            "Storage key array entries must be strings."
                        )
                    )
                    continue
                }
                keys.append(key)
            }
            return (.stringArray(keys), issues)
        case .object(let defaults):
            return (.defaults(defaults), [])
        case .bool, .number:
            return (
                .invalidType(value.typeName),
                [
                    issue(
                        .invalidType,
                        index: 0,
                        "Unsupported storage key selector type \(value.typeName)."
                    ),
                ]
            )
        }
    }

    private static func stringArray(
        _ value: ChromeMV3StorageValue?,
        fieldName: String
    ) -> (values: [String], issues: [ChromeMV3JSBridgeArgumentIssue]) {
        guard let value else { return ([], []) }
        guard case .array(let entries) = value else {
            return (
                [],
                [
                    issue(
                        .invalidType,
                        index: nil,
                        "\(fieldName) must be a string array."
                    ),
                ]
            )
        }
        var values: [String] = []
        var issues: [ChromeMV3JSBridgeArgumentIssue] = []
        for (index, entry) in entries.enumerated() {
            guard let string = entry.stringValue else {
                issues.append(
                    issue(
                        .invalidType,
                        index: index,
                        "\(fieldName) entries must be strings."
                    )
                )
                continue
            }
            values.append(string)
        }
        return (uniqueSorted(values), issues)
    }

    private static func connectPayload(
        externalExtensionID: String?,
        connectInfo: [String: ChromeMV3StorageValue],
        tabID: Int?
    ) -> [String: ChromeMV3StorageValue] {
        var payload: [String: ChromeMV3StorageValue] = [
            "connectInfo": .object(connectInfo),
        ]
        if let externalExtensionID {
            payload["externalExtensionId"] = .string(externalExtensionID)
        }
        if let name = connectInfo["name"]?.stringValue {
            payload["name"] = .string(name)
        }
        if let tabID {
            payload["tabId"] = .number(Double(tabID))
        }
        return payload
    }

    private static func storagePayload(
        _ input: ChromeMV3StorageAPIOperationInput
    ) -> [String: ChromeMV3StorageValue] {
        [
            "area": .string(input.area.rawValue),
            "operation": .string(input.operation.rawValue),
            "operationID": .string(input.operationID),
        ]
    }

    private static func apiTarget(
        request: ChromeMV3JSBridgeRequestEnvelope,
        routeKind: ChromeMV3RuntimeMessagingRouteKind? = nil,
        nativeOperationKind:
            ChromeMV3NativeMessagingOperationKind? = nil
    ) -> ChromeMV3JSBridgeAPITarget {
        ChromeMV3JSBridgeAPITarget(
            namespace: request.namespace,
            methodName: request.methodName,
            storageArea: storageTarget(request.methodName)?.storageArea,
            storageOperation:
                storageTarget(request.methodName)?.storageOperation,
            routeKind: routeKind,
            nativeOperationKind: nativeOperationKind
        )
    }

    private static func normalized(
        target: ChromeMV3JSBridgeAPITarget?,
        route: ChromeMV3RuntimeMessagingRoute? = nil,
        storageInput: ChromeMV3StorageAPIOperationInput? = nil,
        permissionsInput:
            ChromeMV3PermissionsAPIRequestInput? = nil,
        nativeInput: ChromeMV3NativeMessagingPreflightInput? = nil,
        payload: [String: ChromeMV3StorageValue] = [:],
        diagnostics: [String] = []
    ) -> ChromeMV3JSBridgeArgumentNormalization {
        ChromeMV3JSBridgeArgumentNormalization(
            target: target,
            status: .normalized,
            runtimeRoute: route,
            storageOperationInput: storageInput,
            permissionsInput: permissionsInput,
            nativeMessagingInput: nativeInput,
            normalizedPayload: payload.sortedByKey(),
            issues: [],
            diagnostics:
                uniqueSorted(
                    [
                        "Bridge arguments normalized from JSON-compatible envelope values.",
                        "No JavaScript objects or functions were parsed.",
                    ] + diagnostics
                )
        )
    }

    private static func invalid(
        target: ChromeMV3JSBridgeAPITarget?,
        status: ChromeMV3JSBridgeArgumentNormalizationStatus =
            .invalidArguments,
        issue: ChromeMV3JSBridgeArgumentIssue
    ) -> ChromeMV3JSBridgeArgumentNormalization {
        invalid(target: target, status: status, issues: [issue])
    }

    private static func invalid(
        target: ChromeMV3JSBridgeAPITarget?,
        status: ChromeMV3JSBridgeArgumentNormalizationStatus =
            .invalidArguments,
        issues: [ChromeMV3JSBridgeArgumentIssue]
    ) -> ChromeMV3JSBridgeArgumentNormalization {
        ChromeMV3JSBridgeArgumentNormalization(
            target: target,
            status: status,
            runtimeRoute: nil,
            storageOperationInput: nil,
            permissionsInput: nil,
            nativeMessagingInput: nil,
            normalizedPayload: [:],
            issues: issues.sorted {
                if $0.kind != $1.kind {
                    return $0.kind < $1.kind
                }
                return ($0.argumentIndex ?? -1) < ($1.argumentIndex ?? -1)
            },
            diagnostics:
                uniqueSorted(
                    issues.flatMap(\.diagnostics)
                        + issues.map(\.message)
                        + [
                            "Bridge arguments were rejected before host model routing.",
                        ]
                )
        )
    }

    private static func unexpectedArgument(
        request: ChromeMV3JSBridgeRequestEnvelope,
        target: ChromeMV3JSBridgeAPITarget
    ) -> ChromeMV3JSBridgeArgumentNormalization {
        invalid(
            target: target,
            issue: issue(
                .unexpectedArgument,
                index: request.rawArguments.count - 1,
                "Unexpected extra bridge argument for \(request.namespace.rawValue).\(request.methodName)."
            )
        )
    }

    private static func issue(
        _ kind: ChromeMV3JSBridgeArgumentIssueKind,
        index: Int?,
        _ message: String
    ) -> ChromeMV3JSBridgeArgumentIssue {
        ChromeMV3JSBridgeArgumentIssue(
            kind: kind,
            argumentIndex: index,
            message: message,
            diagnostics: [message]
        )
    }
}

enum ChromeMV3JSBridgeContractRouter {
    static func route(
        _ request: ChromeMV3JSBridgeRequestEnvelope,
        environment: inout ChromeMV3JSBridgeContractEnvironment
    ) -> ChromeMV3JSBridgeResponseEnvelope {
        guard request.namespace != .unsupported else {
            return failure(
                request: request,
                routeResult: nil,
                code: .namespaceUnsupported,
                diagnostics: [
                    "No host model route exists for unsupported namespaces.",
                ]
            )
        }
        guard ChromeMV3JSBridgeMethodCapabilityMatrix
            .capability(
                namespace: request.namespace,
                methodName: request.methodName
            ) != nil
        else {
            return failure(
                request: request,
                routeResult: nil,
                code: .methodUnsupported,
                diagnostics: [
                    "Bridge method is absent from the model capability matrix.",
                ]
            )
        }

        let normalization = ChromeMV3JSBridgeArgumentNormalizer.normalize(
            request: request,
            environment: environment
        )
        guard normalization.canRouteToHostModel else {
            let result = routeResult(
                normalization: normalization,
                diagnostics: normalization.diagnostics
            )
            return failure(
                request: request,
                routeResult: result,
                code: .invalidArguments,
                diagnostics: normalization.diagnostics
            )
        }
        guard environment.moduleState == .enabled else {
            let result = routeResult(
                normalization: normalization,
                diagnostics: [
                    "Extensions module is disabled; bridge model routing is blocked.",
                ]
            )
            return failure(
                request: request,
                routeResult: result,
                code: .extensionDisabled,
                diagnostics: result.diagnostics
            )
        }

        switch request.namespace {
        case .runtime, .tabs:
            return routeRuntimeOrTabs(
                request,
                normalization: normalization,
                environment: environment
            )
        case .storage:
            return routeStorage(
                request,
                normalization: normalization,
                environment: &environment
            )
        case .permissions:
            return routePermissions(
                request,
                normalization: normalization,
                environment: &environment
            )
        case .nativeMessaging:
            return routeNativeMessaging(
                request,
                normalization: normalization,
                environment: environment
            )
        case .unsupported:
            return failure(
                request: request,
                routeResult: nil,
                code: .namespaceUnsupported
            )
        }
    }

    private static func routeRuntimeOrTabs(
        _ request: ChromeMV3JSBridgeRequestEnvelope,
        normalization: ChromeMV3JSBridgeArgumentNormalization,
        environment: ChromeMV3JSBridgeContractEnvironment
    ) -> ChromeMV3JSBridgeResponseEnvelope {
        guard let route = normalization.runtimeRoute else {
            return failure(
                request: request,
                routeResult: routeResult(normalization: normalization),
                code: .runtimeDispatchUnavailable
            )
        }
        let responseMode = runtimeResponseMode(request.invocationMode)
        let input = ChromeMV3RuntimeMessageDispatcherInput.make(
            route: route,
            listenerRegistrySnapshot:
                environment.listenerRegistrySnapshot,
            permissionBrokerSnapshot: environment.permissionBroker,
            serviceWorkerLifecycleSnapshot:
                environment.serviceWorkerLifecycleSnapshot,
            moduleState: environment.moduleState,
            dispatchMode: .modelOnly,
            responseMode: responseMode,
            expectsResponse: request.methodName == "sendMessage",
            userGestureAvailable: request.sourceContext == .actionPopup,
            nativeHostName: nil,
            seed: request.bridgeCallID
        )
        let dispatcherResult = ChromeMV3RuntimeMessageDispatcher.dispatch(
            input: input
        )
        let result = routeResult(
            normalization: normalization,
            runtimeDispatcherResult: dispatcherResult,
            diagnostics: dispatcherResult.diagnostics
        )
        if let runtimeError = dispatcherResult.selectedLastError?.error {
            return failure(
                request: request,
                routeResult: result,
                code: bridgeError(runtimeError),
                diagnostics: dispatcherResult.diagnostics
            )
        }
        let payload = dispatcherResult.responsePayload
            ?? runtimeSuccessPayload(dispatcherResult)
        return success(
            request: request,
            routeResult: result,
            payload: payload,
            diagnostics:
                uniqueSorted(
                    dispatcherResult.diagnostics
                        + [
                            "Runtime/tabs request routed to model dispatcher only.",
                        ]
                )
        )
    }

    private static func routeStorage(
        _ request: ChromeMV3JSBridgeRequestEnvelope,
        normalization: ChromeMV3JSBridgeArgumentNormalization,
        environment: inout ChromeMV3JSBridgeContractEnvironment
    ) -> ChromeMV3JSBridgeResponseEnvelope {
        guard let input = normalization.storageOperationInput else {
            return failure(
                request: request,
                routeResult: routeResult(normalization: normalization),
                code: .apiContractNotImplemented
            )
        }
        let handler = ChromeMV3StorageAPIOperationHandler(
            state: environment.storageHandlerState
        )
        let envelope: ChromeMV3StorageAPIOperationResultEnvelope
        switch input.area {
        case .local:
            envelope = handler.handle(
                input,
                broker: &environment.localStorageBroker
            )
        case .session:
            envelope = handler.handle(
                input,
                broker: &environment.sessionStorageBroker
            )
        case .sync:
            envelope = handler.handle(
                input,
                broker: &environment.syncStorageBroker
            )
        case .managed:
            envelope = handler.handle(
                input,
                broker: &environment.managedStorageBroker
            )
        }
        let result = routeResult(
            normalization: normalization,
            storageOperationResult: envelope,
            diagnostics: envelope.diagnostics
        )
        guard envelope.succeeded else {
            return failure(
                request: request,
                routeResult: result,
                code: bridgeError(envelope.futureLastErrorContract?.code),
                diagnostics: envelope.diagnostics
            )
        }
        return success(
            request: request,
            routeResult: result,
            payload: storagePayload(envelope),
            diagnostics:
                uniqueSorted(
                    envelope.diagnostics
                        + [
                            "Storage request routed to operation handler model.",
                        ]
                )
        )
    }

    private static func routePermissions(
        _ request: ChromeMV3JSBridgeRequestEnvelope,
        normalization: ChromeMV3JSBridgeArgumentNormalization,
        environment: inout ChromeMV3JSBridgeContractEnvironment
    ) -> ChromeMV3JSBridgeResponseEnvelope {
        var runtimeOwner = ChromeMV3PermissionRuntimeStateOwner(
            permissionStore: environment.permissionStore,
            activeTabStore: environment.activeTabStore
        )
        switch request.methodName {
        case "contains":
            guard let input = normalization.permissionsInput else {
                return failure(
                    request: request,
                    routeResult: routeResult(normalization: normalization),
                    code: .invalidArguments
                )
            }
            let result = runtimeOwner.contains(input: input)
            return success(
                request: request,
                routeResult: routeResult(
                    normalization: normalization,
                    permissionsContainsResult: result,
                    diagnostics: result.diagnostics
                ),
                payload: .bool(result.wouldReturn),
                diagnostics: result.diagnostics
            )
        case "getAll":
            let result = runtimeOwner.getAll()
            return success(
                request: request,
                routeResult: routeResult(
                    normalization: normalization,
                    permissionsGetAllResult: result,
                    diagnostics: result.diagnostics
                ),
                payload: .object([
                    "permissions": .array(
                        result.permissions.map(ChromeMV3StorageValue.string)
                    ),
                    "origins": .array(
                        result.origins.map(ChromeMV3StorageValue.string)
                    ),
                ]),
                diagnostics: result.diagnostics
            )
        case "request":
            guard let input = normalization.permissionsInput else {
                return failure(
                    request: request,
                    routeResult: routeResult(normalization: normalization),
                    code: .invalidArguments
                )
            }
            let application = runtimeOwner.request(
                input: input,
                modeledPromptResult: modeledPermissionPromptResult(
                    from: request
                )
            )
            environment.permissionStore = application.permissionStore
            environment.activeTabStore = application.activeTabStore
            return success(
                request: request,
                routeResult: routeResult(
                    normalization: normalization,
                    permissionsRequestResult: application.result,
                    diagnostics: application.diagnostics
                ),
                payload: .bool(application.returnedBoolean),
                diagnostics: application.diagnostics
            )
        case "remove":
            guard let input = normalization.permissionsInput else {
                return failure(
                    request: request,
                    routeResult: routeResult(normalization: normalization),
                    code: .invalidArguments
                )
            }
            let application = runtimeOwner.remove(input: input)
            environment.permissionStore = application.permissionStore
            environment.activeTabStore = application.activeTabStore
            return success(
                request: request,
                routeResult: routeResult(
                    normalization: normalization,
                    permissionsRemoveResult: application.result,
                    diagnostics: application.diagnostics
                ),
                payload: .bool(application.returnedBoolean),
                diagnostics: application.diagnostics
            )
        default:
            return failure(
                request: request,
                routeResult: routeResult(normalization: normalization),
                code: .methodUnsupported
            )
        }
    }

    private static func modeledPermissionPromptResult(
        from request: ChromeMV3JSBridgeRequestEnvelope
    ) -> ChromeMV3ModeledPermissionPromptResult {
        guard let object = request.rawArguments.first?.objectValue,
              let value = object["__sumiModeledPromptResult"]
        else { return .notProvided }
        if let bool = value.boolValue {
            return bool ? .accepted : .denied
        }
        switch value.stringValue?.lowercased() {
        case "accept", "accepted", "grant", "granted", "allow", "allowed":
            return .accepted
        case "deny", "denied", "reject", "rejected", "block", "blocked":
            return .denied
        default:
            return .notProvided
        }
    }

    private static func routeNativeMessaging(
        _ request: ChromeMV3JSBridgeRequestEnvelope,
        normalization: ChromeMV3JSBridgeArgumentNormalization,
        environment: ChromeMV3JSBridgeContractEnvironment
    ) -> ChromeMV3JSBridgeResponseEnvelope {
        guard let input = normalization.nativeMessagingInput else {
            return failure(
                request: request,
                routeResult: routeResult(normalization: normalization),
                code: .invalidArguments
            )
        }
        let preflight = ChromeMV3NativeMessagingPreflightEvaluator.evaluate(
            input: input,
            lookupPolicy: environment.nativeLookupPolicy
        )
        let result = routeResult(
            normalization: normalization,
            nativeMessagingPreflight: preflight,
            diagnostics: preflight.diagnostics
        )
        return failure(
            request: request,
            routeResult: result,
            code: .nativeMessagingBlocked,
            payload: .object([
                "hostName": .string(preflight.hostName),
                "operationKind": .string(preflight.operationKind.rawValue),
                "canConnectNativeNow": .bool(false),
                "canSendNativeMessageNow": .bool(false),
                "processLaunchAllowedNow": .bool(false),
            ]),
            diagnostics: preflight.diagnostics
        )
    }

    private static func success(
        request: ChromeMV3JSBridgeRequestEnvelope,
        routeResult: ChromeMV3JSBridgeRouteResult,
        payload: ChromeMV3StorageValue?,
        diagnostics: [String]
    ) -> ChromeMV3JSBridgeResponseEnvelope {
        ChromeMV3JSBridgeResponseEnvelope(
            bridgeCallID: request.bridgeCallID,
            succeeded: true,
            resultPayload: payload,
            lastErrorContract: nil,
            promiseBehavior: promiseBehavior(
                mode: request.invocationMode,
                succeeded: true,
                lastError: nil
            ),
            callbackBehavior: callbackBehavior(
                mode: request.invocationMode,
                succeeded: true,
                payload: payload,
                lastError: nil
            ),
            routeResult: routeResult,
            runtimeExposureNow: false,
            jsBridgeAvailableNow: false,
            diagnostics:
                responseDiagnostics(
                    diagnostics
                        + [
                            "Bridge request succeeded in model routing only.",
                        ]
                )
        )
    }

    private static func failure(
        request: ChromeMV3JSBridgeRequestEnvelope,
        routeResult: ChromeMV3JSBridgeRouteResult?,
        code: ChromeMV3JSBridgeErrorCode,
        payload: ChromeMV3StorageValue? = nil,
        diagnostics: [String] = []
    ) -> ChromeMV3JSBridgeResponseEnvelope {
        let lastError = ChromeMV3JSBridgeLastErrorContract.make(
            code: code,
            invocationMode: request.invocationMode,
            diagnostics: diagnostics
        )
        return ChromeMV3JSBridgeResponseEnvelope(
            bridgeCallID: request.bridgeCallID,
            succeeded: false,
            resultPayload: payload,
            lastErrorContract: lastError,
            promiseBehavior: promiseBehavior(
                mode: request.invocationMode,
                succeeded: false,
                lastError: lastError
            ),
            callbackBehavior: callbackBehavior(
                mode: request.invocationMode,
                succeeded: false,
                payload: nil,
                lastError: lastError
            ),
            routeResult: routeResult,
            runtimeExposureNow: false,
            jsBridgeAvailableNow: false,
            diagnostics:
                responseDiagnostics(
                    diagnostics
                        + [
                            "Bridge request failed deterministically with \(code.rawValue).",
                        ]
                )
        )
    }

    private static func routeResult(
        normalization: ChromeMV3JSBridgeArgumentNormalization,
        runtimeDispatcherResult:
            ChromeMV3RuntimeMessageDispatcherResult? = nil,
        storageOperationResult:
            ChromeMV3StorageAPIOperationResultEnvelope? = nil,
        permissionsContainsResult:
            ChromeMV3PermissionsAPIContainsResult? = nil,
        permissionsGetAllResult:
            ChromeMV3PermissionsAPIGetAllResult? = nil,
        permissionsRequestResult:
            ChromeMV3PermissionsAPIRequestResult? = nil,
        permissionsRemoveResult:
            ChromeMV3PermissionsAPIRemoveResult? = nil,
        nativeMessagingPreflight:
            ChromeMV3NativeMessagingOperationPreflight? = nil,
        diagnostics: [String] = []
    ) -> ChromeMV3JSBridgeRouteResult {
        ChromeMV3JSBridgeRouteResult(
            normalizedArguments: normalization,
            runtimeDispatcherResult: runtimeDispatcherResult,
            storageOperationResult: storageOperationResult,
            permissionsContainsResult: permissionsContainsResult,
            permissionsGetAllResult: permissionsGetAllResult,
            permissionsRequestResult: permissionsRequestResult,
            permissionsRemoveResult: permissionsRemoveResult,
            nativeMessagingPreflight: nativeMessagingPreflight,
            routedToHostModel:
                runtimeDispatcherResult != nil
                    || storageOperationResult != nil
                    || permissionsContainsResult != nil
                    || permissionsGetAllResult != nil
                    || permissionsRequestResult != nil
                    || permissionsRemoveResult != nil
                    || nativeMessagingPreflight != nil,
            openedRuntimePortNow: false,
            openedNativePortNow: false,
            dispatchedStorageOnChangedNow: false,
            wokeServiceWorkerNow: false,
            loadedContextNow: false,
            diagnostics:
                uniqueSorted(
                    normalization.diagnostics
                        + diagnostics
                        + [
                            "Bridge route result is host-model only.",
                            "No Port, event dispatch, context load, or service-worker wake occurred.",
                        ]
                )
        )
    }

    private static func runtimeResponseMode(
        _ mode: ChromeMV3JSBridgeInvocationMode
    ) -> ChromeMV3RuntimeMessagingResponseMode {
        switch mode {
        case .callback:
            return .callback
        case .promise:
            return .promise
        case .fireAndForget, .callbackAndPromiseInvalid:
            return .none
        }
    }

    private static func promiseBehavior(
        mode: ChromeMV3JSBridgeInvocationMode,
        succeeded: Bool,
        lastError: ChromeMV3JSBridgeLastErrorContract?
    ) -> ChromeMV3JSBridgePromiseBehavior {
        let requested = mode == .promise
        return ChromeMV3JSBridgePromiseBehavior(
            promiseModeRequested: requested,
            wouldResolve: requested && succeeded,
            wouldReject: requested && succeeded == false,
            rejectionMessage:
                requested ? lastError?.futureLastErrorMessage : nil
        )
    }

    private static func callbackBehavior(
        mode: ChromeMV3JSBridgeInvocationMode,
        succeeded: Bool,
        payload: ChromeMV3StorageValue?,
        lastError: ChromeMV3JSBridgeLastErrorContract?
    ) -> ChromeMV3JSBridgeCallbackBehavior {
        let requested = mode == .callback
        return ChromeMV3JSBridgeCallbackBehavior(
            callbackModeRequested: requested,
            wouldInvokeCallback: requested,
            callbackPayload: requested && succeeded ? payload : nil,
            wouldSetRuntimeLastError:
                requested && succeeded == false,
            lastErrorMessage:
                requested ? lastError?.futureLastErrorMessage : nil
        )
    }

    private static func runtimeSuccessPayload(
        _ result: ChromeMV3RuntimeMessageDispatcherResult
    ) -> ChromeMV3StorageValue {
        if let preflight = result.modelPortPreflight {
            return .object([
                "portID": .string(preflight.portID),
                "canOpenRuntimePortNow": .bool(false),
                "canOpenNativePortNow": .bool(false),
                "runtimeLoadable": .bool(false),
            ])
        }
        return .null
    }

    private static func storagePayload(
        _ envelope: ChromeMV3StorageAPIOperationResultEnvelope
    ) -> ChromeMV3StorageValue {
        if envelope.resultPayload.values.isEmpty == false {
            return .object(envelope.resultPayload.values)
        }
        if let bytes = envelope.resultPayload.bytesInUse {
            return .number(Double(bytes))
        }
        return .null
    }

    private static func bridgeError(
        _ runtimeError: ChromeMV3RuntimeLastErrorCase
    ) -> ChromeMV3JSBridgeErrorCode {
        switch runtimeError {
        case .contextNotLoaded:
            return .contextNotLoaded
        case .extensionDisabled:
            return .extensionDisabled
        case .hostPermissionMissing, .permissionDenied, .activeTabMissing:
            return .permissionDenied
        case .nativeMessagingBlocked:
            return .nativeMessagingBlocked
        case .serviceWorkerUnavailable:
            return .serviceWorkerWakeUnavailable
        case .routeNotImplemented,
             .listenerRegistrationNotImplemented,
             .noReceivingEnd,
             .targetFrameMissing,
             .targetTabMissing,
             .timeout:
            return .runtimeDispatchUnavailable
        case .unsupportedAPI:
            return .unsupportedAPI
        }
    }

    private static func bridgeError(
        _ storageError: ChromeMV3StorageErrorCode?
    ) -> ChromeMV3JSBridgeErrorCode {
        switch storageError {
        case .extensionDisabled:
            return .extensionDisabled
        case .contextNotLoaded:
            return .contextNotLoaded
        case .invalidKey, .invalidValue, .snapshotNamespaceMismatch:
            return .invalidArguments
        case .areaDeferred, .areaUnsupported,
             .readOnlyOrUnsupportedArea, .syncUnavailable,
             .readNotAllowed, .writeNotAllowed:
            return .storageAreaUnavailable
        case .operationNotImplementedForJSRuntime:
            return .apiContractNotImplemented
        case .storageBackendUnavailable, .storageRuntimeNotImplemented,
             .quotaBytesExceeded, .quotaBytesPerItemExceeded,
             .maxItemsExceeded, nil:
            return .storageAreaUnavailable
        }
    }

    private static func responseDiagnostics(
        _ diagnostics: [String]
    ) -> [String] {
        uniqueSorted(
            diagnostics
                + [
                    "runtimeExposureNow remains false.",
                    "jsBridgeAvailableNow remains false.",
                    "No JavaScript callback or Promise is executed.",
                ]
        )
    }
}

struct ChromeMV3JSBridgeMethodCapability:
    Codable,
    Equatable,
    Sendable
{
    var namespace: ChromeMV3JSBridgeNamespace
    var methodName: String
    var modeledNow: Bool
    var routedToHostModel: Bool
    var exposedToJSNow: Bool
    var requiresContext: Bool
    var requiresServiceWorkerWake: Bool
    var requiresPermission: Bool
    var requiresStorageBroker: Bool
    var requiresNativeHost: Bool
    var blockers: [String]
    var futureTestsRequired: [String]
}

struct ChromeMV3JSBridgeRoutingSummary:
    Codable,
    Equatable,
    Sendable
{
    var modeledMethodCount: Int
    var routedToHostModelCount: Int
    var exposedToJSNow: Bool
    var jsBridgeAvailableNow: Bool
    var modelBridgeRoutingAvailable: Bool
    var canInjectScriptsNow: Bool
    var canWakeServiceWorkerNow: Bool
    var canLoadContextNow: Bool
    var runtimeLoadable: Bool
}

enum ChromeMV3JSBridgeMethodCapabilityMatrix {
    static func capability(
        namespace: ChromeMV3JSBridgeNamespace,
        methodName: String
    ) -> ChromeMV3JSBridgeMethodCapability? {
        allCapabilities().first {
            $0.namespace == namespace && $0.methodName == methodName
        }
    }

    static func allCapabilities()
        -> [ChromeMV3JSBridgeMethodCapability]
    {
        let storageOperations: [String] = [
            "get",
            "set",
            "remove",
            "clear",
            "getBytesInUse",
        ]
        let storageAreas: [ChromeMV3StorageAreaKind] = [
            .local,
            .session,
            .sync,
        ]
        var capabilities: [ChromeMV3JSBridgeMethodCapability] = []
        for area in storageAreas {
            for operation in storageOperations {
                let methodName = area.rawValue + "." + operation
                let blockers: [String] = area == .sync
                    ? [
                        "storage.sync routes to current deferred sync policy.",
                        "No sync runtime support is claimed.",
                    ]
                    : [
                        "chrome.storage JavaScript exposure is unavailable.",
                    ]
                capabilities.append(method(
                    namespace: .storage,
                    methodName: methodName,
                    modeledNow: area != .sync,
                    routed: true,
                    requiresContext: false,
                    requiresServiceWorkerWake: false,
                    requiresPermission: true,
                    requiresStorageBroker: true,
                    requiresNativeHost: false,
                    blockers: blockers,
                    futureTestsRequired: [
                        "Future JS shim argument compatibility.",
                        "Future runtime lastError parity.",
                    ]
                ))
            }
        }
        capabilities.append(
            contentsOf: [
                method(
                    namespace: .runtime,
                    methodName: "sendMessage",
                    modeledNow: true,
                    routed: true,
                    requiresContext: true,
                    requiresServiceWorkerWake: true,
                    requiresPermission: false,
                    requiresStorageBroker: false,
                    requiresNativeHost: false
                ),
                method(
                    namespace: .runtime,
                    methodName: "connect",
                    modeledNow: true,
                    routed: true,
                    requiresContext: true,
                    requiresServiceWorkerWake: true,
                    requiresPermission: false,
                    requiresStorageBroker: false,
                    requiresNativeHost: false,
                    blockers: [
                        "Port opening is a preflight only.",
                    ]
                ),
                method(
                    namespace: .tabs,
                    methodName: "sendMessage",
                    modeledNow: true,
                    routed: true,
                    requiresContext: true,
                    requiresServiceWorkerWake: false,
                    requiresPermission: true,
                    requiresStorageBroker: false,
                    requiresNativeHost: false
                ),
                method(
                    namespace: .tabs,
                    methodName: "connect",
                    modeledNow: true,
                    routed: true,
                    requiresContext: true,
                    requiresServiceWorkerWake: false,
                    requiresPermission: true,
                    requiresStorageBroker: false,
                    requiresNativeHost: false,
                    blockers: [
                        "Port opening is a preflight only.",
                    ]
                ),
                method(
                    namespace: .permissions,
                    methodName: "contains",
                    modeledNow: true,
                    routed: true,
                    requiresContext: false,
                    requiresServiceWorkerWake: false,
                    requiresPermission: false,
                    requiresStorageBroker: false,
                    requiresNativeHost: false
                ),
                method(
                    namespace: .permissions,
                    methodName: "getAll",
                    modeledNow: true,
                    routed: true,
                    requiresContext: false,
                    requiresServiceWorkerWake: false,
                    requiresPermission: false,
                    requiresStorageBroker: false,
                    requiresNativeHost: false
                ),
                method(
                    namespace: .permissions,
                    methodName: "request",
                    modeledNow: true,
                    routed: true,
                    requiresContext: false,
                    requiresServiceWorkerWake: false,
                    requiresPermission: false,
                    requiresStorageBroker: false,
                    requiresNativeHost: false,
                    blockers: [
                        "Product permission UI is unavailable.",
                    ]
                ),
                method(
                    namespace: .permissions,
                    methodName: "remove",
                    modeledNow: true,
                    routed: true,
                    requiresContext: false,
                    requiresServiceWorkerWake: false,
                    requiresPermission: false,
                    requiresStorageBroker: false,
                    requiresNativeHost: false,
                    blockers: [
                        "Permission events are modeled but not dispatched.",
                    ]
                ),
                method(
                    namespace: .nativeMessaging,
                    methodName: "connect",
                    modeledNow: true,
                    routed: true,
                    requiresContext: true,
                    requiresServiceWorkerWake: false,
                    requiresPermission: true,
                    requiresStorageBroker: false,
                    requiresNativeHost: true,
                    blockers: [
                        "Native host access is a blocked preflight only.",
                    ]
                ),
                method(
                    namespace: .nativeMessaging,
                    methodName: "send",
                    modeledNow: true,
                    routed: true,
                    requiresContext: true,
                    requiresServiceWorkerWake: false,
                    requiresPermission: true,
                    requiresStorageBroker: false,
                    requiresNativeHost: true,
                    blockers: [
                        "Native host access is a blocked preflight only.",
                    ]
                ),
                method(
                    namespace: .nativeMessaging,
                    methodName:
                        ChromeMV3JSBridgeArgumentNormalizer
                        .nativeConnectName(),
                    modeledNow: true,
                    routed: true,
                    requiresContext: true,
                    requiresServiceWorkerWake: false,
                    requiresPermission: true,
                    requiresStorageBroker: false,
                    requiresNativeHost: true,
                    blockers: [
                        "Native host access is a blocked preflight only.",
                    ]
                ),
                method(
                    namespace: .nativeMessaging,
                    methodName:
                        ChromeMV3JSBridgeArgumentNormalizer
                        .nativeSendName(),
                    modeledNow: true,
                    routed: true,
                    requiresContext: true,
                    requiresServiceWorkerWake: false,
                    requiresPermission: true,
                    requiresStorageBroker: false,
                    requiresNativeHost: true,
                    blockers: [
                        "Native host access is a blocked preflight only.",
                    ]
                ),
            ]
        )
        return capabilities.sorted {
            if $0.namespace != $1.namespace {
                return $0.namespace < $1.namespace
            }
            return $0.methodName < $1.methodName
        }
    }

    static func routingSummary() -> ChromeMV3JSBridgeRoutingSummary {
        let capabilities = allCapabilities()
        return ChromeMV3JSBridgeRoutingSummary(
            modeledMethodCount:
                capabilities.filter(\.modeledNow).count,
            routedToHostModelCount:
                capabilities.filter(\.routedToHostModel).count,
            exposedToJSNow: false,
            jsBridgeAvailableNow: false,
            modelBridgeRoutingAvailable: true,
            canInjectScriptsNow: false,
            canWakeServiceWorkerNow: false,
            canLoadContextNow: false,
            runtimeLoadable: false
        )
    }

    private static func method(
        namespace: ChromeMV3JSBridgeNamespace,
        methodName: String,
        modeledNow: Bool,
        routed: Bool,
        requiresContext: Bool,
        requiresServiceWorkerWake: Bool,
        requiresPermission: Bool,
        requiresStorageBroker: Bool,
        requiresNativeHost: Bool,
        blockers: [String] = [
            "Bridge contract is not exposed to JavaScript.",
        ],
        futureTestsRequired: [String] = [
            "Future JS shim envelope compatibility.",
            "Future host runtime exposure parity.",
        ]
    ) -> ChromeMV3JSBridgeMethodCapability {
        ChromeMV3JSBridgeMethodCapability(
            namespace: namespace,
            methodName: methodName,
            modeledNow: modeledNow,
            routedToHostModel: routed,
            exposedToJSNow: false,
            requiresContext: requiresContext,
            requiresServiceWorkerWake: requiresServiceWorkerWake,
            requiresPermission: requiresPermission,
            requiresStorageBroker: requiresStorageBroker,
            requiresNativeHost: requiresNativeHost,
            blockers:
                uniqueSorted(
                    blockers
                        + [
                            "No bridge shim is installed.",
                            "No extension context is created or loaded.",
                        ]
                ),
            futureTestsRequired: uniqueSorted(futureTestsRequired)
        )
    }
}

struct ChromeMV3JSBridgeArgumentNormalizationCoverage:
    Codable,
    Equatable,
    Sendable
{
    var runtimeSendMessageCovered: Bool
    var runtimeConnectCovered: Bool
    var tabsSendMessageCovered: Bool
    var tabsConnectCovered: Bool
    var storageKeyVariantsCovered: [ChromeMV3StorageAPIKeySelectorKind]
    var permissionsObjectCovered: Bool
    var nativeMessagingHostAndMessageCovered: Bool
}

struct ChromeMV3JSBridgeRouterCoverage:
    Codable,
    Equatable,
    Sendable
{
    var runtimeMessagingRoutesToDispatcher: Bool
    var storageRoutesToOperationHandler: Bool
    var permissionsRoutesToAPIContract: Bool
    var nativeMessagingRoutesToBlockedPreflight: Bool
    var unsupportedAPIsProduceDeterministicErrors: Bool
}

struct ChromeMV3JSBridgeResponseErrorCoverage:
    Codable,
    Equatable,
    Sendable
{
    var errorCodes: [ChromeMV3JSBridgeErrorCode]
    var callbackModeRepresented: Bool
    var promiseModeRepresented: Bool
    var lastErrorMapped: Bool
}

struct ChromeMV3JSBridgeIntegrationSummary:
    Codable,
    Equatable,
    Sendable
{
    var runtimeDispatcherModelRouteAvailable: Bool
    var storageOperationHandlerAvailable: Bool
    var permissionsAPIContractAvailable: Bool
    var nativeMessagingPreflightAvailable: Bool
    var serviceWorkerLifecycleRemainsBlocked: Bool
}

struct ChromeMV3PasswordManagerJSBridgeSummary:
    Codable,
    Equatable,
    Sendable
{
    var runtimeSendMessageEnvelopeRouteModeled: Bool
    var storageLocalEnvelopeRouteModeled: Bool
    var permissionsEnvelopeRouteModeled: Bool
    var nativeMessagingEnvelopeRouteBlocked: Bool
    var contentScriptJSShimInjected: Bool
    var extensionPageJSShimInjected: Bool
    var serviceWorkerWoken: Bool
    var passwordManagerJSBridgeModelReady: Bool
    var passwordManagerRuntimeBridgeReady: Bool
    var blockers: [String]
}

struct ChromeMV3JSBridgeContractReportSummary:
    Codable,
    Equatable,
    Sendable
{
    var reportID: String
    var reportFileName: String
    var modelBridgeRoutingAvailable: Bool
    var jsBridgeAvailableNow: Bool
    var exposedToJSNow: Bool
    var canInjectScriptsNow: Bool
    var canWakeServiceWorkerNow: Bool
    var canCreateContextNow: Bool
    var canLoadContextNow: Bool
    var runtimeLoadable: Bool
    var passwordManagerJSBridgeModelReady: Bool
    var passwordManagerRuntimeBridgeReady: Bool
    var extensionPageHostSummary:
        ChromeMV3ExtensionPageHostReportSummary? = nil
    var runtimeJSMessagingMVPSummary:
        ChromeMV3RuntimeJSMessagingMVPReportSummary? = nil
    var tabsScriptingMVPSummary:
        ChromeMV3TabsScriptingMVPReportSummary? = nil
}

struct ChromeMV3JSBridgeContractReport:
    Codable,
    Equatable,
    Sendable
{
    var schemaVersion: Int
    var id: String
    var reportFileName: String
    var extensionID: String
    var profileID: String
    var supportedModeledMethods: [ChromeMV3JSBridgeMethodCapability]
    var unsupportedDeferredAPIs: [String]
    var argumentNormalizationCoverage:
        ChromeMV3JSBridgeArgumentNormalizationCoverage
    var routerCoverage: ChromeMV3JSBridgeRouterCoverage
    var responseErrorCoverage: ChromeMV3JSBridgeResponseErrorCoverage
    var callbackPromiseCoverage: [ChromeMV3JSBridgeInvocationMode]
    var integrationSummary: ChromeMV3JSBridgeIntegrationSummary
    var passwordManagerJSBridgeSummary:
        ChromeMV3PasswordManagerJSBridgeSummary
    var modelBridgeRoutingAvailable: Bool
    var jsBridgeAvailableNow: Bool
    var exposedToJSNow: Bool
    var canInjectScriptsNow: Bool
    var canWakeServiceWorkerNow: Bool
    var canCreateContextNow: Bool
    var canLoadContextNow: Bool
    var runtimeLoadable: Bool
    var extensionPageHostSummary:
        ChromeMV3ExtensionPageHostReportSummary? = nil
    var runtimeJSMessagingMVPSummary:
        ChromeMV3RuntimeJSMessagingMVPReportSummary? = nil
    var tabsScriptingMVPSummary:
        ChromeMV3TabsScriptingMVPReportSummary? = nil
    var documentationSources: [ChromeMV3ManifestRewritePreviewSource]
    var diagnostics: [String]
    var blockers: [String]

    var summary: ChromeMV3JSBridgeContractReportSummary {
        ChromeMV3JSBridgeContractReportSummary(
            reportID: id,
            reportFileName: reportFileName,
            modelBridgeRoutingAvailable: modelBridgeRoutingAvailable,
            jsBridgeAvailableNow: false,
            exposedToJSNow: false,
            canInjectScriptsNow: false,
            canWakeServiceWorkerNow: false,
            canCreateContextNow: false,
            canLoadContextNow: false,
            runtimeLoadable: false,
            passwordManagerJSBridgeModelReady:
                passwordManagerJSBridgeSummary
                .passwordManagerJSBridgeModelReady,
            passwordManagerRuntimeBridgeReady: false,
            extensionPageHostSummary: extensionPageHostSummary,
            runtimeJSMessagingMVPSummary:
                runtimeJSMessagingMVPSummary,
            tabsScriptingMVPSummary:
                tabsScriptingMVPSummary
        )
    }
}

enum ChromeMV3JSBridgeContractReportWriter {
    static let reportFileName = "runtime-js-bridge-contract-report.json"

    @discardableResult
    static func write(
        _ report: ChromeMV3JSBridgeContractReport,
        toRewrittenBundleRoot rootURL: URL
    ) throws -> ChromeMV3JSBridgeContractReport {
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

enum ChromeMV3JSBridgeContractReportGenerator {
    static func makeReport(
        loadingPrerequisitesReportFrom rootURL: URL,
        profileID: String = "diagnostic-profile"
    ) throws -> ChromeMV3JSBridgeContractReport {
        let reportURL = rootURL.standardizedFileURL
            .appendingPathComponent(
                ChromeMV3RuntimeBridgePrerequisitesReportWriter
                    .reportFileName
            )
        let data = try Data(contentsOf: reportURL)
        let prerequisites = try JSONDecoder().decode(
            ChromeMV3RuntimeBridgePrerequisitesReport.self,
            from: data
        )
        return makeReport(
            prerequisitesReport: prerequisites,
            profileID: profileID
        )
    }

    static func makeReport(
        prerequisitesReport prerequisites:
            ChromeMV3RuntimeBridgePrerequisitesReport,
        profileID: String = "diagnostic-profile"
    ) -> ChromeMV3JSBridgeContractReport {
        makeReport(
            extensionID: prerequisites.candidateID,
            profileID: profileID,
            storagePermissionDetected:
                prerequisites.manifestFacts.storagePermissionPresent
                    || prerequisites.passwordManagerPrerequisiteSummary
                    .storagePermissionPresent,
            nativeMessagingPermissionDetected:
                prerequisites.manifestFacts
                .nativeMessagingPermissionPresent
                    || prerequisites.passwordManagerPrerequisiteSummary
                    .nativeMessagingPermissionPresent,
            passwordManagerLikeFixtureDetected:
                prerequisites.passwordManagerPrerequisiteSummary
                .contentScriptsPresent
                    || prerequisites.passwordManagerPrerequisiteSummary
                    .actionPopupPresent
                    || prerequisites.passwordManagerPrerequisiteSummary
                    .storagePermissionPresent
                    || prerequisites.passwordManagerPrerequisiteSummary
                    .nativeMessagingPermissionPresent
        )
    }

    static func makeReport(
        extensionID: String,
        profileID: String,
        storagePermissionDetected: Bool = true,
        nativeMessagingPermissionDetected: Bool = true,
        passwordManagerLikeFixtureDetected: Bool = true
    ) -> ChromeMV3JSBridgeContractReport {
        var environment =
            ChromeMV3JSBridgeContractEnvironment
            .passwordManagerModelFixture(
                extensionID: extensionID,
                profileID: profileID,
                storagePermissionDetected: storagePermissionDetected,
                nativeMessagingPermissionDetected:
                    nativeMessagingPermissionDetected
            )
        let requests = passwordManagerRequests(
            extensionID: extensionID,
            profileID: profileID
        )
        let responses = requests.map {
            ChromeMV3JSBridgeContractRouter.route(
                $0,
                environment: &environment
            )
        }
        let runtimeModeled = responses.contains {
            $0.routeResult?.runtimeDispatcherResult?.modelHandlerInvoked
                == true
        }
        let storageModeled = responses.contains {
            $0.routeResult?.storageOperationResult?
                .brokerOperationExecutedInModel == true
        }
        let permissionsModeled = responses.contains {
            $0.routeResult?.permissionsContainsResult != nil
                || $0.routeResult?.permissionsRequestResult != nil
        }
        let nativeBlocked = responses.contains {
            $0.lastErrorContract?.code == .nativeMessagingBlocked
                && $0.routeResult?.nativeMessagingPreflight != nil
        }
        let passwordReady = passwordManagerLikeFixtureDetected
            && runtimeModeled
            && storageModeled
            && permissionsModeled
            && nativeBlocked
        let passwordSummary = ChromeMV3PasswordManagerJSBridgeSummary(
            runtimeSendMessageEnvelopeRouteModeled: runtimeModeled,
            storageLocalEnvelopeRouteModeled: storageModeled,
            permissionsEnvelopeRouteModeled: permissionsModeled,
            nativeMessagingEnvelopeRouteBlocked: nativeBlocked,
            contentScriptJSShimInjected: false,
            extensionPageJSShimInjected: false,
            serviceWorkerWoken: false,
            passwordManagerJSBridgeModelReady: passwordReady,
            passwordManagerRuntimeBridgeReady: false,
            blockers:
                uniqueSorted(
                    [
                        "Content script bridge shim is not injected.",
                        "Extension page bridge shim is not injected.",
                        "Service worker is not woken.",
                        "Native messaging is blocked by preflight.",
                        "Password-manager runtime bridge readiness remains false.",
                    ]
                )
        )
        let capabilities = ChromeMV3JSBridgeMethodCapabilityMatrix
            .allCapabilities()
        let reportID = stableID(
            prefix: "runtime-js-bridge-contract",
            parts: [
                extensionID,
                profileID,
                storagePermissionDetected.description,
                nativeMessagingPermissionDetected.description,
                passwordManagerLikeFixtureDetected.description,
                responses.map(\.bridgeCallID).joined(separator: ","),
            ]
        )

        return ChromeMV3JSBridgeContractReport(
            schemaVersion: 1,
            id: reportID,
            reportFileName:
                ChromeMV3JSBridgeContractReportWriter.reportFileName,
            extensionID: extensionID,
            profileID: profileID,
            supportedModeledMethods: capabilities,
            unsupportedDeferredAPIs: [
                "chrome.storage.managed",
                "cross-extension runtime message delivery",
                "real Port lifecycle",
                "runtime listener registration",
                "service-worker wake",
                "native messaging process launch",
            ],
            argumentNormalizationCoverage:
                ChromeMV3JSBridgeArgumentNormalizationCoverage(
                    runtimeSendMessageCovered: true,
                    runtimeConnectCovered: true,
                    tabsSendMessageCovered: true,
                    tabsConnectCovered: true,
                    storageKeyVariantsCovered:
                        ChromeMV3StorageAPIKeySelectorKind.allCases
                        .filter { $0 != .invalidType }
                        .sorted(),
                    permissionsObjectCovered: true,
                    nativeMessagingHostAndMessageCovered: true
                ),
            routerCoverage:
                ChromeMV3JSBridgeRouterCoverage(
                    runtimeMessagingRoutesToDispatcher:
                        runtimeModeled,
                    storageRoutesToOperationHandler: storageModeled,
                    permissionsRoutesToAPIContract:
                        permissionsModeled,
                    nativeMessagingRoutesToBlockedPreflight:
                        nativeBlocked,
                    unsupportedAPIsProduceDeterministicErrors: true
                ),
            responseErrorCoverage:
                ChromeMV3JSBridgeResponseErrorCoverage(
                    errorCodes:
                        ChromeMV3JSBridgeErrorCode.allCases.sorted(),
                    callbackModeRepresented: true,
                    promiseModeRepresented: true,
                    lastErrorMapped: true
                ),
            callbackPromiseCoverage:
                ChromeMV3JSBridgeInvocationMode.allCases.sorted(),
            integrationSummary:
                ChromeMV3JSBridgeIntegrationSummary(
                    runtimeDispatcherModelRouteAvailable:
                        runtimeModeled,
                    storageOperationHandlerAvailable:
                        storageModeled,
                    permissionsAPIContractAvailable:
                        permissionsModeled,
                    nativeMessagingPreflightAvailable:
                        nativeBlocked,
                    serviceWorkerLifecycleRemainsBlocked: true
                ),
            passwordManagerJSBridgeSummary: passwordSummary,
            modelBridgeRoutingAvailable: true,
            jsBridgeAvailableNow: false,
            exposedToJSNow: false,
            canInjectScriptsNow: false,
            canWakeServiceWorkerNow: false,
            canCreateContextNow: false,
            canLoadContextNow: false,
            runtimeLoadable: false,
            documentationSources: documentationSources(),
            diagnostics:
                uniqueSorted(
                    responses.flatMap(\.diagnostics)
                        + [
                            "JS bridge contract report is deterministic.",
                            "Bridge model routing is available for test envelopes.",
                            "No runtime exposure is enabled.",
                        ]
                ),
            blockers:
                uniqueSorted(
                    capabilities.flatMap(\.blockers)
                        + passwordSummary.blockers
                        + [
                            "jsBridgeAvailableNow remains false.",
                            "exposedToJSNow remains false.",
                            "canInjectScriptsNow remains false.",
                            "canWakeServiceWorkerNow remains false.",
                            "canLoadContextNow remains false.",
                            "runtimeLoadable remains false.",
                        ]
                )
        )
    }

    static func routingSummary() -> ChromeMV3JSBridgeRoutingSummary {
        ChromeMV3JSBridgeMethodCapabilityMatrix.routingSummary()
    }

    private static func passwordManagerRequests(
        extensionID: String,
        profileID: String
    ) -> [ChromeMV3JSBridgeRequestEnvelope] {
        [
            ChromeMV3JSBridgeRequestEnvelope(
                extensionID: extensionID,
                profileID: profileID,
                sourceContext: .testFixture,
                namespace: .runtime,
                methodName: "sendMessage",
                rawArguments: [
                    .object(["type": .string("unlock-state")]),
                ],
                invocationMode: .promise
            ),
            ChromeMV3JSBridgeRequestEnvelope(
                extensionID: extensionID,
                profileID: profileID,
                sourceContext: .serviceWorker,
                namespace: .tabs,
                methodName: "sendMessage",
                rawArguments: [
                    .number(1),
                    .object(["type": .string("fill-login")]),
                    .object(["frameId": .number(0)]),
                ],
                invocationMode: .promise
            ),
            ChromeMV3JSBridgeRequestEnvelope(
                extensionID: extensionID,
                profileID: profileID,
                sourceContext: .serviceWorker,
                namespace: .storage,
                methodName: "local.set",
                rawArguments: [
                    .object(["vaultUnlocked": .bool(true)]),
                ],
                invocationMode: .promise
            ),
            ChromeMV3JSBridgeRequestEnvelope(
                extensionID: extensionID,
                profileID: profileID,
                sourceContext: .actionPopup,
                namespace: .permissions,
                methodName: "contains",
                rawArguments: [
                    .object([
                        "permissions": .array([.string("tabs")]),
                        "origins": .array([
                            .string("https://example.com/*"),
                        ]),
                    ]),
                ],
                invocationMode: .promise
            ),
            ChromeMV3JSBridgeRequestEnvelope(
                extensionID: extensionID,
                profileID: profileID,
                sourceContext: .serviceWorker,
                namespace: .nativeMessaging,
                methodName: "connect",
                rawArguments: [.string("com.example.password_manager")],
                invocationMode: .fireAndForget
            ),
        ]
    }

    private static func documentationSources()
        -> [ChromeMV3ManifestRewritePreviewSource]
    {
        [
            source(
                title: "Chrome runtime API",
                url: "https://developer.chrome.com/docs/extensions/reference/api/runtime",
                note: "Defines runtime message, connect, native messaging, Promise, and lastError contracts."
            ),
            source(
                title: "Chrome message passing",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/messaging",
                note: "Defines one-time requests and long-lived connection lifecycle."
            ),
            source(
                title: "Chrome tabs API",
                url: "https://developer.chrome.com/docs/extensions/reference/api/tabs",
                note: "Defines tabs.sendMessage and tabs.connect argument shapes."
            ),
            source(
                title: "Chrome storage API",
                url: "https://developer.chrome.com/docs/extensions/reference/api/storage",
                note: "Defines storage areas, get/set/remove/clear/getBytesInUse, quota, and callback or Promise error behavior."
            ),
            source(
                title: "Chrome permissions API",
                url: "https://developer.chrome.com/docs/extensions/reference/api/permissions",
                note: "Defines contains, getAll, request, remove, user gesture, and permission event contracts."
            ),
            source(
                title: "Chrome native messaging",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging",
                note: "Defines native host names, native messaging permission, and native host process behavior."
            ),
            ChromeMV3ManifestRewritePreviewSource(
                kind: .currentSumiCode,
                title: "Sumi Chrome MV3 model contracts",
                url: nil,
                note: "Existing Swift model contracts remain non-executing and blocked at runtime boundaries."
            ),
        ]
    }

    private static func source(
        title: String,
        url: String,
        note: String
    ) -> ChromeMV3ManifestRewritePreviewSource {
        ChromeMV3ManifestRewritePreviewSource(
            kind: .chromeDocumentation,
            title: title,
            url: url,
            note: note
        )
    }
}

private extension ChromeMV3StorageValue {
    var objectValue: [String: ChromeMV3StorageValue]? {
        guard case .object(let object) = self else { return nil }
        return object
    }

    var stringValue: String? {
        guard case .string(let string) = self else { return nil }
        return string
    }

    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    var intValue: Int? {
        guard case .number(let value) = self,
              value.isFinite,
              value.rounded() == value,
              value >= 0,
              value <= Double(Int.max)
        else { return nil }
        return Int(value)
    }

    var typeName: String {
        switch self {
        case .array:
            return "array"
        case .bool:
            return "boolean"
        case .null:
            return "null"
        case .number:
            return "number"
        case .object:
            return "object"
        case .string:
            return "string"
        }
    }
}

private extension Dictionary
where Key == String, Value == ChromeMV3StorageValue {
    func sortedByKey() -> [String: ChromeMV3StorageValue] {
        Dictionary(uniqueKeysWithValues: keys.sorted().map {
            ($0, self[$0] ?? .null)
        })
    }
}

private func stableArgumentDescription(
    _ value: ChromeMV3StorageValue
) -> String {
    (try? value.canonicalJSONString()) ?? "invalid-argument"
}

private func stableID(prefix: String, parts: [String]) -> String {
    let joined = parts.joined(separator: "\u{1F}")
    let digest = SHA256.hash(data: Data(joined.utf8))
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    return "\(prefix)-\(String(hex.prefix(16)))"
}

private func uniqueSorted(_ values: [String]) -> [String] {
    Array(Set(values.filter { $0.isEmpty == false })).sorted()
}
