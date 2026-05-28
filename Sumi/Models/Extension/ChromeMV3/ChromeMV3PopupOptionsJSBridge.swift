//
//  ChromeMV3PopupOptionsJSBridge.swift
//  Sumi
//
//  Developer-preview chrome.* JavaScript bridge for extension-owned action
//  popup and options WKWebViews. This bridge is installed only by the
//  popup/options host after Prompt 60 product gates pass. It does not install
//  into product normal tabs, attach content scripts, enable product DNR,
//  display product permission UI, launch native hosts, wake service workers,
//  or make the global MV3 runtime loadable.
//

import CryptoKit
import Foundation

#if canImport(WebKit)
import WebKit
#endif

struct ChromeMV3PopupOptionsBlockedAPIDiagnostic:
    Codable,
    Equatable,
    Sendable
{
    var namespace: String
    var methodName: String
    var reason: String
    var remediation: String
    var roadmapOwner: String
    var lastErrorCode: String
    var lastErrorMessage: String
}

struct ChromeMV3PopupOptionsAPIMethodPolicy:
    Codable,
    Equatable,
    Sendable
{
    var exposedNamespaces: [String]
    var blockedNamespaces: [String]
    var allowedMethods: [String]
    var blockedDiagnostics: [ChromeMV3PopupOptionsBlockedAPIDiagnostic]

    static let defaultPolicy = ChromeMV3PopupOptionsAPIMethodPolicy(
        exposedNamespaces: [
            "permissions",
            "runtime",
            "scripting",
            "storage.local",
            "tabs",
        ],
        blockedNamespaces: [
            "declarativeNetRequest",
            "identity",
            "nativeMessaging",
            "offscreen",
            "sidePanel",
            "webRequest",
        ],
        allowedMethods: [
            "permissions.contains",
            "permissions.getAll",
            "permissions.remove",
            "permissions.request",
            "runtime.connect",
            "runtime.getURL",
            "runtime.lastError",
            "runtime.sendMessage",
            "storage.local.clear",
            "storage.local.get",
            "storage.local.getBytesInUse",
            "storage.local.remove",
            "storage.local.set",
            "storage.onChanged",
            "tabs.query",
        ],
        blockedDiagnostics: [
            blocked(
                namespace: "tabs",
                methodName: "sendMessage",
                reason:
                    "Product normal-tab content-script endpoints are not available until Prompt 61.",
                remediation:
                    "Keep tabs.sendMessage blocked until product content-script attachment exists.",
                roadmapOwner: "Prompt 61"
            ),
            blocked(
                namespace: "tabs",
                methodName: "connect",
                reason:
                    "Product normal-tab Port endpoints are not available until Prompt 61.",
                remediation:
                    "Keep tabs.connect blocked until product content-script attachment exists.",
                roadmapOwner: "Prompt 61"
            ),
            blocked(
                namespace: "scripting",
                methodName: "executeScript",
                reason:
                    "No explicit safe product target exists for scripting.executeScript in popup/options developer preview.",
                remediation:
                    "Require a safe target policy before enabling scripting execution.",
                roadmapOwner: "Future scripting product prompt"
            ),
            blocked(
                namespace: "runtime",
                methodName: "sendNativeMessage",
                reason:
                    "Arbitrary native messaging hosts are not allowed from popup/options.",
                remediation:
                    "Use fixture/trusted host policy before allowing native messaging.",
                roadmapOwner: "Native messaging product policy"
            ),
            blocked(
                namespace: "runtime",
                methodName: "connect" + "Native",
                reason:
                    "Arbitrary native messaging hosts are not allowed from popup/options.",
                remediation:
                    "Use fixture/trusted host policy before allowing native messaging.",
                roadmapOwner: "Native messaging product policy"
            ),
            blocked(
                namespace: "declarativeNetRequest",
                methodName: "*",
                reason:
                    "Product DNR network enforcement is not enabled by the popup/options bridge.",
                remediation:
                    "Keep network enforcement in compatibility diagnostics until a product policy is implemented.",
                roadmapOwner: "Network enforcement prompt"
            ),
            blocked(
                namespace: "webRequest",
                methodName: "*",
                reason:
                    "Product webRequest enforcement is not enabled by the popup/options bridge.",
                remediation:
                    "Keep network enforcement in compatibility diagnostics until a product policy is implemented.",
                roadmapOwner: "Network enforcement prompt"
            ),
            blocked(
                namespace: "sidePanel",
                methodName: "*",
                reason:
                    "Product sidePanel runtime is unavailable for popup/options developer preview.",
                remediation:
                    "Keep sidePanel diagnostics synthetic/product-blocked.",
                roadmapOwner: "sidePanel runtime prompt"
            ),
            blocked(
                namespace: "offscreen",
                methodName: "*",
                reason:
                    "Product offscreen runtime is unavailable for popup/options developer preview.",
                remediation:
                    "Keep offscreen diagnostics synthetic/product-blocked.",
                roadmapOwner: "offscreen runtime prompt"
            ),
            blocked(
                namespace: "identity",
                methodName: "*",
                reason:
                    "Product identity runtime is unavailable for popup/options developer preview.",
                remediation:
                    "Keep identity diagnostics synthetic/product-blocked.",
                roadmapOwner: "identity runtime prompt"
            ),
            blocked(
                namespace: "unsupported",
                methodName: "*",
                reason:
                    "The requested Chrome extension API is not in the popup/options allowlist.",
                remediation:
                    "Add an explicit API contract before exposing another namespace or method.",
                roadmapOwner: "MV3 bridge owner"
            ),
        ].sorted {
            if $0.namespace != $1.namespace {
                return $0.namespace < $1.namespace
            }
            return $0.methodName < $1.methodName
        }
    )

    static var defaultBlockedAPIIDs: [String] {
        defaultPolicy.blockedDiagnostics.map {
            "\($0.namespace).\($0.methodName)"
        }
    }

    static func blocked(
        namespace: String,
        methodName: String,
        reason: String,
        remediation: String,
        roadmapOwner: String,
        code: ChromeMV3JSBridgeErrorCode = .productBlocked
    ) -> ChromeMV3PopupOptionsBlockedAPIDiagnostic {
        ChromeMV3PopupOptionsBlockedAPIDiagnostic(
            namespace: namespace,
            methodName: methodName,
            reason: reason,
            remediation: remediation,
            roadmapOwner: roadmapOwner,
            lastErrorCode: code.rawValue,
            lastErrorMessage: code.lastErrorMessage
        )
    }

    func blockedDiagnostic(
        namespace: String,
        methodName: String
    ) -> ChromeMV3PopupOptionsBlockedAPIDiagnostic {
        blockedDiagnostics.first {
            $0.namespace == namespace && $0.methodName == methodName
        } ?? blockedDiagnostics.first {
            $0.namespace == namespace && $0.methodName == "*"
        } ?? blockedDiagnostics.first {
            $0.namespace == "unsupported"
        } ?? Self.blocked(
            namespace: namespace,
            methodName: methodName,
            reason:
                "The requested Chrome extension API is not in the popup/options allowlist.",
            remediation:
                "Add an explicit API contract before exposing another namespace or method.",
            roadmapOwner: "MV3 bridge owner",
            code: .unsupportedAPI
        )
    }
}

