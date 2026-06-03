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
            "runtime.connectNative",
            "runtime.getURL",
            "runtime.lastError",
            "runtime.nativePort.disconnect",
            "runtime.nativePort.postMessage",
            "runtime.port.disconnect",
            "runtime.port.postMessage",
            "runtime.sendMessage",
            "runtime.sendNativeMessage",
            "storage.local.clear",
            "storage.local.get",
            "storage.local.getBytesInUse",
            "storage.local.remove",
            "storage.local.set",
            "storage.onChanged",
            "tabs.connect",
            "tabs.port.disconnect",
            "tabs.port.postMessage",
            "tabs.query",
            "tabs.sendMessage",
        ],
        blockedDiagnostics: [
            blocked(
                namespace: "tabs",
                methodName: "sendMessage",
                reason:
                    "tabs.sendMessage requires a registered developer-preview content-script endpoint.",
                remediation:
                    "Attach an eligible manifest-declared content script before routing tabs.sendMessage.",
                roadmapOwner: "Prompt 61"
            ),
            blocked(
                namespace: "tabs",
                methodName: "connect",
                reason:
                    "tabs.connect requires a registered developer-preview content-script Port endpoint.",
                remediation:
                    "Attach an eligible manifest-declared content script and register runtime.onConnect before opening a Port.",
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
    var permissionStateRootPath: String?
    var nativeMessagingFixtureHostRootPaths: [String] = []
    var nativeMessagingTrustedHostPolicyRootPath: String?
    var nativeMessagingTrustedHostApprovalRecords:
        [ChromeMV3NativeTrustedHostApprovalRecord] = []
    var nativeMessagingProductPolicy:
        ChromeMV3NativeMessagingProductPolicy = .blockedRuntimeDefault
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
    var activeTabGrants: [ChromeMV3ActiveTabGrant]
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
            permissionStateRootPath: launchRecord.managerStoreRootPath,
            nativeMessagingFixtureHostRootPaths:
                launchRecord.managerStoreRootPath.map {
                    [
                        URL(fileURLWithPath: $0, isDirectory: true)
                            .appendingPathComponent(
                                "NativeMessagingFixtureHosts",
                                isDirectory: true
                            )
                            .path,
                    ]
                } ?? [],
            nativeMessagingTrustedHostPolicyRootPath:
                launchRecord.managerStoreRootPath,
            nativeMessagingTrustedHostApprovalRecords: [],
            nativeMessagingProductPolicy: .blockedRuntimeDefault,
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
            activeTabGrants:
                Self.activeTabGrantsForExplicitActionPopupOpen(
                    launchRecord: launchRecord,
                    bridgeAvailable: bridgeAvailable
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

    private static func activeTabGrantsForExplicitActionPopupOpen(
        launchRecord: ChromeMV3ProductPopupOptionsLaunchRecord,
        bridgeAvailable: Bool
    ) -> [ChromeMV3ActiveTabGrant] {
        guard bridgeAvailable,
              launchRecord.surface == .actionPopup,
              launchRecord.manifestPermissions.contains("activeTab")
        else { return [] }
        return [
            ChromeMV3ActiveTabGrant(
                extensionID: launchRecord.extensionID,
                profileID: launchRecord.profileID,
                tabID: 1,
                scope: .origin("https://example.com"),
                reason: .actionClick,
                userGestureModeled: true,
                createdSequence: 1,
                diagnostics: [
                    "Developer-preview activeTab grant created from explicit action popup open.",
                    "Grant is scoped to the controlled synthetic active tab fixture and expires through lifecycle events.",
                ]
            ),
        ]
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
    var argumentShapeSummary: String
    var succeeded: Bool
    var lastErrorCode: String?
    var lastErrorMessage: String?
    var serviceWorkerWakeAttempted: Bool
    var serviceWorkerLifecycleWakeResult:
        ChromeMV3ServiceWorkerInternalWakeResult?
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
    var permissionPromptGate:
        ChromeMV3PermissionPromptGateRecord
    var permissionPromptRequests: [ChromeMV3PermissionPromptRequest]
    var permissionPromptResults:
        [ChromeMV3PermissionPromptResultRecord]
    var permissionPromptLifecycleRecords:
        [ChromeMV3PermissionPromptLifecycleRecord]
    var permissionEventDispatches:
        [ChromeMV3PermissionEventDispatchRecord]
    var contentScriptEndpointSummary:
        ChromeMV3ContentScriptEndpointRegistrySummary?
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
    var serviceWorkerLifecycleWakeResult:
        ChromeMV3ServiceWorkerInternalWakeResult?
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
            "serviceWorkerLifecycleWakeResult":
                serviceWorkerLifecycleWakeResultFoundationObject,
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

    private var serviceWorkerLifecycleWakeResultFoundationObject: Any {
        guard let serviceWorkerLifecycleWakeResult,
              let data = try? JSONEncoder().encode(
                serviceWorkerLifecycleWakeResult
              ),
              let object = try? JSONSerialization.jsonObject(with: data)
        else { return NSNull() }
        return object
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
    private let contentScriptEndpointRegistry:
        ChromeMV3ContentScriptEndpointRegistry?
    private let permissionPromptPresenter:
        ChromeMV3PermissionPromptPresenting?
    private let permissionPromptGate:
        ChromeMV3PermissionPromptGateRecord
    private let permissionStateStore:
        ChromeMV3DeveloperPreviewPermissionStateStore?
    private let permissionEventDispatcher:
        ChromeMV3PermissionEventDispatching?
    private var permissionPromptRequests:
        [ChromeMV3PermissionPromptRequest] = []
    private var permissionPromptResults:
        [ChromeMV3PermissionPromptResultRecord] = []
    private var permissionPromptLifecycleRecords:
        [ChromeMV3PermissionPromptLifecycleRecord] = []
    private var permissionEventDispatches:
        [ChromeMV3PermissionEventDispatchRecord] = []
    private var permissionPersistenceDiagnostics: [String] = []
    private var callRecords: [ChromeMV3PopupOptionsJSBridgeCallRecord] = []
    private var onChangedPayloads: [ChromeMV3StorageOnChangedEventPayload] = []
    private var syntheticPortIDs: Set<String> = []
    private var serviceWorkerLifecyclePortIDs: Set<String> = []
    private let sharedLifecycleSession:
        ChromeMV3ServiceWorkerSharedLifecycleSession?
    private let lifecycleComponentID: String
    private let nativeMessagingLifecycleComponentID: String
    private var nativeMessagingRuntimeOwner:
        ChromeMV3NativeMessagingRuntimeOwner?
    private var tornDown = false

    init(
        configuration: ChromeMV3PopupOptionsJSBridgeConfiguration,
        contentScriptEndpointRegistry:
            ChromeMV3ContentScriptEndpointRegistry? = nil,
        permissionPromptPresenter:
            ChromeMV3PermissionPromptPresenting? = nil,
        permissionStateStore:
            ChromeMV3DeveloperPreviewPermissionStateStore? = nil,
        permissionEventDispatcher:
            ChromeMV3PermissionEventDispatching? = nil,
        sharedLifecycleSession:
            ChromeMV3ServiceWorkerSharedLifecycleSession? = nil
    ) {
        self.configuration = configuration
        self.contentScriptEndpointRegistry = contentScriptEndpointRegistry
        self.permissionPromptPresenter = permissionPromptPresenter
        self.sharedLifecycleSession = sharedLifecycleSession
        self.lifecycleComponentID =
            stableIDPopupOptionsBridge(
                prefix: "popup-options-extension-page-host",
                parts: [
                    configuration.profileID,
                    configuration.extensionID,
                    configuration.surfaceID,
                ]
            )
        self.nativeMessagingLifecycleComponentID =
            stableIDPopupOptionsBridge(
                prefix: "popup-options-native-fixture",
                parts: [
                    configuration.profileID,
                    configuration.extensionID,
                    configuration.surfaceID,
                ]
            )
        if let permissionStateStore {
            self.permissionStateStore = permissionStateStore
        } else if let rootPath = configuration.permissionStateRootPath,
                  rootPath.isEmpty == false
        {
            self.permissionStateStore =
                ChromeMV3DeveloperPreviewPermissionStateStore(
                    rootURL: URL(fileURLWithPath: rootPath, isDirectory: true)
                )
        } else {
            self.permissionStateStore = nil
        }
        self.permissionEventDispatcher = permissionEventDispatcher
        self.permissionPromptGate =
            ChromeMV3PermissionPromptGateRecord.evaluate(
                moduleEnabled: configuration.moduleState == .enabled,
                extensionEnabled: configuration.bridgeAvailable,
                developerPreviewGate:
                    configuration
                    .popupOptionsJSBridgeAvailableInDeveloperPreview,
                publicProductGate:
                    configuration
                    .popupOptionsJSBridgeAvailableInPublicProduct
            )
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
        if let persisted = self.permissionStateStore?.loadRecord(
            profileID: configuration.profileID,
            extensionID: configuration.extensionID
        ) {
            self.permissionRuntimeOwner =
                ChromeMV3PermissionRuntimeStateOwner(
                    snapshot: persisted.permissionRuntimeSnapshot
                )
            self.permissionPromptRequests = persisted.promptRequests
            self.permissionPromptResults = persisted.promptResults
            self.permissionPromptLifecycleRecords =
                persisted.promptLifecycleRecords
            self.permissionPersistenceDiagnostics = [
                "Loaded persisted developer-preview permission state for popup/options bridge.",
            ]
        } else {
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
                        ),
                    activeTabStore:
                        ChromeMV3ActiveTabGrantStore.from(
                            extensionID: configuration.extensionID,
                            profileID: configuration.profileID,
                            grants: configuration.activeTabGrants
                        )
                )
        }
        self.tabRegistry =
            ChromeMV3SyntheticTabRegistry.passwordManagerFixture(
                extensionID: configuration.extensionID,
                profileID: configuration.profileID,
                includeProductNormalTab: false
            )
        permissionEventDispatcher?.registerChromeMV3PermissionEventPage(
            surfaceID: configuration.surfaceID,
            profileID: configuration.profileID,
            extensionID: configuration.extensionID,
            surface: configuration.surface,
            dispatchHandler: nil
        )
        attachSharedLifecycleComponentsIfNeeded()
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
            permissionPromptGate: permissionPromptGate,
            permissionPromptRequests: permissionPromptRequests,
            permissionPromptResults: permissionPromptResults,
            permissionPromptLifecycleRecords:
                permissionPromptLifecycleRecords,
            permissionEventDispatches:
                uniquePermissionEventDispatches(
                    permissionEventDispatches
                        + (permissionEventDispatcher?
                            .permissionEventDispatchRecords ?? [])
                ),
            contentScriptEndpointSummary:
                contentScriptEndpointRegistry?.summary,
            listenerRegistryClearedOnTeardown: tornDown,
            storageListenersClearedOnTeardown: tornDown,
            portStateClearedOnTeardown: tornDown,
            diagnostics:
                uniqueSortedPopupOptionsBridge(
                    configuration.diagnostics
                        + permissionPersistenceDiagnostics
                        + [
                            "Popup/options bridge diagnostics are scoped to one WebKit host.",
                            "No normal-tab bridge installation is represented by this snapshot.",
                        ]
                )
        )
    }

    var permissionRuntimeSnapshot:
        ChromeMV3PermissionRuntimeStateOwnerSnapshot
    {
        permissionRuntimeOwner.snapshot
    }

    var permissionBroker: ChromeMV3PermissionBroker {
        permissionRuntimeOwner.permissionBroker
    }

    @discardableResult
    func grantActiveTabFromExplicitUserAction(
        tabID: Int = 1,
        sourceSurface: ChromeMV3PermissionPromptSourceSurface = .actionClick,
        sequence: Int = 0
    ) -> ChromeMV3ActiveTabRuntimeGrantResult {
        let tab = tabRegistry.tab(id: tabID)
        let result = ChromeMV3DeveloperPreviewActiveTabUX.grant(
            request:
                ChromeMV3ActiveTabUXRequest(
                    extensionID: configuration.extensionID,
                    profileID: configuration.profileID,
                    tabID: tabID,
                    url: tab?.url ?? "",
                    sourceSurface: sourceSurface,
                    explicitUserGesture: true,
                    sequence: sequence
                ),
            gateRecord: permissionPromptGate,
            owner: &permissionRuntimeOwner
        )
        persistPermissionState(
            diagnostics: [
                result.granted
                    ? "activeTab grant persisted after explicit user action."
                    : "Blocked activeTab grant result persisted for diagnostics.",
            ]
        )
        return result
    }

    @discardableResult
    func applyPermissionLifecycleEvent(
        _ event: ChromeMV3PermissionLifecycleEvent
    ) -> ChromeMV3PermissionRuntimeLifecycleApplication {
        let application = permissionRuntimeOwner.applyLifecycleEvent(event)
        invalidateContentScriptEndpoints(
            reason:
                "Permission lifecycle event invalidated stale content-script endpoints."
        )
        persistPermissionState(diagnostics: application.diagnostics)
        return application
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

    @MainActor
    func handleAsync(
        _ body: Any
    ) async -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        switch ChromeMV3RuntimeJSBridgeHostRequest.parse(body) {
        case .success(let request):
            return await handleAsync(request)
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

    @MainActor
    func handleAsync(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) async -> ChromeMV3PopupOptionsJSBridgeHostResponse {
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
        case ("tabs", "sendMessage"):
            return await tabsSendMessageAsync(request)
        default:
            return handle(request)
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
        case ("runtime", "port.postMessage"):
            return runtimePortPostMessage(request)
        case ("runtime", "port.disconnect"):
            return runtimePortDisconnect(request)
        case ("runtime", "sendNativeMessage"):
            return runtimeSendNativeMessage(request)
        case ("runtime", let method) where method == "connect" + "Native":
            return runtimeConnectNative(request)
        case ("runtime", "nativePort.postMessage"):
            return runtimeNativePortPostMessage(request)
        case ("runtime", "nativePort.disconnect"):
            return runtimeNativePortDisconnect(request)
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
        case ("permissions", "__sumiPermissionEventListenerCount"):
            return permissionsEventListenerCountChanged(request)
        case ("tabs", "query"):
            return tabsQuery(request)
        case ("tabs", "sendMessage"):
            return tabsSendMessage(request)
        case ("tabs", "connect"):
            return tabsConnect(request)
        case ("tabs", "port.postMessage"):
            return tabsPortPostMessage(request)
        case ("tabs", "port.disconnect"):
            return tabsPortDisconnect(request)
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

    func handleServiceWorkerTabsRequest(
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
                sourceContext: .serviceWorker,
                diagnostics: [
                    "Service-worker tabs bridge request blocked because the module, extension, or developer-preview bridge gate is disabled.",
                ]
            )
        }
        switch (request.namespace, request.methodName) {
        case ("tabs", "query"):
            return tabsQuery(request, sourceContextOverride: .serviceWorker)
        case ("tabs", "sendMessage"):
            return tabsSendMessage(
                request,
                sourceContextOverride: .serviceWorker
            )
        default:
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage:
                    ChromeMV3JSBridgeErrorCode.methodUnsupported
                    .lastErrorMessage,
                lastErrorCode:
                    ChromeMV3JSBridgeErrorCode.methodUnsupported.rawValue,
                sourceContext: .serviceWorker,
                diagnostics: [
                    "Only tabs.query and tabs.sendMessage are exposed to the modeled service-worker tab/content-script bridge in this increment.",
                ]
            )
        }
    }

    @MainActor
    func handleServiceWorkerTabsRequestAsync(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) async -> ChromeMV3PopupOptionsJSBridgeHostResponse {
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
                sourceContext: .serviceWorker,
                diagnostics: [
                    "Service-worker tabs bridge request blocked because the module, extension, or developer-preview bridge gate is disabled.",
                ]
            )
        }
        switch (request.namespace, request.methodName) {
        case ("tabs", "query"):
            return tabsQuery(request, sourceContextOverride: .serviceWorker)
        case ("tabs", "sendMessage"):
            return await tabsSendMessageAsync(
                request,
                sourceContextOverride: .serviceWorker
            )
        default:
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage:
                    ChromeMV3JSBridgeErrorCode.methodUnsupported
                    .lastErrorMessage,
                lastErrorCode:
                    ChromeMV3JSBridgeErrorCode.methodUnsupported.rawValue,
                sourceContext: .serviceWorker,
                diagnostics: [
                    "Only tabs.query and tabs.sendMessage are exposed to the modeled service-worker tab/content-script bridge in this increment.",
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
        for portID in serviceWorkerLifecyclePortIDs {
            sharedLifecycleSession?.disconnectKeepalive(
                portID: portID,
                reason: .reset
            )
        }
        serviceWorkerLifecyclePortIDs.removeAll()
        syntheticPortIDs.removeAll()
        nativeMessagingRuntimeOwner?.tearDownForProfileClose()
        nativeMessagingRuntimeOwner = nil
        permissionPromptRequests.removeAll()
        permissionPromptResults.removeAll()
        permissionPromptLifecycleRecords.removeAll()
        permissionEventDispatches.removeAll()
        permissionPersistenceDiagnostics.removeAll()
        permissionEventDispatcher?
            .unregisterChromeMV3PermissionEventPage(
                surfaceID: configuration.surfaceID
            )
        sharedLifecycleSession?.detachComponent(
            componentID: lifecycleComponentID,
            reason: .reset
        )
        sharedLifecycleSession?.detachComponent(
            componentID: nativeMessagingLifecycleComponentID,
            reason: .reset
        )
        tabRegistry.tearDown()
        tornDown = true
    }

    private func attachSharedLifecycleComponentsIfNeeded() {
        guard let sharedLifecycleSession else { return }
        sharedLifecycleSession.attachComponent(
            kind: .extensionPageHostHarness,
            componentID: lifecycleComponentID,
            eventSurfaces: [
                .runtimeOnMessage,
                .runtimeOnConnect,
                .storageOnChanged,
                .permissionsOnAdded,
                .permissionsOnRemoved,
            ],
            keepaliveSources: [.runtimePort],
            diagnostics: [
                "Popup/options host attached to the local experimental shared lifecycle session.",
                "The default runtime remains off unless a caller passes this session explicitly.",
            ]
        )
        sharedLifecycleSession.attachComponent(
            kind: .nativeMessagingFixtureRuntime,
            componentID: nativeMessagingLifecycleComponentID,
            eventSurfaces: [
                .nativePortOnMessage,
                .nativePortOnDisconnect,
            ],
            keepaliveSources: [.nativeMessagingPort],
            diagnostics: [
                "Trusted native-messaging fixture attached to the local experimental shared lifecycle session.",
                "Arbitrary native host discovery remains unavailable.",
            ]
        )
    }

    private func routeServiceWorkerLifecycleEvent(
        source: ChromeMV3ServiceWorkerEventSource,
        payload: ChromeMV3StorageValue?,
        payloadSummary: String,
        componentID: String? = nil,
        componentKind:
            ChromeMV3ServiceWorkerSharedLifecycleComponentKind =
                .extensionPageHostHarness,
        sourceContext: ChromeMV3RuntimeMessagingContextKind? = nil,
        keepaliveKind: ChromeMV3ServiceWorkerInternalKeepaliveKind? = nil,
        portID: String? = nil
    ) -> ChromeMV3ServiceWorkerInternalWakeResult? {
        sharedLifecycleSession?.routeEvent(
            reason: source.wakeReason,
            listenerEvent: source.listenerEvent,
            sourceComponentID: componentID ?? lifecycleComponentID,
            sourceComponentKind: componentKind,
            payload: payload,
            payloadSummary: payloadSummary,
            sourceContext:
                sourceContext ?? configuration.sourceContext.runtimeContext,
            keepaliveKind: keepaliveKind,
            portID: portID
        )
    }

    private func popupServiceWorkerSenderMetadata()
        -> ChromeMV3ServiceWorkerEventSenderMetadata
    {
        ChromeMV3ServiceWorkerEventSenderMetadata(
            tabID: nil,
            frameID: nil,
            documentID: nil,
            sourceURL: configuration.extensionBaseURLString,
            urlRedacted: false,
            redactionState: "extension-owned popup/options sender URL"
        )
    }

    private func dispatchServiceWorkerJSListener(
        source: ChromeMV3ServiceWorkerEventSource,
        arguments: [ChromeMV3StorageValue],
        payloadSummary: String,
        keepaliveKind: ChromeMV3ServiceWorkerInternalKeepaliveKind? = nil,
        portID: String? = nil
    ) -> ChromeMV3ServiceWorkerJSListenerDispatchResult? {
        sharedLifecycleSession?.dispatchRegisteredJSListener(
            source: source,
            arguments: arguments,
            sender: popupServiceWorkerSenderMetadata(),
            payloadSummary: payloadSummary,
            sourceComponentID: lifecycleComponentID,
            sourceComponentKind: .extensionPageHostHarness,
            keepaliveKind: keepaliveKind,
            portID: portID
        )
    }

    private func runtimeLastErrorContract(
        for resultKind: ChromeMV3ServiceWorkerJSDispatchResultKind
    ) -> ChromeMV3RuntimeLastErrorContract {
        switch resultKind {
        case .noListener, .noReceiver:
            return ChromeMV3RuntimeLastErrorContract
                .contract(for: .noReceivingEnd)
        case .blockedByPermission:
            return ChromeMV3RuntimeLastErrorContract
                .contract(for: .permissionDenied)
        case .blockedByGate:
            return ChromeMV3RuntimeLastErrorContract
                .contract(for: .serviceWorkerUnavailable)
        case .delivered, .listenerError, .promiseRejected,
             .sendResponseTimeoutDiagnostic, .unsupportedListenerMode:
            return ChromeMV3RuntimeLastErrorContract
                .contract(for: .timeout)
        }
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
        if let jsResult = dispatchServiceWorkerJSListener(
            source: .popupOptionsRuntimeMessage,
            arguments: [request.arguments[0]],
            payloadSummary: "popup/options runtime.sendMessage"
        ) {
            if jsResult.dispatched {
                return response(
                    request: request,
                    succeeded: true,
                    payload: jsResult.responsePayload ?? .null,
                    serviceWorkerLifecycleWakeResult:
                        jsResult.lifecycleWakeResult,
                    diagnostics:
                        jsResult.diagnostics
                        + [
                            "runtime.sendMessage dispatched to a captured service-worker runtime.onMessage JavaScript listener.",
                        ]
                )
            }
            let contract = runtimeLastErrorContract(for: jsResult.resultKind)
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage:
                    jsResult.lastErrorMessage
                    ?? contract.futureLastErrorMessage,
                lastErrorCode: contract.error.rawValue,
                serviceWorkerLifecycleWakeResult: jsResult.lifecycleWakeResult,
                diagnostics:
                    jsResult.diagnostics
                    + contract.diagnostics
                    + [
                        "runtime.sendMessage reached a captured service-worker JavaScript listener dispatcher but did not receive a response.",
                    ]
            )
        }
        if let lifecycleResult = routeServiceWorkerLifecycleEvent(
            source: .popupOptionsRuntimeMessage,
            payload: request.arguments[0],
            payloadSummary: "popup/options runtime.sendMessage"
        ) {
            guard lifecycleResult.dispatched else {
                let contract = ChromeMV3RuntimeLastErrorContract
                    .contract(for: .noReceivingEnd)
                return response(
                    request: request,
                    succeeded: false,
                    lastErrorMessage:
                        lifecycleResult.lastErrorMessage
                        ?? contract.futureLastErrorMessage,
                    lastErrorCode: contract.error.rawValue,
                    serviceWorkerLifecycleWakeResult: lifecycleResult,
                    diagnostics:
                        lifecycleResult.diagnostics
                        + contract.diagnostics
                        + [
                            "runtime.sendMessage reached the local experimental service-worker lifecycle but no listener accepted it.",
                        ]
                )
            }
            return response(
                request: request,
                succeeded: true,
                payload: lifecycleResult.responsePayload ?? .null,
                serviceWorkerLifecycleWakeResult: lifecycleResult,
                diagnostics:
                    lifecycleResult.diagnostics
                    + [
                        "runtime.sendMessage routed through the local experimental shared lifecycle session.",
                    ]
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
        let connectName = request.arguments.first?.objectValue?["name"]?
            .stringValue ?? ""
        let portID = stableIDPopupOptionsBridge(
            prefix: "popup-options-runtime-port",
            parts: [
                configuration.surfaceID,
                request.bridgeCallID,
                String(syntheticPortIDs.count + 1),
            ]
        )
        let connectPayload = ChromeMV3StorageValue.object([
            "portID": .string(portID),
            "name": .string(connectName),
        ])
        if let jsResult = dispatchServiceWorkerJSListener(
            source: .popupOptionsRuntimeConnect,
            arguments: [connectPayload],
            payloadSummary: "popup/options runtime.connect",
            keepaliveKind: .runtimePort,
            portID: portID
        ) {
            guard jsResult.dispatched else {
                let contract = runtimeLastErrorContract(
                    for: jsResult.resultKind
                )
                return response(
                    request: request,
                    succeeded: false,
                    lastErrorMessage:
                        jsResult.lastErrorMessage
                        ?? contract.futureLastErrorMessage,
                    lastErrorCode: contract.error.rawValue,
                    serviceWorkerLifecycleWakeResult:
                        jsResult.lifecycleWakeResult,
                    diagnostics:
                        jsResult.diagnostics
                        + contract.diagnostics
                        + [
                            "runtime.connect reached a captured service-worker JavaScript runtime.onConnect dispatcher but no Port was opened.",
                        ]
                )
            }
            syntheticPortIDs.insert(portID)
            serviceWorkerLifecyclePortIDs.insert(portID)
            return response(
                request: request,
                succeeded: true,
                payload: .object([
                    "portID": .string(portID),
                    "portKind": .string("serviceWorkerRuntimePort"),
                    "name": .string(connectName),
                    "canOpenRuntimePortNow": .bool(true),
                    "canWakeServiceWorkerNow": .bool(true),
                    "runtimeLoadable": .bool(false),
                ]),
                serviceWorkerLifecycleWakeResult:
                    jsResult.lifecycleWakeResult,
                diagnostics:
                    jsResult.diagnostics
                    + [
                        "runtime.connect delivered a named Port to captured service-worker runtime.onConnect JavaScript listener(s).",
                        "Port ID \(portID) is bound for later runtime Port.postMessage and disconnect delivery.",
                    ]
            )
        }
        if let lifecycleResult = routeServiceWorkerLifecycleEvent(
            source: .popupOptionsRuntimeConnect,
            payload: connectPayload,
            payloadSummary: "popup/options runtime.connect",
            keepaliveKind: .runtimePort,
            portID: portID
        ) {
            guard lifecycleResult.dispatched else {
                let contract = ChromeMV3RuntimeLastErrorContract
                    .contract(for: .noReceivingEnd)
                return response(
                    request: request,
                    succeeded: false,
                    lastErrorMessage:
                        lifecycleResult.lastErrorMessage
                        ?? contract.futureLastErrorMessage,
                    lastErrorCode: contract.error.rawValue,
                    serviceWorkerLifecycleWakeResult: lifecycleResult,
                    diagnostics:
                        lifecycleResult.diagnostics
                        + contract.diagnostics
                        + [
                            "runtime.connect reached the local experimental service-worker lifecycle but no listener accepted it.",
                        ]
                )
            }
            syntheticPortIDs.insert(portID)
            serviceWorkerLifecyclePortIDs.insert(portID)
            return response(
                request: request,
                succeeded: true,
                payload: .object([
                    "portID": .string(portID),
                    "portKind": .string("serviceWorkerRuntimePort"),
                    "canOpenRuntimePortNow": .bool(true),
                    "canWakeServiceWorkerNow": .bool(true),
                    "runtimeLoadable": .bool(false),
                ]),
                serviceWorkerLifecycleWakeResult: lifecycleResult,
                diagnostics:
                    lifecycleResult.diagnostics
                    + [
                        "runtime.connect opened a local experimental service-worker Port keepalive.",
                    ]
            )
        }
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

    private func runtimePortPostMessage(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        guard request.arguments.count == 2,
              let portID = request.arguments[0].stringValue
        else {
            return invalidArguments(
                request,
                "runtime Port postMessage requires portID and message arguments."
            )
        }
        guard serviceWorkerLifecyclePortIDs.contains(portID),
              let sharedLifecycleSession
        else {
            return runtimeLastErrorResponse(
                request,
                error: .noReceivingEnd,
                diagnostics: [
                    "No open popup/options service-worker runtime Port exists for \(portID).",
                ]
            )
        }
        let delivery = sharedLifecycleSession.deliverRuntimePortMessage(
            portID: portID,
            message: request.arguments[1],
            source: .popupOptionsRuntimeConnect,
            sender: popupServiceWorkerSenderMetadata(),
            payloadSummary:
                "popup/options service-worker runtime Port.postMessage",
            sourceComponentID: lifecycleComponentID,
            sourceComponentKind: .extensionPageHostHarness
        )
        if delivery.connected == false {
            serviceWorkerLifecyclePortIDs.remove(portID)
            syntheticPortIDs.remove(portID)
        }
        guard delivery.delivered else {
            let contract = ChromeMV3RuntimeLastErrorContract
                .contract(for: .noReceivingEnd)
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage:
                    delivery.lastErrorMessage
                    ?? contract.futureLastErrorMessage,
                lastErrorCode: contract.error.rawValue,
                serviceWorkerLifecycleWakeResult:
                    delivery.lifecycleWakeResult,
                diagnostics:
                    delivery.diagnostics
                    + contract.diagnostics
                    + [
                        "popup/options Port.postMessage did not reach a captured service-worker Port.",
                    ]
            )
        }
        return response(
            request: request,
            succeeded: true,
            payload: runtimePortDeliveryPayload(
                delivery,
                direction: "popupOptionsToServiceWorker"
            ),
            serviceWorkerLifecycleWakeResult:
                delivery.lifecycleWakeResult,
            diagnostics:
                delivery.diagnostics
                + [
                    "popup/options Port.postMessage reached service-worker Port.onMessage.",
                ]
        )
    }

    private func runtimePortDisconnect(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        guard request.arguments.count == 1,
              let portID = request.arguments[0].stringValue
        else {
            return invalidArguments(
                request,
                "runtime Port disconnect requires one portID argument."
            )
        }
        let wasOpen = serviceWorkerLifecyclePortIDs.remove(portID) != nil
        syntheticPortIDs.remove(portID)
        let delivery = sharedLifecycleSession?.disconnectRuntimePort(
            portID: portID,
            source: .popupOptionsRuntimeConnect,
            sender: popupServiceWorkerSenderMetadata(),
            payloadSummary:
                "popup/options service-worker runtime Port.disconnect",
            sourceComponentID: lifecycleComponentID,
            sourceComponentKind: .extensionPageHostHarness,
            reason: "Port.disconnect called by popup/options."
        )
        if delivery == nil, wasOpen {
            sharedLifecycleSession?.disconnectKeepalive(
                portID: portID,
                reason: .reset
            )
        }
        return response(
            request: request,
            succeeded: true,
            payload: runtimePortDeliveryPayload(
                delivery
                    ?? ChromeMV3ServiceWorkerRuntimePortDeliveryResult(
                        portID: portID,
                        delivered: wasOpen,
                        connected: false,
                        postedMessages: [],
                        onMessageListenerCount: 0,
                        onDisconnectListenerCount: 0,
                        disconnectReason:
                            wasOpen
                                ? "Port.disconnect called by popup/options."
                                : "Port not found.",
                        lastErrorMessage: nil,
                        lifecycleWakeResult: nil,
                        diagnostics: [
                            wasOpen
                                ? "Popup/options runtime Port keepalive was released without a captured service-worker Port dispatcher."
                                : "Popup/options runtime Port disconnect was a no-op because the Port was already closed.",
                        ]
                    ),
                direction: "popupOptionsToServiceWorker"
            ),
            diagnostics:
                (delivery?.diagnostics ?? [])
                + [
                    "popup/options Port.disconnect propagated through the local experimental service-worker Port path when a captured dispatcher was present.",
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

    private func runtimeSendNativeMessage(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        guard request.arguments.count == 2,
              let hostName = request.arguments[0].stringValue
        else {
            return invalidArguments(
                request,
                "runtime.sendNativeMessage requires host name and message arguments."
            )
        }
        let owner = nativeMessagingOwner()
        let result = owner.sendNativeMessage(
            hostName: hostName,
            message: request.arguments[1]
        )
        guard result.succeeded else {
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage: result.lastErrorMessage,
                lastErrorCode: result.lastErrorCode?.rawValue
                    ?? ChromeMV3JSBridgeErrorCode.productBlocked.rawValue,
                blockedAPIDiagnostic:
                    configuration.allowlist.blockedDiagnostic(
                        namespace: "runtime",
                        methodName: request.methodName
                    ),
                nativeHostLaunchAttempted:
                    result.lifecycle.processLaunchAttempted,
                diagnostics:
                    result.diagnostics
                    + [
                        "runtime.sendNativeMessage used trusted-host product preflight before any fixture host launch.",
                    ]
            )
        }
        return response(
            request: request,
            succeeded: true,
            payload: result.response ?? .null,
            nativeHostLaunchAttempted:
                result.lifecycle.processLaunchAttempted,
            diagnostics:
                result.diagnostics
                + [
                    "runtime.sendNativeMessage completed through an approved developer-preview fixture host.",
                    "Stable native messaging remains unavailable.",
                ]
        )
    }

    private func runtimeConnectNative(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        guard request.arguments.count == 1,
              let hostName = request.arguments[0].stringValue
        else {
            return invalidArguments(
                request,
                "runtime.connectNative requires one host name argument."
            )
        }
        let owner = nativeMessagingOwner()
        let result = owner.connectNative(hostName: hostName)
        guard result.succeeded, let portID = result.portID else {
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage: result.lastErrorMessage,
                lastErrorCode: result.lastErrorCode?.rawValue
                    ?? ChromeMV3JSBridgeErrorCode.productBlocked.rawValue,
                blockedAPIDiagnostic:
                    configuration.allowlist.blockedDiagnostic(
                        namespace: "runtime",
                        methodName: request.methodName
                    ),
                nativeHostLaunchAttempted:
                    result.lifecycle.processLaunchAttempted,
                diagnostics:
                    result.diagnostics
                    + [
                        "runtime.connectNative used trusted-host product preflight before any fixture host launch.",
                    ]
            )
        }
        syntheticPortIDs.insert(portID)
        let lifecycleResult = routeServiceWorkerLifecycleEvent(
            source: .nativeMessagingConnect,
            payload: .object([
                "portID": .string(portID),
                "hostName": .string(hostName),
            ]),
            payloadSummary: "trusted native-messaging fixture connectNative",
            componentID: nativeMessagingLifecycleComponentID,
            componentKind: .nativeMessagingFixtureRuntime,
            sourceContext: .nativeApplication,
            keepaliveKind: .nativeMessagingPort,
            portID: portID
        )
        if lifecycleResult != nil {
            serviceWorkerLifecyclePortIDs.insert(portID)
        }
        return response(
            request: request,
            succeeded: true,
            payload: .object([
                "portID": .string(portID),
                "hostName": .string(hostName),
                "portKind": .string("nativeMessagingTrustedFixturePort"),
                "canOpenRuntimePortNow": .bool(false),
                "canWakeServiceWorkerNow": .bool(lifecycleResult != nil),
                "runtimeLoadable": .bool(false),
            ]),
            serviceWorkerLifecycleWakeResult: lifecycleResult,
            nativeHostLaunchAttempted:
                result.lifecycle.processLaunchAttempted,
            diagnostics:
                result.diagnostics
                + (lifecycleResult?.diagnostics ?? [])
                + [
                    "runtime.connectNative opened a developer-preview trusted fixture Port.",
                    lifecycleResult == nil
                        ? "No service-worker keepalive is started without a shared lifecycle session."
                        : "Native fixture Port was mirrored into the local experimental service-worker lifecycle.",
                ]
        )
    }

    private func runtimeNativePortPostMessage(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        guard request.arguments.count == 2,
              let portID = request.arguments[0].stringValue
        else {
            return invalidArguments(
                request,
                "native Port postMessage requires portID and message arguments."
            )
        }
        guard let owner = nativeMessagingRuntimeOwner else {
            return runtimeLastErrorResponse(
                request,
                error: .noReceivingEnd,
                diagnostics: [
                    "No native messaging runtime owner exists for this popup/options page."
                ]
            )
        }
        let result = owner.postMessage(
            portID: portID,
            message: request.arguments[1]
        )
        if result.succeeded == false {
            syntheticPortIDs.remove(portID)
        }
        let lifecycleResult =
            result.succeeded
                ? routeServiceWorkerLifecycleEvent(
                    source: .nativeMessagingMessage,
                    payload: .object([
                        "portID": .string(result.portID),
                        "hostName": .string(result.hostName),
                        "message": request.arguments[1],
                    ]),
                    payloadSummary:
                        "trusted native-messaging fixture Port.postMessage",
                    componentID: nativeMessagingLifecycleComponentID,
                    componentKind: .nativeMessagingFixtureRuntime,
                    sourceContext: .nativeApplication,
                    portID: portID
                )
                : nil
        return response(
            request: request,
            succeeded: result.succeeded,
            payload: .object([
                "portID": .string(result.portID),
                "hostName": .string(result.hostName),
                "response": result.response ?? .null,
            ]),
            lastErrorMessage: result.lastErrorMessage,
            lastErrorCode: result.lastErrorCode?.rawValue,
            serviceWorkerLifecycleWakeResult: lifecycleResult,
            nativeHostLaunchAttempted:
                result.lifecycle.processLaunchAttempted,
            diagnostics:
                result.diagnostics
                + (lifecycleResult?.diagnostics ?? [])
        )
    }

    private func runtimeNativePortDisconnect(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        guard request.arguments.count == 1,
              let portID = request.arguments[0].stringValue
        else {
            return invalidArguments(
                request,
                "native Port disconnect requires one portID argument."
            )
        }
        guard let owner = nativeMessagingRuntimeOwner else {
            return response(
                request: request,
                succeeded: true,
                payload: .object([
                    "portID": .string(portID),
                    "disconnected": .bool(false),
                    "disconnectReason": .string(
                        "No native messaging runtime owner is available."
                    ),
                ]),
                diagnostics: [
                    "Native Port disconnect was a deterministic no-op because no owner exists."
                ]
            )
        }
        let result = owner.disconnect(
            portID: portID,
            reason: .nativeHostExited
        )
        syntheticPortIDs.remove(portID)
        if serviceWorkerLifecyclePortIDs.remove(portID) != nil {
            sharedLifecycleSession?.disconnectKeepalive(
                portID: portID,
                reason: .reset
            )
        }
        return response(
            request: request,
            succeeded: true,
            payload: .object([
                "portID": .string(portID),
                "hostName": result.hostName.map(ChromeMV3StorageValue.string)
                    ?? .null,
                "disconnected": .bool(result.disconnected),
                "activePortCountAfterDisconnect":
                    .number(Double(result.activePortCountAfterDisconnect)),
            ]),
            nativeHostLaunchAttempted:
                result.lifecycle?.processLaunchAttempted ?? false,
            diagnostics:
                result.diagnostics
                + [
                    "Native fixture Port disconnect releases any mirrored local experimental service-worker keepalive.",
                ]
        )
    }

    private func runtimePortDeliveryPayload(
        _ delivery: ChromeMV3ServiceWorkerRuntimePortDeliveryResult,
        direction: String
    ) -> ChromeMV3StorageValue {
        var object: [String: ChromeMV3StorageValue] = [
            "portID": .string(delivery.portID),
            "delivered": .bool(delivery.delivered),
            "connected": .bool(delivery.connected),
            "disconnected": .bool(delivery.connected == false),
            "direction": .string(direction),
            "postedMessages": .array(delivery.postedMessages),
            "onMessageListenerCount":
                .number(Double(delivery.onMessageListenerCount)),
            "onDisconnectListenerCount":
                .number(Double(delivery.onDisconnectListenerCount)),
        ]
        if let disconnectReason = delivery.disconnectReason {
            object["disconnectReason"] = .string(disconnectReason)
        }
        return .object(object)
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
            let lifecycleResult = onChanged.flatMap {
                routeServiceWorkerLifecycleEvent(
                    source: .storageChanged,
                    payload: storageOnChangedLifecyclePayload($0),
                    payloadSummary: "popup/options storage.onChanged",
                    sourceContext: configuration.sourceContext.runtimeContext
                )
            }
            return response(
                request: request,
                succeeded: true,
                payload: storageResultPayload(from: envelope),
                onChangedPayload: onChanged,
                serviceWorkerLifecycleWakeResult: lifecycleResult,
                diagnostics:
                    envelope.diagnostics
                        + (lifecycleResult?.diagnostics ?? [])
                        + [
                            "storage.local operation used the existing storage operation handler.",
                            lifecycleResult == nil
                                ? "storage.onChanged dispatch is in-page only without a shared lifecycle session."
                                : "storage.onChanged routed through the local experimental service-worker lifecycle.",
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
            let requestResult = ChromeMV3PermissionsAPIContractEvaluator
                .request(
                    input: input,
                    permissionStore: permissionRuntimeOwner.permissionStore,
                    activeTabStore: permissionRuntimeOwner.activeTabStore
                )
            if requestResult.wouldBeAllowedByModel {
                let application = permissionRuntimeOwner.request(input: input)
                return response(
                    request: request,
                    succeeded: true,
                    payload: .bool(application.returnedBoolean),
                    permissionEventPayload: nil,
                    diagnostics:
                        application.diagnostics
                            + [
                                "permissions.request returned true because the requested permissions were already granted.",
                                "No prompt was displayed and no new grant was created.",
                            ]
                )
            }

            let promptRequest = ChromeMV3PermissionPromptRequest.make(
                sequence: permissionPromptRequests.count
                    + permissionPromptResults.count
                    + 1,
                extensionName: configuration.extensionID,
                sourceSurface:
                    configuration.sourceContext.permissionPromptSourceSurface,
                input: input,
                requestResult: requestResult,
                permissionStore: permissionRuntimeOwner.permissionStore,
                gateRecord: permissionPromptGate
            )
            permissionPromptRequests.append(promptRequest)
            appendPromptLifecycle(
                promptRequest,
                stage: .promptCreated,
                diagnostics: [
                    "chrome.permissions.request created a developer-preview prompt request record.",
                ]
            )

            guard requestResult.wouldRequirePrompt,
                  promptRequest.promptEligibility.canPrompt
            else {
                let application = permissionRuntimeOwner.request(input: input)
                let blockedResult = promptRequest.result(
                    .blocked,
                    diagnostics: promptRequest.promptEligibility.diagnostics
                )
                permissionPromptResults.append(blockedResult)
                appendPromptLifecycle(
                    promptRequest,
                    stage: .blocked,
                    resultDisposition: .blocked,
                    diagnostics: blockedResult.diagnostics
                )
                let diagnostic = permissionRequestFailure(
                    result: application.result,
                    promptResult: .notProvided,
                    promptRequest: promptRequest,
                    promptResultRecord: blockedResult
                )
                persistPermissionState(diagnostics: diagnostic.diagnostics)
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

            guard let permissionPromptPresenter else {
                let unavailable = promptRequest.result(
                    .unavailable,
                    diagnostics: [
                        "Permission prompt required, but no developer-preview presenter is installed.",
                    ]
                )
                permissionPromptResults.append(unavailable)
                appendPromptLifecycle(
                    promptRequest,
                    stage: .blocked,
                    resultDisposition: .unavailable,
                    diagnostics: unavailable.diagnostics
                )
                let application = permissionRuntimeOwner.request(input: input)
                let diagnostic = permissionRequestFailure(
                    result: application.result,
                    promptResult: .notProvided,
                    promptRequest: promptRequest,
                    promptResultRecord: unavailable
                )
                persistPermissionState(diagnostics: diagnostic.diagnostics)
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

            appendPromptLifecycle(
                promptRequest,
                stage: .promptPresented,
                diagnostics: [
                    "Developer-preview permission prompt presenter was invoked.",
                ]
            )
            let promptResultRecord =
                permissionPromptPresenter
                .presentChromeMV3PermissionPrompt(promptRequest)
            permissionPromptResults.append(promptResultRecord)
            appendPromptLifecycle(
                promptRequest,
                stage: lifecycleStage(for: promptResultRecord.disposition),
                resultDisposition: promptResultRecord.disposition,
                diagnostics: promptResultRecord.diagnostics
            )

            switch promptResultRecord.disposition {
            case .accepted:
                let application = permissionRuntimeOwner.request(
                    input: input,
                    modeledPromptResult: .accepted,
                    productPromptResult: promptResultRecord
                )
                let dispatchRecord = dispatchPermissionEventIfNeeded(
                    application.result.eventPayloadIfAccepted,
                    sourceSurfaceID: configuration.surfaceID
                )
                invalidateContentScriptEndpoints(
                    reason:
                        "chrome.permissions.request granted host/API access for popup/options bridge."
                )
                appendPromptLifecycle(
                    promptRequest,
                    stage: .downstreamInvalidated,
                    resultDisposition: .accepted,
                    diagnostics:
                        dispatchRecord?.diagnostics
                        ?? [
                            "No permissions.onAdded dispatch payload was available for downstream invalidation diagnostics.",
                        ]
                )
                appendPromptLifecycle(
                    promptRequest,
                    stage: .resultPersisted,
                    resultDisposition: .accepted,
                    diagnostics: application.diagnostics
                )
                persistPermissionState(diagnostics: application.diagnostics)
                let lifecycleResult =
                    application.result.eventPayloadIfAccepted.flatMap {
                        routeServiceWorkerLifecycleEvent(
                            source: .permissionsAdded,
                            payload: permissionsLifecyclePayload($0),
                            payloadSummary:
                                "popup/options permissions.onAdded",
                            sourceContext:
                                configuration.sourceContext.runtimeContext
                        )
                    }
                return response(
                    request: request,
                    succeeded: true,
                    payload: .bool(application.returnedBoolean),
                    permissionEventPayload:
                        application.result.eventPayloadIfAccepted,
                    serviceWorkerLifecycleWakeResult: lifecycleResult,
                    diagnostics:
                        application.diagnostics
                            + promptResultRecord.diagnostics
                            + (dispatchRecord?.diagnostics ?? [])
                            + (lifecycleResult?.diagnostics ?? [])
                            + [
                                "permissions.request used an explicit developer-preview product prompt result.",
                            ]
                )
            case .denied:
                let application = permissionRuntimeOwner.request(
                    input: input,
                    modeledPromptResult: .denied,
                    productPromptResult: promptResultRecord
                )
                appendPromptLifecycle(
                    promptRequest,
                    stage: .resultPersisted,
                    resultDisposition: .denied,
                    diagnostics: application.diagnostics
                )
                persistPermissionState(diagnostics: application.diagnostics)
                return response(
                    request: request,
                    succeeded: true,
                    payload: .bool(false),
                    permissionEventPayload: nil,
                    diagnostics:
                        application.diagnostics
                            + promptResultRecord.diagnostics
                            + [
                                "permissions.request was denied by explicit developer-preview product prompt result.",
                            ]
                )
            case .dismissed:
                let application = permissionRuntimeOwner.request(
                    input: input,
                    modeledPromptResult: .dismissed,
                    productPromptResult: promptResultRecord
                )
                appendPromptLifecycle(
                    promptRequest,
                    stage: .resultPersisted,
                    resultDisposition: .dismissed,
                    diagnostics: application.diagnostics
                )
                persistPermissionState(diagnostics: application.diagnostics)
                return response(
                    request: request,
                    succeeded: true,
                    payload: .bool(false),
                    permissionEventPayload: nil,
                    diagnostics:
                        application.diagnostics
                            + promptResultRecord.diagnostics
                            + [
                                "permissions.request was dismissed by explicit developer-preview product prompt result.",
                            ]
                )
            case .blocked, .unavailable:
                let application = permissionRuntimeOwner.request(input: input)
                let diagnostic = permissionRequestFailure(
                    result: application.result,
                    promptResult: .notProvided,
                    promptRequest: promptRequest,
                    promptResultRecord: promptResultRecord
                )
                appendPromptLifecycle(
                    promptRequest,
                    stage: .resultPersisted,
                    resultDisposition: promptResultRecord.disposition,
                    diagnostics: diagnostic.diagnostics
                )
                persistPermissionState(diagnostics: diagnostic.diagnostics)
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
            invalidateContentScriptEndpoints(
                reason:
                    "chrome.permissions.remove revoked host/API access for popup/options bridge."
            )
            if input.permissions.contains("nativeMessaging") {
                nativeMessagingRuntimeOwner?.tearDownForExtensionDisable()
                nativeMessagingRuntimeOwner = nil
                syntheticPortIDs.removeAll()
            }
            let dispatchRecord = dispatchPermissionEventIfNeeded(
                application.result.eventPayloadIfApplied,
                sourceSurfaceID: configuration.surfaceID
            )
            persistPermissionState(diagnostics: application.diagnostics)
            let lifecycleResult =
                application.result.eventPayloadIfApplied.flatMap {
                    routeServiceWorkerLifecycleEvent(
                        source: .permissionsRemoved,
                        payload: permissionsLifecyclePayload($0),
                        payloadSummary: "popup/options permissions.onRemoved",
                        sourceContext: configuration.sourceContext.runtimeContext
                    )
                }
            return response(
                request: request,
                succeeded: true,
                payload: .bool(true),
                permissionEventPayload:
                    application.result.eventPayloadIfApplied,
                serviceWorkerLifecycleWakeResult: lifecycleResult,
                diagnostics:
                    application.diagnostics
                    + (dispatchRecord?.diagnostics ?? [])
                    + (lifecycleResult?.diagnostics ?? [])
            )
        }
    }

    private func permissionsEventListenerCountChanged(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        guard request.arguments.count == 2,
              let eventName = request.arguments[0].stringValue,
              let listenerCount = request.arguments[1].intValue
        else {
            return invalidArguments(
                request,
                "permissions event listener count updates require eventName and listenerCount."
            )
        }
        let eventKind: ChromeMV3PermissionsAPIEventKind?
        switch eventName {
        case "onAdded":
            eventKind = .onAdded
        case "onRemoved":
            eventKind = .onRemoved
        default:
            eventKind = nil
        }
        guard let eventKind else {
            return invalidArguments(
                request,
                "Unsupported permissions event listener name."
            )
        }
        permissionEventDispatcher?
            .updateChromeMV3PermissionEventListenerCount(
                surfaceID: configuration.surfaceID,
                profileID: configuration.profileID,
                extensionID: configuration.extensionID,
                surface: configuration.surface,
                eventKind: eventKind,
                listenerCount: listenerCount
            )
        return response(
            request: request,
            succeeded: true,
            payload: .object([
                "eventName": .string(eventName),
                "listenerCount": .number(Double(max(0, listenerCount))),
                "registeredOpenPage": .bool(permissionEventDispatcher != nil),
            ]),
            diagnostics: [
                "Popup/options page reported permissions.\(eventName) listener count.",
                "Listener tracking is used only for already-open page event dispatch.",
            ]
        )
    }

    private func tabsQuery(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest,
        sourceContextOverride: ChromeMV3JSBridgeSourceContext? = nil
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
        if let registry = contentScriptEndpointRegistry {
            let result = ChromeMV3ContentScriptTabsMessagingBridge.query(
                registry: registry,
                request:
                    ChromeMV3ContentScriptTabsQueryRequest(
                        extensionID: configuration.extensionID,
                        profileID: configuration.profileID,
                        sourceContext:
                            sourceContextOverride
                                ?? configuration.sourceContext,
                        queryInfo: queryInfo,
                        permissionBroker:
                            permissionRuntimeOwner.permissionBroker,
                        activeTabID: nil
                    )
            )
            return response(
                request: request,
                succeeded: true,
                payload: .array(result.tabs),
                sourceContext: sourceContextOverride,
                diagnostics:
                    result.diagnostics
                        + [
                            "tabs.query used the captured content-script endpoint registry for the active eligible tab only.",
                            "No broad product tab enumeration occurred.",
                        ]
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

    private func tabsSendMessage(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest,
        sourceContextOverride: ChromeMV3JSBridgeSourceContext? = nil
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        guard request.arguments.count >= 2 else {
            return invalidArguments(
                request,
                "tabs.sendMessage requires tabId and message arguments."
            )
        }
        guard request.arguments.count <= 3 else {
            return invalidArguments(
                request,
                "tabs.sendMessage accepts at most tabId, message, and options."
            )
        }
        guard let tabID = request.arguments[0].intValue else {
            return invalidArguments(
                request,
                "tabs.sendMessage tabId must be an integer."
            )
        }
        let options = request.arguments.count == 3
            ? request.arguments[2].objectValue
            : [:]
        if request.arguments.count == 3, options == nil {
            return invalidArguments(
                request,
                "tabs.sendMessage options must be an object."
            )
        }
        let frameID = options?["frameId"]?.intValue
        let documentID = options?["documentId"]?.stringValue
        guard let registry = contentScriptEndpointRegistry else {
            return runtimeLastErrorResponse(
                request,
                error: .noReceivingEnd,
                diagnostics: [
                    "No content-script endpoint registry is available for tabs.sendMessage target tab/frame/document.",
                    "Endpoint lookup classification: endpointMissing.",
                ]
            )
        }
        let result = ChromeMV3ContentScriptTabsMessagingBridge.sendMessage(
            registry: registry,
            request:
                ChromeMV3ContentScriptTabsSendMessageRequest(
                    extensionID: configuration.extensionID,
                    profileID: configuration.profileID,
                    sourceContext:
                        sourceContextOverride ?? configuration.sourceContext,
                    extensionBaseURLString:
                        configuration.extensionBaseURLString,
                    tabID: tabID,
                    frameID: frameID,
                    documentID: documentID,
                    message: request.arguments[1],
                    permissionBroker:
                        permissionRuntimeOwner.permissionBroker,
                    responseMode:
                        request.invocationMode == .callback
                            ? .callback
                            : .promise,
                    userGestureAvailable:
                        (sourceContextOverride ?? configuration.sourceContext)
                            == .actionPopup,
                    bridgeCallID: request.bridgeCallID
                )
        )
        if let error = result.selectedLastError {
            return runtimeLastErrorResponse(
                request,
                contract: error,
                diagnostics: result.diagnostics
            )
        }
        return response(
            request: request,
            succeeded: true,
            payload: result.responsePayload ?? .null,
            sourceContext: sourceContextOverride,
            diagnostics:
                result.diagnostics
                    + [
                        "tabs.sendMessage routed to a registered developer-preview content-script endpoint.",
                        "No arbitrary scripting.executeScript path was used.",
                    ]
        )
    }

    @MainActor
    private func tabsSendMessageAsync(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest,
        sourceContextOverride: ChromeMV3JSBridgeSourceContext? = nil
    ) async -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        guard request.arguments.count >= 2 else {
            return invalidArguments(
                request,
                "tabs.sendMessage requires tabId and message arguments."
            )
        }
        guard request.arguments.count <= 3 else {
            return invalidArguments(
                request,
                "tabs.sendMessage accepts at most tabId, message, and options."
            )
        }
        guard let tabID = request.arguments[0].intValue else {
            return invalidArguments(
                request,
                "tabs.sendMessage tabId must be an integer."
            )
        }
        let options = request.arguments.count == 3
            ? request.arguments[2].objectValue
            : [:]
        if request.arguments.count == 3, options == nil {
            return invalidArguments(
                request,
                "tabs.sendMessage options must be an object."
            )
        }
        let frameID = options?["frameId"]?.intValue
        let documentID = options?["documentId"]?.stringValue
        guard let registry = contentScriptEndpointRegistry else {
            return runtimeLastErrorResponse(
                request,
                error: .noReceivingEnd,
                diagnostics: [
                    "No content-script endpoint registry is available for tabs.sendMessage target tab/frame/document.",
                    "Endpoint lookup classification: endpointMissing.",
                ]
            )
        }
        let result = await ChromeMV3ContentScriptTabsMessagingBridge
            .sendMessageAsync(
                registry: registry,
                request:
                    ChromeMV3ContentScriptTabsSendMessageRequest(
                        extensionID: configuration.extensionID,
                        profileID: configuration.profileID,
                        sourceContext:
                            sourceContextOverride
                                ?? configuration.sourceContext,
                        extensionBaseURLString:
                            configuration.extensionBaseURLString,
                        tabID: tabID,
                        frameID: frameID,
                        documentID: documentID,
                        message: request.arguments[1],
                        permissionBroker:
                            permissionRuntimeOwner.permissionBroker,
                        responseMode:
                            request.invocationMode == .callback
                                ? .callback
                                : .promise,
                        userGestureAvailable:
                            (sourceContextOverride ?? configuration.sourceContext)
                                == .actionPopup,
                        bridgeCallID: request.bridgeCallID
                    )
            )
        if let error = result.selectedLastError {
            return runtimeLastErrorResponse(
                request,
                contract: error,
                diagnostics: result.diagnostics
            )
        }
        return response(
            request: request,
            succeeded: true,
            payload: result.responsePayload ?? .null,
            sourceContext: sourceContextOverride,
            diagnostics:
                result.diagnostics
                    + [
                        "tabs.sendMessage routed to a registered developer-preview content-script endpoint.",
                        "No arbitrary scripting.executeScript path was used.",
                    ]
        )
    }

    private func tabsConnect(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        guard request.arguments.count >= 1 else {
            return invalidArguments(
                request,
                "tabs.connect requires a tabId argument."
            )
        }
        guard request.arguments.count <= 2 else {
            return invalidArguments(
                request,
                "tabs.connect accepts at most tabId and connectInfo."
            )
        }
        guard let tabID = request.arguments[0].intValue else {
            return invalidArguments(
                request,
                "tabs.connect tabId must be an integer."
            )
        }
        let connectInfo = request.arguments.count == 2
            ? request.arguments[1].objectValue
            : [:]
        if request.arguments.count == 2, connectInfo == nil {
            return invalidArguments(
                request,
                "tabs.connect connectInfo must be an object."
            )
        }
        let frameID = connectInfo?["frameId"]?.intValue
        let documentID = connectInfo?["documentId"]?.stringValue
        let name = connectInfo?["name"]?.stringValue ?? ""
        if let permissionFailure = tabPermissionFailure(
            request: request,
            tabID: tabID,
            requestName: "tabs.connect"
        ) {
            return permissionFailure
        }
        guard let registry = contentScriptEndpointRegistry else {
            return runtimeLastErrorResponse(
                request,
                error: .noReceivingEnd,
                diagnostics: [
                    "No content-script endpoint registry is available for tabs.connect target tab/frame/document.",
                    "Endpoint lookup classification: endpointMissing.",
                ]
            )
        }
        let lookup = registry.targetEndpointLookup(
            extensionID: configuration.extensionID,
            profileID: configuration.profileID,
            tabID: tabID,
            frameID: frameID,
            documentID: documentID
        )
        guard let endpoint = lookup.endpoint else {
            return runtimeLastErrorResponse(
                request,
                error: .noReceivingEnd,
                diagnostics:
                    lookup.diagnostics
                    + [
                        "No content-script endpoint exists for tabs.connect target tab/frame/document."
                    ]
            )
        }
        let route = ChromeMV3RuntimeMessagingRoute.make(
            kind: .tabsConnect,
            extensionID: configuration.extensionID,
            profileID: configuration.profileID,
            tabID: endpoint.tabID,
            frameID: endpoint.frameID,
            documentID: endpoint.documentID,
            sourceURL: configuration.extensionBaseURLString,
            targetURL: endpoint.frameTarget.urlString
        )
        let permission = ChromeMV3RuntimeMessagingPermissionDecision.evaluate(
            route: route,
            permissionBroker: permissionRuntimeOwner.permissionBroker,
            userGestureAvailable:
                configuration.sourceContext == .actionPopup
        )
        guard permission.allowedForFutureDispatch else {
            return runtimeLastErrorResponse(
                request,
                error: runtimeError(permission),
                diagnostics:
                    permission.brokerDiagnostics
                        + [permission.diagnosticReason]
            )
        }
        guard let port = registry.openPortIfAvailable(
            extensionID: configuration.extensionID,
            profileID: configuration.profileID,
            tabID: endpoint.tabID,
            frameID: endpoint.frameID,
            documentID: endpoint.documentID,
            name: name
        ) else {
            return runtimeLastErrorResponse(
                request,
                error: .noReceivingEnd,
                diagnostics:
                    lookup.diagnostics
                    + [
                        "Target content-script endpoint is present but has no runtime.onConnect listener."
                    ]
            )
        }
        syntheticPortIDs.insert(port.portID)
        return response(
            request: request,
            succeeded: true,
            payload: .object([
                "portID": .string(port.portID),
                "portKind": .string("contentScriptEndpointPort"),
                "endpointID": .string(port.endpointID),
                "sender": senderPayload(port.sender),
                "canOpenRuntimePortNow": .bool(true),
                "canWakeServiceWorkerNow": .bool(false),
                "runtimeLoadable": .bool(false),
            ]),
            diagnostics:
                lookup.diagnostics
                    + port.diagnostics
                    + [
                        "tabs.connect created a modeled Port to a content-script endpoint.",
                        "No product service-worker wake or native host launch occurred.",
                    ]
        )
    }

    private func tabsPortPostMessage(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        guard request.arguments.count == 2 else {
            return invalidArguments(
                request,
                "tabs Port postMessage requires portID and message arguments."
            )
        }
        guard let portID = request.arguments[0].stringValue else {
            return invalidArguments(
                request,
                "tabs Port postMessage portID must be a string."
            )
        }
        guard let registry = contentScriptEndpointRegistry else {
            return runtimeLastErrorResponse(
                request,
                error: .noReceivingEnd,
                diagnostics: [
                    "No content-script endpoint registry is available for tabs Port delivery."
                ]
            )
        }
        let delivery = registry.deliverPopupOptionsPortMessage(
            portID: portID,
            payload: request.arguments[1]
        )
        guard delivery.delivered else {
            return runtimeLastErrorResponse(
                request,
                error: .noReceivingEnd,
                diagnostics: delivery.diagnostics
            )
        }
        return response(
            request: request,
            succeeded: true,
            payload: portDeliveryPayload(delivery),
            diagnostics:
                delivery.diagnostics
                    + [
                        "popup/options Port.postMessage reached the modeled content-script endpoint.",
                        "No service-worker keepalive was opened for Port delivery.",
                    ]
        )
    }

    private func tabsPortDisconnect(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        guard request.arguments.count == 1 else {
            return invalidArguments(
                request,
                "tabs Port disconnect requires one portID argument."
            )
        }
        guard let portID = request.arguments[0].stringValue else {
            return invalidArguments(
                request,
                "tabs Port disconnect portID must be a string."
            )
        }
        guard let registry = contentScriptEndpointRegistry else {
            return response(
                request: request,
                succeeded: true,
                payload: .object([
                    "portID": .string(portID),
                    "disconnected": .bool(false),
                    "disconnectReason": .string(
                        "No content-script endpoint registry is available."
                    ),
                ]),
                diagnostics: [
                    "tabs Port disconnect was a deterministic no-op because no endpoint registry is available."
                ]
            )
        }
        let delivery = registry.disconnectPort(
            portID: portID,
            reason: "Port.disconnect called by popup/options."
        )
        syntheticPortIDs.remove(portID)
        return response(
            request: request,
            succeeded: true,
            payload: portDeliveryPayload(delivery),
            diagnostics:
                delivery.diagnostics
                    + [
                        "popup/options Port.disconnect deterministically notified both modeled endpoints when present.",
                    ]
        )
    }

    private func portDeliveryPayload(
        _ delivery: ChromeMV3ContentScriptPortDeliveryResult
    ) -> ChromeMV3StorageValue {
        var object: [String: ChromeMV3StorageValue] = [
            "portID": .string(delivery.portID),
            "direction": .string(delivery.direction.rawValue),
            "delivered": .bool(delivery.delivered),
            "payload": delivery.payload ?? .null,
        ]
        if let endpointID = delivery.endpointID {
            object["endpointID"] = .string(endpointID)
        }
        if let reason = delivery.disconnectReason {
            object["disconnectReason"] = .string(reason)
        }
        return .object(object)
    }

    private func senderPayload(
        _ sender: ChromeMV3ContentScriptSenderMetadata
    ) -> ChromeMV3StorageValue {
        var object: [String: ChromeMV3StorageValue] = [
            "id": .string(sender.extensionID),
            "extensionID": .string(sender.extensionID),
            "profileID": .string(sender.profileID),
            "tabId": .number(Double(sender.tabID)),
            "frameId": .number(Double(sender.frameID)),
            "documentId": .string(sender.documentID),
            "navigationSequence": .number(Double(sender.navigationSequence)),
            "lifecycleSessionID": .string(sender.lifecycleSessionID),
            "endpointID": .string(sender.endpointID),
            "urlRedacted": .bool(sender.urlRedacted),
            "originRedacted": .bool(sender.originRedacted),
        ]
        if let parentFrameID = sender.parentFrameID {
            object["parentFrameId"] = .number(Double(parentFrameID))
        }
        if let url = sender.url {
            object["url"] = .string(url)
        }
        if let origin = sender.origin {
            object["origin"] = .string(origin)
        }
        if let redactionReason = sender.redactionReason {
            object["redactionReason"] = .string(redactionReason)
        }
        return .object(object)
    }

    private func invalidateContentScriptEndpoints(reason: String) {
        contentScriptEndpointRegistry?.invalidateForPermissionChange(
            extensionID: configuration.extensionID,
            profileID: configuration.profileID,
            permissionBroker: permissionRuntimeOwner.permissionBroker,
            reason: reason
        )
    }

    private func nativeMessagingOwner()
        -> ChromeMV3NativeMessagingRuntimeOwner
    {
        if let owner = nativeMessagingRuntimeOwner,
           owner.activePortCount > 0
        {
            return owner
        }
        let owner = ChromeMV3NativeMessagingRuntimeOwner(
            configuration: .internalFixture(
                extensionID: configuration.extensionID,
                profileID: configuration.profileID,
                fixtureHostRootPaths:
                    configuration.nativeMessagingFixtureHostRootPaths,
                moduleState: configuration.moduleState,
                explicitInternalNativeMessagingBridgeAllowed:
                    configuration.bridgeAvailable,
                permissionState: nativeMessagingPermissionState(),
                productPolicy: configuration.nativeMessagingProductPolicy,
                trustedHostApprovalRecords:
                    nativeMessagingTrustedHostRecords()
            )
        )
        nativeMessagingRuntimeOwner = owner
        return owner
    }

    private func nativeMessagingPermissionState()
        -> ChromeMV3NativeMessagingPermissionState
    {
        let decision = permissionRuntimeOwner.permissionBroker
            .apiPermissionDecision("nativeMessaging")
        if decision.hasPermission {
            return .grantedByManifest
        }
        if decision.unsupported {
            return .unsupported
        }
        if decision.deferred || decision.wouldNeedPrompt {
            return .deferred
        }
        if decision.denied || decision.revoked {
            return .denied
        }
        return .missing
    }

    private func nativeMessagingTrustedHostRecords()
        -> [ChromeMV3NativeTrustedHostApprovalRecord]
    {
        var records = configuration.nativeMessagingTrustedHostApprovalRecords
        if let rootPath = configuration.nativeMessagingTrustedHostPolicyRootPath,
           rootPath.isEmpty == false
        {
            let store = ChromeMV3NativeTrustedHostPolicyStore(
                rootURL: URL(fileURLWithPath: rootPath, isDirectory: true)
            )
            records.append(
                contentsOf:
                    store.loadSnapshot(
                        profileID: configuration.profileID,
                        extensionID: configuration.extensionID
                    )
                    .records
            )
        }
        return records.sorted {
            if $0.hostName != $1.hostName {
                return $0.hostName < $1.hostName
            }
            return $0.approvalSequence < $1.approvalSequence
        }
    }

    private func appendPromptLifecycle(
        _ request: ChromeMV3PermissionPromptRequest,
        stage: ChromeMV3PermissionPromptLifecycleStage,
        resultDisposition:
            ChromeMV3PermissionPromptResultDisposition? = nil,
        diagnostics: [String]
    ) {
        permissionPromptLifecycleRecords.append(
            ChromeMV3PermissionPromptLifecycleRecord(
                request: request,
                stage: stage,
                resultDisposition: resultDisposition,
                diagnostics: diagnostics
            )
        )
        permissionPromptLifecycleRecords.sort {
            if $0.sequence != $1.sequence {
                return $0.sequence < $1.sequence
            }
            if $0.requestID != $1.requestID {
                return $0.requestID < $1.requestID
            }
            return $0.stage < $1.stage
        }
    }

    private func lifecycleStage(
        for disposition: ChromeMV3PermissionPromptResultDisposition
    ) -> ChromeMV3PermissionPromptLifecycleStage {
        switch disposition {
        case .accepted:
            return .accepted
        case .denied:
            return .denied
        case .dismissed:
            return .dismissed
        case .blocked, .unavailable:
            return .blocked
        }
    }

    private func dispatchPermissionEventIfNeeded(
        _ payload: ChromeMV3PermissionsAPIEventPayload?,
        sourceSurfaceID: String?
    ) -> ChromeMV3PermissionEventDispatchRecord? {
        guard let payload else { return nil }
        guard let permissionEventDispatcher else {
            let registry = ChromeMV3PermissionEventDispatchRegistry()
            let record = registry.dispatchChromeMV3PermissionEvent(
                payload,
                sourceSurfaceID: sourceSurfaceID
            )
            permissionEventDispatches.append(record)
            return record
        }
        let record = permissionEventDispatcher
            .dispatchChromeMV3PermissionEvent(
                payload,
                sourceSurfaceID: sourceSurfaceID
            )
        permissionEventDispatches.append(record)
        return record
    }

    private func persistPermissionState(diagnostics: [String]) {
        guard let permissionStateStore else { return }
        do {
            _ = try permissionStateStore.save(
                owner: permissionRuntimeOwner,
                gateRecord: permissionPromptGate,
                promptRequests: permissionPromptRequests,
                promptResults: permissionPromptResults,
                promptLifecycleRecords: permissionPromptLifecycleRecords,
                diagnostics: diagnostics
            )
            permissionPersistenceDiagnostics =
                uniqueSortedPopupOptionsBridge(
                    permissionPersistenceDiagnostics
                        + [
                            "Persisted developer-preview permission state sidecar for popup/options bridge.",
                        ]
                )
        } catch {
            permissionPersistenceDiagnostics =
                uniqueSortedPopupOptionsBridge(
                    permissionPersistenceDiagnostics
                        + [
                            "Failed to persist developer-preview permission state: \(error.localizedDescription)",
                        ]
                )
        }
    }

    private func runtimeLastErrorResponse(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest,
        error: ChromeMV3RuntimeLastErrorCase,
        diagnostics: [String]
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        runtimeLastErrorResponse(
            request,
            contract:
                ChromeMV3RuntimeLastErrorContract.contract(for: error),
            diagnostics: diagnostics
        )
    }

    private func tabPermissionFailure(
        request: ChromeMV3RuntimeJSBridgeHostRequest,
        tabID: Int,
        requestName: String
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse? {
        guard let tab = tabRegistry.tab(id: tabID) else {
            return nil
        }
        let decision = permissionRuntimeOwner.permissionBroker
            .hostAccessDecision(url: tab.url, tabID: tab.id)
        guard decision.hasHostAccess == false else { return nil }
        let error: ChromeMV3RuntimeLastErrorCase
        if decision.missingReason == .permissionDenied
            || decision.missingReason == .permissionRevoked
        {
            error = .permissionDenied
        } else if decision.missingReason == .activeTabMissing
                    || permissionRuntimeOwner.permissionBroker
                    .activeTabPermissionDeclared
        {
            error = .activeTabMissing
        } else {
            error = .hostPermissionMissing
        }
        return runtimeLastErrorResponse(
            request,
            error: error,
            diagnostics:
                decision.diagnostics
                    + [
                        "\(requestName) target failed host/activeTab permission checks before endpoint lookup.",
                        "Permission denied and noReceivingEnd are kept distinct.",
                    ]
        )
    }

    private func runtimeLastErrorResponse(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest,
        contract: ChromeMV3RuntimeLastErrorContract,
        diagnostics: [String]
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        response(
            request: request,
            succeeded: false,
            lastErrorMessage: contract.futureLastErrorMessage,
            lastErrorCode: contract.error.rawValue,
            diagnostics: diagnostics + contract.diagnostics
        )
    }

    private func runtimeError(
        _ permission: ChromeMV3RuntimeMessagingPermissionDecision
    ) -> ChromeMV3RuntimeLastErrorCase {
        switch permission.missingGrantReason {
        case .missingActiveTabGrant, .activeTabGrantExpired,
             .userGestureRequired:
            return .activeTabMissing
        case .missingHostPermission:
            return .hostPermissionMissing
        case .missingTabPermission, .permissionDenied:
            return .permissionDenied
        case .nativeMessagingBlocked:
            return .nativeMessagingBlocked
        case .none:
            return .permissionDenied
        }
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
        serviceWorkerLifecycleWakeResult:
            ChromeMV3ServiceWorkerInternalWakeResult? = nil,
        nativeHostLaunchAttempted: Bool = false,
        sourceContext: ChromeMV3JSBridgeSourceContext? = nil,
        diagnostics: [String]
    ) -> ChromeMV3PopupOptionsJSBridgeHostResponse {
        let resolvedNamespace = request?.namespace ?? namespace ?? "unsupported"
        let resolvedMethod = request?.methodName ?? methodName ?? "unknown"
        let mode = request?.invocationMode ?? .promise
        let serviceWorkerWakeAttempted =
            serviceWorkerLifecycleWakeResult != nil
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
            serviceWorkerWakeAttempted: serviceWorkerWakeAttempted,
            serviceWorkerLifecycleWakeResult:
                serviceWorkerLifecycleWakeResult,
            nativeHostLaunchAttempted: nativeHostLaunchAttempted,
            runtimeLoadable: false,
            diagnostics:
                uniqueSortedPopupOptionsBridge(
                    configuration.diagnostics
                        + diagnostics
                        + (serviceWorkerLifecycleWakeResult?.diagnostics ?? [])
                        + [
                            "Popup/options bridge handled the call inside an extension-owned WebKit host.",
                            bridgeAttemptDiagnostic(
                                serviceWorkerWakeAttempted:
                                    serviceWorkerWakeAttempted,
                                nativeHostLaunchAttempted:
                                    nativeHostLaunchAttempted
                            ),
                        ]
                )
        )
        callRecords.append(
            ChromeMV3PopupOptionsJSBridgeCallRecord(
                bridgeCallID: response.bridgeCallID,
                extensionID: configuration.extensionID,
                profileID: configuration.profileID,
                surface: configuration.surface,
                sourceContext: sourceContext ?? configuration.sourceContext,
                namespace: resolvedNamespace,
                methodName: resolvedMethod,
                invocationMode: mode,
                argumentShapeSummary:
                    argumentShapeSummary(for: request),
                succeeded: succeeded,
                lastErrorCode: response.lastErrorCode,
                lastErrorMessage: response.lastErrorMessage,
                serviceWorkerWakeAttempted: serviceWorkerWakeAttempted,
                serviceWorkerLifecycleWakeResult:
                    serviceWorkerLifecycleWakeResult,
                nativeHostLaunchAttempted: nativeHostLaunchAttempted,
                normalTabRuntimeBridgeAvailable: false,
                contentScriptAttachmentAvailableInProduct: false,
                diagnostics: response.diagnostics
            )
        )
        return response
    }

    private func argumentShapeSummary(
        for request: ChromeMV3RuntimeJSBridgeHostRequest?
    ) -> String {
        guard let arguments = request?.arguments else {
            return "arguments:none"
        }
        guard arguments.isEmpty == false else {
            return "arguments:0"
        }
        return arguments.enumerated().map { index, value in
            "arg\(index)=\(storageValueShape(value))"
        }.joined(separator: ";")
    }

    private func storageValueShape(_ value: ChromeMV3StorageValue) -> String {
        switch value {
        case .array(let values):
            return "array:length=\(values.count)"
        case .bool:
            return "bool"
        case .null:
            return "null"
        case .number:
            return "number"
        case .object(let object):
            return "object:keyCount=\(object.keys.count);keys=\(object.keys.sorted().joined(separator: ","))"
        case .string(let string):
            return "string:length=\(string.count)"
        }
    }

    private func bridgeAttemptDiagnostic(
        serviceWorkerWakeAttempted: Bool,
        nativeHostLaunchAttempted: Bool
    ) -> String {
        if serviceWorkerWakeAttempted && nativeHostLaunchAttempted {
            return "Local experimental service-worker routing and trusted native-host fixture launch were both attempted."
        }
        if serviceWorkerWakeAttempted {
            return "Local experimental service-worker routing was attempted; runtimeLoadable remains false."
        }
        if nativeHostLaunchAttempted {
            return "Native host launch was attempted only after trusted developer-preview preflight passed."
        }
        return "No normal-tab bridge, product content-script attachment, service-worker wake, native host launch, or runtimeLoadable change occurred."
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

    private func permissionRequestFailure(
        result: ChromeMV3PermissionsAPIRequestResult,
        promptResult: ChromeMV3ModeledPermissionPromptResult,
        promptRequest: ChromeMV3PermissionPromptRequest? = nil,
        promptResultRecord:
            ChromeMV3PermissionPromptResultRecord? = nil
    ) -> (code: String, message: String, diagnostics: [String]) {
        let classifications = result.itemDecisions.map(\.classification)
        let promptDiagnostics =
            (promptRequest?.diagnostics ?? [])
            + (promptResultRecord?.diagnostics ?? [])
        if promptResultRecord?.disposition == .unavailable
            || (result.wouldRequirePrompt
                && promptResult == .notProvided
                && promptResultRecord == nil)
        {
            return (
                ChromeMV3JSBridgeErrorCode.productUIUnavailable.rawValue,
                "Permission prompt required, but product permission UI is unavailable in popup/options developer preview.",
                uniqueSortedPopupOptionsBridge(
                    promptDiagnostics
                        + [
                            "Install a developer-preview permission prompt presenter before requesting optional permissions.",
                            "No permission was granted silently.",
                        ]
                )
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
        if promptResultRecord?.disposition == .blocked {
            return (
                ChromeMV3JSBridgeErrorCode.permissionDenied.rawValue,
                "Permission request was blocked by developer-preview permission prompt policy.",
                uniqueSortedPopupOptionsBridge(
                    promptDiagnostics
                        + ["Permission request was blocked before prompting."]
                )
            )
        }
        if result.wouldRequirePrompt && promptResult == .denied {
            return (
                ChromeMV3JSBridgeErrorCode.permissionDenied.rawValue,
                "Permission request was denied by the developer-preview prompt result.",
                ["Permission request denial was returned deterministically."]
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
            serviceWorkerWakeRequired: sharedLifecycleSession != nil,
            blockers:
                sharedLifecycleSession == nil
                    ? [
                        "Popup/options storage.onChanged dispatch is in-page only.",
                        "No service-worker wake is performed without a shared lifecycle session.",
                        "No product normal-tab listener is registered.",
                    ]
                    : [
                        "Popup/options storage.onChanged also routes to the local experimental service-worker lifecycle.",
                        "The default runtime remains off.",
                    ],
            serviceWorkerWakePreflight: nil
        )
    }

    private func storageOnChangedLifecyclePayload(
        _ payload: ChromeMV3StorageOnChangedEventPayload
    ) -> ChromeMV3StorageValue {
        var changes: [String: ChromeMV3StorageValue] = [:]
        for change in payload.changes {
            var object: [String: ChromeMV3StorageValue] = [:]
            if let oldValue = change.oldValue {
                object["oldValue"] = oldValue
            }
            if let newValue = change.newValue {
                object["newValue"] = newValue
            }
            changes[change.key] = .object(object)
        }
        return .object([
            "areaName": .string(payload.areaName),
            "changes": .object(changes),
            "changedKeys":
                .array(payload.changedKeys.map(ChromeMV3StorageValue.string)),
            "extensionID": .string(payload.extensionID),
            "profileID": .string(payload.profileID),
        ])
    }

    private func permissionsLifecyclePayload(
        _ payload: ChromeMV3PermissionsAPIEventPayload
    ) -> ChromeMV3StorageValue {
        .object([
            "eventKind": .string(payload.eventKind.rawValue),
            "source": .string(payload.source.rawValue),
            "extensionID": .string(payload.extensionID),
            "profileID": .string(payload.profileID),
            "permissions":
                .array(payload.permissions.map(ChromeMV3StorageValue.string)),
            "origins":
                .array(payload.origins.map(ChromeMV3StorageValue.string)),
        ])
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

          function dispatchDisconnect(state, port, message) {
            const previousLastError = lastErrorValue;
            lastErrorValue = message ? { message } : undefined;
            try {
              state.onDisconnect.dispatch(port);
            } finally {
              lastErrorValue = previousLastError;
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
            if (namespace === "runtime" && methodName === "sendNativeMessage") {
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

          function notifyPermissionListenerCount(eventName, count) {
            if (eventName !== "onAdded" && eventName !== "onRemoved") {
              return;
            }
            bridgePost(
              "permissions",
              "__sumiPermissionEventListenerCount",
              "fireAndForget",
              [eventName, count]
            ).catch(() => {});
          }

          function makeEvent(eventName) {
            const listeners = [];
            return Object.freeze({
              addListener(listener) {
                if (typeof listener === "function" && !listeners.includes(listener)) {
                  listeners.push(listener);
                  notifyPermissionListenerCount(eventName, listeners.length);
                }
              },
              removeListener(listener) {
                const index = listeners.indexOf(listener);
                if (index >= 0) {
                  listeners.splice(index, 1);
                  notifyPermissionListenerCount(eventName, listeners.length);
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

          const storageOnChanged = makeEvent("storage.onChanged");
          const permissionsOnAdded = makeEvent("onAdded");
          const permissionsOnRemoved = makeEvent("onRemoved");

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
            globalThis.__sumiDispatchChromeMV3PermissionEvent(payload);
          }

          Object.defineProperty(globalThis, "__sumiDispatchChromeMV3PermissionEvent", {
            value(rawPayload) {
              const payload = normalizePermissionEvent(rawPayload);
              if (!payload) {
                return { dispatched: false, listenerCount: 0, eventKind: "" };
              }
              const target = payload.eventKind === "onAdded"
                ? permissionsOnAdded
                : (payload.eventKind === "onRemoved" ? permissionsOnRemoved : null);
              if (!target) {
                return { dispatched: false, listenerCount: 0, eventKind: payload.eventKind };
              }
              const listenerCount = target.hasListeners() ? 1 : 0;
              if (!target.hasListeners()) {
                return { dispatched: false, listenerCount: 0, eventKind: payload.eventKind };
              }
              target.__sumiDispatch({
                permissions: payload.permissions,
                origins: payload.origins
              });
              return {
                dispatched: true,
                listenerCount,
                eventKind: payload.eventKind
              };
            },
            configurable: false
          });

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

          function createPort(name, delivery) {
            const port = {};
            const state = {
              id: null,
              disconnected: false,
              delivery: delivery || null,
              sender: null,
              pendingMessages: [],
              deliveredMessageCount: 0,
              onMessage: makePortEvent(),
              onDisconnect: makePortEvent()
            };
            function markDisconnected(message) {
              if (state.disconnected) {
                return;
              }
              state.disconnected = true;
              state.pendingMessages = [];
              dispatchDisconnect(state, port, message || null);
            }
            function dispatchPostedMessages(payload) {
              const messages = payload && Array.isArray(payload.postedMessages)
                ? payload.postedMessages
                : [];
              const nextMessages = messages.slice(state.deliveredMessageCount);
              state.deliveredMessageCount = messages.length;
              nextMessages.forEach((postedMessage) => {
                state.onMessage.dispatch(postedMessage, port);
              });
              if (payload && payload.connected === false) {
                markDisconnected(null);
              }
            }
            function sendNativePortMessage(message) {
              if (!state.delivery || !state.delivery.namespace || !state.delivery.postMessage) {
                state.onMessage.dispatch(message, port);
                return;
              }
              if (!state.id) {
                state.pendingMessages.push(message);
                return;
              }
              bridgePost(
                state.delivery.namespace,
                state.delivery.postMessage,
                "fireAndForget",
                [state.id, message]
              ).then((response) => {
                if (!response.succeeded) {
                  markDisconnected(response.lastErrorMessage);
                  return;
                }
                dispatchPostedMessages(response.resultPayload || {});
              }).catch(() => markDisconnected("Native messaging port is closed."));
            }
            function flushPendingMessages() {
              if (!state.id || state.disconnected || state.pendingMessages.length === 0) {
                return;
              }
              const messages = state.pendingMessages.splice(0, state.pendingMessages.length);
              messages.forEach(sendNativePortMessage);
            }
            Object.defineProperty(port, "name", {
              value: name || "",
              enumerable: true
            });
            Object.defineProperty(port, "sender", {
              get() {
                return state.sender || undefined;
              },
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
                sendNativePortMessage(toJSONCompatible(message));
              },
              enumerable: true
            });
            Object.defineProperty(port, "disconnect", {
              value() {
                if (state.disconnected) {
                  return;
                }
                if (state.delivery && state.delivery.namespace && state.delivery.disconnect && state.id) {
                  bridgePost(
                    state.delivery.namespace,
                    state.delivery.disconnect,
                    "fireAndForget",
                    [state.id]
                  );
                }
                markDisconnected();
              },
              enumerable: true
            });
            portState.set(port, state);
            state.flushPendingMessages = flushPendingMessages;
            state.markDisconnected = markDisconnected;
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
              const port = createPort(parseConnectName(args), {
                namespace: "runtime",
                postMessage: "port.postMessage",
                disconnect: "port.disconnect"
              });
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
                    state.markDisconnected(response.lastErrorMessage);
                    return;
                  }
                  const payload = response.resultPayload || {};
                  state.id = payload.portID || state.id;
                  state.sender = payload.sender || null;
                  state.flushPendingMessages();
                })
                .catch(() => state.markDisconnected(null));
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
              const port = createPort("", {
                namespace: "runtime",
                postMessage: "nativePort.postMessage",
                disconnect: "nativePort.disconnect"
              });
              const state = portState.get(port);
              bridgePost("runtime", nativeConnectMethod, "fireAndForget", [application])
                .then((response) => {
                  if (!response.succeeded) {
                    state.markDisconnected(response.lastErrorMessage);
                    return;
                  }
                  const payload = response.resultPayload || {};
                  state.id = payload.portID || state.id;
                  state.flushPendingMessages();
                })
                .catch(() => state.markDisconnected("Native messaging port is closed."));
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
              const port = createPort(connectInfo && connectInfo.name, {
                namespace: "tabs",
                postMessage: "port.postMessage",
                disconnect: "port.disconnect"
              });
              const state = portState.get(port);
              bridgePost("tabs", "connect", "fireAndForget", [tabId, connectInfo || {}])
                .then((response) => {
                  if (!response.succeeded) {
                    state.markDisconnected();
                    return;
                  }
                  const payload = response.resultPayload || {};
                  state.id = payload.portID || state.id;
                  state.sender = payload.sender || null;
                  state.flushPendingMessages();
                })
                .catch(state.markDisconnected);
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
        let response = await handler.handleAsync(message.body)
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

private func uniquePermissionEventDispatches(
    _ records: [ChromeMV3PermissionEventDispatchRecord]
) -> [ChromeMV3PermissionEventDispatchRecord] {
    var seen: Set<String> = []
    var unique: [ChromeMV3PermissionEventDispatchRecord] = []
    for record in records.sorted(by: {
        if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
        return $0.id < $1.id
    }) {
        if seen.insert(record.id).inserted {
            unique.append(record)
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

    var intValue: Int? {
        guard case .number(let value) = self,
              value.isFinite,
              value.rounded() == value,
              value >= Double(Int.min),
              value <= Double(Int.max)
        else { return nil }
        return Int(value)
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
