//
//  ChromeMV3RuntimeJSMessagingMVP.swift
//  Sumi
//
//  DEBUG/internal runtime-only chrome.runtime JavaScript bridge MVP for
//  controlled synthetic extension surfaces. This is not product Chrome MV3
//  runtime support, not normal-tab content-script support, not product native
//  messaging, and not a service-worker lifecycle implementation.
//

import CryptoKit
import Foundation

enum ChromeMV3RuntimeJSBridgeEventName:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case onConnect
    case onMessage

    static func < (
        lhs: ChromeMV3RuntimeJSBridgeEventName,
        rhs: ChromeMV3RuntimeJSBridgeEventName
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var surfaceKind: ChromeMV3RuntimeListenerSurfaceKind {
        switch self {
        case .onMessage:
            return .runtimeOnMessageServiceWorker
        case .onConnect:
            return .runtimeOnConnectServiceWorker
        }
    }
}

enum ChromeMV3RuntimeJSBridgeSurfaceKind:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case actionPopup
    case approvedTestSurface
    case extensionPageFixture
    case optionsPage
    case optionsUI

    static func < (
        lhs: ChromeMV3RuntimeJSBridgeSurfaceKind,
        rhs: ChromeMV3RuntimeJSBridgeSurfaceKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var sourceContext: ChromeMV3JSBridgeSourceContext {
        switch self {
        case .actionPopup:
            return .actionPopup
        case .optionsPage, .optionsUI:
            return .optionsPage
        case .extensionPageFixture, .approvedTestSurface:
            return .extensionPage
        }
    }
}

struct ChromeMV3RuntimeJSBridgeConfiguration:
    Codable,
    Equatable,
    Sendable
{
    var extensionID: String
    var profileID: String
    var surfaceID: String
    var surfaceKind: ChromeMV3RuntimeJSBridgeSurfaceKind
    var extensionBaseURLString: String?
    var moduleState: ChromeMV3ProfileHostModuleState
    var explicitInternalRuntimeJSBridgeAllowed: Bool
    var runtimeJSBridgeAvailableInSyntheticHarness: Bool
    var runtimeJSBridgeAvailableInProduct: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var serviceWorkerWakeAvailable: Bool
    var nativeMessagingAvailable: Bool
    var nativeMessagingAvailableInInternalFixture: Bool
    var nativeMessagingAvailableInProduct: Bool
    var explicitInternalNativeMessagingBridgeAllowed: Bool
    var nativeMessagingFixtureHostRootPaths: [String]
    var nativeMessagingPermissionState:
        ChromeMV3NativeMessagingPermissionState
    var runtimeLoadable: Bool
    var diagnostics: [String]

    var sourceContext: ChromeMV3JSBridgeSourceContext {
        surfaceKind.sourceContext
    }

    static func syntheticHarness(
        extensionID: String = "runtime-js-mvp-extension",
        profileID: String = "runtime-js-mvp-profile",
        surfaceID: String = "runtime-js-mvp-synthetic-surface",
        surfaceKind: ChromeMV3RuntimeJSBridgeSurfaceKind =
            .extensionPageFixture,
        extensionBaseURLString: String? =
            "chrome-extension://runtime-js-mvp-extension/",
        moduleState: ChromeMV3ProfileHostModuleState = .enabled,
        explicitInternalRuntimeJSBridgeAllowed: Bool = true,
        explicitInternalNativeMessagingBridgeAllowed: Bool = false,
        nativeMessagingFixtureHostRootPaths: [String] = [],
        nativeMessagingPermissionState:
            ChromeMV3NativeMessagingPermissionState = .missing
    ) -> ChromeMV3RuntimeJSBridgeConfiguration {
        let normalizedExtensionID = normalized(
            extensionID,
            fallback: "runtime-js-mvp-extension"
        )
        let normalizedProfileID = normalized(
            profileID,
            fallback: "runtime-js-mvp-profile"
        )
        let allowed = explicitInternalRuntimeJSBridgeAllowed
            && moduleState == .enabled
        let normalizedFixtureRoots =
            nativeMessagingFixtureHostRootPaths.map {
                URL(fileURLWithPath: $0, isDirectory: true)
                    .standardizedFileURL
                    .path
            }.sorted()
        let internalNativeMessagingAllowed =
            allowed
                && explicitInternalNativeMessagingBridgeAllowed
                && normalizedFixtureRoots.isEmpty == false
        return ChromeMV3RuntimeJSBridgeConfiguration(
            extensionID: normalizedExtensionID,
            profileID: normalizedProfileID,
            surfaceID: normalized(surfaceID, fallback: "synthetic-surface"),
            surfaceKind: surfaceKind,
            extensionBaseURLString: extensionBaseURLString,
            moduleState: moduleState,
            explicitInternalRuntimeJSBridgeAllowed:
                explicitInternalRuntimeJSBridgeAllowed,
            runtimeJSBridgeAvailableInSyntheticHarness: allowed,
            runtimeJSBridgeAvailableInProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            serviceWorkerWakeAvailable: false,
            nativeMessagingAvailable: false,
            nativeMessagingAvailableInInternalFixture:
                internalNativeMessagingAllowed,
            nativeMessagingAvailableInProduct: false,
            explicitInternalNativeMessagingBridgeAllowed:
                explicitInternalNativeMessagingBridgeAllowed,
            nativeMessagingFixtureHostRootPaths: normalizedFixtureRoots,
            nativeMessagingPermissionState: nativeMessagingPermissionState,
            runtimeLoadable: false,
            diagnostics:
                uniqueSorted([
                    "Runtime-only JS bridge is confined to a DEBUG/internal synthetic surface.",
                    "Product runtime exposure remains unavailable.",
                    "Normal-tab runtime bridge remains unavailable.",
                    internalNativeMessagingAllowed
                        ? "Internal fixture native messaging is available only for explicit fixture roots."
                        : "Service-worker wake and native messaging remain unavailable.",
                    "Product native messaging remains unavailable.",
                    "runtimeLoadable remains false.",
                ])
        )
    }
}

struct ChromeMV3RuntimeJSSyntheticListenerRegistration:
    Codable,
    Equatable,
    Sendable
{
    var listenerID: String
    var eventName: ChromeMV3RuntimeJSBridgeEventName
    var extensionID: String
    var profileID: String
    var surfaceID: String
    var registeredSequence: Int
    var diagnostics: [String]
}

struct ChromeMV3RuntimeJSSyntheticListenerRegistrySummary:
    Codable,
    Equatable,
    Sendable
{
    var surfaceID: String
    var extensionID: String
    var profileID: String
    var onMessageListenerCount: Int
    var onConnectListenerCount: Int
    var registeredListenerIDs: [String]
    var modelEndpointCount: Int
    var listenerRegistryScopedToSyntheticSurface: Bool
    var persistsBeyondSyntheticHostLifecycle: Bool
    var serviceWorkerWakeAvailable: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var diagnostics: [String]
}

final class ChromeMV3RuntimeJSSyntheticListenerRegistry {
    private let configuration: ChromeMV3RuntimeJSBridgeConfiguration
    private var registrations:
        [ChromeMV3RuntimeJSBridgeEventName:
            [String: ChromeMV3RuntimeJSSyntheticListenerRegistration]]
    private var nextSequence = 0

    init(configuration: ChromeMV3RuntimeJSBridgeConfiguration) {
        self.configuration = configuration
        self.registrations = [:]
    }

    func register(
        eventName: ChromeMV3RuntimeJSBridgeEventName,
        listenerID: String
    ) -> ChromeMV3RuntimeJSSyntheticListenerRegistration {
        nextSequence += 1
        let normalizedListenerID = normalized(
            listenerID,
            fallback:
                stableID(
                    prefix: "runtime-js-listener",
                    parts: [
                        configuration.surfaceID,
                        eventName.rawValue,
                        String(nextSequence),
                    ]
                )
        )
        let registration = ChromeMV3RuntimeJSSyntheticListenerRegistration(
            listenerID: normalizedListenerID,
            eventName: eventName,
            extensionID: configuration.extensionID,
            profileID: configuration.profileID,
            surfaceID: configuration.surfaceID,
            registeredSequence: nextSequence,
            diagnostics: [
                "Listener registration is scoped to the synthetic runtime JS bridge surface.",
                "No product normal-tab listener is registered.",
                "No service worker is woken.",
            ]
        )
        registrations[eventName, default: [:]][normalizedListenerID] =
            registration
        return registration
    }

    @discardableResult
    func remove(
        eventName: ChromeMV3RuntimeJSBridgeEventName,
        listenerID: String
    ) -> Bool {
        registrations[eventName]?.removeValue(forKey: listenerID) != nil
    }

    func has(
        eventName: ChromeMV3RuntimeJSBridgeEventName,
        listenerID: String
    ) -> Bool {
        registrations[eventName]?[listenerID] != nil
    }

    func listenerCount(
        for eventName: ChromeMV3RuntimeJSBridgeEventName
    ) -> Int {
        registrations[eventName]?.count ?? 0
    }

    func tearDown() {
        registrations.removeAll()
        nextSequence = 0
    }

