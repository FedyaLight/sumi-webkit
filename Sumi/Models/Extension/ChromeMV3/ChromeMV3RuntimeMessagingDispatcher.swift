//
//  ChromeMV3RuntimeMessagingDispatcher.swift
//  Sumi
//
//  Deterministic host-side Chrome MV3 runtime messaging dispatcher skeleton.
//  This file routes model/test messages only. It does not import WebKit,
//  create or load contexts, register JavaScript listeners, inject scripts,
//  execute extension code, wake service workers, open real ports, launch native
//  messaging, or schedule background work.
//

import CryptoKit
import Foundation

enum ChromeMV3RuntimeModelListenerEndpointKind:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case actionPopupModel
    case contentScriptModel
    case extensionPageModel
    case nativeMessagingBlockedModel
    case optionsPageModel
    case serviceWorkerModel

    static func < (
        lhs: ChromeMV3RuntimeModelListenerEndpointKind,
        rhs: ChromeMV3RuntimeModelListenerEndpointKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3RuntimeModelHandlerOutcomeKind:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case modeledError
    case noResponse
    case response
}

struct ChromeMV3RuntimeModelHandlerOutcome:
    Codable,
    Equatable,
    Sendable
{
    var kind: ChromeMV3RuntimeModelHandlerOutcomeKind
    var responsePayload: ChromeMV3StorageValue?
    var error: ChromeMV3RuntimeLastErrorCase?
    var diagnostics: [String]

    static func response(
        _ payload: ChromeMV3StorageValue,
        diagnostics: [String] = []
    ) -> ChromeMV3RuntimeModelHandlerOutcome {
        ChromeMV3RuntimeModelHandlerOutcome(
            kind: .response,
            responsePayload: payload,
            error: nil,
            diagnostics:
                uniqueSorted(["Model handler returns JSON-compatible response."]
                    + diagnostics)
        )
    }

    static func noResponse(
        diagnostics: [String] = []
    ) -> ChromeMV3RuntimeModelHandlerOutcome {
        ChromeMV3RuntimeModelHandlerOutcome(
            kind: .noResponse,
            responsePayload: nil,
            error: nil,
            diagnostics:
                uniqueSorted(["Model handler returns no response."]
                    + diagnostics)
        )
    }

    static func modeledError(
        _ error: ChromeMV3RuntimeLastErrorCase,
        diagnostics: [String] = []
    ) -> ChromeMV3RuntimeModelHandlerOutcome {
        ChromeMV3RuntimeModelHandlerOutcome(
            kind: .modeledError,
            responsePayload: nil,
            error: error,
            diagnostics:
                uniqueSorted(
                    [
                        "Model handler returns \(error.rawValue).",
                    ] + diagnostics
                )
        )
    }
}

struct ChromeMV3RuntimeModelMessageHandler:
    Codable,
    Equatable,
    Sendable
{
    var handlerID: String
    var listenerID: String
    var outcome: ChromeMV3RuntimeModelHandlerOutcome
    var diagnostics: [String]

    static func make(
        listenerID: String,
        outcome: ChromeMV3RuntimeModelHandlerOutcome,
        seed: String = "model-handler",
        diagnostics: [String] = []
    ) -> ChromeMV3RuntimeModelMessageHandler {
        ChromeMV3RuntimeModelMessageHandler(
            handlerID: stableID(
                prefix: "model-handler",
                parts: [seed, listenerID, outcome.kind.rawValue]
            ),
            listenerID: listenerID,
            outcome: outcome,
            diagnostics:
                uniqueSorted(
                    [
                        "Handler is a deterministic Swift model handler.",
                        "No JavaScript listener or extension code is invoked.",
                    ] + diagnostics
                )
        )
    }

    func invoke(
        input: ChromeMV3RuntimeMessageDispatcherInput,
        endpointID: String
    ) -> ChromeMV3RuntimeModelHandlerInvocation {
        ChromeMV3RuntimeModelHandlerInvocation(
            handlerID: handlerID,
            endpointID: endpointID,
            listenerID: listenerID,
            routeKind: input.route.kind,
            messageID: input.messageEnvelope.messageID,
            responsePayload: outcome.responsePayload,
            selectedLastError:
                outcome.error.map(ChromeMV3RuntimeLastErrorContract.contract),
            diagnostics:
                uniqueSorted(
                    diagnostics
                        + outcome.diagnostics
                        + [
                            "Model handler invocation is synchronous and deterministic.",
                            "No callback or Promise is executed.",
                        ]
                )
        )
    }
}

struct ChromeMV3RuntimeModelHandlerInvocation:
    Codable,
    Equatable,
    Sendable
{
    var handlerID: String
    var endpointID: String
    var listenerID: String
    var routeKind: ChromeMV3RuntimeMessagingRouteKind
    var messageID: String
    var responsePayload: ChromeMV3StorageValue?
    var selectedLastError: ChromeMV3RuntimeLastErrorContract?
    var diagnostics: [String]
}

struct ChromeMV3RuntimeModelListenerEndpoint:
    Codable,
    Equatable,
    Sendable
{
    var endpointID: String
    var extensionID: String
    var profileID: String
    var listenerSurface: ChromeMV3RuntimeListenerSurface
    var listenerID: String
    var endpointKind: ChromeMV3RuntimeModelListenerEndpointKind
    var canReceiveModelMessages: Bool
    var canReceiveRuntimeMessagesNow: Bool
    var bypassesServiceWorkerWakeForModelOnlyDispatch: Bool
    var handler: ChromeMV3RuntimeModelMessageHandler?
    var diagnostics: [String]

    static func make(
        surface: ChromeMV3RuntimeListenerSurface,
        endpointKind: ChromeMV3RuntimeModelListenerEndpointKind,
        canReceiveModelMessages: Bool = true,
        bypassesServiceWorkerWakeForModelOnlyDispatch: Bool = false,
        handlerOutcome: ChromeMV3RuntimeModelHandlerOutcome? = nil,
        seed: String = "model-endpoint",
        diagnostics: [String] = []
    ) -> ChromeMV3RuntimeModelListenerEndpoint {
        let listenerID = ChromeMV3RuntimeListenerRegistrationContract
            .make(surface: surface)
            .listenerID
        let endpointID = stableID(
            prefix: "model-endpoint",
            parts: [
                seed,
                surface.extensionID,
                surface.profileID,
                surface.surface.rawValue,
                endpointKind.rawValue,
                surface.tabID.map(String.init) ?? "no-tab",
                surface.frameID.map(String.init) ?? "no-frame",
            ]
        )
        let handler = handlerOutcome.map {
            ChromeMV3RuntimeModelMessageHandler.make(
                listenerID: listenerID,
                outcome: $0,
                seed: endpointID
            )
        }
        return ChromeMV3RuntimeModelListenerEndpoint(
            endpointID: endpointID,
            extensionID: surface.extensionID,
            profileID: surface.profileID,
            listenerSurface: surface,
            listenerID: listenerID,
            endpointKind: endpointKind,
            canReceiveModelMessages: canReceiveModelMessages,
            canReceiveRuntimeMessagesNow: false,
            bypassesServiceWorkerWakeForModelOnlyDispatch:
                bypassesServiceWorkerWakeForModelOnlyDispatch,
            handler: handler,
            diagnostics:
                uniqueSorted(
                    [
                        "Endpoint is model/test only.",
                        "canReceiveRuntimeMessagesNow remains false.",
                        "No real listener is registered.",
                    ] + diagnostics
                )
        )
    }
}