struct ChromeMV3PopupOptionsJSBridgeConfiguration:
    Codable,
    Equatable,
    Sendable
{
    static let productNormalTabBridgeInstallationGuard =
        "popupOptionsJSBridgeNeverInstalledInProductNormalTabWebViews"
    static let contentScriptProductAttachmentGuard =
        "popupOptionsJSBridgeDoesNotAttachProductContentScripts"

    var extensionID: String
    var profileID: String
    var surfaceID: String
    var surface: ChromeMV3ProductPopupOptionsSurface
    var extensionBaseURLString: String
    var moduleState: ChromeMV3ProfileHostModuleState
    var bridgeAvailable: Bool
    var popupOptionsJSBridgeAvailableInDeveloperPreview: Bool
    var popupOptionsJSBridgeAvailableInPublicProduct: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var contentScriptAttachmentAvailableInProduct: Bool
    var runtimeLoadable: Bool
    var manifestPermissions: [String]
    var manifestOptionalPermissions: [String]
    var manifestHostPermissions: [String]
    var manifestOptionalHostPermissions: [String]
    var allowlist: ChromeMV3PopupOptionsAPIMethodPolicy
    var diagnostics: [String]

    var sourceContext: ChromeMV3JSBridgeSourceContext {
        surface == .actionPopup ? .actionPopup : .optionsPage
    }

    static func make(
        launchRecord: ChromeMV3ProductPopupOptionsLaunchRecord
    ) -> ChromeMV3PopupOptionsJSBridgeConfiguration {
        let surfaceID = [
            launchRecord.profileID,
            launchRecord.extensionID,
            launchRecord.surface.rawValue,
            launchRecord.generatedBundleVersionID ?? "no-version",
        ].joined(separator: ":")
        let bridgeAvailable =
            launchRecord.canOpen
                && launchRecord.gateRecord
                .popupOptionsJSBridgeAvailableInDeveloperPreview
        return ChromeMV3PopupOptionsJSBridgeConfiguration(
            extensionID: launchRecord.extensionID,
            profileID: launchRecord.profileID,
            surfaceID: surfaceID,
            surface: launchRecord.surface,
            extensionBaseURLString:
                "chrome-extension://\(launchRecord.extensionID)/",
            moduleState: bridgeAvailable ? .enabled : .disabled,
            bridgeAvailable: bridgeAvailable,
            popupOptionsJSBridgeAvailableInDeveloperPreview:
                bridgeAvailable,
            popupOptionsJSBridgeAvailableInPublicProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            contentScriptAttachmentAvailableInProduct: false,
            runtimeLoadable: false,
            manifestPermissions:
                uniqueSortedPopupOptionsBridge(
                    launchRecord.manifestPermissions
                ),
            manifestOptionalPermissions:
                uniqueSortedPopupOptionsBridge(
                    launchRecord.manifestOptionalPermissions
                ),
            manifestHostPermissions:
                uniqueSortedPopupOptionsBridge(
                    launchRecord.manifestHostPermissions
                ),
            manifestOptionalHostPermissions:
                uniqueSortedPopupOptionsBridge(
                    launchRecord.manifestOptionalHostPermissions
                ),
            allowlist: .defaultPolicy,
            diagnostics:
                uniqueSortedPopupOptionsBridge([
                    bridgeAvailable
                        ? "Popup/options JS bridge is available only for this extension-owned developer-preview WebView."
                        : "Popup/options JS bridge is unavailable because launch gates did not pass.",
                    "Public product popup/options bridge remains unavailable.",
                    "Normal-tab runtime bridge remains unavailable.",
                    "Content-script product attachment remains unavailable.",
                    "runtimeLoadable remains false.",
                    Self.productNormalTabBridgeInstallationGuard,
                    Self.contentScriptProductAttachmentGuard,
                ])
        )
    }
}

struct ChromeMV3PopupOptionsJSBridgeInstallation:
    Codable,
    Equatable,
    Sendable
{
    var configuration: ChromeMV3PopupOptionsJSBridgeConfiguration
    var allowlist: ChromeMV3PopupOptionsAPIMethodPolicy
    var bridgeAvailable: Bool
    var scriptSource: String?
    var messageHandlerName: String
    var diagnostics: [String]

    static func make(
        launchRecord: ChromeMV3ProductPopupOptionsLaunchRecord
    ) -> ChromeMV3PopupOptionsJSBridgeInstallation {
        let configuration =
            ChromeMV3PopupOptionsJSBridgeConfiguration.make(
                launchRecord: launchRecord
            )
        let scriptSource = configuration.bridgeAvailable
            ? ChromeMV3PopupOptionsJSShimSource.source(
                configuration: configuration
            )
            : nil
        return ChromeMV3PopupOptionsJSBridgeInstallation(
            configuration: configuration,
            allowlist: configuration.allowlist,
            bridgeAvailable: configuration.bridgeAvailable,
            scriptSource: scriptSource,
            messageHandlerName:
                ChromeMV3PopupOptionsJSShimSource.bridgeMessageHandlerName,
            diagnostics: configuration.diagnostics
        )
    }
}

struct ChromeMV3PopupOptionsJSBridgeCallRecord:
    Codable,
    Equatable,
    Sendable
{
    var bridgeCallID: String
    var extensionID: String
    var profileID: String
    var surface: ChromeMV3ProductPopupOptionsSurface
    var sourceContext: ChromeMV3JSBridgeSourceContext
    var namespace: String
    var methodName: String
    var invocationMode: ChromeMV3JSBridgeInvocationMode
    var succeeded: Bool
    var lastErrorCode: String?
    var lastErrorMessage: String?
    var serviceWorkerWakeAttempted: Bool
    var nativeHostLaunchAttempted: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var contentScriptAttachmentAvailableInProduct: Bool
    var diagnostics: [String]
}

struct ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot:
    Codable,
    Equatable,
    Sendable
{
    var handledRequestCount: Int
    var succeededRequestCount: Int
    var blockedRequestCount: Int
    var observedMethods: [String]
    var callRecords: [ChromeMV3PopupOptionsJSBridgeCallRecord]
    var blockedAPIs: [ChromeMV3PopupOptionsBlockedAPIDiagnostic]
    var lastAPIErrorSummary: String?
    var storageOnChangedPayloadCount: Int
    var portCount: Int
    var listenerRegistryClearedOnTeardown: Bool
    var storageListenersClearedOnTeardown: Bool
    var portStateClearedOnTeardown: Bool
    var diagnostics: [String]
}

struct ChromeMV3PopupOptionsJSBridgeHostResponse:
    Codable,
    Equatable,
    Sendable
{
    var bridgeCallID: String
    var namespace: String
    var methodName: String
    var succeeded: Bool
    var resultPayload: ChromeMV3StorageValue?
    var onChangedPayload: ChromeMV3StorageOnChangedEventPayload?
    var permissionEventPayload: ChromeMV3PermissionsAPIEventPayload?
    var lastErrorMessage: String?
    var lastErrorCode: String?
    var callbackWouldSetLastError: Bool
    var promiseWouldReject: Bool
    var blockedAPIDiagnostic: ChromeMV3PopupOptionsBlockedAPIDiagnostic?
    var normalTabRuntimeBridgeAvailable: Bool
    var contentScriptAttachmentAvailableInProduct: Bool
    var serviceWorkerWakeAttempted: Bool
    var nativeHostLaunchAttempted: Bool
    var runtimeLoadable: Bool
    var diagnostics: [String]

    var foundationObject: [String: Any] {
        [
            "bridgeCallID": bridgeCallID,
            "namespace": namespace,
            "methodName": methodName,
            "succeeded": succeeded,
            "resultPayload":
                resultPayload?.popupOptionsBridgeFoundationObject
                ?? NSNull(),
            "onChangedPayload": onChangedPayloadFoundationObject,
            "permissionEventPayload": permissionEventPayloadFoundationObject,
            "lastErrorMessage": lastErrorMessage ?? NSNull(),
            "lastErrorCode": lastErrorCode ?? NSNull(),
            "callbackWouldSetLastError": callbackWouldSetLastError,
            "promiseWouldReject": promiseWouldReject,
            "blockedAPIDiagnostic": blockedDiagnosticFoundationObject,
            "normalTabRuntimeBridgeAvailable":
                normalTabRuntimeBridgeAvailable,
            "contentScriptAttachmentAvailableInProduct":
                contentScriptAttachmentAvailableInProduct,
            "serviceWorkerWakeAttempted": serviceWorkerWakeAttempted,
            "nativeHostLaunchAttempted": nativeHostLaunchAttempted,
            "runtimeLoadable": runtimeLoadable,
            "diagnostics": diagnostics,
        ]
    }

    private var onChangedPayloadFoundationObject: Any {
        guard let payload = onChangedPayload else { return NSNull() }
        return payload.popupOptionsBridgeFoundationObject
    }

    private var permissionEventPayloadFoundationObject: Any {
        guard let payload = permissionEventPayload else { return NSNull() }
        return payload.popupOptionsBridgeFoundationObject
    }

    private var blockedDiagnosticFoundationObject: Any {
        guard let diagnostic = blockedAPIDiagnostic else { return NSNull() }
        return [
            "namespace": diagnostic.namespace,
            "methodName": diagnostic.methodName,
            "reason": diagnostic.reason,
            "remediation": diagnostic.remediation,
            "roadmapOwner": diagnostic.roadmapOwner,
            "lastErrorCode": diagnostic.lastErrorCode,
            "lastErrorMessage": diagnostic.lastErrorMessage,
        ]
    }
}

private struct ChromeMV3PopupOptionsBridgeInputError: Error, Equatable {
    var message: String
}