    var summary: ChromeMV3RuntimeJSSyntheticListenerRegistrySummary {
        let allRegistrations = registrations.values.flatMap(\.values)
            .sorted {
                if $0.eventName != $1.eventName {
                    return $0.eventName < $1.eventName
                }
                return $0.listenerID < $1.listenerID
            }
        return ChromeMV3RuntimeJSSyntheticListenerRegistrySummary(
            surfaceID: configuration.surfaceID,
            extensionID: configuration.extensionID,
            profileID: configuration.profileID,
            onMessageListenerCount: listenerCount(for: .onMessage),
            onConnectListenerCount: listenerCount(for: .onConnect),
            registeredListenerIDs:
                allRegistrations.map(\.listenerID).uniqueSorted(),
            modelEndpointCount: modelSnapshot().endpoints.count,
            listenerRegistryScopedToSyntheticSurface: true,
            persistsBeyondSyntheticHostLifecycle: false,
            serviceWorkerWakeAvailable: false,
            normalTabRuntimeBridgeAvailable: false,
            diagnostics:
                uniqueSorted(
                    allRegistrations.flatMap(\.diagnostics)
                        + [
                            "Synthetic listener registry is an instance owned by one bridge handler.",
                            "Teardown clears registered listener identifiers.",
                        ]
                )
        )
    }

    func modelSnapshot()
        -> ChromeMV3RuntimeModelListenerRegistrySnapshot
    {
        var endpoints: [ChromeMV3RuntimeModelListenerEndpoint] = []
        if listenerCount(for: .onMessage) > 0 {
            endpoints.append(
                modelEndpoint(
                    eventName: .onMessage,
                    handlerOutcome:
                        .response(
                            .object([
                                "ok": .bool(true),
                                "target": .string(
                                    "runtimeJSSyntheticOnMessageModel"
                                ),
                                "listenerCount": .number(
                                    Double(listenerCount(for: .onMessage))
                                ),
                            ]),
                            diagnostics: [
                                "Synthetic JS onMessage listener registration is represented as a deterministic model receiver.",
                            ]
                        )
                )
            )
        }
        if listenerCount(for: .onConnect) > 0 {
            endpoints.append(
                modelEndpoint(
                    eventName: .onConnect,
                    handlerOutcome: nil
                )
            )
        }
        return ChromeMV3RuntimeModelListenerRegistrySnapshot.make(
            extensionID: configuration.extensionID,
            profileID: configuration.profileID,
            endpoints: endpoints,
            diagnostics: [
                "Runtime JS synthetic listener snapshot is bridge-local.",
                "No global app-wide runtime state is used.",
            ]
        )
    }

    private func modelEndpoint(
        eventName: ChromeMV3RuntimeJSBridgeEventName,
        handlerOutcome: ChromeMV3RuntimeModelHandlerOutcome?
    ) -> ChromeMV3RuntimeModelListenerEndpoint {
        let surface = ChromeMV3RuntimeListenerSurface.make(
            surface: eventName.surfaceKind,
            extensionID: configuration.extensionID,
            profileID: configuration.profileID
        )
        return ChromeMV3RuntimeModelListenerEndpoint.make(
            surface: surface,
            endpointKind: .serviceWorkerModel,
            canReceiveModelMessages: true,
            bypassesServiceWorkerWakeForModelOnlyDispatch: true,
            handlerOutcome: handlerOutcome,
            seed:
                "runtime-js-\(configuration.surfaceID)-\(eventName.rawValue)",
            diagnostics: [
                "Endpoint exists only so the existing Swift dispatcher can evaluate a synthetic JS-facing runtime route.",
                "The bridge does not create, load, or wake a real service worker.",
            ]
        )
    }
}

struct ChromeMV3RuntimeJSBridgeHostRequest:
    Codable,
    Equatable,
    Sendable
{
    var bridgeCallID: String
    var namespace: String
    var methodName: String
    var invocationMode: ChromeMV3JSBridgeInvocationMode
    var arguments: [ChromeMV3StorageValue]
    var listenerID: String?
    var eventName: ChromeMV3RuntimeJSBridgeEventName?
    var portID: String?
    var diagnostics: [String]

    static func parse(_ body: Any) -> Result<
        ChromeMV3RuntimeJSBridgeHostRequest,
        ChromeMV3RuntimeJSBridgeHostRequestParseError
    > {
        guard let object = body as? [String: Any] else {
            return .failure(
                ChromeMV3RuntimeJSBridgeHostRequestParseError(
                    message:
                        "Runtime JS bridge request body must be an object."
                )
            )
        }
        guard let methodName = string(object["methodName"]),
              methodName.isEmpty == false
        else {
            return .failure(
                ChromeMV3RuntimeJSBridgeHostRequestParseError(
                    message:
                        "Runtime JS bridge request methodName is missing."
                )
            )
        }
        let namespace = string(object["namespace"]) ?? "runtime"
        let mode = ChromeMV3JSBridgeInvocationMode(
            rawValue: string(object["invocationMode"]) ?? "promise"
        ) ?? .promise
        let rawArguments = object["arguments"] as? [Any] ?? []
        var arguments: [ChromeMV3StorageValue] = []
        for rawArgument in rawArguments {
            guard let value = ChromeMV3StorageValue(runtimeJSBridgeValue: rawArgument)
            else {
                return .failure(
                    ChromeMV3RuntimeJSBridgeHostRequestParseError(
                        message:
                            "Runtime JS bridge arguments must be JSON-compatible."
                    )
                )
            }
            arguments.append(value)
        }
        let eventName = string(object["eventName"])
            .flatMap(ChromeMV3RuntimeJSBridgeEventName.init(rawValue:))
        let callID = string(object["bridgeCallID"]) ?? stableID(
            prefix: "runtime-js-bridge-call",
            parts: [
                namespace,
                methodName,
                mode.rawValue,
                arguments
                    .map { (try? $0.canonicalJSONString()) ?? "argument" }
                    .joined(separator: "|"),
            ]
        )
        return .success(
            ChromeMV3RuntimeJSBridgeHostRequest(
                bridgeCallID: callID,
                namespace: namespace,
                methodName: methodName,
                invocationMode: mode,
                arguments: arguments,
                listenerID: string(object["listenerID"]),
                eventName: eventName,
                portID: string(object["portID"]),
                diagnostics: [
                    "Runtime JS bridge request parsed from WebKit reply message body.",
                ]
            )
        )
    }

    private static func string(_ value: Any?) -> String? {
        value as? String
    }
}

struct ChromeMV3RuntimeJSBridgeHostRequestParseError:
    Error,
    Equatable,
    Sendable
{
    var message: String
}

struct ChromeMV3RuntimeJSBridgeHostResponse:
    Codable,
    Equatable,
    Sendable
{
    var bridgeCallID: String
    var namespace: String
    var methodName: String
    var succeeded: Bool
    var resultPayload: ChromeMV3StorageValue?
    var lastErrorMessage: String?
    var lastErrorCode: String?
    var callbackWouldSetLastError: Bool
    var promiseWouldReject: Bool
    var runtimeDispatcherResult:
        ChromeMV3RuntimeMessageDispatcherResult?
    var listenerRegistrySummary:
        ChromeMV3RuntimeJSSyntheticListenerRegistrySummary
    var runtimeJSBridgeAvailableInSyntheticHarness: Bool
    var runtimeJSBridgeAvailableInProduct: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var serviceWorkerWakeAvailable: Bool
    var nativeMessagingAvailable: Bool
    var nativeMessagingAvailableInInternalFixture: Bool
    var nativeMessagingAvailableInProduct: Bool
    var runtimeLoadable: Bool
    var diagnostics: [String]

    var foundationObject: [String: Any] {
        [
            "bridgeCallID": bridgeCallID,
            "namespace": namespace,
            "methodName": methodName,
            "succeeded": succeeded,
            "resultPayload":
                resultPayload?.runtimeJSBridgeFoundationObject
                ?? NSNull(),
            "lastErrorMessage": lastErrorMessage ?? NSNull(),
            "lastErrorCode": lastErrorCode ?? NSNull(),
            "callbackWouldSetLastError": callbackWouldSetLastError,
            "promiseWouldReject": promiseWouldReject,
            "listenerRegistrySummary":
                listenerRegistrySummary.foundationObject,
            "runtimeJSBridgeAvailableInSyntheticHarness":
                runtimeJSBridgeAvailableInSyntheticHarness,
            "runtimeJSBridgeAvailableInProduct":
                runtimeJSBridgeAvailableInProduct,
            "normalTabRuntimeBridgeAvailable":
                normalTabRuntimeBridgeAvailable,
            "serviceWorkerWakeAvailable": serviceWorkerWakeAvailable,
            "nativeMessagingAvailable": nativeMessagingAvailable,
            "nativeMessagingAvailableInInternalFixture":
                nativeMessagingAvailableInInternalFixture,
            "nativeMessagingAvailableInProduct":
                nativeMessagingAvailableInProduct,
            "runtimeLoadable": runtimeLoadable,
            "diagnostics": diagnostics,
        ]
    }
}

final class ChromeMV3RuntimeJSBridgeHandler {
    let configuration: ChromeMV3RuntimeJSBridgeConfiguration
    let listenerRegistry: ChromeMV3RuntimeJSSyntheticListenerRegistry
    private(set) var handledRequestCount = 0
    private(set) var sendMessageDispatchCount = 0
    private(set) var modelPortCreateCount = 0
    private(set) var modelPortDisconnectCount = 0
    private(set) var modelPortPostMessageCount = 0
    private(set) var nativeSendMessageCount = 0
    private(set) var nativePortCreateCount = 0
    private(set) var nativePortDisconnectCount = 0
    private(set) var nativePortPostMessageCount = 0
    private(set) var rejectedRequestCount = 0
    private let nativeMessagingRuntimeOwner:
        ChromeMV3NativeMessagingRuntimeOwner?