struct ChromeMV3RuntimeModelListenerRegistrySummary:
    Codable,
    Equatable,
    Sendable
{
    var endpointCount: Int
    var endpointKinds: [ChromeMV3RuntimeModelListenerEndpointKind]
    var listenerSurfaces: [ChromeMV3RuntimeListenerSurfaceKind]
    var endpointsCanReceiveModelMessages: Bool
    var endpointsCanReceiveRuntimeMessagesNow: Bool
}

struct ChromeMV3RuntimeModelListenerRegistrySnapshot:
    Codable,
    Equatable,
    Sendable
{
    var extensionID: String
    var profileID: String
    var endpoints: [ChromeMV3RuntimeModelListenerEndpoint]
    var canReceiveRuntimeMessagesNow: Bool
    var diagnostics: [String]

    var summary: ChromeMV3RuntimeModelListenerRegistrySummary {
        ChromeMV3RuntimeModelListenerRegistrySummary(
            endpointCount: endpoints.count,
            endpointKinds:
                endpoints.map(\.endpointKind).uniqueSorted(),
            listenerSurfaces:
                endpoints.map(\.listenerSurface.surface).uniqueSorted(),
            endpointsCanReceiveModelMessages:
                endpoints.contains { $0.canReceiveModelMessages },
            endpointsCanReceiveRuntimeMessagesNow: false
        )
    }

    static func make(
        extensionID: String,
        profileID: String,
        endpoints: [ChromeMV3RuntimeModelListenerEndpoint] = [],
        diagnostics: [String] = []
    ) -> ChromeMV3RuntimeModelListenerRegistrySnapshot {
        let normalizedExtensionID = normalized(
            extensionID,
            fallback: "unknown-extension"
        )
        let normalizedProfileID = normalized(
            profileID,
            fallback: "unknown-profile"
        )
        return ChromeMV3RuntimeModelListenerRegistrySnapshot(
            extensionID: normalizedExtensionID,
            profileID: normalizedProfileID,
            endpoints:
                endpoints
                .filter {
                    $0.extensionID == normalizedExtensionID
                        && $0.profileID == normalizedProfileID
                }
                .sorted {
                    if $0.listenerSurface.surface != $1.listenerSurface.surface {
                        return $0.listenerSurface.surface
                            < $1.listenerSurface.surface
                    }
                    return $0.endpointID < $1.endpointID
                },
            canReceiveRuntimeMessagesNow: false,
            diagnostics:
                uniqueSorted(
                    [
                        "Model listener registry snapshot is host-side only.",
                        "No JavaScript listeners, user scripts, WebKit handlers, or service-worker wake are registered.",
                    ] + diagnostics
                )
        )
    }

    static func empty(
        extensionID: String,
        profileID: String
    ) -> ChromeMV3RuntimeModelListenerRegistrySnapshot {
        make(
            extensionID: extensionID,
            profileID: profileID,
            diagnostics: ["No model listener endpoints are registered."]
        )
    }

    static func passwordManagerModelFixture(
        extensionID: String,
        profileID: String,
        tabID: Int = 1,
        frameID: Int = 0
    ) -> ChromeMV3RuntimeModelListenerRegistrySnapshot {
        let serviceWorkerSurface = ChromeMV3RuntimeListenerSurface.make(
            surface: .runtimeOnMessageServiceWorker,
            extensionID: extensionID,
            profileID: profileID
        )
        let contentScriptSurface = ChromeMV3RuntimeListenerSurface.make(
            surface: .tabsMessageContentScript,
            extensionID: extensionID,
            profileID: profileID,
            tabID: tabID,
            frameID: frameID
        )
        let serviceWorkerEndpoint =
            ChromeMV3RuntimeModelListenerEndpoint.make(
                surface: serviceWorkerSurface,
                endpointKind: .serviceWorkerModel,
                bypassesServiceWorkerWakeForModelOnlyDispatch: true,
                handlerOutcome: .response(
                    .object([
                        "ok": .bool(true),
                        "target": .string("serviceWorkerModel"),
                    ])
                ),
                seed: "password-manager-service-worker-model",
                diagnostics: [
                    "Service-worker model endpoint explicitly bypasses runtime wake for model-only dispatch.",
                ]
            )
        let contentEndpoint =
            ChromeMV3RuntimeModelListenerEndpoint.make(
                surface: contentScriptSurface,
                endpointKind: .contentScriptModel,
                handlerOutcome: .response(
                    .object([
                        "ok": .bool(true),
                        "target": .string("contentScriptModel"),
                    ])
                ),
                seed: "password-manager-content-script-model"
            )
        return make(
            extensionID: extensionID,
            profileID: profileID,
            endpoints: [serviceWorkerEndpoint, contentEndpoint],
            diagnostics: [
                "Password-manager-like model endpoints cover content script, popup, service-worker, and tab message paths.",
            ]
        )
    }

    func endpoints(
        matching route: ChromeMV3RuntimeMessagingRoute
    ) -> [ChromeMV3RuntimeModelListenerEndpoint] {
        let surfaces = Set(
            ChromeMV3RuntimeListenerResolver
                .expectedReceivingSurfaces(for: route.kind)
        )
        return endpoints.filter { endpoint in
            guard endpoint.extensionID == route.extensionID,
                  endpoint.profileID == route.profileID,
                  surfaces.contains(endpoint.listenerSurface.surface)
            else { return false }
            if endpoint.listenerSurface.requiresTabFrameTargeting {
                guard endpoint.listenerSurface.tabID == route.tabID else {
                    return false
                }
                if let routeFrameID = route.frameID,
                   let endpointFrameID = endpoint.listenerSurface.frameID
                {
                    return routeFrameID == endpointFrameID
                }
            }
            return true
        }
        .sorted {
            if $0.listenerSurface.surface != $1.listenerSurface.surface {
                return $0.listenerSurface.surface < $1.listenerSurface.surface
            }
            return $0.endpointID < $1.endpointID
        }
    }
}

enum ChromeMV3RuntimeMessageDispatcherMode:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case modelOnly
    case runtimeRequestedButBlocked
}