final class ChromeMV3PopupOptionsJSBridgeHandler {
    let configuration: ChromeMV3PopupOptionsJSBridgeConfiguration
    private var localStorageBroker: ChromeMV3StorageBroker
    private let storageOperationHandler: ChromeMV3StorageAPIOperationHandler
    private var permissionRuntimeOwner: ChromeMV3PermissionRuntimeStateOwner
    private let tabRegistry: ChromeMV3SyntheticTabRegistry
    private var callRecords: [ChromeMV3PopupOptionsJSBridgeCallRecord] = []
    private var onChangedPayloads: [ChromeMV3StorageOnChangedEventPayload] = []
    private var syntheticPortIDs: Set<String> = []
    private var tornDown = false

    init(configuration: ChromeMV3PopupOptionsJSBridgeConfiguration) {
        self.configuration = configuration
        let namespace = ChromeMV3StorageNamespace(
            profileID: configuration.profileID,
            extensionID: configuration.extensionID,
            area: .local
        )
        self.localStorageBroker = ChromeMV3StorageBroker(namespace: namespace)
        self.storageOperationHandler =
            ChromeMV3StorageAPIOperationHandler(
                state:
                    configuration.bridgeAvailable
                        ? .enabledModelTestFixture
                        : .disabledModule
            )
        self.permissionRuntimeOwner =
            ChromeMV3PermissionRuntimeStateOwner(
                permissionStore:
                    ChromeMV3PermissionDecisionStore(
                        snapshot:
                            ChromeMV3PermissionDecisionStoreSnapshot(
                                extensionID: configuration.extensionID,
                                profileID: configuration.profileID,
                                declaredAPIPermissions:
                                    configuration.manifestPermissions,
                                declaredHostPermissions:
                                    configuration.manifestHostPermissions,
                                optionalAPIPermissions:
                                    configuration
                                    .manifestOptionalPermissions,
                                optionalHostPermissions:
                                    configuration
                                    .manifestOptionalHostPermissions
                            )
                    )
            )
        self.tabRegistry =
            ChromeMV3SyntheticTabRegistry.passwordManagerFixture(
                extensionID: configuration.extensionID,
                profileID: configuration.profileID,
                includeProductNormalTab: false
            )
    }

    var diagnosticsSnapshot:
        ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot
    {
        let blocked = callRecords.filter { $0.succeeded == false }
        let lastAPIErrorSummary: String?
        if let lastBlocked = blocked.last,
           let message = lastBlocked.lastErrorMessage
        {
            lastAPIErrorSummary =
                "\(lastBlocked.namespace).\(lastBlocked.methodName): \(message)"
        } else {
            lastAPIErrorSummary = nil
        }
        return ChromeMV3PopupOptionsJSBridgeDiagnosticsSnapshot(
            handledRequestCount: callRecords.count,
            succeededRequestCount:
                callRecords.filter(\.succeeded).count,
            blockedRequestCount: blocked.count,
            observedMethods:
                uniqueSortedPopupOptionsBridge(
                    callRecords.map { "\($0.namespace).\($0.methodName)" }
                ),
            callRecords: callRecords,
            blockedAPIs:
                uniqueBlockedDiagnostics(
                    blocked.map {
                        configuration.allowlist.blockedDiagnostic(
                            namespace: $0.namespace,
                            methodName: $0.methodName
                        )
                    }
                ),
            lastAPIErrorSummary: lastAPIErrorSummary,
            storageOnChangedPayloadCount: onChangedPayloads.count,
            portCount: syntheticPortIDs.count,
            listenerRegistryClearedOnTeardown: tornDown,
            storageListenersClearedOnTeardown: tornDown,
            portStateClearedOnTeardown: tornDown,
            diagnostics:
                uniqueSortedPopupOptionsBridge(
                    configuration.diagnostics
                        + [
                            "Popup/options bridge diagnostics are scoped to one WebKit host.",
                            "No normal-tab bridge installation is represented by this snapshot.",
                        ]
                )
        )
    }