    init(configuration: ChromeMV3RuntimeJSBridgeConfiguration) {
        self.configuration = configuration
        self.listenerRegistry =
            ChromeMV3RuntimeJSSyntheticListenerRegistry(
                configuration: configuration
            )
        if configuration.nativeMessagingAvailableInInternalFixture {
            self.nativeMessagingRuntimeOwner =
                ChromeMV3NativeMessagingRuntimeOwner(
                    configuration: .internalFixture(
                        extensionID: configuration.extensionID,
                        profileID: configuration.profileID,
                        fixtureHostRootPaths:
                            configuration.nativeMessagingFixtureHostRootPaths,
                        moduleState: configuration.moduleState,
                        explicitInternalNativeMessagingBridgeAllowed:
                            configuration
                            .explicitInternalNativeMessagingBridgeAllowed,
                        permissionState:
                            configuration.nativeMessagingPermissionState
                    )
                )
        } else {
            self.nativeMessagingRuntimeOwner = nil
        }
    }

    func handle(_ body: Any) -> ChromeMV3RuntimeJSBridgeHostResponse {
        handledRequestCount += 1
        switch ChromeMV3RuntimeJSBridgeHostRequest.parse(body) {
        case .success(let request):
            return handle(request)
        case .failure(let error):
            rejectedRequestCount += 1
            return response(
                request: nil,
                methodName: "parse",
                succeeded: false,
                lastErrorMessage: error.message,
                lastErrorCode: ChromeMV3JSBridgeErrorCode.invalidArguments
                    .rawValue,
                diagnostics: [error.message]
            )
        }
    }

    func handle(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3RuntimeJSBridgeHostResponse {
        guard configuration.moduleState == .enabled,
              configuration.explicitInternalRuntimeJSBridgeAllowed
        else {
            rejectedRequestCount += 1
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage:
                    ChromeMV3JSBridgeErrorCode.extensionDisabled
                    .lastErrorMessage,
                lastErrorCode: ChromeMV3JSBridgeErrorCode.extensionDisabled
                    .rawValue,
                diagnostics: [
                    "Runtime JS bridge request blocked because the extensions module or explicit DEBUG/internal gate is disabled.",
                ]
            )
        }
        guard request.namespace == "runtime" else {
            rejectedRequestCount += 1
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage:
                    ChromeMV3JSBridgeErrorCode.namespaceUnsupported
                    .lastErrorMessage,
                lastErrorCode:
                    ChromeMV3JSBridgeErrorCode.namespaceUnsupported.rawValue,
                diagnostics: [
                    "Runtime JS MVP bridge accepts only the runtime namespace.",
                ]
            )
        }