struct ChromeMV3RuntimeMessageDispatcherInput:
    Codable,
    Equatable,
    Sendable
{
    var route: ChromeMV3RuntimeMessagingRoute
    var messageEnvelope: ChromeMV3RuntimeMessageEnvelope
    var listenerRegistrySnapshot:
        ChromeMV3RuntimeModelListenerRegistrySnapshot
    var permissionBrokerSnapshot: ChromeMV3PermissionBroker
    var serviceWorkerLifecycleSnapshot:
        ChromeMV3ServiceWorkerLifecycleStateSnapshot
    var moduleState: ChromeMV3ProfileHostModuleState
    var dispatchMode: ChromeMV3RuntimeMessageDispatcherMode
    var userGestureAvailable: Bool
    var nativeHostName: String?

    static func make(
        route: ChromeMV3RuntimeMessagingRoute,
        listenerRegistrySnapshot:
            ChromeMV3RuntimeModelListenerRegistrySnapshot,
        permissionBrokerSnapshot: ChromeMV3PermissionBroker,
        serviceWorkerLifecycleSnapshot:
            ChromeMV3ServiceWorkerLifecycleStateSnapshot? = nil,
        moduleState: ChromeMV3ProfileHostModuleState = .enabled,
        dispatchMode: ChromeMV3RuntimeMessageDispatcherMode = .modelOnly,
        responseMode: ChromeMV3RuntimeMessagingResponseMode = .promise,
        expectsResponse: Bool = true,
        userGestureAvailable: Bool = false,
        nativeHostName: String? = nil,
        seed: String = "runtime-message-dispatcher"
    ) -> ChromeMV3RuntimeMessageDispatcherInput {
        let permission = ChromeMV3RuntimeMessagingPermissionDecision
            .evaluate(
                route: route,
                permissionBroker: permissionBrokerSnapshot,
                userGestureAvailable: userGestureAvailable
            )
        let envelope = ChromeMV3RuntimeMessageEnvelope.make(
            route: route,
            expectsResponse: expectsResponse,
            responseMode: responseMode,
            permissionDecision: permission,
            seed: seed
        )
        return ChromeMV3RuntimeMessageDispatcherInput(
            route: route,
            messageEnvelope: envelope,
            listenerRegistrySnapshot: listenerRegistrySnapshot,
            permissionBrokerSnapshot: permissionBrokerSnapshot,
            serviceWorkerLifecycleSnapshot:
                serviceWorkerLifecycleSnapshot
                ?? .blocked(
                    extensionID: route.extensionID,
                    profileID: route.profileID
                ),
            moduleState: moduleState,
            dispatchMode: dispatchMode,
            userGestureAvailable: userGestureAvailable,
            nativeHostName: nativeHostName
        )
    }
}

enum ChromeMV3RuntimeDispatcherCallbackBehavior:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case noCallbackRequested
    case wouldInvokeWithNoArgumentsAndSetLastError
    case wouldInvokeWithNoResponse
    case wouldInvokeWithResponse
}

enum ChromeMV3RuntimeDispatcherPromiseBehavior:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case notRequested
    case wouldReject
    case wouldResolveUndefined
    case wouldResolveWithResponse
}

struct ChromeMV3RuntimeModelPortPreflight:
    Codable,
    Equatable,
    Sendable
{
    var modelPortPreflightEvaluated: Bool
    var portKind: ChromeMV3RuntimePortKind
    var portID: String
    var selectedDisconnectReason: ChromeMV3RuntimePortDisconnectReason
    var serviceWorkerKeepaliveImplication: String
    var keepaliveSource: ChromeMV3ServiceWorkerKeepaliveSource?
    var nativeMessagingPreflight:
        ChromeMV3NativeMessagingPreflightSummary?
    var nativeMessagingOperationID: String?
    var canOpenRuntimePortNow: Bool
    var canOpenNativePortNow: Bool
    var canWakeServiceWorkerNow: Bool
    var runtimeLoadable: Bool
    var diagnostics: [String]
}

struct ChromeMV3RuntimeMessageDispatcherResult:
    Codable,
    Equatable,
    Sendable
{
    var dispatchAttemptID: String
    var routeKind: ChromeMV3RuntimeMessagingRouteKind
    var acceptedByPreflight: Bool
    var receivingEndpointFound: Bool
    var selectedEndpoint:
        ChromeMV3RuntimeModelListenerEndpoint?
    var modelHandlerInvoked: Bool
    var runtimeHandlerInvoked: Bool
    var responsePayload: ChromeMV3StorageValue?
    var selectedLastError: ChromeMV3RuntimeLastErrorContract?
    var callbackBehavior:
        ChromeMV3RuntimeDispatcherCallbackBehavior
    var promiseBehavior:
        ChromeMV3RuntimeDispatcherPromiseBehavior
    var permissionDecision:
        ChromeMV3RuntimeMessagingPermissionDecision
    var listenerResolution:
        ChromeMV3RuntimeListenerResolutionResult
    var serviceWorkerWakePreflight:
        ChromeMV3ServiceWorkerWakePreflight?
    var modelPortPreflight:
        ChromeMV3RuntimeModelPortPreflight?
    var canDispatchModelMessagesNow: Bool
    var canDispatchMessagesNow: Bool
    var canDispatchRuntimeMessagesNow: Bool
    var canWakeServiceWorkerNow: Bool
    var canLoadContextNow: Bool
    var canOpenPortNow: Bool
    var runtimeLoadable: Bool
    var diagnostics: [String]
}

enum ChromeMV3RuntimeMessageDispatcher {
    static func dispatch(
        input: ChromeMV3RuntimeMessageDispatcherInput
    ) -> ChromeMV3RuntimeMessageDispatcherResult {
        let permission = ChromeMV3RuntimeMessagingPermissionDecision
            .evaluate(
                route: input.route,
                envelope: input.messageEnvelope,
                permissionBroker: input.permissionBrokerSnapshot,
                userGestureAvailable: input.userGestureAvailable
            )
        let serviceWorkerAvailability =
            ChromeMV3RuntimeServiceWorkerEventAvailabilityContract.make(
                serviceWorkerScriptDeclared:
                    input.serviceWorkerLifecycleSnapshot
                    .serviceWorkerScriptDeclared,
                serviceWorkerObjectAcceptedByWebKit:
                    input.serviceWorkerLifecycleSnapshot
                    .objectAcceptedByWebKit
            )
        let contractRegistry = contractRegistry(
            from: input.listenerRegistrySnapshot
        )
        let listenerResolution = ChromeMV3RuntimeListenerResolver.resolve(
            route: input.route,
            listenerRegistrySnapshot: contractRegistry,
            permissionDecision: permission,
            serviceWorkerAvailability: serviceWorkerAvailability,
            contentScriptAvailability:
                .diagnosticFixture(
                    contentScriptsDeclared:
                        hasContentScriptEndpoint(input.listenerRegistrySnapshot)
                ),
            extensionPageAvailability:
                .diagnosticFixture(extensionPageHostRequired: true)
        )
        let wakePreflight = input.route.requiresServiceWorkerWake
            ? ChromeMV3ServiceWorkerWakePreflight.evaluate(
                request: .forRoute(
                    input.route,
                    eventSeed: input.messageEnvelope.messageID,
                    extensionModuleEnabled:
                        input.moduleState == .enabled
                ),
                lifecycleState: input.serviceWorkerLifecycleSnapshot
            )
            : nil

        if isPortRoute(input.route.kind) {
            return portPreflightResult(
                input: input,
                permission: permission,
                listenerResolution: listenerResolution,
                wakePreflight: wakePreflight
            )
        }

        let endpoints = input.listenerRegistrySnapshot.endpoints(
            matching: input.route
        )
        let endpoint = endpoints.first
        let preflightError = firstOneShotBlocker(
            input: input,
            permission: permission,
            selectedEndpoint: endpoint,
            wakePreflight: wakePreflight
        )

        let invocation: ChromeMV3RuntimeModelHandlerInvocation?
        if preflightError == nil,
           input.dispatchMode == .modelOnly,
           let endpoint,
           let handler = endpoint.handler
        {
            invocation = handler.invoke(
                input: input,
                endpointID: endpoint.endpointID
            )
        } else {
            invocation = nil
        }

        let selectedError =
            preflightError.map(ChromeMV3RuntimeLastErrorContract.contract)
            ?? invocation?.selectedLastError
        let response = selectedError == nil
            ? invocation?.responsePayload
            : nil
        let canDispatchModel =
            input.dispatchMode == .modelOnly
            && preflightError == nil
            && invocation != nil
            && selectedError == nil

        return ChromeMV3RuntimeMessageDispatcherResult(
            dispatchAttemptID: dispatchAttemptID(input),
            routeKind: input.route.kind,
            acceptedByPreflight: preflightError == nil,
            receivingEndpointFound: endpoint != nil,
            selectedEndpoint: endpoint,
            modelHandlerInvoked: invocation != nil,
            runtimeHandlerInvoked: false,
            responsePayload: response,
            selectedLastError: selectedError,
            callbackBehavior: callbackBehavior(
                responseMode: input.messageEnvelope.responseMode,
                responsePayload: response,
                selectedLastError: selectedError
            ),
            promiseBehavior: promiseBehavior(
                responseMode: input.messageEnvelope.responseMode,
                responsePayload: response,
                selectedLastError: selectedError
            ),
            permissionDecision: permission,
            listenerResolution: listenerResolution,
            serviceWorkerWakePreflight: wakePreflight,
            modelPortPreflight: nil,
            canDispatchModelMessagesNow: canDispatchModel,
            canDispatchMessagesNow: false,
            canDispatchRuntimeMessagesNow: false,
            canWakeServiceWorkerNow: false,
            canLoadContextNow: false,
            canOpenPortNow: false,
            runtimeLoadable: false,
            diagnostics: diagnostics(
                input: input,
                endpoint: endpoint,
                preflightError: preflightError,
                invocation: invocation,
                selectedError: selectedError,
                listenerResolution: listenerResolution,
                wakePreflight: wakePreflight
            )
        )
    }