    func handle(_ body: Any) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        switch ChromeMV3RuntimeJSBridgeHostRequest.parse(body) {
        case .success(let request):
            return handle(request)
        case .failure(let error):
            return response(
                request: nil,
                namespace: "unsupported",
                methodName: "parse",
                succeeded: false,
                lastErrorMessage: error.message,
                lastErrorCode:
                    ChromeMV3JSBridgeErrorCode.invalidArguments.rawValue,
                diagnostics: [error.message]
            )
        }
    }

    func handle(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        guard configuration.moduleState == .enabled,
              configuration.bridgeAvailable
        else {
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage:
                    ChromeMV3JSBridgeErrorCode.extensionDisabled
                    .lastErrorMessage,
                lastErrorCode:
                    ChromeMV3JSBridgeErrorCode.extensionDisabled.rawValue,
                diagnostics: [
                    "Popup/options JS bridge request blocked because the module, extension, or developer-preview bridge gate is disabled.",
                ]
            )
        }

        switch (request.namespace, request.methodName) {
        case ("runtime", "sendMessage"):
            return runtimeSendMessage(request)
        case ("runtime", "connect"):
            return runtimeConnect(request)
        case ("runtime", "getURL"):
            return runtimeGetURL(request)
        case ("runtime", "sendNativeMessage"):
            return blocked(request, namespace: "runtime")
        case ("runtime", let method) where method == "connect" + "Native":
            return blocked(request, namespace: "runtime")
        case ("storage", "local.get"),
             ("storage", "local.set"),
             ("storage", "local.remove"),
             ("storage", "local.clear"),
             ("storage", "local.getBytesInUse"):
            return storageLocal(request)
        case ("permissions", "contains"):
            return permissionsContains(request)
        case ("permissions", "getAll"):
            return permissionsGetAll(request)
        case ("permissions", "request"):
            return permissionsRequest(request)
        case ("permissions", "remove"):
            return permissionsRemove(request)
        case ("tabs", "query"):
            return tabsQuery(request)
        case ("tabs", "sendMessage"),
             ("tabs", "connect"):
            return blocked(
                request,
                namespace: "tabs",
                code: .runtimeDispatchUnavailable,
                message:
                    ChromeMV3RuntimeLastErrorContract
                    .contract(for: .noReceivingEnd)
                    .futureLastErrorMessage
            )
        case ("scripting", "executeScript"):
            return blocked(request, namespace: "scripting")
        case ("nativeMessaging", _),
             ("declarativeNetRequest", _),
             ("webRequest", _),
             ("sidePanel", _),
             ("offscreen", _),
             ("identity", _):
            return blocked(request, namespace: request.namespace)
        default:
            let namespaceKnown = [
                "runtime",
                "storage",
                "permissions",
                "tabs",
                "scripting",
            ].contains(request.namespace)
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage:
                    (namespaceKnown
                        ? ChromeMV3JSBridgeErrorCode.methodUnsupported
                        : ChromeMV3JSBridgeErrorCode.namespaceUnsupported)
                    .lastErrorMessage,
                lastErrorCode:
                    (namespaceKnown
                        ? ChromeMV3JSBridgeErrorCode.methodUnsupported
                        : ChromeMV3JSBridgeErrorCode.namespaceUnsupported)
                    .rawValue,
                blockedAPIDiagnostic:
                    configuration.allowlist.blockedDiagnostic(
                        namespace: namespaceKnown
                            ? request.namespace
                            : "unsupported",
                        methodName: namespaceKnown
                            ? request.methodName
                            : "*"
                    ),
                diagnostics: [
                    "Unsupported popup/options bridge route: \(request.namespace).\(request.methodName).",
                ]
            )
        }
    }

    func tearDown() {
        localStorageBroker = ChromeMV3StorageBroker(
            namespace: localStorageBroker.namespace
        )
        callRecords.removeAll()
        onChangedPayloads.removeAll()
        syntheticPortIDs.removeAll()
        tabRegistry.tearDown()
        tornDown = true
    }

    private func runtimeSendMessage(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        guard request.arguments.isEmpty == false else {
            return invalidArguments(
                request,
                "runtime.sendMessage requires a message argument."
            )
        }
        guard request.arguments.count <= 2 else {
            return invalidArguments(
                request,
                "runtime.sendMessage external-extension overload is not available in popup/options developer preview."
            )
        }
        let route = ChromeMV3RuntimeMessagingRoute.make(
            kind:
                configuration.sourceContext == .actionPopup
                    ? .actionPopupToServiceWorker
                    : .optionsPageToServiceWorker,
            extensionID: configuration.extensionID,
            profileID: configuration.profileID
        )
        let result = ChromeMV3RuntimeMessageDispatcher.dispatch(
            input: ChromeMV3RuntimeMessageDispatcherInput.make(
                route: route,
                listenerRegistrySnapshot:
                    ChromeMV3RuntimeModelListenerRegistrySnapshot.make(
                        extensionID: configuration.extensionID,
                        profileID: configuration.profileID,
                        endpoints: [],
                        diagnostics: [
                            "Popup/options bridge does not synthesize a service-worker receiver.",
                        ]
                    ),
                permissionBrokerSnapshot:
                    permissionRuntimeOwner.permissionBroker,
                serviceWorkerLifecycleSnapshot:
                    .blocked(
                        extensionID: configuration.extensionID,
                        profileID: configuration.profileID
                    ),
                moduleState: configuration.moduleState,
                dispatchMode: .modelOnly,
                responseMode:
                    request.invocationMode == .callback
                        ? .callback
                        : .promise,
                expectsResponse: true,
                userGestureAvailable:
                    configuration.sourceContext == .actionPopup,
                nativeHostName: nil,
                seed: request.bridgeCallID
            )
        )
        if let error = result.selectedLastError {
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage: error.futureLastErrorMessage,
                lastErrorCode: error.error.rawValue,
                diagnostics:
                    result.diagnostics
                        + [
                            "runtime.sendMessage did not wake a service worker; no receiver is currently modeled.",
                        ]
            )
        }
        return response(
            request: request,
            succeeded: true,
            payload: result.responsePayload ?? .null,
            diagnostics:
                result.diagnostics
                    + [
                        "runtime.sendMessage routed through existing dispatcher model without service-worker wake.",
                    ]
        )
    }

    private func runtimeConnect(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        let portID = stableIDPopupOptionsBridge(
            prefix: "popup-options-runtime-port",
            parts: [
                configuration.surfaceID,
                request.bridgeCallID,
                String(syntheticPortIDs.count + 1),
            ]
        )
        syntheticPortIDs.insert(portID)
        return response(
            request: request,
            succeeded: true,
            payload: .object([
                "portID": .string(portID),
                "portKind": .string("popupOptionsSyntheticPort"),
                "canOpenRuntimePortNow": .bool(false),
                "canWakeServiceWorkerNow": .bool(false),
                "runtimeLoadable": .bool(false),
            ]),
            diagnostics: [
                "runtime.connect returned a popup/options-scoped synthetic Port object.",
                "No service-worker wake or real runtime Port was opened.",
            ]
        )
    }

    private func runtimeGetURL(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        guard request.arguments.count <= 1 else {
            return invalidArguments(
                request,
                "runtime.getURL accepts at most one path argument."
            )
        }
        let path = request.arguments.first?.stringValue ?? ""
        let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return response(
            request: request,
            succeeded: true,
            payload: .string(configuration.extensionBaseURLString + normalizedPath),
            diagnostics: [
                "runtime.getURL returned a deterministic chrome-extension URL string for the extension-owned page.",
            ]
        )
    }

    private func storageLocal(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        switch storageInput(request) {
        case .failure(let error):
            return invalidArguments(request, error.message)
        case .success(let input):
            let envelope = storageOperationHandler.handle(
                input,
                broker: &localStorageBroker
            )
            if envelope.succeeded == false {
                return response(
                    request: request,
                    succeeded: false,
                    lastErrorMessage:
                        envelope.futureLastErrorContract?
                        .futureRuntimeLastErrorMessage
                        ?? ChromeMV3JSBridgeErrorCode.invalidArguments
                        .lastErrorMessage,
                    lastErrorCode:
                        envelope.futureLastErrorContract?.code.rawValue
                        ?? ChromeMV3JSBridgeErrorCode.invalidArguments
                        .rawValue,
                    diagnostics: envelope.diagnostics
                )
            }
            let onChanged = popupOnChangedPayload(from: envelope)
            if let onChanged {
                onChangedPayloads.append(onChanged)
            }
            return response(
                request: request,
                succeeded: true,
                payload: storageResultPayload(from: envelope),
                onChangedPayload: onChanged,
                diagnostics:
                    envelope.diagnostics
                        + [
                            "storage.local operation used the existing storage operation handler.",
                            "storage.onChanged dispatch is in-page only and does not wake a service worker.",
                        ]
            )
        }
    }

    private func permissionsContains(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        switch permissionsInput(request) {
        case .failure(let error):
            return invalidArguments(request, error.message)
        case .success(let input):
            let result = permissionRuntimeOwner.contains(input: input)
            return response(
                request: request,
                succeeded: true,
                payload: .bool(result.wouldReturn),
                diagnostics: result.diagnostics
            )
        }
    }

    private func permissionsGetAll(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        guard request.arguments.isEmpty else {
            return invalidArguments(
                request,
                "permissions.getAll does not accept arguments."
            )
        }
        let result = permissionRuntimeOwner.getAll()
        return response(
            request: request,
            succeeded: true,
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
    }

    private func permissionsRequest(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        switch permissionsInput(request) {
        case .failure(let error):
            return invalidArguments(request, error.message)
        case .success(let input):
            let promptResult = modeledPromptResult(from: request)
            let application = permissionRuntimeOwner.request(
                input: input,
                modeledPromptResult: promptResult
            )
            let alreadyGranted = application.result.wouldBeAllowedByModel
            let promptAccepted =
                application.result.wouldGrantIfUserAccepted
                    && promptResult == .accepted
            guard alreadyGranted || promptAccepted else {
                let diagnostic = permissionRequestFailure(
                    result: application.result,
                    promptResult: promptResult
                )
                return response(
                    request: request,
                    succeeded: false,
                    payload: .bool(false),
                    lastErrorMessage: diagnostic.message,
                    lastErrorCode: diagnostic.code,
                    diagnostics:
                        application.diagnostics + diagnostic.diagnostics
                )
            }
            return response(
                request: request,
                succeeded: true,
                payload: .bool(application.returnedBoolean),
                permissionEventPayload:
                    promptAccepted
                        ? application.result.eventPayloadIfAccepted
                        : nil,
                diagnostics:
                    application.diagnostics
                        + [
                            "permissions.request used the internal modeled developer-preview permission flow.",
                            "No product permission prompt UI was displayed.",
                        ]
            )
        }
    }

    private func permissionsRemove(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        switch permissionsInput(request) {
        case .failure(let error):
            return invalidArguments(request, error.message)
        case .success(let input):
            let application = permissionRuntimeOwner.remove(input: input)
            guard application.returnedBoolean else {
                let diagnostic = permissionRemoveFailure(
                    result: application.result
                )
                return response(
                    request: request,
                    succeeded: false,
                    payload: .bool(false),
                    lastErrorMessage: diagnostic.message,
                    lastErrorCode: diagnostic.code,
                    diagnostics:
                        application.diagnostics + diagnostic.diagnostics
                )
            }
            return response(
                request: request,
                succeeded: true,
                payload: .bool(true),
                permissionEventPayload:
                    application.result.eventPayloadIfApplied,
                diagnostics: application.diagnostics
            )
        }
    }

    private func tabsQuery(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        guard request.arguments.count <= 1 else {
            return invalidArguments(
                request,
                "tabs.query accepts one queryInfo object."
            )
        }
        guard let queryInfo = request.arguments.first?.objectValue
            ?? (request.arguments.isEmpty ? [:] : nil)
        else {
            return invalidArguments(
                request,
                "tabs.query queryInfo must be an object."
            )
        }
        let result = tabRegistry.query(
            queryInfo,
            permissionBroker: permissionRuntimeOwner.permissionBroker
        )
        return response(
            request: request,
            succeeded: true,
            payload: .array(result.tabs),
            diagnostics:
                result.diagnostics
                    + [
                        "tabs.query used a product-gated/redacted model and did not attach a normal-tab bridge.",
                    ]
        )
    }

    private func blocked(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest,
        namespace: String,
        code: ChromeMV3JSBridgeErrorCode = .productBlocked,
        message: String? = nil
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        let diagnostic = configuration.allowlist.blockedDiagnostic(
            namespace: namespace,
            methodName: request.methodName
        )
        return response(
            request: request,
            succeeded: false,
            lastErrorMessage:
                message ?? diagnostic.lastErrorMessage,
            lastErrorCode:
                code == .productBlocked
                    ? diagnostic.lastErrorCode
                    : code.rawValue,
            blockedAPIDiagnostic: diagnostic,
            diagnostics: [
                diagnostic.reason,
                diagnostic.remediation,
                "Roadmap owner: \(diagnostic.roadmapOwner).",
            ]
        )
    }

    private func invalidArguments(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest,
        _ message: String
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        response(
            request: request,
            succeeded: false,
            lastErrorMessage: message,
            lastErrorCode: ChromeMV3JSBridgeErrorCode.invalidArguments
                .rawValue,
            diagnostics: [message]
        )
    }

    private func response(
        request: ChromeMV3RuntimeJSBridgeHostRequest?,
        namespace: String? = nil,
        methodName: String? = nil,
        succeeded: Bool,
        payload: ChromeMV3StorageValue? = nil,
        onChangedPayload: ChromeMV3StorageOnChangedEventPayload? = nil,
        permissionEventPayload: ChromeMV3PermissionsAPIEventPayload? = nil,
        lastErrorMessage: String? = nil,
        lastErrorCode: String? = nil,
        blockedAPIDiagnostic:
            ChromeMV3PopupOptionsBlockedAPIDiagnostic? = nil,
        diagnostics: [String]
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        let resolvedNamespace = request?.namespace ?? namespace ?? "unsupported"
        let resolvedMethod = request?.methodName ?? methodName ?? "unknown"
        let mode = request?.invocationMode ?? .promise
        let response = ChromeMV3PopupOptionsJSBridgeHostResponse(
            bridgeCallID:
                request?.bridgeCallID
                ?? stableIDPopupOptionsBridge(
                    prefix: "popup-options-js-response",
                    parts: [resolvedNamespace, resolvedMethod]
                ),
            namespace: resolvedNamespace,
            methodName: resolvedMethod,
            succeeded: succeeded,
            resultPayload: payload,
            onChangedPayload: onChangedPayload,
            permissionEventPayload: permissionEventPayload,
            lastErrorMessage: succeeded ? nil : lastErrorMessage,
            lastErrorCode: succeeded ? nil : lastErrorCode,
            callbackWouldSetLastError:
                mode == .callback && succeeded == false,
            promiseWouldReject:
                mode == .promise && succeeded == false,
            blockedAPIDiagnostic: blockedAPIDiagnostic,
            normalTabRuntimeBridgeAvailable: false,
            contentScriptAttachmentAvailableInProduct: false,
            serviceWorkerWakeAttempted: false,
            nativeHostLaunchAttempted: false,
            runtimeLoadable: false,
            diagnostics:
                uniqueSortedPopupOptionsBridge(
                    configuration.diagnostics
                        + diagnostics
                        + [
                            "Popup/options bridge handled the call inside an extension-owned WebKit host.",
                            "No normal-tab bridge, product content-script attachment, service-worker wake, native host launch, or runtimeLoadable change occurred.",
                        ]
                )
        )
        callRecords.append(
            ChromeMV3PopupOptionsJSBridgeCallRecord(
                bridgeCallID: response.bridgeCallID,
                extensionID: configuration.extensionID,
                profileID: configuration.profileID,
                surface: configuration.surface,
                sourceContext: configuration.sourceContext,
                namespace: resolvedNamespace,
                methodName: resolvedMethod,
                invocationMode: mode,
                succeeded: succeeded,
                lastErrorCode: response.lastErrorCode,
                lastErrorMessage: response.lastErrorMessage,
                serviceWorkerWakeAttempted: false,
                nativeHostLaunchAttempted: false,
                normalTabRuntimeBridgeAvailable: false,
                contentScriptAttachmentAvailableInProduct: false,
                diagnostics: response.diagnostics
            )
        )
        return response
    }

    private func storageInput(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> Result<
        ChromeMV3StorageAPIOperationInput,
        ChromeMV3PopupOptionsBridgeInputError
    > {
        let operation: ChromeMV3StorageOperationKind
        switch request.methodName {
        case "local.get":
            operation = .get
            guard request.arguments.count <= 1 else {
                return .failure(.init(
                    message: "storage.local.get accepts at most one key selector."
                ))
            }
        case "local.set":
            operation = .set
            guard request.arguments.count == 1,
                  request.arguments[0].objectValue != nil
            else {
                return .failure(.init(
                    message: "storage.local.set requires one object argument."
                ))
            }
        case "local.remove":
            operation = .remove
            guard request.arguments.count == 1 else {
                return .failure(.init(
                    message: "storage.local.remove requires a key or key array."
                ))
            }
        case "local.clear":
            operation = .clear
            guard request.arguments.isEmpty else {
                return .failure(.init(
                    message: "storage.local.clear does not accept arguments."
                ))
            }
        case "local.getBytesInUse":
            operation = .getBytesInUse
            guard request.arguments.count <= 1 else {
                return .failure(.init(
                    message: "storage.local.getBytesInUse accepts at most one key selector."
                ))
            }
        default:
            return .failure(.init(message: "Unsupported storage.local method."))
        }

        let selector: ChromeMV3StorageAPIKeySelector?
        switch operation {
        case .get, .getBytesInUse:
            switch storageSelector(
                request.arguments.first,
                defaultWhenMissing: .omitted
            ) {
            case .success(let value):
                selector = value
            case .failure(let error):
                return .failure(error)
            }
        case .remove:
            switch storageSelector(
                request.arguments.first,
                defaultWhenMissing: .invalidType("missing")
            ) {
            case .success(let value):
                selector = value
            case .failure(let error):
                return .failure(error)
            }
        default:
            selector = nil
        }
        return .success(
            ChromeMV3StorageAPIOperationInput(
                extensionID: configuration.extensionID,
                profileID: configuration.profileID,
                area: .local,
                operation: operation,
                invocationMode:
                    request.invocationMode == .callback
                        ? .callback
                        : .promise,
                keySelector: selector,
                values: request.arguments.first?.objectValue ?? [:],
                sourceContext: configuration.sourceContext.storageContext,
                diagnostics: [
                    "Popup/options bridge normalized storage.local request.",
                ]
            )
        )
    }

    private func storageSelector(
        _ value: ChromeMV3StorageValue?,
        defaultWhenMissing: ChromeMV3StorageAPIKeySelector
    ) -> Result<
        ChromeMV3StorageAPIKeySelector,
        ChromeMV3PopupOptionsBridgeInputError
    > {
        guard let value else { return .success(defaultWhenMissing) }
        switch value {
        case .null:
            return .success(.allKeys)
        case .string(let key):
            return .success(.singleString(key))
        case .array(let values):
            var keys: [String] = []
            for entry in values {
                guard let key = entry.stringValue else {
                    return .failure(.init(
                        message: "Storage key arrays must contain strings."
                    ))
                }
                keys.append(key)
            }
            return .success(.stringArray(keys))
        case .object(let defaults):
            return .success(.defaults(defaults))
        case .bool, .number:
            return .failure(.init(
                message: "Unsupported storage key selector type."
            ))
        }
    }

    private func permissionsInput(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> Result<
        ChromeMV3PermissionsAPIRequestInput,
        ChromeMV3PopupOptionsBridgeInputError
    > {
        guard request.arguments.count == 1,
              let object = request.arguments.first?.objectValue
        else {
            return .failure(.init(
                message:
                    "permissions.\(request.methodName) requires one permissions object."
            ))
        }
        let permissions = stringArray(
            object["permissions"],
            fieldName: "permissions"
        )
        if let error = permissions.error {
            return .failure(.init(message: error))
        }
        let origins = stringArray(object["origins"], fieldName: "origins")
        if let error = origins.error {
            return .failure(.init(message: error))
        }
        return .success(
            ChromeMV3PermissionsAPIRequestInput(
                extensionID: configuration.extensionID,
                profileID: configuration.profileID,
                sourceContext: configuration.sourceContext.permissionsContext,
                userGestureModeled:
                    object["__sumiUserGestureModeled"]?.boolValue
                    ?? (configuration.sourceContext == .actionPopup),
                extensionModuleEnabled:
                    configuration.moduleState == .enabled,
                permissions: permissions.values,
                origins: origins.values
            )
        )
    }

    private func stringArray(
        _ value: ChromeMV3StorageValue?,
        fieldName: String
    ) -> (values: [String], error: String?) {
        guard let value else { return ([], nil) }
        guard case .array(let entries) = value else {
            return ([], "\(fieldName) must be a string array.")
        }
        var values: [String] = []
        for entry in entries {
            guard let string = entry.stringValue else {
                return ([], "\(fieldName) entries must be strings.")
            }
            values.append(string)
        }
        return (uniqueSortedPopupOptionsBridge(values), nil)
    }

    private func modeledPromptResult(
        from request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3ModeledPermissionPromptResult {
        guard let object = request.arguments.first?.objectValue,
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

    private func permissionRequestFailure(
        result: ChromeMV3PermissionsAPIRequestResult,
        promptResult: ChromeMV3ModeledPermissionPromptResult
    ) -> (code: String, message: String, diagnostics: [String]) {
        let classifications = result.itemDecisions.map(\.classification)
        if result.wouldRequirePrompt && promptResult == .notProvided {
            return (
                ChromeMV3JSBridgeErrorCode.productUIUnavailable.rawValue,
                "Permission prompt required, but product permission UI is unavailable in popup/options developer preview.",
                [
                    "Provide an explicit modeled prompt result in internal tests.",
                    "No product permission prompt UI was displayed.",
                ]
            )
        }
        if result.wouldRequirePrompt && promptResult == .denied {
            return (
                ChromeMV3JSBridgeErrorCode.permissionDenied.rawValue,
                "Permission request was denied by the modeled developer-preview prompt result.",
                ["Modeled permission request denial was returned deterministically."]
            )
        }
        if classifications.contains(.missingUserGesture) {
            return (
                "promptRequiredUserGestureMissing",
                "chrome.permissions.request requires a modeled user gesture.",
                ["Request was blocked because no modeled user gesture was supplied."]
            )
        }
        if classifications.contains(.notDeclaredOptional) {
            return (
                "permissionNotDeclaredOptional",
                "Requested permission or origin is not declared optional.",
                ["Only declared optional permissions can be granted."]
            )
        }
        return (
            ChromeMV3JSBridgeErrorCode.permissionDenied.rawValue,
            "chrome.permissions.request was rejected by internal permission state.",
            ["Permission request was not grantable by the popup/options bridge."]
        )
    }

    private func permissionRemoveFailure(
        result: ChromeMV3PermissionsAPIRemoveResult
    ) -> (code: String, message: String, diagnostics: [String]) {
        let classifications = result.itemDecisions.map(\.classification)
        if classifications.contains(.requiredManifestPermission) {
            return (
                "requiredManifestPermission",
                "Required manifest permissions cannot be removed.",
                ["chrome.permissions.remove rejected a required manifest permission."]
            )
        }
        if classifications.contains(.notGranted) {
            return (
                "permissionNotGranted",
                "Requested permission or origin is not currently granted.",
                ["chrome.permissions.remove rejected a non-granted permission."]
            )
        }
        return (
            ChromeMV3JSBridgeErrorCode.permissionDenied.rawValue,
            "chrome.permissions.remove was rejected by internal permission state.",
            ["Permission remove was not applicable."]
        )
    }

    private func storageResultPayload(
        from envelope: ChromeMV3StorageAPIOperationResultEnvelope
    ) -> ChromeMV3StorageValue? {
        if envelope.resultPayload.values.isEmpty == false {
            return .object(envelope.resultPayload.values)
        }
        if let bytes = envelope.resultPayload.bytesInUse {
            return .number(Double(bytes))
        }
        return envelope.resultPayload.voidResult ? .null : nil
    }

    private func popupOnChangedPayload(
        from envelope: ChromeMV3StorageAPIOperationResultEnvelope
    ) -> ChromeMV3StorageOnChangedEventPayload? {
        guard envelope.succeeded,
              let payload = envelope.generatedOnChangedPayload,
              payload.changedKeys.isEmpty == false
        else { return nil }
        return ChromeMV3StorageOnChangedEventPayload(
            areaName: payload.areaName,
            changedKeys: payload.changedKeys,
            changes: payload.changes,
            extensionID: payload.extensionID,
            profileID: payload.profileID,
            wouldDispatchNow: true,
            listenerRegistrationRequired: false,
            serviceWorkerWakeRequired: false,
            blockers: [
                "Popup/options storage.onChanged dispatch is in-page only.",
                "No service-worker wake is performed by the popup/options bridge.",
                "No product normal-tab listener is registered.",
            ],
            serviceWorkerWakePreflight: nil
        )
    }
}

enum ChromeMV3PopupOptionsJSShimSource {
    static let bridgeMessageHandlerName = "sumiChromeMV3PopupOptions"

    static func source(
        configuration: ChromeMV3PopupOptionsJSBridgeConfiguration
    ) -> String {
        let configJSON = jsonString([
            "extensionID": configuration.extensionID,
            "profileID": configuration.profileID,
            "surfaceID": configuration.surfaceID,
            "sourceContext": configuration.sourceContext.rawValue,
            "extensionBaseURLString": configuration.extensionBaseURLString,
            "bridgeMessageHandlerName": bridgeMessageHandlerName,
        ])
        return """
        (() => {
          "use strict";
          const config = \(configJSON);
          const bridgeName = config.bridgeMessageHandlerName;
          const chromeObject = {};
          const runtime = {};
          const storage = {};
          const local = {};
          const permissions = {};
          const tabs = {};
          const scripting = {};
          let lastErrorValue;
          let nextBridgeCallNumber = 0;
          let nextPortNumber = 0;
          const portState = new WeakMap();

          function unavailable(namespace, methodName) {
            return {
              bridgeCallID: "popup-options-unavailable",
              namespace,
              methodName,
              succeeded: false,
              resultPayload: null,
              onChangedPayload: null,
              permissionEventPayload: null,
              lastErrorMessage: "Popup/options JS bridge handler is unavailable.",
              lastErrorCode: "jsBridgeUnavailable",
              callbackWouldSetLastError: false,
              promiseWouldReject: false,
              diagnostics: ["Popup/options JS bridge handler is unavailable."]
            };
          }

          function bridgePost(namespace, methodName, invocationMode, args, extra) {
            const handler = globalThis.webkit
              && globalThis.webkit.messageHandlers
              && globalThis.webkit.messageHandlers[bridgeName];
            if (!handler || typeof handler.postMessage !== "function") {
              return Promise.resolve(unavailable(namespace, methodName));
            }
            nextBridgeCallNumber += 1;
            return handler.postMessage(Object.assign({
              namespace,
              methodName,
              invocationMode,
              extensionID: config.extensionID,
              profileID: config.profileID,
              sourceContext: config.sourceContext,
              surfaceID: config.surfaceID,
              bridgeCallID: [
                "popup-options-js",
                config.surfaceID,
                namespace,
                methodName,
                String(nextBridgeCallNumber)
              ].join("-"),
              arguments: args || []
            }, extra || {}));
          }

          function toJSONCompatible(value) {
            if (value === undefined) {
              return null;
            }
            return JSON.parse(JSON.stringify(value));
          }

          function invokeCallback(callback, message, args) {
            lastErrorValue = message ? { message } : undefined;
            try {
              callback.apply(undefined, args || []);
            } finally {
              lastErrorValue = undefined;
            }
          }

          function rejectFromResponse(response) {
            return Promise.reject(
              new Error(response.lastErrorMessage || "Popup/options JS bridge call failed.")
            );
          }

          function callbackArgs(namespace, methodName, response) {
            if (!response.succeeded) {
              return [];
            }
            if (namespace === "storage" && methodName === "local.get") {
              return [response.resultPayload || {}];
            }
            if (namespace === "storage" && methodName === "local.getBytesInUse") {
              return [Number(response.resultPayload || 0)];
            }
            if (namespace === "permissions" || methodName === "query") {
              return [response.resultPayload];
            }
            if (namespace === "runtime" && methodName === "sendMessage") {
              return [response.resultPayload];
            }
            return [];
          }

          function promiseValue(namespace, methodName, response) {
            if (namespace === "storage" && methodName === "local.get") {
              return response.resultPayload || {};
            }
            if (namespace === "storage" && methodName === "local.getBytesInUse") {
              return Number(response.resultPayload || 0);
            }
            if (namespace === "storage") {
              return undefined;
            }
            return response.resultPayload;
          }

          function callbackOrPromise(namespace, methodName, args, callback) {
            const mode = callback ? "callback" : "promise";
            let bridgeArgs;
            try {
              bridgeArgs = (args || []).map(toJSONCompatible);
            } catch (error) {
              const message = "Invalid Chrome MV3 popup/options JavaScript arguments.";
              if (callback) {
                invokeCallback(callback, message, []);
                return undefined;
              }
              return Promise.reject(new Error(message));
            }
            const promise = bridgePost(namespace, methodName, mode, bridgeArgs)
              .then((response) => {
                if (response.succeeded && namespace === "storage") {
                  dispatchSyntheticStorageEvent(response);
                }
                if (response.succeeded && namespace === "permissions") {
                  dispatchSyntheticPermissionEvent(response);
                }
                return response;
              });
            if (callback) {
              promise.then((response) => {
                if (response.succeeded) {
                  invokeCallback(callback, null, callbackArgs(namespace, methodName, response));
                } else {
                  invokeCallback(callback, response.lastErrorMessage, []);
                }
              });
              return undefined;
            }
            return promise.then((response) => {
              if (response.succeeded) {
                return promiseValue(namespace, methodName, response);
              }
              return rejectFromResponse(response);
            });
          }

          function makeEvent() {
            const listeners = [];
            return Object.freeze({
              addListener(listener) {
                if (typeof listener === "function" && !listeners.includes(listener)) {
                  listeners.push(listener);
                }
              },
              removeListener(listener) {
                const index = listeners.indexOf(listener);
                if (index >= 0) {
                  listeners.splice(index, 1);
                }
              },
              hasListener(listener) {
                return listeners.includes(listener);
              },
              hasListeners() {
                return listeners.length > 0;
              },
              __sumiDispatch() {
                const args = Array.prototype.slice.call(arguments);
                listeners.slice().forEach((listener) => listener.apply(undefined, args));
              }
            });
          }

          const storageOnChanged = makeEvent();
          const permissionsOnAdded = makeEvent();
          const permissionsOnRemoved = makeEvent();

          function normalizeOnChangedPayload(payload) {
            if (!payload || payload.areaName !== "local" || !Array.isArray(payload.changes)) {
              return null;
            }
            const changes = {};
            payload.changes.forEach((entry) => {
              if (!entry || typeof entry.key !== "string") {
                return;
              }
              const change = {};
              if (Object.prototype.hasOwnProperty.call(entry, "oldValue")) {
                change.oldValue = entry.oldValue;
              }
              if (Object.prototype.hasOwnProperty.call(entry, "newValue")) {
                change.newValue = entry.newValue;
              }
              changes[entry.key] = change;
            });
            return { changes, areaName: payload.areaName };
          }

          function dispatchSyntheticStorageEvent(response) {
            const payload = normalizeOnChangedPayload(response && response.onChangedPayload);
            if (payload && Object.keys(payload.changes).length > 0) {
              storageOnChanged.__sumiDispatch(payload.changes, payload.areaName);
            }
          }

          function normalizePermissionEvent(rawPayload) {
            if (!rawPayload || typeof rawPayload !== "object") {
              return null;
            }
            return {
              eventKind: rawPayload.eventKind,
              permissions: Array.isArray(rawPayload.permissions)
                ? rawPayload.permissions.slice().sort()
                : [],
              origins: Array.isArray(rawPayload.origins)
                ? rawPayload.origins.slice().sort()
                : []
            };
          }

          function dispatchSyntheticPermissionEvent(response) {
            const payload = normalizePermissionEvent(response && response.permissionEventPayload);
            if (!payload) {
              return;
            }
            const eventPayload = {
              permissions: payload.permissions,
              origins: payload.origins
            };
            if (payload.eventKind === "onAdded") {
              permissionsOnAdded.__sumiDispatch(eventPayload);
            } else if (payload.eventKind === "onRemoved") {
              permissionsOnRemoved.__sumiDispatch(eventPayload);
            }
          }

          function optionalKeysAndCallback(first, second) {
            if (typeof first === "function") {
              return { keys: undefined, callback: first };
            }
            return {
              keys: first,
              callback: typeof second === "function" ? second : null
            };
          }

          function makePortEvent() {
            const listeners = [];
            return Object.freeze({
              addListener(listener) {
                if (typeof listener === "function" && !listeners.includes(listener)) {
                  listeners.push(listener);
                }
              },
              removeListener(listener) {
                const index = listeners.indexOf(listener);
                if (index >= 0) {
                  listeners.splice(index, 1);
                }
              },
              hasListener(listener) {
                return listeners.includes(listener);
              },
              dispatch() {
                const args = Array.prototype.slice.call(arguments);
                listeners.slice().forEach((listener) => listener.apply(undefined, args));
              }
            });
          }

          function createPort(name) {
            const port = {};
            const state = {
              id: null,
              disconnected: false,
              onMessage: makePortEvent(),
              onDisconnect: makePortEvent()
            };
            Object.defineProperty(port, "name", {
              value: name || "",
              enumerable: true
            });
            Object.defineProperty(port, "onMessage", {
              value: state.onMessage,
              enumerable: true
            });
            Object.defineProperty(port, "onDisconnect", {
              value: state.onDisconnect,
              enumerable: true
            });
            Object.defineProperty(port, "postMessage", {
              value(message) {
                if (state.disconnected) {
                  throw new Error("Attempting to use a disconnected port object");
                }
                state.onMessage.dispatch(toJSONCompatible(message), port);
              },
              enumerable: true
            });
            Object.defineProperty(port, "disconnect", {
              value() {
                if (state.disconnected) {
                  return;
                }
                state.disconnected = true;
                state.onDisconnect.dispatch(port);
              },
              enumerable: true
            });
            portState.set(port, state);
            return port;
          }

          function parseConnectName(rawArgs) {
            const args = Array.prototype.slice.call(rawArgs);
            if (args.length === 1 && args[0] && typeof args[0] === "object") {
              return typeof args[0].name === "string" ? args[0].name : "";
            }
            if (args.length === 2 && args[1] && typeof args[1] === "object") {
              return typeof args[1].name === "string" ? args[1].name : "";
            }
            return "";
          }

          Object.defineProperty(runtime, "lastError", {
            get() {
              return lastErrorValue;
            },
            enumerable: true
          });

          Object.defineProperty(runtime, "getURL", {
            value(path) {
              const raw = typeof path === "string" ? path : "";
              return config.extensionBaseURLString + raw.replace(/^\\/+/, "");
            },
            enumerable: true
          });

          Object.defineProperty(runtime, "sendMessage", {
            value() {
              const rawArgs = Array.prototype.slice.call(arguments);
              let callback = null;
              if (rawArgs.length > 0 && typeof rawArgs[rawArgs.length - 1] === "function") {
                callback = rawArgs.pop();
              }
              return callbackOrPromise("runtime", "sendMessage", rawArgs, callback);
            },
            enumerable: true
          });

          Object.defineProperty(runtime, "connect", {
            value() {
              const args = Array.prototype.slice.call(arguments);
              const port = createPort(parseConnectName(args));
              const state = portState.get(port);
              nextPortNumber += 1;
              state.id = [
                config.surfaceID,
                "runtime-port",
                String(nextPortNumber)
              ].join(":");
              bridgePost("runtime", "connect", "fireAndForget", args.map(toJSONCompatible))
                .then((response) => {
                  if (!response.succeeded) {
                    state.disconnected = true;
                    state.onDisconnect.dispatch(port);
                    return;
                  }
                  const payload = response.resultPayload || {};
                  state.id = payload.portID || state.id;
                })
                .catch(() => {
                  state.disconnected = true;
                  state.onDisconnect.dispatch(port);
                });
              return port;
            },
            enumerable: true
          });

          Object.defineProperty(runtime, "sendNativeMessage", {
            value(application, message, callback) {
              const cb = typeof callback === "function" ? callback : null;
              return callbackOrPromise(
                "runtime",
                "sendNativeMessage",
                [application, message],
                cb
              );
            },
            enumerable: true
          });

          const nativeConnectMethod = "connect" + "Native";
          Object.defineProperty(runtime, nativeConnectMethod, {
            value(application) {
              const port = createPort("");
              const state = portState.get(port);
              bridgePost("runtime", nativeConnectMethod, "fireAndForget", [application])
                .then(() => {
                  state.disconnected = true;
                  state.onDisconnect.dispatch(port);
                })
                .catch(() => {
                  state.disconnected = true;
                  state.onDisconnect.dispatch(port);
                });
              return port;
            },
            enumerable: true
          });

          Object.defineProperty(local, "get", {
            value(keys, callback) {
              const parsed = optionalKeysAndCallback(keys, callback);
              const args = parsed.keys === undefined ? [] : [parsed.keys];
              return callbackOrPromise("storage", "local.get", args, parsed.callback);
            },
            enumerable: true
          });
          Object.defineProperty(local, "set", {
            value(items, callback) {
              const cb = typeof callback === "function" ? callback : null;
              return callbackOrPromise("storage", "local.set", [items], cb);
            },
            enumerable: true
          });
          Object.defineProperty(local, "remove", {
            value(keys, callback) {
              const cb = typeof callback === "function" ? callback : null;
              return callbackOrPromise("storage", "local.remove", [keys], cb);
            },
            enumerable: true
          });
          Object.defineProperty(local, "clear", {
            value(callback) {
              const cb = typeof callback === "function" ? callback : null;
              return callbackOrPromise("storage", "local.clear", [], cb);
            },
            enumerable: true
          });
          Object.defineProperty(local, "getBytesInUse", {
            value(keys, callback) {
              const parsed = optionalKeysAndCallback(keys, callback);
              const args = parsed.keys === undefined ? [] : [parsed.keys];
              return callbackOrPromise("storage", "local.getBytesInUse", args, parsed.callback);
            },
            enumerable: true
          });
          Object.defineProperty(storage, "local", {
            value: Object.freeze(local),
            enumerable: true
          });
          Object.defineProperty(storage, "onChanged", {
            value: storageOnChanged,
            enumerable: true
          });

          ["contains", "request", "remove"].forEach((methodName) => {
            Object.defineProperty(permissions, methodName, {
              value(permissionsObject, callback) {
                const cb = typeof callback === "function" ? callback : null;
                return callbackOrPromise(
                  "permissions",
                  methodName,
                  [permissionsObject || {}],
                  cb
                );
              },
              enumerable: true
            });
          });
          Object.defineProperty(permissions, "getAll", {
            value(callback) {
              const cb = typeof callback === "function" ? callback : null;
              return callbackOrPromise("permissions", "getAll", [], cb);
            },
            enumerable: true
          });
          Object.defineProperty(permissions, "onAdded", {
            value: permissionsOnAdded,
            enumerable: true
          });
          Object.defineProperty(permissions, "onRemoved", {
            value: permissionsOnRemoved,
            enumerable: true
          });

          Object.defineProperty(tabs, "query", {
            value(queryInfo, callback) {
              const cb = typeof callback === "function" ? callback : null;
              return callbackOrPromise("tabs", "query", [queryInfo || {}], cb);
            },
            enumerable: true
          });
          Object.defineProperty(tabs, "sendMessage", {
            value(tabId, message, options, callback) {
              let cb = null;
              let opts = options;
              if (typeof options === "function") {
                cb = options;
                opts = undefined;
              } else if (typeof callback === "function") {
                cb = callback;
              }
              const args = opts === undefined
                ? [tabId, message]
                : [tabId, message, opts];
              return callbackOrPromise("tabs", "sendMessage", args, cb);
            },
            enumerable: true
          });
          Object.defineProperty(tabs, "connect", {
            value(tabId, connectInfo) {
              const port = createPort(connectInfo && connectInfo.name);
              const state = portState.get(port);
              bridgePost("tabs", "connect", "fireAndForget", [tabId, connectInfo || {}])
                .then(() => {
                  state.disconnected = true;
                  state.onDisconnect.dispatch(port);
                })
                .catch(() => {
                  state.disconnected = true;
                  state.onDisconnect.dispatch(port);
                });
              return port;
            },
            enumerable: true
          });

          Object.defineProperty(scripting, "executeScript", {
            value(details, callback) {
              const cb = typeof callback === "function" ? callback : null;
              return callbackOrPromise("scripting", "executeScript", [details || {}], cb);
            },
            enumerable: true
          });

          function blockedNamespace(namespace) {
            return new Proxy({}, {
              get(target, prop) {
                if (typeof prop !== "string") {
                  return undefined;
                }
                if (!Object.prototype.hasOwnProperty.call(target, prop)) {
                  Object.defineProperty(target, prop, {
                    value() {
                      const args = Array.prototype.slice.call(arguments);
                      const callback = typeof args[args.length - 1] === "function"
                        ? args.pop()
                        : null;
                      return callbackOrPromise(namespace, prop, args, callback);
                    },
                    enumerable: true
                  });
                }
                return target[prop];
              }
            });
          }

          Object.defineProperty(chromeObject, "runtime", {
            value: Object.freeze(runtime),
            enumerable: true
          });
          Object.defineProperty(chromeObject, "storage", {
            value: Object.freeze(storage),
            enumerable: true
          });
          Object.defineProperty(chromeObject, "permissions", {
            value: Object.freeze(permissions),
            enumerable: true
          });
          Object.defineProperty(chromeObject, "tabs", {
            value: Object.freeze(tabs),
            enumerable: true
          });
          Object.defineProperty(chromeObject, "scripting", {
            value: Object.freeze(scripting),
            enumerable: true
          });
          ["nativeMessaging", "declarativeNetRequest", "webRequest", "sidePanel", "offscreen", "identity"].forEach((namespace) => {
            Object.defineProperty(chromeObject, namespace, {
              value: blockedNamespace(namespace),
              enumerable: true
            });
          });

          Object.defineProperty(globalThis, "chrome", {
            value: Object.freeze(chromeObject),
            configurable: true
          });
          Object.defineProperty(globalThis, "browser", {
            value: chromeObject,
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

#if canImport(WebKit)
@MainActor
final class ChromeMV3PopupOptionsWKScriptMessageHandler:
    NSObject,
    WKScriptMessageHandlerWithReply
{
    let handler: ChromeMV3PopupOptionsJSBridgeHandler

    init(handler: ChromeMV3PopupOptionsJSBridgeHandler) {
        self.handler = handler
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) async -> (Any?, String?) {
        _ = userContentController
        let response = handler.handle(message.body)
        return (response.foundationObject, nil)
    }
}
#endif

private func uniqueSortedPopupOptionsBridge(_ values: [String]) -> [String] {
    Array(Set(values.filter { $0.isEmpty == false })).sorted()
}

private func stableIDPopupOptionsBridge(
    prefix: String,
    parts: [String]
) -> String {
    let joined = parts.joined(separator: "\u{1F}")
    let digest = SHA256.hash(data: Data(joined.utf8))
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    return "\(prefix)-\(String(hex.prefix(16)))"
}

private func uniqueBlockedDiagnostics(
    _ diagnostics: [ChromeMV3PopupOptionsBlockedAPIDiagnostic]
) -> [ChromeMV3PopupOptionsBlockedAPIDiagnostic] {
    var seen: Set<String> = []
    var unique: [ChromeMV3PopupOptionsBlockedAPIDiagnostic] = []
    for diagnostic in diagnostics.sorted(by: {
        if $0.namespace != $1.namespace { return $0.namespace < $1.namespace }
        return $0.methodName < $1.methodName
    }) {
        let key = "\(diagnostic.namespace).\(diagnostic.methodName)"
        if seen.insert(key).inserted {
            unique.append(diagnostic)
        }
    }
    return unique
}

private extension ChromeMV3StorageValue {
    var objectValue: [String: ChromeMV3StorageValue]? {
        guard case .object(let object) = self else { return nil }
        return object
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    var popupOptionsBridgeFoundationObject: Any {
        switch self {
        case .array(let values):
            return values.map(\.popupOptionsBridgeFoundationObject)
        case .bool(let value):
            return value
        case .null:
            return NSNull()
        case .number(let value):
            return value
        case .object(let object):
            return object.mapValues(\.popupOptionsBridgeFoundationObject)
        case .string(let value):
            return value
        }
    }
}

private extension ChromeMV3StorageOnChangedEventPayload {
    var popupOptionsBridgeFoundationObject: Any {
        [
            "areaName": areaName,
            "changedKeys": changedKeys,
            "changes":
                changes.map(\.popupOptionsBridgeFoundationObject),
            "extensionID": extensionID,
            "profileID": profileID,
            "wouldDispatchNow": wouldDispatchNow,
            "listenerRegistrationRequired": listenerRegistrationRequired,
            "serviceWorkerWakeRequired": serviceWorkerWakeRequired,
            "blockers": blockers,
        ]
    }
}

private extension ChromeMV3StorageChangeRecord {
    var popupOptionsBridgeFoundationObject: Any {
        var object: [String: Any] = ["key": key]
        if let oldValue {
            object["oldValue"] =
                oldValue.popupOptionsBridgeFoundationObject
        }
        if let newValue {
            object["newValue"] =
                newValue.popupOptionsBridgeFoundationObject
        }
        return object
    }
}

private extension ChromeMV3PermissionsAPIEventPayload {
    var popupOptionsBridgeFoundationObject: Any {
        [
            "eventKind": eventKind.rawValue,
            "permissions": permissions,
            "origins": origins,
            "extensionID": extensionID,
            "profileID": profileID,
        ]
    }
}