        switch request.methodName {
        case "sendMessage":
            return routeRuntimeMethod(request)
        case "sendNativeMessage":
            return routeSendNativeMessage(request)
        case "connect":
            return routeConnect(request)
        case "connectNative":
            return routeConnectNative(request)
        case "onMessage.addListener":
            return registerListener(request, eventName: .onMessage)
        case "onMessage.removeListener":
            return removeListener(request, eventName: .onMessage)
        case "onMessage.hasListener":
            return hasListener(request, eventName: .onMessage)
        case "onConnect.addListener":
            return registerListener(request, eventName: .onConnect)
        case "onConnect.removeListener":
            return removeListener(request, eventName: .onConnect)
        case "onConnect.hasListener":
            return hasListener(request, eventName: .onConnect)
        case "Port.disconnect":
            modelPortDisconnectCount += 1
            return response(
                request: request,
                succeeded: true,
                payload: .object([
                    "portID": .string(request.portID ?? "unknown-port"),
                    "disconnectReason": .string("disconnectCalled"),
                    "runtimeLoadable": .bool(false),
                ]),
                diagnostics: [
                    "Model Port disconnect was recorded without opening a native or runtime Port.",
                ]
            )
        case "Port.postMessage":
            modelPortPostMessageCount += 1
            return response(
                request: request,
                succeeded: true,
                payload: .object([
                    "portID": .string(request.portID ?? "unknown-port"),
                    "postMessageDeliveredByNativeRuntime": .bool(false),
                    "messageExchangeMode": .string("syntheticPeerOnly"),
                ]),
                diagnostics: [
                    "Port.postMessage is model-only; native/runtime delivery is not available.",
                ]
            )
        case "NativePort.disconnect":
            nativePortDisconnectCount += 1
            return routeNativePortDisconnect(request)
        case "NativePort.postMessage":
            nativePortPostMessageCount += 1
            return routeNativePortPostMessage(request)
        default:
            rejectedRequestCount += 1
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage:
                    ChromeMV3JSBridgeErrorCode.methodUnsupported
                    .lastErrorMessage,
                lastErrorCode: ChromeMV3JSBridgeErrorCode.methodUnsupported
                    .rawValue,
                diagnostics: [
                    "Unsupported runtime JS MVP bridge method: \(request.methodName).",
                ]
            )
        }
    }

    func tearDown() {
        listenerRegistry.tearDown()
        _ = nativeMessagingRuntimeOwner?.tearDownForExtensionDisable()
    }

    private func routeRuntimeMethod(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3RuntimeJSBridgeHostResponse {
        sendMessageDispatchCount += 1
        let bridgeResponse = routeThroughJSBridgeContract(request)
        let runtimeResult =
            bridgeResponse.routeResult?.runtimeDispatcherResult
        if let lastError = preferredLastError(
            bridgeResponse: bridgeResponse
        ) {
            rejectedRequestCount += 1
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage: lastError.message,
                lastErrorCode: lastError.code,
                runtimeDispatcherResult: runtimeResult,
                diagnostics:
                    uniqueSorted(
                        bridgeResponse.diagnostics
                            + [
                                "sendMessage reached the Swift dispatcher and produced a deterministic runtime lastError.",
                            ]
                    )
            )
        }
        return response(
            request: request,
            succeeded: true,
            payload: bridgeResponse.resultPayload ?? .null,
            runtimeDispatcherResult: runtimeResult,
            diagnostics:
                uniqueSorted(
                    bridgeResponse.diagnostics
                        + [
                            "sendMessage reached the Swift dispatcher through the JS bridge contract.",
                        ]
                )
        )
    }

    private func routeConnect(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3RuntimeJSBridgeHostResponse {
        let bridgeResponse = routeThroughJSBridgeContract(request)
        let runtimeResult =
            bridgeResponse.routeResult?.runtimeDispatcherResult
        guard let preflight = runtimeResult?.modelPortPreflight else {
            let lastError = preferredLastError(bridgeResponse: bridgeResponse)
            rejectedRequestCount += 1
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage:
                    lastError?.message
                    ?? ChromeMV3JSBridgeErrorCode.invalidArguments
                    .lastErrorMessage,
                lastErrorCode:
                    lastError?.code
                    ?? ChromeMV3JSBridgeErrorCode.invalidArguments.rawValue,
                runtimeDispatcherResult: runtimeResult,
                diagnostics: bridgeResponse.diagnostics
            )
        }
        modelPortCreateCount += 1
        return response(
            request: request,
            succeeded: true,
            payload: .object([
                "portID": .string(preflight.portID),
                "portKind": .string(preflight.portKind.rawValue),
                "name": request.arguments.first?.objectValue?["name"]
                    ?? .string(""),
                "selectedDisconnectReason":
                    .string(preflight.selectedDisconnectReason.rawValue),
                "onConnectListenerCount":
                    .number(
                        Double(listenerRegistry.listenerCount(for: .onConnect))
                    ),
                "canOpenRuntimePortNow": .bool(false),
                "canOpenNativePortNow": .bool(false),
                "canWakeServiceWorkerNow": .bool(false),
                "runtimeLoadable": .bool(false),
            ]),
            runtimeDispatcherResult: runtimeResult,
            diagnostics:
                uniqueSorted(
                    bridgeResponse.diagnostics
                        + [
                            "connect reached the Swift dispatcher for model Port preflight.",
                            "The JS shim creates only a synthetic model Port object.",
                        ]
                )
        )
    }

    private func routeSendNativeMessage(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3RuntimeJSBridgeHostResponse {
        nativeSendMessageCount += 1
        guard let owner = nativeMessagingRuntimeOwner else {
            rejectedRequestCount += 1
            return nativeUnavailableResponse(request)
        }
        guard let hostName = request.arguments.first?.stringValue,
              let message = request.arguments.dropFirst().first
        else {
            rejectedRequestCount += 1
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage:
                    ChromeMV3NativeMessagingRuntimeErrorCode
                    .invalidArguments.lastErrorMessage,
                lastErrorCode:
                    ChromeMV3NativeMessagingRuntimeErrorCode
                    .invalidArguments.rawValue,
                diagnostics: [
                    "sendNativeMessage requires a host name and JSON-compatible message.",
                ]
            )
        }
        let result = owner.sendNativeMessage(
            hostName: hostName,
            message: message
        )
        if result.succeeded == false {
            rejectedRequestCount += 1
        }
        return response(
            request: request,
            succeeded: result.succeeded,
            payload: result.response,
            lastErrorMessage: result.lastErrorMessage,
            lastErrorCode: result.lastErrorCode?.rawValue,
            diagnostics:
                uniqueSorted(
                    result.diagnostics
                        + [
                            "sendNativeMessage executed only through the internal fixture native messaging owner.",
                        ]
                )
        )
    }

    private func routeConnectNative(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3RuntimeJSBridgeHostResponse {
        nativePortCreateCount += 1
        guard let owner = nativeMessagingRuntimeOwner else {
            rejectedRequestCount += 1
            return nativeUnavailableResponse(request)
        }
        guard let hostName = request.arguments.first?.stringValue else {
            rejectedRequestCount += 1
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage:
                    ChromeMV3NativeMessagingRuntimeErrorCode
                    .invalidArguments.lastErrorMessage,
                lastErrorCode:
                    ChromeMV3NativeMessagingRuntimeErrorCode
                    .invalidArguments.rawValue,
                diagnostics: [
                    "connectNative requires a native host name.",
                ]
            )
        }
        let result = owner.connectNative(hostName: hostName)
        if result.succeeded == false {
            rejectedRequestCount += 1
        }
        return response(
            request: request,
            succeeded: result.succeeded,
            payload: .object([
                "portID": .string(result.portID ?? ""),
                "hostName": .string(hostName),
                "processLaunchAllowedForFixtureHost":
                    .bool(
                        result.launchPolicy
                            .processLaunchAllowedForFixtureHost
                    ),
                "processLaunchAllowedInProduct": .bool(false),
                "nativeMessagingAvailableInProduct": .bool(false),
                "runtimeLoadable": .bool(false),
            ]),
            lastErrorMessage: result.lastErrorMessage,
            lastErrorCode: result.lastErrorCode?.rawValue,
            diagnostics:
                uniqueSorted(
                    result.diagnostics
                        + [
                            "connectNative opened only an internal fixture native Port.",
                            "No service-worker keepalive parity is claimed.",
                        ]
                )
        )
    }

    private func routeNativePortPostMessage(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3RuntimeJSBridgeHostResponse {
        guard let owner = nativeMessagingRuntimeOwner else {
            rejectedRequestCount += 1
            return nativeUnavailableResponse(request)
        }
        guard let portID = request.portID,
              let message = request.arguments.first
        else {
            rejectedRequestCount += 1
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage:
                    ChromeMV3NativeMessagingRuntimeErrorCode
                    .invalidArguments.lastErrorMessage,
                lastErrorCode:
                    ChromeMV3NativeMessagingRuntimeErrorCode
                    .invalidArguments.rawValue,
                diagnostics: [
                    "NativePort.postMessage requires a portID and message.",
                ]
            )
        }
        let result = owner.postMessage(portID: portID, message: message)
        if result.succeeded == false {
            rejectedRequestCount += 1
        }
        return response(
            request: request,
            succeeded: result.succeeded,
            payload: .object([
                "portID": .string(portID),
                "message": result.response ?? .null,
                "disconnectReason":
                    .string(
                        result.lifecycle.disconnectReason?.rawValue ?? ""
                    ),
                "runtimeLoadable": .bool(false),
            ]),
            lastErrorMessage: result.lastErrorMessage,
            lastErrorCode: result.lastErrorCode?.rawValue,
            diagnostics: result.diagnostics
        )
    }

    private func routeNativePortDisconnect(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3RuntimeJSBridgeHostResponse {
        guard let owner = nativeMessagingRuntimeOwner else {
            rejectedRequestCount += 1
            return nativeUnavailableResponse(request)
        }
        guard let portID = request.portID else {
            rejectedRequestCount += 1
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage:
                    ChromeMV3NativeMessagingRuntimeErrorCode
                    .invalidArguments.lastErrorMessage,
                lastErrorCode:
                    ChromeMV3NativeMessagingRuntimeErrorCode
                    .invalidArguments.rawValue,
                diagnostics: [
                    "NativePort.disconnect requires a portID.",
                ]
            )
        }
        let result = owner.disconnect(
            portID: portID,
            reason: .nativeHostExited
        )
        return response(
            request: request,
            succeeded: true,
            payload: .object([
                "portID": .string(portID),
                "disconnected": .bool(result.disconnected),
                "activePortCountAfterDisconnect":
                    .number(Double(result.activePortCountAfterDisconnect)),
                "runtimeLoadable": .bool(false),
            ]),
            diagnostics: result.diagnostics
        )
    }

    private func nativeUnavailableResponse(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3RuntimeJSBridgeHostResponse {
        response(
            request: request,
            succeeded: false,
            lastErrorMessage:
                ChromeMV3NativeMessagingRuntimeErrorCode
                .fixtureGateDisabled.lastErrorMessage,
            lastErrorCode:
                ChromeMV3NativeMessagingRuntimeErrorCode
                .fixtureGateDisabled.rawValue,
            diagnostics: [
                "Native messaging is available only in explicit DEBUG/internal fixture scope.",
                "Product native messaging remains unavailable.",
            ]
        )
    }

    private func registerListener(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest,
        eventName: ChromeMV3RuntimeJSBridgeEventName
    ) -> ChromeMV3RuntimeJSBridgeHostResponse {
        guard let listenerID = request.listenerID,
              listenerID.isEmpty == false
        else {
            rejectedRequestCount += 1
            return response(
                request: request,
                succeeded: false,
                lastErrorMessage:
                    ChromeMV3JSBridgeErrorCode.invalidArguments
                    .lastErrorMessage,
                lastErrorCode: ChromeMV3JSBridgeErrorCode.invalidArguments
                    .rawValue,
                diagnostics: [
                    "Listener registration requires a synthetic listenerID.",
                ]
            )
        }
        let registration = listenerRegistry.register(
            eventName: eventName,
            listenerID: listenerID
        )
        return response(
            request: request,
            succeeded: true,
            payload: .object([
                "listenerID": .string(registration.listenerID),
                "eventName": .string(eventName.rawValue),
                "listenerCount":
                    .number(Double(listenerRegistry.listenerCount(for: eventName))),
            ]),
            diagnostics: registration.diagnostics
        )
    }

    private func removeListener(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest,
        eventName: ChromeMV3RuntimeJSBridgeEventName
    ) -> ChromeMV3RuntimeJSBridgeHostResponse {
        let removed = request.listenerID.map {
            listenerRegistry.remove(eventName: eventName, listenerID: $0)
        } ?? false
        return response(
            request: request,
            succeeded: true,
            payload: .bool(removed),
            diagnostics: [
                "Synthetic \(eventName.rawValue) listener removal was evaluated.",
            ]
        )
    }

    private func hasListener(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest,
        eventName: ChromeMV3RuntimeJSBridgeEventName
    ) -> ChromeMV3RuntimeJSBridgeHostResponse {
        let present = request.listenerID.map {
            listenerRegistry.has(eventName: eventName, listenerID: $0)
        } ?? false
        return response(
            request: request,
            succeeded: true,
            payload: .bool(present),
            diagnostics: [
                "Synthetic \(eventName.rawValue) listener presence was evaluated.",
            ]
        )
    }

    private func routeThroughJSBridgeContract(
        _ request: ChromeMV3RuntimeJSBridgeHostRequest
    ) -> ChromeMV3JSBridgeResponseEnvelope {
        var environment =
            ChromeMV3JSBridgeContractEnvironment
            .passwordManagerModelFixture(
                extensionID: configuration.extensionID,
                profileID: configuration.profileID,
                moduleState: configuration.moduleState
            )
        environment.listenerRegistrySnapshot =
            listenerRegistry.modelSnapshot()
        environment.serviceWorkerLifecycleSnapshot = .blocked(
            extensionID: configuration.extensionID,
            profileID: configuration.profileID
        )
        let bridgeRequest = ChromeMV3JSBridgeRequestEnvelope(
            bridgeCallID: request.bridgeCallID,
            extensionID: configuration.extensionID,
            profileID: configuration.profileID,
            sourceContext: configuration.sourceContext,
            namespace: .runtime,
            methodName: request.methodName,
            rawArguments: request.arguments,
            invocationMode: request.invocationMode
        )
        return ChromeMV3JSBridgeContractRouter.route(
            bridgeRequest,
            environment: &environment
        )
    }

    private func preferredLastError(
        bridgeResponse: ChromeMV3JSBridgeResponseEnvelope
    ) -> (message: String, code: String)? {
        if let runtimeError = bridgeResponse.routeResult?
            .runtimeDispatcherResult?
            .selectedLastError
        {
            return (
                runtimeError.futureLastErrorMessage,
                runtimeError.error.rawValue
            )
        }
        if let bridgeError = bridgeResponse.lastErrorContract {
            return (
                bridgeError.futureLastErrorMessage,
                bridgeError.code.rawValue
            )
        }
        return nil
    }

    private func response(
        request: ChromeMV3RuntimeJSBridgeHostRequest?,
        methodName: String? = nil,
        succeeded: Bool,
        payload: ChromeMV3StorageValue? = nil,
        lastErrorMessage: String? = nil,
        lastErrorCode: String? = nil,
        runtimeDispatcherResult:
            ChromeMV3RuntimeMessageDispatcherResult? = nil,
        diagnostics: [String] = []
    ) -> ChromeMV3RuntimeJSBridgeHostResponse {
        let invocationMode = request?.invocationMode ?? .promise
        let callbackError =
            invocationMode == .callback && succeeded == false
        let promiseReject =
            invocationMode == .promise && succeeded == false
        return ChromeMV3RuntimeJSBridgeHostResponse(
            bridgeCallID: request?.bridgeCallID
                ?? stableID(prefix: "runtime-js-bridge-response", parts: [
                    methodName ?? "unknown",
                    succeeded.description,
                ]),
            namespace: request?.namespace ?? "runtime",
            methodName: request?.methodName ?? methodName ?? "unknown",
            succeeded: succeeded,
            resultPayload: payload,
            lastErrorMessage: lastErrorMessage,
            lastErrorCode: lastErrorCode,
            callbackWouldSetLastError: callbackError,
            promiseWouldReject: promiseReject,
            runtimeDispatcherResult: runtimeDispatcherResult,
            listenerRegistrySummary: listenerRegistry.summary,
            runtimeJSBridgeAvailableInSyntheticHarness:
                configuration.runtimeJSBridgeAvailableInSyntheticHarness,
            runtimeJSBridgeAvailableInProduct:
                configuration.runtimeJSBridgeAvailableInProduct,
            normalTabRuntimeBridgeAvailable:
                configuration.normalTabRuntimeBridgeAvailable,
            serviceWorkerWakeAvailable:
                configuration.serviceWorkerWakeAvailable,
            nativeMessagingAvailable:
                configuration.nativeMessagingAvailable,
            nativeMessagingAvailableInInternalFixture:
                configuration.nativeMessagingAvailableInInternalFixture,
            nativeMessagingAvailableInProduct:
                configuration.nativeMessagingAvailableInProduct,
            runtimeLoadable: false,
            diagnostics:
                uniqueSorted(
                    configuration.diagnostics
                        + diagnostics
                        + [
                            "Runtime JS bridge handler is runtime-only.",
                            "No tabs, storage, permissions, scripting, or nativeMessaging namespace is exposed by this runtime-only shim.",
                            "Product native messaging remains unavailable.",
                        ]
                )
        )
    }
}