    private static func portPreflightResult(
        input: ChromeMV3RuntimeMessageDispatcherInput,
        permission: ChromeMV3RuntimeMessagingPermissionDecision,
        listenerResolution: ChromeMV3RuntimeListenerResolutionResult,
        wakePreflight: ChromeMV3ServiceWorkerWakePreflight?
    ) -> ChromeMV3RuntimeMessageDispatcherResult {
        let runtimePortContract = ChromeMV3RuntimePortContract.model(
            route: input.route,
            envelope: input.messageEnvelope,
            permissionSnapshot:
                runtimePermissionSnapshot(input.permissionBrokerSnapshot),
            readiness: ChromeMV3RuntimeMessagingReadinessSnapshot(
                extensionModuleEnabled: input.moduleState == .enabled,
                contextLoaded: false,
                targetTabExists: input.route.tabID != nil || input.route.requiresTabPermission == false,
                targetFrameExists: input.route.frameID != nil || input.route.kind != .serviceWorkerToFrame,
                receiverListenerRegistered:
                    listenerResolution.receivingListenerModeled,
                serviceWorkerLifecycleReady: false,
                canCreateContextNow: false,
                canLoadContextNow: false,
                runtimeLoadable: false
            ),
        )
        let nativePreflight: ChromeMV3NativeMessagingOperationPreflight?
        if input.route.kind == .nativeMessaging {
            nativePreflight = ChromeMV3NativeMessagingPreflightEvaluator
                .evaluate(
                    input: ChromeMV3NativeMessagingPreflightInput(
                        extensionID: input.route.extensionID,
                        profileID: input.route.profileID,
                        hostName: input.nativeHostName
                            ?? "unknown.native.host",
                        operationKind: .longLivedNativePort,
                        sourceContext: input.route.source.context,
                        permissionState: nativePermissionState(
                            input.permissionBrokerSnapshot
                        ),
                        productPolicy:
                            ChromeMV3NativeMessagingProductPolicy(
                                extensionModuleEnabled:
                                    input.moduleState == .enabled,
                                nativeMessagingAllowedByProductPolicy: true,
                                userConsentRequired: true,
                                userConsentGranted: false
                            )
                    ),
                    lookupPolicy: .macOS(
                        extensionModuleEnabled:
                            input.moduleState == .enabled
                    )
                )
        } else {
            nativePreflight = nil
        }
        let preflight = ChromeMV3RuntimeModelPortPreflight(
            modelPortPreflightEvaluated: true,
            portKind: runtimePortContract.portKind,
            portID: runtimePortContract.portID,
            selectedDisconnectReason:
                input.route.kind == .nativeMessaging
                    ? .nativeHostExited
                    : .routeUnsupported,
            serviceWorkerKeepaliveImplication:
                runtimePortContract.serviceWorkerKeepaliveImplication,
            keepaliveSource: runtimePortContract.keepaliveSource,
            nativeMessagingPreflight:
                nativePreflight.map(nativePreflightSummary),
            nativeMessagingOperationID: nativePreflight?.operationID,
            canOpenRuntimePortNow: false,
            canOpenNativePortNow: false,
            canWakeServiceWorkerNow: false,
            runtimeLoadable: false,
            diagnostics:
                uniqueSorted(
                    runtimePortContract.diagnostics
                        + (nativePreflight?.diagnostics ?? [])
                        + [
                            "Port/connect request evaluated as model preflight only.",
                            "No runtime Port is opened.",
                            "No native Port is opened.",
                        ]
                )
        )
        let error =
            input.moduleState == .disabled
                ? ChromeMV3RuntimeLastErrorCase.extensionDisabled
                : (input.route.kind == .nativeMessaging
                    ? .nativeMessagingBlocked
                    : .routeNotImplemented)
        let selectedError = ChromeMV3RuntimeLastErrorContract.contract(
            for: error
        )
        return ChromeMV3RuntimeMessageDispatcherResult(
            dispatchAttemptID: dispatchAttemptID(input),
            routeKind: input.route.kind,
            acceptedByPreflight: input.moduleState == .enabled,
            receivingEndpointFound:
                listenerResolution.receivingListenerModeled,
            selectedEndpoint: input.listenerRegistrySnapshot
                .endpoints(matching: input.route)
                .first,
            modelHandlerInvoked: false,
            runtimeHandlerInvoked: false,
            responsePayload: nil,
            selectedLastError: selectedError,
            callbackBehavior: callbackBehavior(
                responseMode: input.messageEnvelope.responseMode,
                responsePayload: nil,
                selectedLastError: selectedError
            ),
            promiseBehavior: promiseBehavior(
                responseMode: input.messageEnvelope.responseMode,
                responsePayload: nil,
                selectedLastError: selectedError
            ),
            permissionDecision: permission,
            listenerResolution: listenerResolution,
            serviceWorkerWakePreflight: wakePreflight,
            modelPortPreflight: preflight,
            canDispatchModelMessagesNow: false,
            canDispatchMessagesNow: false,
            canDispatchRuntimeMessagesNow: false,
            canWakeServiceWorkerNow: false,
            canLoadContextNow: false,
            canOpenPortNow: false,
            runtimeLoadable: false,
            diagnostics:
                uniqueSorted(
                    preflight.diagnostics
                        + [
                            "Connect route returns deterministic preflight only.",
                            "runtimeHandlerInvoked remains false.",
                            "canOpenPortNow remains false.",
                            "runtimeLoadable remains false.",
                        ]
                )
        )
    }