struct ChromeMV3RuntimeJSShimCoverage:
    Codable,
    Equatable,
    Sendable
{
    var exposedChromeNamespaces: [String]
    var runtimeMethods: [String]
    var runtimeEvents: [String]
    var portMembers: [String]
    var callbackModeSupported: Bool
    var promiseModeSupported: Bool
    var lastErrorScopedToCallbackTurn: Bool
    var unsupportedChromeNamespaces: [String]
}

enum ChromeMV3RuntimeJSShimSource {
    static let bridgeMessageHandlerName = "sumiChromeMV3Runtime"

    static var coverage: ChromeMV3RuntimeJSShimCoverage {
        ChromeMV3RuntimeJSShimCoverage(
            exposedChromeNamespaces: ["runtime"],
            runtimeMethods: [
                "connect",
                "connectNative",
                "sendMessage",
                "sendNativeMessage",
            ],
            runtimeEvents: ["onConnect", "onMessage"],
            portMembers: [
                "disconnect",
                "name",
                "onDisconnect",
                "onMessage",
                "postMessage",
                "sender",
            ],
            callbackModeSupported: true,
            promiseModeSupported: true,
            lastErrorScopedToCallbackTurn: true,
            unsupportedChromeNamespaces: [
                "nativeMessaging",
                "permissions",
                "scripting",
                "storage",
                "tabs",
            ]
        )
    }