    private static func firstOneShotBlocker(
        input: ChromeMV3RuntimeMessageDispatcherInput,
        permission: ChromeMV3RuntimeMessagingPermissionDecision,
        selectedEndpoint: ChromeMV3RuntimeModelListenerEndpoint?,
        wakePreflight: ChromeMV3ServiceWorkerWakePreflight?
    ) -> ChromeMV3RuntimeLastErrorCase? {
        guard input.moduleState == .enabled else {
            return .extensionDisabled
        }
        if input.route.requiresNativeMessaging {
            return .nativeMessagingBlocked
        }
        if input.route.requiresTabPermission && input.route.tabID == nil {
            return .targetTabMissing
        }
        if input.route.kind == .serviceWorkerToFrame
            && input.route.frameID == nil
        {
            return .targetFrameMissing
        }
        if permission.allowedForFutureDispatch == false {
            return permissionError(permission)
        }
        if isSupportedOneShotModelRoute(input.route.kind) == false {
            return .routeNotImplemented
        }
        guard let selectedEndpoint else {
            return .noReceivingEnd
        }
        guard selectedEndpoint.canReceiveModelMessages else {
            return .listenerRegistrationNotImplemented
        }
        if input.dispatchMode == .runtimeRequestedButBlocked {
            return .contextNotLoaded
        }
        if input.route.requiresServiceWorkerWake,
           (wakePreflight?.canWakeServiceWorkerNow ?? false) == false,
           selectedEndpoint.bypassesServiceWorkerWakeForModelOnlyDispatch == false
        {
            return .serviceWorkerUnavailable
        }
        guard selectedEndpoint.handler != nil else {
            return .listenerRegistrationNotImplemented
        }
        return nil
    }

    private static func permissionError(
        _ permission: ChromeMV3RuntimeMessagingPermissionDecision
    ) -> ChromeMV3RuntimeLastErrorCase {
        switch permission.missingGrantReason {
        case .missingHostPermission:
            return .hostPermissionMissing
        case .missingActiveTabGrant, .activeTabGrantExpired,
             .userGestureRequired:
            return .activeTabMissing
        case .missingTabPermission, .permissionDenied:
            return .permissionDenied
        case .nativeMessagingBlocked:
            return .nativeMessagingBlocked
        case .none:
            return .permissionDenied
        }
    }

    private static func callbackBehavior(
        responseMode: ChromeMV3RuntimeMessagingResponseMode,
        responsePayload: ChromeMV3StorageValue?,
        selectedLastError: ChromeMV3RuntimeLastErrorContract?
    ) -> ChromeMV3RuntimeDispatcherCallbackBehavior {
        guard responseMode == .callback else {
            return .noCallbackRequested
        }
        if selectedLastError != nil {
            return .wouldInvokeWithNoArgumentsAndSetLastError
        }
        return responsePayload == nil
            ? .wouldInvokeWithNoResponse
            : .wouldInvokeWithResponse
    }

    private static func promiseBehavior(
        responseMode: ChromeMV3RuntimeMessagingResponseMode,
        responsePayload: ChromeMV3StorageValue?,
        selectedLastError: ChromeMV3RuntimeLastErrorContract?
    ) -> ChromeMV3RuntimeDispatcherPromiseBehavior {
        guard responseMode == .promise else {
            return .notRequested
        }
        if selectedLastError != nil {
            return .wouldReject
        }
        return responsePayload == nil
            ? .wouldResolveUndefined
            : .wouldResolveWithResponse
    }

    private static func diagnostics(
        input: ChromeMV3RuntimeMessageDispatcherInput,
        endpoint: ChromeMV3RuntimeModelListenerEndpoint?,
        preflightError: ChromeMV3RuntimeLastErrorCase?,
        invocation: ChromeMV3RuntimeModelHandlerInvocation?,
        selectedError: ChromeMV3RuntimeLastErrorContract?,
        listenerResolution: ChromeMV3RuntimeListenerResolutionResult,
        wakePreflight: ChromeMV3ServiceWorkerWakePreflight?
    ) -> [String] {
        var diagnostics = [
            "Runtime message dispatcher skeleton is model-only.",
            "Route \(input.route.kind.rawValue) was evaluated without WebKit, JavaScript, real listeners, service-worker wake, native launch, or Port opening.",
            "Dispatch mode: \(input.dispatchMode.rawValue).",
            "runtimeHandlerInvoked remains false.",
            "canDispatchRuntimeMessagesNow remains false.",
            "canWakeServiceWorkerNow remains false.",
            "canLoadContextNow remains false.",
            "runtimeLoadable remains false.",
        ]
        diagnostics.append(
            endpoint.map {
                "Selected model endpoint \($0.endpointID) for \($0.listenerSurface.surface.rawValue)."
            } ?? "No model endpoint was selected."
        )
        if let preflightError {
            diagnostics.append(
                "Dispatcher preflight selected \(preflightError.rawValue)."
            )
        }
        if let selectedError {
            diagnostics.append(
                "Selected lastError message: \(selectedError.futureLastErrorMessage)"
            )
        }
        diagnostics.append(contentsOf: endpoint?.diagnostics ?? [])
        diagnostics.append(contentsOf: invocation?.diagnostics ?? [])
        diagnostics.append(contentsOf: listenerResolution.diagnostics)
        diagnostics.append(contentsOf: wakePreflight?.diagnostics ?? [])
        return uniqueSorted(diagnostics)
    }

    private static func contractRegistry(
        from registry: ChromeMV3RuntimeModelListenerRegistrySnapshot
    ) -> ChromeMV3RuntimeListenerRegistrySnapshot {
        ChromeMV3RuntimeListenerRegistrySnapshot(
            registrations:
                registry.endpoints
                .map {
                    ChromeMV3RuntimeListenerRegistrationContract.make(
                        surface: $0.listenerSurface
                    )
                }
                .sorted { $0.listenerID < $1.listenerID },
            listenerRegistrationImplementedNow: false,
            dispatchImplementedNow: false,
            diagnostics:
                uniqueSorted(
                    registry.diagnostics
                        + [
                            "Contract registry was adapted from model endpoints.",
                            "Real listener registration remains unavailable.",
                        ]
                )
        )
    }

    private static func hasContentScriptEndpoint(
        _ registry: ChromeMV3RuntimeModelListenerRegistrySnapshot
    ) -> Bool {
        registry.endpoints.contains {
            $0.endpointKind == .contentScriptModel
        }
    }

    private static func isSupportedOneShotModelRoute(
        _ route: ChromeMV3RuntimeMessagingRouteKind
    ) -> Bool {
        switch route {
        case .runtimeSendMessage, .tabsSendMessage,
             .contentScriptToServiceWorker,
             .extensionPageToServiceWorker,
             .actionPopupToServiceWorker,
             .optionsPageToServiceWorker,
             .serviceWorkerToTab:
            return true
        default:
            return false
        }
    }

    private static func isPortRoute(
        _ route: ChromeMV3RuntimeMessagingRouteKind
    ) -> Bool {
        switch route {
        case .runtimeConnect, .tabsConnect, .nativeMessaging:
            return true
        default:
            return false
        }
    }

    private static func nativePermissionState(
        _ broker: ChromeMV3PermissionBroker
    ) -> ChromeMV3NativeMessagingPermissionState {
        let decision = broker.apiPermissionDecision("nativeMessaging")
        if decision.hasPermission {
            return .grantedByManifest
        }
        if decision.denied || decision.revoked {
            return .denied
        }
        if decision.deferred {
            return .deferred
        }
        if decision.unsupported {
            return .unsupported
        }
        return .missing
    }

    private static func runtimePermissionSnapshot(
        _ broker: ChromeMV3PermissionBroker
    ) -> ChromeMV3RuntimeMessagingPermissionSnapshot {
        ChromeMV3RuntimeMessagingPermissionSnapshot(
            grantedHostPermissions:
                (broker.state.hostPermissions
                    + broker.state.grantedOptionalHostPermissions)
                .sorted(),
            optionalPermissions: broker.state.optionalPermissions,
            optionalHostPermissions: broker.state.optionalHostPermissions,
            tabPermissionGranted: broker.hasAPIPermission("tabs"),
            activeTabPermissionDeclared: broker.activeTabPermissionDeclared,
            activeTabGrants:
                broker.activeTabBroker.grants.map {
                    ChromeMV3RuntimeMessagingActiveTabGrant(
                        tabID: $0.tabID,
                        origin: $0.scope.diagnosticValue,
                        createdByUserGesture: $0.userGestureModeled,
                        expiresOnTabClose:
                            $0.expiryTriggers.contains(.tabClose),
                        expiresOnNavigation:
                            $0.expiryTriggers.contains(.tabNavigation),
                        expiredByTabClose:
                            $0.expiryRecord?.trigger == .tabClose,
                        expiredByNavigation:
                            $0.expiryRecord?.trigger == .tabNavigation
                    )
                },
            deniedPermissions: broker.state.deniedPermissions,
            userGestureAvailable: false
        )
    }

    private static func nativePreflightSummary(
        _ preflight: ChromeMV3NativeMessagingOperationPreflight
    ) -> ChromeMV3NativeMessagingPreflightSummary {
        ChromeMV3NativeMessagingPreflightSummary(
            operationID: preflight.operationID,
            operationKind: preflight.operationKind,
            hostLookupStatus: preflight.hostLookupResult.status,
            authorizedByManifest:
                preflight.authorizationResult.authorizedByManifest,
            hasNativeMessagingPermission:
                preflight.authorizationResult.hasNativeMessagingPermission,
            canConnectNativeNow: false,
            canSendNativeMessageNow: false,
            processLaunchAllowedNow: false,
            canOpenPortNow: false,
            canWakeServiceWorkerNow: false,
            blockerCount: preflight.blockers.count
        )
    }

    private static func dispatchAttemptID(
        _ input: ChromeMV3RuntimeMessageDispatcherInput
    ) -> String {
        stableID(
            prefix: "model-dispatch",
            parts: [
                input.route.kind.rawValue,
                input.messageEnvelope.messageID,
                input.route.extensionID,
                input.route.profileID,
                input.dispatchMode.rawValue,
            ]
        )
    }
}

struct ChromeMV3RuntimeDispatcherRouteCoverage:
    Codable,
    Equatable,
    Sendable
{
    var routeKind: ChromeMV3RuntimeMessagingRouteKind
    var oneShotModelDispatchCovered: Bool
    var connectPreflightCovered: Bool
    var runtimeDispatchAvailable: Bool
    var selectedLastErrorWhenBlocked: ChromeMV3RuntimeLastErrorCase?
}

struct ChromeMV3RuntimeDispatcherCallbackPromiseLastErrorCoverage:
    Codable,
    Equatable,
    Sendable
{
    var callbackBehaviors:
        [ChromeMV3RuntimeDispatcherCallbackBehavior]
    var promiseBehaviors:
        [ChromeMV3RuntimeDispatcherPromiseBehavior]
    var lastErrorCases: [ChromeMV3RuntimeLastErrorCase]
}

struct ChromeMV3PasswordManagerDispatcherFlowSummary:
    Codable,
    Equatable,
    Sendable
{
    var contentScriptToServiceWorkerModelRouteCovered: Bool
    var popupToServiceWorkerModelRouteCovered: Bool
    var serviceWorkerToTabContentModelRouteCovered: Bool
    var portConnectModelPreflightCovered: Bool
    var nativeMessagingConnectBlocked: Bool
    var hostPermissionOrActiveTabRequirementStatus: String
    var storageModelAvailabilityStatus: String
    var jsBridgeMissing: Bool
    var realListenerRegistrationMissing: Bool
    var serviceWorkerWakeMissing: Bool
    var passwordManagerModelMessagingReady: Bool
    var passwordManagerRuntimeMessagingReady: Bool
    var blockers: [String]
}

struct ChromeMV3RuntimeMessageDispatcherSkeletonReportSummary:
    Codable,
    Equatable,
    Sendable
{
    var reportID: String
    var reportFileName: String
    var modelOnlyDispatchAvailable: Bool
    var runtimeDispatchAvailable: Bool
    var jsBridgeAvailable: Bool
    var canWakeServiceWorkerNow: Bool
    var canOpenPortNow: Bool
    var canLoadContextNow: Bool
    var runtimeLoadable: Bool
    var passwordManagerModelMessagingReady: Bool
    var passwordManagerRuntimeMessagingReady: Bool
    var jsBridgeRoutingSummary:
        ChromeMV3JSBridgeRoutingSummary? = nil
}

struct ChromeMV3RuntimeMessageDispatcherSkeletonReport:
    Codable,
    Equatable,
    Sendable
{
    var schemaVersion: Int
    var id: String
    var reportFileName: String
    var extensionID: String
    var profileID: String
    var modelListenerRegistrySummary:
        ChromeMV3RuntimeModelListenerRegistrySummary
    var oneShotRouteCoverage:
        [ChromeMV3RuntimeDispatcherRouteCoverage]
    var portConnectPreflightCoverage:
        [ChromeMV3RuntimeDispatcherRouteCoverage]
    var callbackPromiseLastErrorCoverage:
        ChromeMV3RuntimeDispatcherCallbackPromiseLastErrorCoverage
    var passwordManagerMessagingFlowSummary:
        ChromeMV3PasswordManagerDispatcherFlowSummary
    var jsBridgeRoutingSummary:
        ChromeMV3JSBridgeRoutingSummary? = nil
    var modelOnlyDispatchAvailable: Bool
    var runtimeDispatchAvailable: Bool
    var jsBridgeAvailable: Bool
    var canWakeServiceWorkerNow: Bool
    var canOpenPortNow: Bool
    var canLoadContextNow: Bool
    var runtimeLoadable: Bool
    var diagnostics: [String]
    var documentationSources: [ChromeMV3ManifestRewritePreviewSource]

    var summary: ChromeMV3RuntimeMessageDispatcherSkeletonReportSummary {
        ChromeMV3RuntimeMessageDispatcherSkeletonReportSummary(
            reportID: id,
            reportFileName: reportFileName,
            modelOnlyDispatchAvailable: modelOnlyDispatchAvailable,
            runtimeDispatchAvailable: false,
            jsBridgeAvailable: false,
            canWakeServiceWorkerNow: false,
            canOpenPortNow: false,
            canLoadContextNow: false,
            runtimeLoadable: false,
            passwordManagerModelMessagingReady:
                passwordManagerMessagingFlowSummary
                .passwordManagerModelMessagingReady,
            passwordManagerRuntimeMessagingReady: false,
            jsBridgeRoutingSummary: jsBridgeRoutingSummary
        )
    }
}