    static func source(
        configuration: ChromeMV3RuntimeJSBridgeConfiguration
    ) -> String {
        let configJSON = jsonString([
            "extensionID": configuration.extensionID,
            "profileID": configuration.profileID,
            "surfaceID": configuration.surfaceID,
            "sourceContext": configuration.sourceContext.rawValue,
            "extensionBaseURLString":
                configuration.extensionBaseURLString ?? "",
            "bridgeMessageHandlerName": bridgeMessageHandlerName,
        ])
        return """
        (() => {
          "use strict";
          const config = \(configJSON);
          const bridgeName = config.bridgeMessageHandlerName;
          const chromeObject = {};
          const runtime = {};
          let lastErrorValue;
          let nextListenerNumber = 0;
          let nextPortNumber = 0;
          let nextBridgeCallNumber = 0;
          let pendingRegistrations = [];
          const portState = new WeakMap();

          function bridgeUnavailableResponse(methodName) {
            return {
              bridgeCallID: "runtime-js-unavailable",
              namespace: "runtime",
              methodName,
              succeeded: false,
              resultPayload: null,
              lastErrorMessage: "Runtime JS bridge handler is unavailable.",
              lastErrorCode: "jsBridgeUnavailable",
              callbackWouldSetLastError: false,
              promiseWouldReject: false,
              diagnostics: ["Runtime JS bridge handler is unavailable."]
            };
          }

          function bridgePost(methodName, invocationMode, args, extra) {
            const handler = globalThis.webkit
              && globalThis.webkit.messageHandlers
              && globalThis.webkit.messageHandlers[bridgeName];
            if (!handler || typeof handler.postMessage !== "function") {
              return Promise.resolve(bridgeUnavailableResponse(methodName));
            }
            nextBridgeCallNumber += 1;
            const body = Object.assign({
              namespace: "runtime",
              methodName,
              invocationMode,
              extensionID: config.extensionID,
              profileID: config.profileID,
              sourceContext: config.sourceContext,
              surfaceID: config.surfaceID,
              bridgeCallID: [
                "runtime-js",
                config.surfaceID,
                methodName,
                String(nextBridgeCallNumber)
              ].join("-"),
              arguments: args || []
            }, extra || {});
            return handler.postMessage(body);
          }

          function toJSONCompatible(value) {
            if (value === undefined) {
              return null;
            }
            return JSON.parse(JSON.stringify(value));
          }

          function normalizeArguments(args) {
            return Array.prototype.slice.call(args).map(toJSONCompatible);
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
              new Error(response.lastErrorMessage || "Runtime JS bridge call failed.")
            );
          }

          function makeEvent(eventName) {
            const entries = [];
            const ids = new Map();
            function method(suffix) {
              return eventName + "." + suffix;
            }
            return Object.freeze({
              addListener(listener) {
                if (typeof listener !== "function") {
                  return;
                }
                if (ids.has(listener)) {
                  return;
                }
                nextListenerNumber += 1;
                const listenerID = [
                  config.surfaceID,
                  eventName,
                  String(nextListenerNumber)
                ].join(":");
                ids.set(listener, listenerID);
                entries.push({ listener, listenerID });
                pendingRegistrations.push(
                  bridgePost(method("addListener"), "fireAndForget", [], {
                    listenerID,
                    eventName
                  }).catch(() => undefined)
                );
              },
              removeListener(listener) {
                const listenerID = ids.get(listener);
                if (!listenerID) {
                  return;
                }
                ids.delete(listener);
                const index = entries.findIndex((entry) => entry.listener === listener);
                if (index >= 0) {
                  entries.splice(index, 1);
                }
                pendingRegistrations.push(
                  bridgePost(method("removeListener"), "fireAndForget", [], {
                    listenerID,
                    eventName
                  }).catch(() => undefined)
                );
              },
              hasListener(listener) {
                return ids.has(listener);
              },
              async dispatch() {
                const snapshot = entries.slice();
                for (const entry of snapshot) {
                  const result = await entry.listener.apply(
                    undefined,
                    Array.prototype.slice.call(arguments)
                  );
                  if (result !== undefined) {
                    return { didRespond: true, value: result };
                  }
                }
                return { didRespond: false, value: undefined };
              },
              snapshot() {
                return entries.slice();
              }
            });
          }

          const onMessageEvent = makeEvent("onMessage");
          const onConnectEvent = makeEvent("onConnect");

          async function flushRegistrations() {
            const pending = pendingRegistrations.splice(0);
            if (pending.length > 0) {
              await Promise.all(pending);
            }
          }

          async function dispatchOnMessage(message) {
            const sender = {
              id: config.extensionID,
              url: config.extensionBaseURLString || undefined
            };
            const listeners = onMessageEvent.snapshot();
            for (const entry of listeners) {
              let responded = false;
              let responseValue;
              const sendResponse = (value) => {
                if (!responded) {
                  responded = true;
                  responseValue = value === undefined ? null : value;
                }
              };
              const returned = entry.listener(message, sender, sendResponse);
              if (returned && typeof returned.then === "function") {
                const awaited = await returned;
                if (awaited !== undefined) {
                  return { didRespond: true, value: awaited };
                }
              } else if (returned !== undefined && returned !== true) {
                return { didRespond: true, value: returned };
              }
              if (responded) {
                return { didRespond: true, value: responseValue };
              }
            }
            return { didRespond: false, value: undefined };
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

          function createPort(name, sender, options) {
            const port = {};
            const nativePort = !!(options && options.nativePort);
            const state = {
              id: null,
              disconnected: false,
              peer: null,
              onMessage: makePortEvent(),
              onDisconnect: makePortEvent(),
              readyPromise: null
            };
            Object.defineProperty(port, "name", {
              value: name || "",
              enumerable: true
            });
            if (sender) {
              Object.defineProperty(port, "sender", {
                value: sender,
                enumerable: true
              });
            }
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
                const safeMessage = toJSONCompatible(message);
                const deliver = () => {
                  if (state.disconnected) {
                    return Promise.resolve({
                      succeeded: false,
                      lastErrorMessage: "Native messaging port is closed."
                    });
                  }
                  return bridgePost(
                    nativePort ? "NativePort.postMessage" : "Port.postMessage",
                    "fireAndForget",
                    [safeMessage],
                    {
                    portID: state.id
                    }
                  );
                };
                const delivery = nativePort && state.readyPromise
                  ? state.readyPromise.then(deliver)
                  : deliver();
                delivery.then((response) => {
                  if (nativePort && response && response.succeeded) {
                    const payload = response.resultPayload || {};
                    if (Object.prototype.hasOwnProperty.call(payload, "message")) {
                      state.onMessage.dispatch(payload.message, port);
                    }
                  } else if (nativePort && response && !response.succeeded) {
                    state.disconnected = true;
                    state.onDisconnect.dispatch(port);
                  }
                }).catch(() => {
                  if (nativePort) {
                    state.disconnected = true;
                    state.onDisconnect.dispatch(port);
                  }
                });
                if (state.peer && !state.peer.disconnected) {
                  state.peer.onMessage.dispatch(safeMessage, state.peer.port);
                }
              },
              enumerable: true
            });
            Object.defineProperty(port, "disconnect", {
              value() {
                if (state.disconnected) {
                  return;
                }
                state.disconnected = true;
                bridgePost(
                  nativePort ? "NativePort.disconnect" : "Port.disconnect",
                  "fireAndForget",
                  [],
                  {
                  portID: state.id
                  }
                ).catch(() => undefined);
                state.onDisconnect.dispatch(port);
                if (state.peer && !state.peer.disconnected) {
                  state.peer.disconnected = true;
                  state.peer.onDisconnect.dispatch(state.peer.port);
                }
              },
              enumerable: true
            });
            state.port = port;
            portState.set(port, state);
            return port;
          }

          function parseConnectArgs(rawArgs) {
            const args = Array.prototype.slice.call(rawArgs);
            let name = "";
            if (args.length === 1 && args[0] && typeof args[0] === "object") {
              name = typeof args[0].name === "string" ? args[0].name : "";
            }
            if (args.length === 2 && args[1] && typeof args[1] === "object") {
              name = typeof args[1].name === "string" ? args[1].name : "";
            }
            return { bridgeArgs: normalizeArguments(args), name };
          }

          Object.defineProperty(runtime, "lastError", {
            get() {
              return lastErrorValue;
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
              let bridgeArgs;
              try {
                bridgeArgs = rawArgs.map(toJSONCompatible);
              } catch (error) {
                const message = "Invalid Chrome MV3 JavaScript bridge arguments.";
                if (callback) {
                  invokeCallback(callback, message, []);
                  return undefined;
                }
                return Promise.reject(new Error(message));
              }
              const mode = callback ? "callback" : "promise";
              const promise = flushRegistrations()
                .then(() => bridgePost("sendMessage", mode, bridgeArgs))
                .then(async (response) => {
                  if (!response.succeeded) {
                    return response;
                  }
                  const local = await dispatchOnMessage(bridgeArgs[0]);
                  if (local.didRespond) {
                    response.resultPayload = toJSONCompatible(local.value);
                  }
                  return response;
                });
              if (callback) {
                promise.then((response) => {
                  if (response.succeeded) {
                    invokeCallback(callback, null, [response.resultPayload]);
                  } else {
                    invokeCallback(callback, response.lastErrorMessage, []);
                  }
                });
                return undefined;
              }
              return promise.then((response) => {
                if (response.succeeded) {
                  return response.resultPayload;
                }
                return rejectFromResponse(response);
              });
            },
            enumerable: true
          });

          Object.defineProperty(runtime, "sendNativeMessage", {
            value(application, message, callback) {
              const cb = typeof callback === "function" ? callback : null;
              let bridgeArgs;
              try {
                bridgeArgs = [application, message].map(toJSONCompatible);
              } catch (error) {
                const lastError = "Invalid Chrome MV3 JavaScript bridge arguments.";
                if (cb) {
                  invokeCallback(cb, lastError, []);
                  return undefined;
                }
                return Promise.reject(new Error(lastError));
              }
              const mode = cb ? "callback" : "promise";
              const promise = bridgePost("sendNativeMessage", mode, bridgeArgs);
              if (cb) {
                promise.then((response) => {
                  if (response.succeeded) {
                    invokeCallback(cb, null, [response.resultPayload]);
                  } else {
                    invokeCallback(cb, response.lastErrorMessage, []);
                  }
                });
                return undefined;
              }
              return promise.then((response) => {
                if (response.succeeded) {
                  return response.resultPayload;
                }
                return rejectFromResponse(response);
              });
            },
            enumerable: true
          });

          Object.defineProperty(runtime, "connect", {
            value() {
              const parsed = parseConnectArgs(arguments);
              const port = createPort(parsed.name, null);
              const senderState = portState.get(port);
              nextPortNumber += 1;
              senderState.id = [
                config.surfaceID,
                "pending-port",
                String(nextPortNumber)
              ].join(":");
              const connectPromise = flushRegistrations()
                .then(() => bridgePost("connect", "fireAndForget", parsed.bridgeArgs))
                .then((response) => {
                  if (!response.succeeded) {
                    senderState.disconnected = true;
                    senderState.onDisconnect.dispatch(port);
                    return;
                  }
                  const payload = response.resultPayload || {};
                  senderState.id = payload.portID || senderState.id;
                  const receiver = createPort(parsed.name, {
                    id: config.extensionID,
                    url: config.extensionBaseURLString || undefined
                  });
                  const receiverState = portState.get(receiver);
                  receiverState.id = senderState.id + ":receiver";
                  senderState.peer = receiverState;
                  receiverState.peer = senderState;
                  onConnectEvent.snapshot().forEach((entry) => {
                    entry.listener(receiver);
                  });
                })
                .catch(() => {
                  senderState.disconnected = true;
                  senderState.onDisconnect.dispatch(port);
                });
              pendingRegistrations.push(connectPromise.catch(() => undefined));
              return port;
            },
            enumerable: true
          });

          Object.defineProperty(runtime, "connectNative", {
            value(application) {
              const port = createPort("", null, { nativePort: true });
              const state = portState.get(port);
              nextPortNumber += 1;
              state.id = [
                config.surfaceID,
                "pending-native-port",
                String(nextPortNumber)
              ].join(":");
              state.readyPromise = bridgePost(
                "connectNative",
                "fireAndForget",
                [toJSONCompatible(application)]
              )
                .then((response) => {
                  if (!response.succeeded) {
                    state.disconnected = true;
                    state.onDisconnect.dispatch(port);
                    return response;
                  }
                  const payload = response.resultPayload || {};
                  state.id = payload.portID || state.id;
                  return response;
                })
                .catch(() => {
                  state.disconnected = true;
                  state.onDisconnect.dispatch(port);
                  return {
                    succeeded: false,
                    lastErrorMessage: "Native messaging port is closed."
                  };
                });
              return port;
            },
            enumerable: true
          });

          Object.defineProperty(runtime, "onMessage", {
            value: onMessageEvent,
            enumerable: true
          });
          Object.defineProperty(runtime, "onConnect", {
            value: onConnectEvent,
            enumerable: true
          });

          Object.defineProperty(chromeObject, "runtime", {
            value: Object.freeze(runtime),
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

struct ChromeMV3RuntimeJSMessagingMVPBehaviorSummary:
    Codable,
    Equatable,
    Sendable
{
    var sendMessageCallbackRoutesToSwiftDispatcher: Bool
    var sendMessagePromiseRoutesToSwiftDispatcher: Bool
    var onMessageListenerRegistrationModeled: Bool
    var connectCreatesModelPort: Bool
    var onConnectListenerRegistrationModeled: Bool
    var callbackLastErrorScoped: Bool
    var promiseRejectsOnError: Bool
    var noReceivingEndMapped: Bool
    var invalidArgumentsMapped: Bool
    var noNativeMessagingOpened: Bool
    var noServiceWorkerWake: Bool
}

struct ChromeMV3RuntimeJSMessagingMVPReportSummary:
    Codable,
    Equatable,
    Sendable
{
    var reportID: String
    var reportFileName: String
    var runtimeJSBridgeAvailableInSyntheticHarness: Bool
    var runtimeJSBridgeAvailableInProduct: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var serviceWorkerWakeAvailable: Bool
    var nativeMessagingAvailable: Bool
    var runtimeLoadable: Bool
    var productRuntimeExposed: Bool
    var sendMessageMVPAvailable: Bool
    var connectPortMVPAvailable: Bool
}

struct ChromeMV3RuntimeJSMessagingMVPReport:
    Codable,
    Equatable,
    Sendable
{
    var schemaVersion: Int
    var id: String
    var reportFileName: String
    var extensionID: String
    var profileID: String
    var shimCoverage: ChromeMV3RuntimeJSShimCoverage
    var bridgeHandlerCoveredMethods: [String]
    var listenerRegistrySummary:
        ChromeMV3RuntimeJSSyntheticListenerRegistrySummary
    var behaviorSummary: ChromeMV3RuntimeJSMessagingMVPBehaviorSummary
    var sendMessageCases:
        [ChromeMV3RuntimeJSBridgeHostResponse]
    var connectPortCases:
        [ChromeMV3RuntimeJSBridgeHostResponse]
    var lastErrorCallbackPromiseCases:
        [ChromeMV3RuntimeJSBridgeHostResponse]
    var syntheticExtensionPageTestStatus: String
    var runtimeJSBridgeAvailableInSyntheticHarness: Bool
    var runtimeJSBridgeAvailableInProduct: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var serviceWorkerWakeAvailable: Bool
    var nativeMessagingAvailable: Bool
    var runtimeLoadable: Bool
    var productRuntimeExposed: Bool
    var documentationSources:
        [ChromeMV3WebKitObjectAcceptanceDocumentationSource]
    var diagnostics: [String]

    var summary: ChromeMV3RuntimeJSMessagingMVPReportSummary {
        ChromeMV3RuntimeJSMessagingMVPReportSummary(
            reportID: id,
            reportFileName: reportFileName,
            runtimeJSBridgeAvailableInSyntheticHarness:
                runtimeJSBridgeAvailableInSyntheticHarness,
            runtimeJSBridgeAvailableInProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            serviceWorkerWakeAvailable: false,
            nativeMessagingAvailable: false,
            runtimeLoadable: false,
            productRuntimeExposed: false,
            sendMessageMVPAvailable:
                behaviorSummary
                .sendMessagePromiseRoutesToSwiftDispatcher
                    || behaviorSummary
                    .sendMessageCallbackRoutesToSwiftDispatcher,
            connectPortMVPAvailable:
                behaviorSummary.connectCreatesModelPort
        )
    }
}

enum ChromeMV3RuntimeJSMessagingMVPReportWriter {
    static let reportFileName =
        "runtime-js-runtime-messaging-mvp-report.json"

    @discardableResult
    static func write(
        _ report: ChromeMV3RuntimeJSMessagingMVPReport,
        toRewrittenBundleRoot rootURL: URL
    ) throws -> ChromeMV3RuntimeJSMessagingMVPReport {
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

enum ChromeMV3RuntimeJSMessagingMVPReportGenerator {
    static func makeReport(
        extensionID: String = "runtime-js-mvp-extension",
        profileID: String = "runtime-js-mvp-profile",
        moduleState: ChromeMV3ProfileHostModuleState = .enabled
    ) -> ChromeMV3RuntimeJSMessagingMVPReport {
        let configuration = ChromeMV3RuntimeJSBridgeConfiguration
            .syntheticHarness(
                extensionID: extensionID,
                profileID: profileID,
                moduleState: moduleState
            )
        let handler = ChromeMV3RuntimeJSBridgeHandler(
            configuration: configuration
        )
        let noReceiver = handler.handle(
            request(
                "sendMessage",
                invocationMode: .callback,
                arguments: [.object(["kind": .string("noReceiver")])]
            )
        )
        _ = handler.handle(
            listenerRequest("onMessage.addListener", listenerID: "message-1")
        )
        let callbackSend = handler.handle(
            request(
                "sendMessage",
                invocationMode: .callback,
                arguments: [.object(["kind": .string("callback")])]
            )
        )
        let promiseSend = handler.handle(
            request(
                "sendMessage",
                invocationMode: .promise,
                arguments: [.object(["kind": .string("promise")])]
            )
        )
        let invalidSend = handler.handle(
            request("sendMessage", invocationMode: .promise)
        )
        _ = handler.handle(
            listenerRequest("onConnect.addListener", listenerID: "connect-1")
        )
        let connect = handler.handle(
            request(
                "connect",
                invocationMode: .fireAndForget,
                arguments: [.object(["name": .string("mvp")])]
            )
        )
        let disconnect = handler.handle(
            portRequest("Port.disconnect", portID: "model-port-1")
        )
        let postMessage = handler.handle(
            portRequest(
                "Port.postMessage",
                portID: "model-port-1",
                arguments: [.object(["hello": .string("port")])]
            )
        )
        let responses = [
            noReceiver,
            callbackSend,
            promiseSend,
            invalidSend,
            connect,
            disconnect,
            postMessage,
        ]
        let behavior = ChromeMV3RuntimeJSMessagingMVPBehaviorSummary(
            sendMessageCallbackRoutesToSwiftDispatcher:
                callbackSend.runtimeDispatcherResult != nil,
            sendMessagePromiseRoutesToSwiftDispatcher:
                promiseSend.runtimeDispatcherResult != nil,
            onMessageListenerRegistrationModeled:
                handler.listenerRegistry.listenerCount(for: .onMessage) > 0,
            connectCreatesModelPort: connect.succeeded,
            onConnectListenerRegistrationModeled:
                handler.listenerRegistry.listenerCount(for: .onConnect) > 0,
            callbackLastErrorScoped:
                noReceiver.callbackWouldSetLastError,
            promiseRejectsOnError:
                invalidSend.promiseWouldReject,
            noReceivingEndMapped:
                noReceiver.lastErrorCode
                    == ChromeMV3RuntimeLastErrorCase.noReceivingEnd.rawValue,
            invalidArgumentsMapped:
                invalidSend.lastErrorCode
                    == ChromeMV3JSBridgeErrorCode.invalidArguments.rawValue,
            noNativeMessagingOpened:
                responses.allSatisfy { $0.nativeMessagingAvailable == false },
            noServiceWorkerWake:
                responses.allSatisfy { $0.serviceWorkerWakeAvailable == false }
        )
        let reportID = stableID(
            prefix: "runtime-js-messaging-mvp",
            parts: [
                configuration.extensionID,
                configuration.profileID,
                responses.map(\.bridgeCallID).joined(separator: "|"),
            ]
        )
        return ChromeMV3RuntimeJSMessagingMVPReport(
            schemaVersion: 1,
            id: reportID,
            reportFileName:
                ChromeMV3RuntimeJSMessagingMVPReportWriter.reportFileName,
            extensionID: configuration.extensionID,
            profileID: configuration.profileID,
            shimCoverage: ChromeMV3RuntimeJSShimSource.coverage,
            bridgeHandlerCoveredMethods: [
                "NativePort.disconnect",
                "NativePort.postMessage",
                "Port.disconnect",
                "Port.postMessage",
                "connect",
                "connectNative",
                "onConnect.addListener",
                "onConnect.hasListener",
                "onConnect.removeListener",
                "onMessage.addListener",
                "onMessage.hasListener",
                "onMessage.removeListener",
                "sendMessage",
                "sendNativeMessage",
            ],
            listenerRegistrySummary: handler.listenerRegistry.summary,
            behaviorSummary: behavior,
            sendMessageCases: [noReceiver, callbackSend, promiseSend, invalidSend],
            connectPortCases: [connect, disconnect, postMessage],
            lastErrorCallbackPromiseCases: [noReceiver, invalidSend],
            syntheticExtensionPageTestStatus:
                "Model and WebKit synthetic harness paths are DEBUG/internal only; product runtime remains unavailable.",
            runtimeJSBridgeAvailableInSyntheticHarness:
                configuration.runtimeJSBridgeAvailableInSyntheticHarness,
            runtimeJSBridgeAvailableInProduct: false,
            normalTabRuntimeBridgeAvailable: false,
            serviceWorkerWakeAvailable: false,
            nativeMessagingAvailable: false,
            runtimeLoadable: false,
            productRuntimeExposed: false,
            documentationSources: documentationSources(),
            diagnostics:
                uniqueSorted(
                    responses.flatMap(\.diagnostics)
                        + [
                            "Runtime JS messaging MVP report is deterministic.",
                            "The shim is runtime-only and synthetic-surface gated.",
                            "No normal-tab bridge is installed.",
                            "No service-worker wake, native messaging, or product UI is added.",
                        ]
                )
        )
    }

    private static func request(
        _ methodName: String,
        invocationMode: ChromeMV3JSBridgeInvocationMode,
        arguments: [ChromeMV3StorageValue] = []
    ) -> ChromeMV3RuntimeJSBridgeHostRequest {
        ChromeMV3RuntimeJSBridgeHostRequest(
            bridgeCallID:
                stableID(
                    prefix: "runtime-js-report-call",
                    parts: [
                        methodName,
                        invocationMode.rawValue,
                        arguments.map {
                            (try? $0.canonicalJSONString()) ?? "argument"
                        }.joined(separator: "|"),
                    ]
                ),
            namespace: "runtime",
            methodName: methodName,
            invocationMode: invocationMode,
            arguments: arguments,
            listenerID: nil,
            eventName: nil,
            portID: nil,
            diagnostics: []
        )
    }

    private static func listenerRequest(
        _ methodName: String,
        listenerID: String
    ) -> ChromeMV3RuntimeJSBridgeHostRequest {
        ChromeMV3RuntimeJSBridgeHostRequest(
            bridgeCallID:
                stableID(
                    prefix: "runtime-js-listener-call",
                    parts: [methodName, listenerID]
                ),
            namespace: "runtime",
            methodName: methodName,
            invocationMode: .fireAndForget,
            arguments: [],
            listenerID: listenerID,
            eventName: nil,
            portID: nil,
            diagnostics: []
        )
    }

    private static func portRequest(
        _ methodName: String,
        portID: String,
        arguments: [ChromeMV3StorageValue] = []
    ) -> ChromeMV3RuntimeJSBridgeHostRequest {
        ChromeMV3RuntimeJSBridgeHostRequest(
            bridgeCallID:
                stableID(
                    prefix: "runtime-js-port-call",
                    parts: [methodName, portID]
                ),
            namespace: "runtime",
            methodName: methodName,
            invocationMode: .fireAndForget,
            arguments: arguments,
            listenerID: nil,
            eventName: nil,
            portID: portID,
            diagnostics: []
        )
    }

    private static func documentationSources()
        -> [ChromeMV3WebKitObjectAcceptanceDocumentationSource]
    {
        [
            source(
                kind: "chromeDocumentation",
                title: "Chrome runtime API",
                url: "https://developer.chrome.com/docs/extensions/reference/api/runtime/",
                note: "Defines runtime.sendMessage, runtime.onMessage, runtime.connect, runtime.onConnect, Port, and runtime.lastError."
            ),
            source(
                kind: "chromeDocumentation",
                title: "Chrome message passing",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/messaging",
                note: "Defines callback, Promise, listener response, and long-lived connection behavior."
            ),
            source(
                kind: "appleDeveloperDocumentation",
                title: "WKUserContentController script message handlers",
                url: "https://developer.apple.com/documentation/webkit/wkusercontentcontroller/add(_:contentworld:name:)",
                note: "Defines content-world-scoped JavaScript message handlers."
            ),
            source(
                kind: "appleDeveloperDocumentation",
                title: "WKWebView evaluateJavaScript content world",
                url: "https://developer.apple.com/documentation/webkit/wkwebview/evaluatejavascript(_:in:contentworld:)",
                note: "Defines evaluating JavaScript in a chosen WKContentWorld."
            ),
            source(
                kind: "localAppleSDKHeaders",
                title: "MacOSX WebKit headers",
                url: nil,
                note: "Local headers document WKScriptMessageHandlerWithReply promise reply semantics and WKContentWorld scoping."
            ),
            source(
                kind: "currentSumiCode",
                title: "Sumi Chrome MV3 runtime models",
                url: nil,
                note: "The MVP routes through existing JS bridge contracts and runtime dispatcher models while keeping product runtime unavailable."
            ),
        ]
    }

    private static func source(
        kind: String,
        title: String,
        url: String?,
        note: String
    ) -> ChromeMV3WebKitObjectAcceptanceDocumentationSource {
        ChromeMV3WebKitObjectAcceptanceDocumentationSource(
            kind: kind,
            title: title,
            url: url,
            note: note
        )
    }
}

#if DEBUG
import WebKit

@available(macOS 15.5, *)
@MainActor
private final class ChromeMV3RuntimeJSScriptMessageHandler:
    NSObject,
    WKScriptMessageHandlerWithReply
{
    let handler: ChromeMV3RuntimeJSBridgeHandler

    init(handler: ChromeMV3RuntimeJSBridgeHandler) {
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

struct ChromeMV3RuntimeJSSyntheticHarnessResult:
    Codable,
    Equatable,
    Sendable
{
    var scriptEvaluationSucceeded: Bool
    var scriptResultJSON: String?
    var report: ChromeMV3RuntimeJSMessagingMVPReport
    var listenerRegistrySummary:
        ChromeMV3RuntimeJSSyntheticListenerRegistrySummary
    var userScriptCount: Int
    var scriptMessageHandlerCount: Int
    var syntheticWebViewCreated: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeJSBridgeAvailableInProduct: Bool
    var runtimeLoadable: Bool
    var diagnostics: [String]
}

@available(macOS 15.5, *)
@MainActor
private final class ChromeMV3RuntimeJSSyntheticNavigationObserver:
    NSObject,
    WKNavigationDelegate
{
    private var continuation:
        CheckedContinuation<Result<Void, Error>, Never>?

    func wait() async -> Result<Void, Error> {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
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

    private func finish(_ result: Result<Void, Error>) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

@available(macOS 15.5, *)
enum ChromeMV3RuntimeJSSyntheticHarness {
    @MainActor
    static func run(
        scriptBody: String,
        configuration: ChromeMV3RuntimeJSBridgeConfiguration =
            .syntheticHarness(),
        html: String =
            "<!doctype html><meta charset='utf-8'><title>Runtime JS MVP</title>"
    ) async -> ChromeMV3RuntimeJSSyntheticHarnessResult {
        let webViewConfiguration = WKWebViewConfiguration()
        webViewConfiguration.sumiIsNormalTabWebViewConfiguration = false
        let bridgeHandler = ChromeMV3RuntimeJSBridgeHandler(
            configuration: configuration
        )
        let scriptHandler = ChromeMV3RuntimeJSScriptMessageHandler(
            handler: bridgeHandler
        )
        webViewConfiguration.userContentController.addScriptMessageHandler(
            scriptHandler,
            contentWorld: .page,
            name: ChromeMV3RuntimeJSShimSource.bridgeMessageHandlerName
        )
        let webView = WKWebView(
            frame: .zero,
            configuration: webViewConfiguration
        )
        let observer = ChromeMV3RuntimeJSSyntheticNavigationObserver()
        webView.navigationDelegate = observer
        _ = webView.loadHTMLString(html, baseURL: nil)
        let navigationResult = await observer.wait()
        var diagnostics: [String] = [
            "Synthetic WKWebView is hidden and is not registered as a product tab.",
            "Runtime-only shim is evaluated in WKContentWorld.page for this controlled test surface.",
        ]
        if case .failure(let error) = navigationResult {
            diagnostics.append(error.localizedDescription)
        }

        let shimSource = ChromeMV3RuntimeJSShimSource.source(
            configuration: configuration
        )
        var scriptSucceeded = false
        var resultJSON: String?
        if case .success = navigationResult {
            do {
                _ = try await webView.evaluateJavaScript(
                    shimSource,
                    in: nil,
                    contentWorld: .page
                )
                let result = try await webView.callAsyncJavaScript(
                    scriptBody,
                    arguments: [:],
                    in: nil,
                    contentWorld: .page
                )
                resultJSON = ChromeMV3StorageValue(
                    runtimeJSBridgeValue: result ?? NSNull()
                )
                .flatMap { try? $0.canonicalJSONString() }
                scriptSucceeded = true
            } catch {
                diagnostics.append(error.localizedDescription)
            }
        }
        webView.navigationDelegate = nil
        webViewConfiguration.userContentController
            .removeScriptMessageHandler(
                forName:
                    ChromeMV3RuntimeJSShimSource.bridgeMessageHandlerName,
                contentWorld: .page
            )
        let report = ChromeMV3RuntimeJSMessagingMVPReportGenerator.makeReport(
            extensionID: configuration.extensionID,
            profileID: configuration.profileID,
            moduleState: configuration.moduleState
        )
        return ChromeMV3RuntimeJSSyntheticHarnessResult(
            scriptEvaluationSucceeded: scriptSucceeded,
            scriptResultJSON: resultJSON,
            report: report,
            listenerRegistrySummary: bridgeHandler.listenerRegistry.summary,
            userScriptCount:
                webViewConfiguration.userContentController.userScripts.count,
            scriptMessageHandlerCount: 1,
            syntheticWebViewCreated: true,
            normalTabRuntimeBridgeAvailable: false,
            runtimeJSBridgeAvailableInProduct: false,
            runtimeLoadable: false,
            diagnostics:
                uniqueSorted(
                    diagnostics
                        + bridgeHandler.listenerRegistry.summary.diagnostics
                )
        )
    }
}
#endif

private extension ChromeMV3StorageValue {
    init?(runtimeJSBridgeValue value: Any) {
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
                guard let value = ChromeMV3StorageValue(
                    runtimeJSBridgeValue: item
                ) else {
                    return nil
                }
                values.append(value)
            }
            self = .array(values)
            return
        }
        if let object = value as? [String: Any] {
            var values: [String: ChromeMV3StorageValue] = [:]
            for (key, item) in object {
                guard let value = ChromeMV3StorageValue(
                    runtimeJSBridgeValue: item
                ) else {
                    return nil
                }
                values[key] = value
            }
            self = .object(values)
            return
        }
        return nil
    }

    var runtimeJSBridgeFoundationObject: Any {
        switch self {
        case .array(let values):
            return values.map(\.runtimeJSBridgeFoundationObject)
        case .bool(let value):
            return value
        case .null:
            return NSNull()
        case .number(let value):
            return value
        case .object(let object):
            return object.mapValues(\.runtimeJSBridgeFoundationObject)
        case .string(let value):
            return value
        }
    }

    var objectValue: [String: ChromeMV3StorageValue]? {
        guard case .object(let object) = self else { return nil }
        return object
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }
}

private extension ChromeMV3RuntimeJSSyntheticListenerRegistrySummary {
    var foundationObject: [String: Any] {
        [
            "surfaceID": surfaceID,
            "extensionID": extensionID,
            "profileID": profileID,
            "onMessageListenerCount": onMessageListenerCount,
            "onConnectListenerCount": onConnectListenerCount,
            "registeredListenerIDs": registeredListenerIDs,
            "modelEndpointCount": modelEndpointCount,
            "listenerRegistryScopedToSyntheticSurface":
                listenerRegistryScopedToSyntheticSurface,
            "persistsBeyondSyntheticHostLifecycle":
                persistsBeyondSyntheticHostLifecycle,
            "serviceWorkerWakeAvailable": serviceWorkerWakeAvailable,
            "normalTabRuntimeBridgeAvailable":
                normalTabRuntimeBridgeAvailable,
            "diagnostics": diagnostics,
        ]
    }
}

private extension Array where Element: Hashable & Comparable {
    func uniqueSorted() -> [Element] {
        Array(Set(self)).sorted()
    }
}

private func normalized(_ value: String, fallback: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? fallback : trimmed
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