enum ChromeMV3RuntimeMessageDispatcherSkeletonReportWriter {
    static let reportFileName =
        "runtime-message-dispatcher-skeleton-report.json"

    @discardableResult
    static func write(
        _ report: ChromeMV3RuntimeMessageDispatcherSkeletonReport,
        toRewrittenBundleRoot rootURL: URL
    ) throws -> ChromeMV3RuntimeMessageDispatcherSkeletonReport {
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

enum ChromeMV3RuntimeMessageDispatcherSkeletonReportGenerator {
    static func makeReport(
        prerequisitesReport prerequisites:
            ChromeMV3RuntimeBridgePrerequisitesReport,
        profileID: String = "diagnostic-profile"
    ) -> ChromeMV3RuntimeMessageDispatcherSkeletonReport {
        let extensionID = prerequisites.candidateID
        let permissionStore = ChromeMV3PermissionLifecycleReportGenerator
            .permissionStore(
                prerequisites: prerequisites,
                extensionID: extensionID,
                profileID: profileID
            )
        let activeTabStore = ChromeMV3ActiveTabGrantStore.empty(
            extensionID: extensionID,
            profileID: profileID
        )
        let permissionBroker = permissionStore.permissionBroker(
            activeTabStore: activeTabStore
        )
        let registry =
            ChromeMV3RuntimeModelListenerRegistrySnapshot
            .passwordManagerModelFixture(
                extensionID: extensionID,
                profileID: profileID
            )
        let lifecycleState =
            ChromeMV3ServiceWorkerLifecycleStateSnapshot.blocked(
                extensionID: extensionID,
                profileID: profileID,
                serviceWorkerScriptDeclared:
                    prerequisites.manifestFacts
                    .backgroundServiceWorkerPresent
            )
        let storageSummary =
            ChromeMV3StorageBrokerReadinessReportGenerator.makeReport(
                prerequisitesReport: prerequisites,
                profileID: profileID
            ).summary
        let oneShotRoutes: [ChromeMV3RuntimeMessagingRouteKind] = [
            .runtimeSendMessage,
            .tabsSendMessage,
            .contentScriptToServiceWorker,
            .extensionPageToServiceWorker,
            .actionPopupToServiceWorker,
            .optionsPageToServiceWorker,
            .serviceWorkerToTab,
        ]
        let oneShotResults = oneShotRoutes.map {
            dispatchResult(
                kind: $0,
                extensionID: extensionID,
                profileID: profileID,
                permissionBroker: permissionBroker,
                registry: registry,
                lifecycleState: lifecycleState
            )
        }
        let connectResults = [
            ChromeMV3RuntimeMessagingRouteKind.runtimeConnect,
            .tabsConnect,
            .nativeMessaging,
        ].map {
            dispatchResult(
                kind: $0,
                extensionID: extensionID,
                profileID: profileID,
                permissionBroker: permissionBroker,
                registry: registry,
                lifecycleState: lifecycleState,
                payloadClassification: .portConnectionRequest
            )
        }
        let password = passwordSummary(
            oneShotResults: oneShotResults,
            connectResults: connectResults,
            permissionBroker: permissionBroker,
            storageSummary: storageSummary
        )
        let reportID = stableID(
            prefix: "runtime-message-dispatcher-skeleton",
            parts: [
                extensionID,
                profileID,
                prerequisites.id,
                registry.summary.endpointCount.description,
            ]
        )

        return ChromeMV3RuntimeMessageDispatcherSkeletonReport(
            schemaVersion: 1,
            id: reportID,
            reportFileName:
                ChromeMV3RuntimeMessageDispatcherSkeletonReportWriter
                .reportFileName,
            extensionID: extensionID,
            profileID: profileID,
            modelListenerRegistrySummary: registry.summary,
            oneShotRouteCoverage:
                oneShotResults.map(routeCoverage).sorted {
                    $0.routeKind < $1.routeKind
                },
            portConnectPreflightCoverage:
                connectResults.map(routeCoverage).sorted {
                    $0.routeKind < $1.routeKind
                },
            callbackPromiseLastErrorCoverage:
                callbackPromiseLastErrorCoverage(),
            passwordManagerMessagingFlowSummary: password,
            jsBridgeRoutingSummary:
                ChromeMV3JSBridgeContractReportGenerator
                .routingSummary(),
            modelOnlyDispatchAvailable: true,
            runtimeDispatchAvailable: false,
            jsBridgeAvailable: false,
            canWakeServiceWorkerNow: false,
            canOpenPortNow: false,
            canLoadContextNow: false,
            runtimeLoadable: false,
            diagnostics:
                uniqueSorted(
                    oneShotResults.flatMap(\.diagnostics)
                        + connectResults.flatMap(\.diagnostics)
                        + [
                            "Dispatcher skeleton can route model-only messages to deterministic Swift handlers.",
                            "Runtime dispatch remains unavailable.",
                            "JavaScript bridge remains unavailable.",
                            "No service-worker wake, context load, Port open, or native host launch occurs.",
                            "Sumi does not claim Chrome MV3 runtime support.",
                        ]
                ),
            documentationSources: documentationSources()
        )
    }

    static func makeReport(
        loadingPrerequisitesReportFrom rootURL: URL,
        fileManager: FileManager = .default
    ) throws -> ChromeMV3RuntimeMessageDispatcherSkeletonReport {
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
        _ = fileManager
        return makeReport(prerequisitesReport: prerequisites)
    }

    private static func dispatchResult(
        kind: ChromeMV3RuntimeMessagingRouteKind,
        extensionID: String,
        profileID: String,
        permissionBroker: ChromeMV3PermissionBroker,
        registry: ChromeMV3RuntimeModelListenerRegistrySnapshot,
        lifecycleState: ChromeMV3ServiceWorkerLifecycleStateSnapshot,
        payloadClassification:
            ChromeMV3RuntimeMessagingPayloadClassification = .jsonLike
    ) -> ChromeMV3RuntimeMessageDispatcherResult {
        let route = ChromeMV3RuntimeMessagingRoute.make(
            kind: kind,
            extensionID: extensionID,
            profileID: profileID,
            tabID: 1,
            frameID: 0,
            documentID: "document-0",
            sourceURL: "https://example.com/login",
            targetURL: "https://example.com/login"
        )
        let permission = ChromeMV3RuntimeMessagingPermissionDecision.evaluate(
            route: route,
            permissionBroker: permissionBroker
        )
        let envelope = ChromeMV3RuntimeMessageEnvelope.make(
            route: route,
            payloadClassification: payloadClassification,
            permissionDecision: permission,
            seed: "dispatcher-report-\(kind.rawValue)"
        )
        let input = ChromeMV3RuntimeMessageDispatcherInput(
            route: route,
            messageEnvelope: envelope,
            listenerRegistrySnapshot: registry,
            permissionBrokerSnapshot: permissionBroker,
            serviceWorkerLifecycleSnapshot: lifecycleState,
            moduleState: .enabled,
            dispatchMode: .modelOnly,
            userGestureAvailable: false,
            nativeHostName: "com.example.password_manager"
        )
        return ChromeMV3RuntimeMessageDispatcher.dispatch(input: input)
    }

    private static func routeCoverage(
        _ result: ChromeMV3RuntimeMessageDispatcherResult
    ) -> ChromeMV3RuntimeDispatcherRouteCoverage {
        ChromeMV3RuntimeDispatcherRouteCoverage(
            routeKind: result.routeKind,
            oneShotModelDispatchCovered:
                result.modelPortPreflight == nil
                    && (result.canDispatchModelMessagesNow
                        || result.selectedLastError != nil),
            connectPreflightCovered:
                result.modelPortPreflight?.modelPortPreflightEvaluated
                ?? false,
            runtimeDispatchAvailable: false,
            selectedLastErrorWhenBlocked: result.selectedLastError?.error
        )
    }

    private static func callbackPromiseLastErrorCoverage()
        -> ChromeMV3RuntimeDispatcherCallbackPromiseLastErrorCoverage
    {
        ChromeMV3RuntimeDispatcherCallbackPromiseLastErrorCoverage(
            callbackBehaviors:
                ChromeMV3RuntimeDispatcherCallbackBehavior.allCases,
            promiseBehaviors:
                ChromeMV3RuntimeDispatcherPromiseBehavior.allCases,
            lastErrorCases:
                ChromeMV3RuntimeLastErrorCase.allCases.sorted()
        )
    }

    private static func passwordSummary(
        oneShotResults: [ChromeMV3RuntimeMessageDispatcherResult],
        connectResults: [ChromeMV3RuntimeMessageDispatcherResult],
        permissionBroker: ChromeMV3PermissionBroker,
        storageSummary: ChromeMV3StorageBrokerReadinessReportSummary
    ) -> ChromeMV3PasswordManagerDispatcherFlowSummary {
        func passed(_ kind: ChromeMV3RuntimeMessagingRouteKind) -> Bool {
            oneShotResults.first { $0.routeKind == kind }?
                .canDispatchModelMessagesNow ?? false
        }
        let nativeBlocked =
            connectResults.first { $0.routeKind == .nativeMessaging }?
            .selectedLastError?.error == .nativeMessagingBlocked
        let portCovered =
            connectResults.contains {
                ($0.routeKind == .runtimeConnect
                    || $0.routeKind == .tabsConnect)
                    && $0.modelPortPreflight?
                    .modelPortPreflightEvaluated == true
            }
        let hostDecision = permissionBroker.hostAccessDecision(
            url: "https://example.com/login",
            tabID: 1
        )
        let modelReady =
            passed(.contentScriptToServiceWorker)
                && passed(.actionPopupToServiceWorker)
                && passed(.serviceWorkerToTab)
                && portCovered
                && nativeBlocked
        return ChromeMV3PasswordManagerDispatcherFlowSummary(
            contentScriptToServiceWorkerModelRouteCovered:
                passed(.contentScriptToServiceWorker),
            popupToServiceWorkerModelRouteCovered:
                passed(.actionPopupToServiceWorker),
            serviceWorkerToTabContentModelRouteCovered:
                passed(.serviceWorkerToTab),
            portConnectModelPreflightCovered: portCovered,
            nativeMessagingConnectBlocked: nativeBlocked,
            hostPermissionOrActiveTabRequirementStatus:
                hostDecision.hasHostAccess
                    ? "Host permission or activeTab access modeled for https://example.com/login."
                    : "Host permission or activeTab access is missing for https://example.com/login.",
            storageModelAvailabilityStatus:
                storageSummary.brokerModelOperationsAvailable
                    ? "storage.local/session broker model operations are available to host-side tests."
                    : "storage broker model operations are unavailable.",
            jsBridgeMissing: true,
            realListenerRegistrationMissing: true,
            serviceWorkerWakeMissing: true,
            passwordManagerModelMessagingReady: modelReady,
            passwordManagerRuntimeMessagingReady: false,
            blockers:
                uniqueSorted(
                    [
                        "Password-manager runtime messaging remains blocked.",
                        "JavaScript bridge is missing.",
                        "Real listener registration is missing.",
                        "Service-worker wake is missing.",
                        "Native messaging runtime remains blocked.",
                    ] + oneShotResults
                        .filter { $0.canDispatchModelMessagesNow == false }
                        .map {
                            "\($0.routeKind.rawValue) model path did not produce a successful model response."
                        }
                )
        )
    }

    private static func documentationSources()
        -> [ChromeMV3ManifestRewritePreviewSource]
    {
        [
            source(
                title: "Chrome message passing",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/messaging",
                note: "Defines one-time requests, runtime and tabs message boundaries, JSON serialization, and long-lived Port channels."
            ),
            source(
                title: "Chrome runtime API",
                url: "https://developer.chrome.com/docs/extensions/reference/api/runtime",
                note: "Defines runtime.sendMessage, runtime.onMessage, runtime.connect, runtime.onConnect, Port, MessageSender, and runtime.lastError behavior."
            ),
            source(
                title: "Chrome tabs API",
                url: "https://developer.chrome.com/docs/extensions/reference/api/tabs",
                note: "Defines tabs.sendMessage and tabs.connect delivery to content scripts in a tab, frame, or document."
            ),
            source(
                title: "Chrome extension service-worker lifecycle",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle",
                note: "Defines extension service-worker lifetime and long-lived messaging keepalive implications."
            ),
            source(
                title: "Chrome native messaging",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging",
                note: "Defines native messaging permission, host validation, native Port behavior, and content-script restriction."
            ),
            ChromeMV3ManifestRewritePreviewSource(
                kind: .currentSumiCode,
                title: "Sumi Chrome MV3 contracts",
                url: nil,
                note: "Dispatcher composes existing route, listener, permission, storage, native messaging, service-worker, lastError, and Port models without enabling runtime execution."
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

private func stableID(prefix: String, parts: [String]) -> String {
    let seed = parts.joined(separator: "|")
    return "\(prefix)-\(sha256Hex(Data(seed.utf8)).prefix(32))"
}

private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }
        .joined()
}

private func uniqueSorted(_ values: [String]) -> [String] {
    Array(Set(values.filter { $0.isEmpty == false })).sorted()
}

private func normalized(_ value: String, fallback: String) -> String {
    value.isEmpty ? fallback : value
}

private extension Array where Element == ChromeMV3RuntimeModelListenerEndpointKind {
    func uniqueSorted() -> [ChromeMV3RuntimeModelListenerEndpointKind] {
        Array(Set(self)).sorted()
    }
}

private extension Array where Element == ChromeMV3RuntimeListenerSurfaceKind {
    func uniqueSorted() -> [ChromeMV3RuntimeListenerSurfaceKind] {
        Array(Set(self)).sorted()
    }
}
