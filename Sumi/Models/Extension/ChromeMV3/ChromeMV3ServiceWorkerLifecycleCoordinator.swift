//
//  ChromeMV3ServiceWorkerLifecycleCoordinator.swift
//  Sumi
//
//  Deterministic Chrome MV3 extension service-worker lifecycle coordinator
//  skeleton. This file models wake requests, event preflight, pending events,
//  idle release, hard timeout, Port keepalive, native messaging blockers, alarm
//  placeholders, and reports only. It does not import WebKit, create or load
//  contexts, execute extension code, register listeners, dispatch events, open
//  ports, launch native hosts, or schedule background work.
//

import CryptoKit
import Foundation

enum ChromeMV3ServiceWorkerLifecycleState:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case contextCreatedButNotLoaded
    case contextNotCreated
    case failed
    case idleEligible
    case loadedButNotRunning
    case notCreated
    case objectAcceptedButNoContext
    case running
    case stopped

    static func < (
        lhs: ChromeMV3ServiceWorkerLifecycleState,
        rhs: ChromeMV3ServiceWorkerLifecycleState
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3ServiceWorkerLifecycleStateSnapshot:
    Codable,
    Equatable,
    Sendable
{
    var state: ChromeMV3ServiceWorkerLifecycleState
    var extensionID: String
    var profileID: String
    var serviceWorkerScriptDeclared: Bool
    var objectAcceptedByWebKit: Bool
    var contextCreated: Bool
    var contextLoaded: Bool
    var workerRunningNow: Bool
    var workerWakeAvailableNow: Bool
    var runtimeLoadable: Bool
    var permanentBackgroundForbidden: Bool
    var blockers: [String]

    static func blocked(
        extensionID: String,
        profileID: String,
        serviceWorkerScriptDeclared: Bool = true,
        objectAcceptedByWebKit: Bool = false
    ) -> ChromeMV3ServiceWorkerLifecycleStateSnapshot {
        let normalizedExtensionID = normalized(
            extensionID,
            fallback: "unknown-extension"
        )
        let normalizedProfileID = normalized(
            profileID,
            fallback: "unknown-profile"
        )
        let state: ChromeMV3ServiceWorkerLifecycleState
        if serviceWorkerScriptDeclared == false {
            state = .notCreated
        } else if objectAcceptedByWebKit {
            state = .objectAcceptedButNoContext
        } else {
            state = .contextNotCreated
        }

        return ChromeMV3ServiceWorkerLifecycleStateSnapshot(
            state: state,
            extensionID: normalizedExtensionID,
            profileID: normalizedProfileID,
            serviceWorkerScriptDeclared: serviceWorkerScriptDeclared,
            objectAcceptedByWebKit: objectAcceptedByWebKit,
            contextCreated: false,
            contextLoaded: false,
            workerRunningNow: false,
            workerWakeAvailableNow: false,
            runtimeLoadable: false,
            permanentBackgroundForbidden: true,
            blockers: uniqueSorted(
                [
                    serviceWorkerScriptDeclared
                        ? nil
                        : "No background service-worker script is declared.",
                    objectAcceptedByWebKit
                        ? "WebKit object acceptance is diagnostic only; no context is created."
                        : "No WebKit extension object is used by this lifecycle model.",
                    "Service-worker context is not created.",
                    "Service-worker context is not loaded.",
                    "Service-worker wake is not implemented.",
                    "Service-worker execution is not implemented.",
                    "Permanent background execution is forbidden.",
                    "runtimeLoadable remains false.",
                ].compactMap { $0 }
            )
        )
    }

    static func diagnostic(
        state: ChromeMV3ServiceWorkerLifecycleState,
        extensionID: String = "extension-a",
        profileID: String = "profile-a"
    ) -> ChromeMV3ServiceWorkerLifecycleStateSnapshot {
        var snapshot = blocked(
            extensionID: extensionID,
            profileID: profileID,
            serviceWorkerScriptDeclared: state != .notCreated,
            objectAcceptedByWebKit: state == .objectAcceptedButNoContext
        )
        snapshot.state = state
        snapshot.contextCreated = false
        snapshot.contextLoaded = false
        snapshot.workerRunningNow = false
        snapshot.workerWakeAvailableNow = false
        snapshot.runtimeLoadable = false
        snapshot.blockers = uniqueSorted(
            snapshot.blockers
                + [
                    "Diagnostic state \(state.rawValue) is represented without starting a worker.",
                ]
        )
        return snapshot
    }

    private static func normalized(
        _ value: String,
        fallback: String
    ) -> String {
        value.isEmpty ? fallback : value
    }
}

enum ChromeMV3ServiceWorkerWakeReason:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case actionClicked
    case actionPopupEvent
    case alarm
    case alarmPlaceholder
    case installOrUpdateEvent
    case nativeMessagingConnect
    case nativeMessagingMessage
    case permissionsChanged
    case runtimeConnect
    case runtimeMessage
    case storageChanged
    case tabsConnect
    case tabsMessage
    case testFixture

    static func < (
        lhs: ChromeMV3ServiceWorkerWakeReason,
        rhs: ChromeMV3ServiceWorkerWakeReason
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3ServiceWorkerWakeBlocker:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case contextLoadRequired
    case contextNotCreated
    case contextNotLoaded
    case extensionDisabled
    case listenerRegistrationUnavailable
    case nativeMessagingBlocked
    case permanentBackgroundForbidden
    case permissionOrActiveTabRequired
    case runtimeLoadableFalse
    case serviceWorkerAvailabilityRequired
    case serviceWorkerWakeUnavailable

    static func < (
        lhs: ChromeMV3ServiceWorkerWakeBlocker,
        rhs: ChromeMV3ServiceWorkerWakeBlocker
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3ServiceWorkerWakeRequest:
    Codable,
    Equatable,
    Sendable
{
    var extensionID: String
    var profileID: String
    var eventID: String
    var reason: ChromeMV3ServiceWorkerWakeReason
    var sourceContext: ChromeMV3RuntimeMessagingContextKind
    var targetListenerSurface: ChromeMV3RuntimeListenerSurfaceKind
    var requiresListenerRegistration: Bool
    var requiresContextLoad: Bool
    var requiresServiceWorkerAvailability: Bool
    var requiresPermissionOrActiveTab: Bool
    var canWakeNow: Bool
    var blockers: [ChromeMV3ServiceWorkerWakeBlocker]
    var diagnosticMessages: [String]

    static func make(
        extensionID: String,
        profileID: String,
        reason: ChromeMV3ServiceWorkerWakeReason,
        sourceContext: ChromeMV3RuntimeMessagingContextKind,
        targetListenerSurface: ChromeMV3RuntimeListenerSurfaceKind,
        eventSeed: String? = nil,
        requiresPermissionOrActiveTab: Bool = false,
        extensionModuleEnabled: Bool = true
    ) -> ChromeMV3ServiceWorkerWakeRequest {
        let normalizedExtensionID = normalized(
            extensionID,
            fallback: "unknown-extension"
        )
        let normalizedProfileID = normalized(
            profileID,
            fallback: "unknown-profile"
        )
        let seed = eventSeed ?? [
            normalizedExtensionID,
            normalizedProfileID,
            reason.rawValue,
            sourceContext.rawValue,
            targetListenerSurface.rawValue,
        ].joined(separator: "|")
        let native = reason == .nativeMessagingConnect
            || reason == .nativeMessagingMessage
        let blockers = uniqueSortedBlockers(
            [
                extensionModuleEnabled
                    ? nil
                    : .extensionDisabled,
                .listenerRegistrationUnavailable,
                .contextNotCreated,
                .contextLoadRequired,
                .contextNotLoaded,
                .serviceWorkerAvailabilityRequired,
                .serviceWorkerWakeUnavailable,
                .runtimeLoadableFalse,
                .permanentBackgroundForbidden,
                requiresPermissionOrActiveTab
                    ? .permissionOrActiveTabRequired
                    : nil,
                native ? .nativeMessagingBlocked : nil,
            ].compactMap { $0 }
        )
        let messages = uniqueSorted(
            blockers.map { message(for: $0) }
                + [
                    "Wake reason \(reason.rawValue) is modeled only.",
                    "No service worker is woken.",
                    "No event is dispatched.",
                ]
        )

        return ChromeMV3ServiceWorkerWakeRequest(
            extensionID: normalizedExtensionID,
            profileID: normalizedProfileID,
            eventID: stableID(prefix: "sw-event", parts: [seed]),
            reason: reason,
            sourceContext: sourceContext,
            targetListenerSurface: targetListenerSurface,
            requiresListenerRegistration: true,
            requiresContextLoad: true,
            requiresServiceWorkerAvailability: true,
            requiresPermissionOrActiveTab: requiresPermissionOrActiveTab,
            canWakeNow: false,
            blockers: blockers,
            diagnosticMessages: messages
        )
    }

    static func forRoute(
        _ route: ChromeMV3RuntimeMessagingRoute,
        eventSeed: String? = nil,
        extensionModuleEnabled: Bool = true
    ) -> ChromeMV3ServiceWorkerWakeRequest {
        let reason: ChromeMV3ServiceWorkerWakeReason
        switch route.kind {
        case .runtimeConnect, .extensionPageToServiceWorker,
             .actionPopupToServiceWorker, .optionsPageToServiceWorker:
            reason = route.kind == .runtimeConnect ? .runtimeConnect : .runtimeMessage
        case .contentScriptToServiceWorker, .runtimeSendMessage:
            reason = .runtimeMessage
        case .tabsConnect:
            reason = .tabsConnect
        case .tabsSendMessage:
            reason = .tabsMessage
        case .nativeMessaging:
            reason = .nativeMessagingConnect
        case .serviceWorkerToTab, .serviceWorkerToFrame,
             .serviceWorkerToExtensionPage:
            reason = .runtimeMessage
        }

        return make(
            extensionID: route.extensionID,
            profileID: route.profileID,
            reason: reason,
            sourceContext: route.source.context,
            targetListenerSurface:
                targetSurface(for: reason, routeKind: route.kind),
            eventSeed:
                eventSeed
                    ?? "\(route.kind.rawValue)|\(route.extensionID)|\(route.profileID)",
            requiresPermissionOrActiveTab:
                route.requiresHostPermission
                    || route.requiresActiveTab
                    || route.requiresTabPermission,
            extensionModuleEnabled: extensionModuleEnabled
        )
    }

    static func storageChanged(
        extensionID: String,
        profileID: String,
        areaName: String,
        changedKeys: [String],
        extensionModuleEnabled: Bool = true
    ) -> ChromeMV3ServiceWorkerWakeRequest {
        make(
            extensionID: extensionID,
            profileID: profileID,
            reason: .storageChanged,
            sourceContext: .serviceWorker,
            targetListenerSurface: .serviceWorkerLifecycleEventListener,
            eventSeed:
                "storage|\(areaName)|\(changedKeys.sorted().joined(separator: ","))",
            extensionModuleEnabled: extensionModuleEnabled
        )
    }

    static func permissionsChanged(
        extensionID: String,
        profileID: String,
        eventKind: ChromeMV3PermissionsAPIEventKind,
        extensionModuleEnabled: Bool = true
    ) -> ChromeMV3ServiceWorkerWakeRequest {
        make(
            extensionID: extensionID,
            profileID: profileID,
            reason: .permissionsChanged,
            sourceContext: .serviceWorker,
            targetListenerSurface: .serviceWorkerLifecycleEventListener,
            eventSeed: "permissions|\(eventKind.rawValue)",
            extensionModuleEnabled: extensionModuleEnabled
        )
    }

    static func nativeMessagingConnect(
        extensionID: String,
        profileID: String
    ) -> ChromeMV3ServiceWorkerWakeRequest {
        make(
            extensionID: extensionID,
            profileID: profileID,
            reason: .nativeMessagingConnect,
            sourceContext: .serviceWorker,
            targetListenerSurface: .nativeMessagingPortListener
        )
    }

    private static func targetSurface(
        for reason: ChromeMV3ServiceWorkerWakeReason,
        routeKind: ChromeMV3RuntimeMessagingRouteKind
    ) -> ChromeMV3RuntimeListenerSurfaceKind {
        switch reason {
        case .runtimeConnect, .tabsConnect:
            return .runtimeOnConnectServiceWorker
        case .nativeMessagingConnect:
            return .nativeMessagingPortListener
        default:
            return routeKind == .runtimeConnect
                ? .runtimeOnConnectServiceWorker
                : .runtimeOnMessageServiceWorker
        }
    }

    private static func normalized(
        _ value: String,
        fallback: String
    ) -> String {
        value.isEmpty ? fallback : value
    }

    private static func message(
        for blocker: ChromeMV3ServiceWorkerWakeBlocker
    ) -> String {
        switch blocker {
        case .contextLoadRequired:
            return "A loaded extension context would be required for future wake."
        case .contextNotCreated:
            return "No extension context is created."
        case .contextNotLoaded:
            return "No extension context is loaded."
        case .extensionDisabled:
            return "The extensions module is disabled."
        case .listenerRegistrationUnavailable:
            return "The target event listener is not registered."
        case .nativeMessagingBlocked:
            return "Native messaging Port lifecycle is blocked and deferred."
        case .permanentBackgroundForbidden:
            return "Permanent background execution remains forbidden."
        case .permissionOrActiveTabRequired:
            return "Permission or activeTab preflight is required before future dispatch."
        case .runtimeLoadableFalse:
            return "runtimeLoadable remains false."
        case .serviceWorkerAvailabilityRequired:
            return "Service-worker availability is required but unavailable now."
        case .serviceWorkerWakeUnavailable:
            return "Service-worker wake remains unavailable now."
        }
    }
}

struct ChromeMV3ServiceWorkerWakePreflight:
    Codable,
    Equatable,
    Sendable
{
    var request: ChromeMV3ServiceWorkerWakeRequest
    var lifecycleState: ChromeMV3ServiceWorkerLifecycleStateSnapshot
    var canQueuePendingEventInModel: Bool
    var canWakeServiceWorkerNow: Bool
    var canDispatchEventsNow: Bool
    var canLoadContextNow: Bool
    var runtimeLoadable: Bool
    var blockers: [ChromeMV3ServiceWorkerWakeBlocker]
    var diagnostics: [String]

    static func evaluate(
        request: ChromeMV3ServiceWorkerWakeRequest,
        lifecycleState: ChromeMV3ServiceWorkerLifecycleStateSnapshot? = nil
    ) -> ChromeMV3ServiceWorkerWakePreflight {
        let state = lifecycleState ?? .blocked(
            extensionID: request.extensionID,
            profileID: request.profileID
        )
        let blockers = uniqueSortedBlockers(
            request.blockers
                + [
                    state.contextCreated ? nil : .contextNotCreated,
                    state.contextLoaded ? nil : .contextNotLoaded,
                    state.workerWakeAvailableNow
                        ? nil
                        : .serviceWorkerWakeUnavailable,
                    state.runtimeLoadable ? nil : .runtimeLoadableFalse,
                ].compactMap { $0 }
        )
        return ChromeMV3ServiceWorkerWakePreflight(
            request: request,
            lifecycleState: state,
            canQueuePendingEventInModel: true,
            canWakeServiceWorkerNow: false,
            canDispatchEventsNow: false,
            canLoadContextNow: false,
            runtimeLoadable: false,
            blockers: blockers,
            diagnostics: uniqueSorted(
                request.diagnosticMessages
                    + state.blockers
                    + [
                        "Wake preflight is deterministic and non-executing.",
                        "Pending event may be queued in model form only.",
                        "canWakeServiceWorkerNow remains false.",
                        "canDispatchEventsNow remains false.",
                        "canLoadContextNow remains false.",
                    ]
            )
        )
    }
}

enum ChromeMV3ServiceWorkerPendingEventStatus:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case blocked
    case dropped
    case queuedModelOnly

    static func < (
        lhs: ChromeMV3ServiceWorkerPendingEventStatus,
        rhs: ChromeMV3ServiceWorkerPendingEventStatus
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3ServiceWorkerPendingEvent:
    Codable,
    Equatable,
    Sendable
{
    var sequence: Int
    var eventID: String
    var extensionID: String
    var profileID: String
    var reason: ChromeMV3ServiceWorkerWakeReason
    var targetListenerSurface: ChromeMV3RuntimeListenerSurfaceKind
    var status: ChromeMV3ServiceWorkerPendingEventStatus
    var payloadSummary: String
    var wouldDispatchNow: Bool
    var diagnostics: [String]
}

struct ChromeMV3ServiceWorkerPendingEventQueueSnapshot:
    Codable,
    Equatable,
    Sendable
{
    var events: [ChromeMV3ServiceWorkerPendingEvent]
    var queuedCount: Int
    var blockedCount: Int
    var droppedCount: Int
    var dispatchAttemptedNow: Bool
    var diagnostics: [String]
}

struct ChromeMV3ServiceWorkerPendingEventQueue:
    Codable,
    Equatable,
    Sendable
{
    private(set) var events: [ChromeMV3ServiceWorkerPendingEvent]
    private(set) var nextSequence: Int

    init(
        events: [ChromeMV3ServiceWorkerPendingEvent] = [],
        nextSequence: Int = 1
    ) {
        self.events = events.sorted { $0.sequence < $1.sequence }
        self.nextSequence = max(nextSequence, (events.map(\.sequence).max() ?? 0) + 1)
    }

    static let empty = ChromeMV3ServiceWorkerPendingEventQueue()

    mutating func enqueue(
        preflight: ChromeMV3ServiceWorkerWakePreflight,
        payloadSummary: String
    ) -> ChromeMV3ServiceWorkerPendingEvent {
        let event = ChromeMV3ServiceWorkerPendingEvent(
            sequence: nextSequence,
            eventID: preflight.request.eventID,
            extensionID: preflight.request.extensionID,
            profileID: preflight.request.profileID,
            reason: preflight.request.reason,
            targetListenerSurface: preflight.request.targetListenerSurface,
            status: .queuedModelOnly,
            payloadSummary: payloadSummary,
            wouldDispatchNow: false,
            diagnostics: uniqueSorted(
                preflight.diagnostics
                    + [
                        "Event queued in model form only.",
                        "No worker wake or dispatch was attempted.",
                    ]
            )
        )
        events.append(event)
        events.sort { $0.sequence < $1.sequence }
        nextSequence += 1
        return event
    }

    mutating func markEventBlocked(
        eventID: String,
        reason: String
    ) {
        update(eventID: eventID, status: .blocked, reason: reason)
    }

    mutating func markEventDropped(
        eventID: String,
        reason: String
    ) {
        update(eventID: eventID, status: .dropped, reason: reason)
    }

    func snapshot() -> ChromeMV3ServiceWorkerPendingEventQueueSnapshot {
        ChromeMV3ServiceWorkerPendingEventQueueSnapshot(
            events: events.sorted { $0.sequence < $1.sequence },
            queuedCount:
                events.filter { $0.status == .queuedModelOnly }.count,
            blockedCount: events.filter { $0.status == .blocked }.count,
            droppedCount: events.filter { $0.status == .dropped }.count,
            dispatchAttemptedNow: false,
            diagnostics: [
                "Pending event queue is in-memory model state only.",
                "No service-worker wake or event dispatch is performed.",
                "No background persistence or scheduling is started.",
            ]
        )
    }

    private mutating func update(
        eventID: String,
        status: ChromeMV3ServiceWorkerPendingEventStatus,
        reason: String
    ) {
        events = events.map { event in
            guard event.eventID == eventID else { return event }
            var copy = event
            copy.status = status
            copy.diagnostics = uniqueSorted(
                copy.diagnostics + ["Pending event \(status.rawValue): \(reason)"]
            )
            return copy
        }.sorted { $0.sequence < $1.sequence }
    }
}

struct ChromeMV3ServiceWorkerIdleReleasePolicy:
    Codable,
    Equatable,
    Sendable
{
    var idleAfterInactivitySeconds: Int
    var modeledOnly: Bool
    var schedulesDeadlineNow: Bool
    var releasesWorkerNow: Bool
    var diagnostics: [String]
}

struct ChromeMV3ServiceWorkerHardTimeoutPolicy:
    Codable,
    Equatable,
    Sendable
{
    var maximumSingleRequestSeconds: Int
    var fetchResponseLimitSeconds: Int
    var modeledOnly: Bool
    var schedulesDeadlineNow: Bool
    var terminatesWorkerNow: Bool
    var diagnostics: [String]
}

struct ChromeMV3ServiceWorkerLongRunningOperationPolicy:
    Codable,
    Equatable,
    Sendable
{
    var maximumOperationSeconds: Int
    var promptBasedAPIsMayExceedInFuture: Bool
    var modeledOnly: Bool
    var diagnostics: [String]
}

struct ChromeMV3ServiceWorkerPendingResponsePolicy:
    Codable,
    Equatable,
    Sendable
{
    var responseMode: ChromeMV3RuntimeMessagingResponseMode
    var timeoutPolicy: ChromeMV3RuntimeMessagingTimeoutPolicy
    var schedulesDeadlineNow: Bool
    var rejectsPromiseNow: Bool
    var invokesCallbackNow: Bool
    var diagnostics: [String]
}

struct ChromeMV3ServiceWorkerPortKeepalivePolicy:
    Codable,
    Equatable,
    Sendable
{
    var portKind: ChromeMV3RuntimePortKind
    var wouldKeepAliveInFuture: Bool
    var implementedNow: Bool
    var opensPortNow: Bool
    var diagnostics: [String]
}

struct ChromeMV3ServiceWorkerNativeMessagingPortPolicy:
    Codable,
    Equatable,
    Sendable
{
    var wouldKeepAliveInFuture: Bool
    var implementedNow: Bool
    var nativeMessagingBlocked: Bool
    var opensPortNow: Bool
    var launchesHostNow: Bool
    var passwordManagerRelevant: Bool
    var blockers: [String]
}

struct ChromeMV3ServiceWorkerAlarmWakePolicy:
    Codable,
    Equatable,
    Sendable
{
    var minimumPeriodSecondsModeled: Int
    var wakeReason: ChromeMV3ServiceWorkerWakeReason
    var implementedNow: Bool
    var schedulesAlarmNow: Bool
    var wakesWorkerNow: Bool
    var diagnostics: [String]
}

struct ChromeMV3ServiceWorkerLifecyclePolicySet:
    Codable,
    Equatable,
    Sendable
{
    var idleRelease: ChromeMV3ServiceWorkerIdleReleasePolicy
    var hardTimeout: ChromeMV3ServiceWorkerHardTimeoutPolicy
    var longRunningOperation:
        ChromeMV3ServiceWorkerLongRunningOperationPolicy
    var pendingResponse: ChromeMV3ServiceWorkerPendingResponsePolicy
    var longLivedPortKeepalive:
        [ChromeMV3ServiceWorkerPortKeepalivePolicy]
    var nativeMessagingPort:
        ChromeMV3ServiceWorkerNativeMessagingPortPolicy
    var alarmWake: ChromeMV3ServiceWorkerAlarmWakePolicy
    var permanentBackgroundForbidden: Bool
    var diagnostics: [String]

    static let modeled = ChromeMV3ServiceWorkerLifecyclePolicySet(
        idleRelease: ChromeMV3ServiceWorkerIdleReleasePolicy(
            idleAfterInactivitySeconds: 30,
            modeledOnly: true,
            schedulesDeadlineNow: false,
            releasesWorkerNow: false,
            diagnostics: [
                "Chrome documents extension service-worker shutdown after 30 seconds of inactivity.",
                "Sumi records the value only; no deadline is scheduled.",
            ]
        ),
        hardTimeout: ChromeMV3ServiceWorkerHardTimeoutPolicy(
            maximumSingleRequestSeconds: 300,
            fetchResponseLimitSeconds: 30,
            modeledOnly: true,
            schedulesDeadlineNow: false,
            terminatesWorkerNow: false,
            diagnostics: [
                "Chrome documents a 5 minute limit for a single request.",
                "Chrome documents a 30 second fetch response limit.",
                "Sumi records timeout policy only.",
            ]
        ),
        longRunningOperation:
            ChromeMV3ServiceWorkerLongRunningOperationPolicy(
                maximumOperationSeconds: 300,
                promptBasedAPIsMayExceedInFuture: true,
                modeledOnly: true,
                diagnostics: [
                    "Long-running operation timeout behavior is a future runtime input.",
                    "No keepalive call loop is implemented.",
                ]
            ),
        pendingResponse: ChromeMV3ServiceWorkerPendingResponsePolicy(
            responseMode: .promise,
            timeoutPolicy: .futureOneTimeMessageResponse,
            schedulesDeadlineNow: false,
            rejectsPromiseNow: false,
            invokesCallbackNow: false,
            diagnostics: [
                "Pending response timeout policy is modeled for future callback and Promise compatibility.",
                "No response channel is opened.",
            ]
        ),
        longLivedPortKeepalive: [
            ChromeMV3ServiceWorkerPortKeepalivePolicy(
                portKind: .runtimeConnect,
                wouldKeepAliveInFuture: true,
                implementedNow: false,
                opensPortNow: false,
                diagnostics: [
                    "Chrome documents long-lived messaging behavior that can affect worker lifetime when messages are sent.",
                    "Opening a runtime Port is not implemented.",
                ]
            ),
            ChromeMV3ServiceWorkerPortKeepalivePolicy(
                portKind: .tabsConnect,
                wouldKeepAliveInFuture: true,
                implementedNow: false,
                opensPortNow: false,
                diagnostics: [
                    "Chrome tabs.connect Port delivery is modeled for future keepalive policy.",
                    "Opening a tabs Port is not implemented.",
                ]
            ),
        ],
        nativeMessagingPort: ChromeMV3ServiceWorkerNativeMessagingPortPolicy(
            wouldKeepAliveInFuture: true,
            implementedNow: false,
            nativeMessagingBlocked: true,
            opensPortNow: false,
            launchesHostNow: false,
            passwordManagerRelevant: true,
            blockers: [
                "Native messaging Port would affect service-worker lifetime in Chrome.",
                "Sumi blocks native messaging host lookup and launch.",
                "Password-manager native messaging flow remains unavailable.",
            ]
        ),
        alarmWake: ChromeMV3ServiceWorkerAlarmWakePolicy(
            minimumPeriodSecondsModeled: 30,
            wakeReason: .alarm,
            implementedNow: false,
            schedulesAlarmNow: false,
            wakesWorkerNow: false,
            diagnostics: [
                "Chrome documents alarms as service-worker events and a 30 second minimum period in current Chrome.",
                "Sumi models alarm wake only; no alarm scheduler is added.",
            ]
        ),
        permanentBackgroundForbidden: true,
        diagnostics: [
            "Lifecycle policies are deterministic values.",
            "No deadlines, repeated checks, wake, or dispatch are started.",
            "Permanent background behavior is rejected for Chrome Manifest V3.",
        ]
    )
}

enum ChromeMV3ServiceWorkerKeepaliveSourceKind:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case alarmEvent
    case futureAPIEvent
    case nativeMessagingPort
    case pendingResponse
    case runtimePort
    case storageEventDispatch
    case tabsPort

    static func < (
        lhs: ChromeMV3ServiceWorkerKeepaliveSourceKind,
        rhs: ChromeMV3ServiceWorkerKeepaliveSourceKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3ServiceWorkerKeepaliveSource:
    Codable,
    Equatable,
    Sendable
{
    var kind: ChromeMV3ServiceWorkerKeepaliveSourceKind
    var sourceID: String
    var extensionID: String
    var profileID: String
    var wouldKeepAliveInFuture: Bool
    var implementedNow: Bool
    var passwordManagerRelevance: Bool
    var blockers: [String]

    static func make(
        kind: ChromeMV3ServiceWorkerKeepaliveSourceKind,
        extensionID: String,
        profileID: String,
        sourceSeed: String? = nil
    ) -> ChromeMV3ServiceWorkerKeepaliveSource {
        let normalizedExtensionID = extensionID.isEmpty
            ? "unknown-extension"
            : extensionID
        let normalizedProfileID = profileID.isEmpty
            ? "unknown-profile"
            : profileID
        let wouldKeepAlive: Bool
        let passwordRelevant: Bool
        switch kind {
        case .runtimePort, .tabsPort, .nativeMessagingPort,
             .pendingResponse, .storageEventDispatch, .alarmEvent,
             .futureAPIEvent:
            wouldKeepAlive = true
            passwordRelevant = kind == .runtimePort
                || kind == .tabsPort
                || kind == .nativeMessagingPort
                || kind == .pendingResponse
                || kind == .storageEventDispatch
        }
        let native = kind == .nativeMessagingPort
        let seed = sourceSeed ?? "\(kind.rawValue)|\(normalizedExtensionID)|\(normalizedProfileID)"

        return ChromeMV3ServiceWorkerKeepaliveSource(
            kind: kind,
            sourceID: stableID(prefix: "sw-keepalive", parts: [seed]),
            extensionID: normalizedExtensionID,
            profileID: normalizedProfileID,
            wouldKeepAliveInFuture: wouldKeepAlive,
            implementedNow: false,
            passwordManagerRelevance: passwordRelevant,
            blockers: uniqueSorted(
                [
                    "Keepalive source \(kind.rawValue) is modeled only.",
                    "No worker lifetime is extended now.",
                    "No Port, response channel, storage event, alarm, or API event is opened now.",
                    native
                        ? "Native messaging keepalive is blocked with native messaging runtime."
                        : nil,
                ].compactMap { $0 }
            )
        )
    }

    static func allModeled(
        extensionID: String,
        profileID: String
    ) -> [ChromeMV3ServiceWorkerKeepaliveSource] {
        ChromeMV3ServiceWorkerKeepaliveSourceKind.allCases.sorted().map {
            make(kind: $0, extensionID: extensionID, profileID: profileID)
        }
    }
}

enum ChromeMV3ServiceWorkerLifecycleDiagnosticKind:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case alarmWakePlaceholder
    case contextNotLoaded
    case eventQueuedInModelOnly
    case extensionDisabledCleanupRequired
    case hardTimeoutModeled
    case idleReleaseModeled
    case listenerUnavailable
    case messagingWakePreflightModeled
    case nativeMessagingKeepaliveBlocked
    case permanentBackgroundRejected
    case permissionWakePreflightModeled
    case portKeepaliveModeled
    case serviceWorkerUnavailable
    case storageWakePreflightModeled
    case wakeBlocked
    case wakeRequested

    static func < (
        lhs: ChromeMV3ServiceWorkerLifecycleDiagnosticKind,
        rhs: ChromeMV3ServiceWorkerLifecycleDiagnosticKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3ServiceWorkerLifecycleDiagnostic:
    Codable,
    Equatable,
    Sendable
{
    var sequence: Int
    var kind: ChromeMV3ServiceWorkerLifecycleDiagnosticKind
    var eventID: String?
    var message: String
    var blockers: [ChromeMV3ServiceWorkerWakeBlocker]
}

struct ChromeMV3ServiceWorkerLifecycleCoordinator:
    Codable,
    Equatable,
    Sendable
{
    var lifecycleState: ChromeMV3ServiceWorkerLifecycleStateSnapshot
    var policies: ChromeMV3ServiceWorkerLifecyclePolicySet
    var pendingEventQueue: ChromeMV3ServiceWorkerPendingEventQueue
    var diagnostics: [ChromeMV3ServiceWorkerLifecycleDiagnostic]
    var nextDiagnosticSequence: Int

    init(
        lifecycleState: ChromeMV3ServiceWorkerLifecycleStateSnapshot,
        policies: ChromeMV3ServiceWorkerLifecyclePolicySet = .modeled,
        pendingEventQueue: ChromeMV3ServiceWorkerPendingEventQueue = .empty,
        diagnostics: [ChromeMV3ServiceWorkerLifecycleDiagnostic] = [],
        nextDiagnosticSequence: Int = 1
    ) {
        self.lifecycleState = lifecycleState
        self.policies = policies
        self.pendingEventQueue = pendingEventQueue
        self.diagnostics = diagnostics.sorted { $0.sequence < $1.sequence }
        self.nextDiagnosticSequence = max(
            nextDiagnosticSequence,
            (diagnostics.map(\.sequence).max() ?? 0) + 1
        )
    }

    static func blocked(
        extensionID: String,
        profileID: String,
        serviceWorkerScriptDeclared: Bool = true,
        objectAcceptedByWebKit: Bool = false
    ) -> ChromeMV3ServiceWorkerLifecycleCoordinator {
        let state = ChromeMV3ServiceWorkerLifecycleStateSnapshot.blocked(
            extensionID: extensionID,
            profileID: profileID,
            serviceWorkerScriptDeclared: serviceWorkerScriptDeclared,
            objectAcceptedByWebKit: objectAcceptedByWebKit
        )
        var coordinator = ChromeMV3ServiceWorkerLifecycleCoordinator(
            lifecycleState: state
        )
        coordinator.record(
            .idleReleaseModeled,
            eventID: nil,
            message: "Idle release policy is modeled without scheduling."
        )
        coordinator.record(
            .hardTimeoutModeled,
            eventID: nil,
            message: "Hard timeout policy is modeled without scheduling."
        )
        coordinator.record(
            .permanentBackgroundRejected,
            eventID: nil,
            message: "Permanent background execution is rejected."
        )
        return coordinator
    }

    func wakePreflight(
        request: ChromeMV3ServiceWorkerWakeRequest
    ) -> ChromeMV3ServiceWorkerWakePreflight {
        ChromeMV3ServiceWorkerWakePreflight.evaluate(
            request: request,
            lifecycleState: lifecycleState
        )
    }

    mutating func enqueueModeledEvent(
        preflight: ChromeMV3ServiceWorkerWakePreflight,
        payloadSummary: String
    ) -> ChromeMV3ServiceWorkerPendingEvent {
        record(
            .wakeRequested,
            eventID: preflight.request.eventID,
            message: "Wake requested for \(preflight.request.reason.rawValue).",
            blockers: preflight.blockers
        )
        record(
            .wakeBlocked,
            eventID: preflight.request.eventID,
            message: "Wake blocked; event stays model-only.",
            blockers: preflight.blockers
        )
        let event = pendingEventQueue.enqueue(
            preflight: preflight,
            payloadSummary: payloadSummary
        )
        record(
            .eventQueuedInModelOnly,
            eventID: event.eventID,
            message: "Pending event queued without dispatch.",
            blockers: preflight.blockers
        )
        return event
    }

    mutating func record(
        _ kind: ChromeMV3ServiceWorkerLifecycleDiagnosticKind,
        eventID: String?,
        message: String,
        blockers: [ChromeMV3ServiceWorkerWakeBlocker] = []
    ) {
        diagnostics.append(
            ChromeMV3ServiceWorkerLifecycleDiagnostic(
                sequence: nextDiagnosticSequence,
                kind: kind,
                eventID: eventID,
                message: message,
                blockers: uniqueSortedBlockers(blockers)
            )
        )
        diagnostics.sort { $0.sequence < $1.sequence }
        nextDiagnosticSequence += 1
    }

    func keepaliveSource(
        kind: ChromeMV3ServiceWorkerKeepaliveSourceKind,
        sourceSeed: String? = nil
    ) -> ChromeMV3ServiceWorkerKeepaliveSource {
        ChromeMV3ServiceWorkerKeepaliveSource.make(
            kind: kind,
            extensionID: lifecycleState.extensionID,
            profileID: lifecycleState.profileID,
            sourceSeed: sourceSeed
        )
    }
}

struct ChromeMV3ServiceWorkerIntegrationSummary:
    Codable,
    Equatable,
    Sendable
{
    var messagingRoutesReferenceWakePreflight: Bool
    var listenerResolutionReferencesLifecycle: Bool
    var storageOnChangedReferencesWakePreflight: Bool
    var permissionEventsReferenceWakePreflight: Bool
    var portLifecycleReferencesKeepalivePolicy: Bool
    var dispatchImplementedNow: Bool
    var diagnostics: [String]
}

struct ChromeMV3PasswordManagerServiceWorkerSummary:
    Codable,
    Equatable,
    Sendable
{
    var contentScriptMessageRequiresServiceWorkerWake: Bool
    var popupMessageRequiresServiceWorkerWake: Bool
    var storageOnChangedMayRequireServiceWorkerWake: Bool
    var nativeMessagingPortWouldAffectKeepaliveButBlocked: Bool
    var runtimePortKeepaliveImplemented: Bool
    var idleUnloadPolicyModeledButNotActive: Bool
    var passwordManagerServiceWorkerReady: Bool
    var passwordManagerServiceWorkerReadyInFixture: Bool
    var blockers: [String]
}

struct ChromeMV3ServiceWorkerLifecycleReportSummary:
    Codable,
    Equatable,
    Sendable
{
    var reportID: String
    var reportFileName: String
    var lifecycleState: ChromeMV3ServiceWorkerLifecycleState
    var wakeReasonsModeled: [ChromeMV3ServiceWorkerWakeReason]
    var pendingEventCount: Int
    var canWakeServiceWorkerNow: Bool
    var canDispatchEventsNow: Bool
    var canOpenPortNow: Bool
    var canLoadContextNow: Bool
    var runtimeLoadable: Bool
    var passwordManagerServiceWorkerReady: Bool
    var serviceWorkerLifecycleAvailableInInternalFixture: Bool
    var serviceWorkerWakeAvailableInProduct: Bool
    var serviceWorkerPermanentBackgroundAvailable: Bool
    var nativePortKeepaliveAvailableInFixture: Bool
    var passwordManagerServiceWorkerReadyInFixture: Bool
    var passwordManagerProductRuntimeReady: Bool
}

struct ChromeMV3ServiceWorkerLifecycleReport:
    Codable,
    Equatable,
    Sendable
{
    var schemaVersion: Int
    var id: String
    var reportFileName: String
    var extensionID: String
    var profileID: String
    var lifecycleStateSummary:
        ChromeMV3ServiceWorkerLifecycleStateSnapshot
    var internalLifecycleSnapshot:
        ChromeMV3ServiceWorkerInternalLifecycleSnapshot
    var wakeRequestCoverage: [ChromeMV3ServiceWorkerWakeRequest]
    var wakePreflightCoverage: [ChromeMV3ServiceWorkerWakePreflight]
    var pendingEventQueueSnapshot:
        ChromeMV3ServiceWorkerPendingEventQueueSnapshot
    var idleAndTimeoutPolicy: ChromeMV3ServiceWorkerLifecyclePolicySet
    var keepalivePolicy: [ChromeMV3ServiceWorkerKeepaliveSource]
    var nativeMessagingPortBlocker:
        ChromeMV3ServiceWorkerNativeMessagingPortPolicy
    var alarmWakePlaceholder: ChromeMV3ServiceWorkerAlarmWakePolicy
    var lifecycleDiagnostics:
        [ChromeMV3ServiceWorkerLifecycleDiagnostic]
    var integrationSummary: ChromeMV3ServiceWorkerIntegrationSummary
    var messagingReportSummary:
        ChromeMV3RuntimeMessagingContractReportSummary? = nil
    var listenerReportSummary:
        ChromeMV3RuntimeListenerContractReportSummary? = nil
    var storageBrokerReadinessReportSummary:
        ChromeMV3StorageBrokerReadinessReportSummary? = nil
    var storageAPIOperationsReportSummary:
        ChromeMV3StorageAPIOperationsReportSummary? = nil
    var permissionBrokerReadinessReportSummary:
        ChromeMV3PermissionBrokerReadinessReportSummary? = nil
    var permissionLifecycleReportSummary:
        ChromeMV3PermissionLifecycleReportSummary? = nil
    var permissionsAPIContractReportSummary:
        ChromeMV3PermissionsAPIContractReportSummary? = nil
    var passwordManagerServiceWorkerSummary:
        ChromeMV3PasswordManagerServiceWorkerSummary
    var canWakeServiceWorkerNow: Bool
    var canDispatchEventsNow: Bool
    var canOpenPortNow: Bool
    var canLoadContextNow: Bool
    var runtimeLoadable: Bool
    var serviceWorkerLifecycleAvailableInInternalFixture: Bool
    var serviceWorkerWakeAvailableInProduct: Bool
    var serviceWorkerPermanentBackgroundAvailable: Bool
    var nativePortKeepaliveAvailableInFixture: Bool
    var passwordManagerServiceWorkerReadyInFixture: Bool
    var passwordManagerProductRuntimeReady: Bool
    var documentationSources: [ChromeMV3ManifestRewritePreviewSource]
    var diagnostics: [String]
    var blockers: [String]

    var summary: ChromeMV3ServiceWorkerLifecycleReportSummary {
        ChromeMV3ServiceWorkerLifecycleReportSummary(
            reportID: id,
            reportFileName: reportFileName,
            lifecycleState: lifecycleStateSummary.state,
            wakeReasonsModeled: wakeRequestCoverage.map(\.reason).uniqueSorted(),
            pendingEventCount:
                pendingEventQueueSnapshot.events.count,
            canWakeServiceWorkerNow: false,
            canDispatchEventsNow: false,
            canOpenPortNow: false,
            canLoadContextNow: false,
            runtimeLoadable: false,
            passwordManagerServiceWorkerReady:
                passwordManagerServiceWorkerReadyInFixture,
            serviceWorkerLifecycleAvailableInInternalFixture:
                serviceWorkerLifecycleAvailableInInternalFixture,
            serviceWorkerWakeAvailableInProduct: false,
            serviceWorkerPermanentBackgroundAvailable: false,
            nativePortKeepaliveAvailableInFixture:
                nativePortKeepaliveAvailableInFixture,
            passwordManagerServiceWorkerReadyInFixture:
                passwordManagerServiceWorkerReadyInFixture,
            passwordManagerProductRuntimeReady: false
        )
    }
}

enum ChromeMV3ServiceWorkerLifecycleReportWriter {
    static let reportFileName = "runtime-service-worker-lifecycle-report.json"

    @discardableResult
    static func write(
        _ report: ChromeMV3ServiceWorkerLifecycleReport,
        toRewrittenBundleRoot rootURL: URL
    ) throws -> ChromeMV3ServiceWorkerLifecycleReport {
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

enum ChromeMV3ServiceWorkerLifecycleReportGenerator {
    static func makeReport(
        prerequisitesReport prerequisites:
            ChromeMV3RuntimeBridgePrerequisitesReport,
        profileID: String = "diagnostic-profile",
        messagingReportSummary:
            ChromeMV3RuntimeMessagingContractReportSummary? = nil,
        listenerReportSummary:
            ChromeMV3RuntimeListenerContractReportSummary? = nil,
        storageBrokerReadinessReportSummary:
            ChromeMV3StorageBrokerReadinessReportSummary? = nil,
        storageAPIOperationsReportSummary:
            ChromeMV3StorageAPIOperationsReportSummary? = nil,
        permissionBrokerReadinessReportSummary:
            ChromeMV3PermissionBrokerReadinessReportSummary? = nil,
        permissionLifecycleReportSummary:
            ChromeMV3PermissionLifecycleReportSummary? = nil,
        permissionsAPIContractReportSummary:
            ChromeMV3PermissionsAPIContractReportSummary? = nil
    ) -> ChromeMV3ServiceWorkerLifecycleReport {
        let objectAccepted =
            prerequisites.contextReadinessConsumerDiagnostic.state == .ready
        return makeReport(
            extensionID: prerequisites.candidateID,
            profileID: profileID,
            serviceWorkerScriptDeclared:
                prerequisites.manifestFacts.backgroundServiceWorkerPresent,
            objectAcceptedByWebKit: objectAccepted,
            passwordManagerLikeFixtureDetected:
                prerequisites.passwordManagerPrerequisiteSummary
                .contentScriptsPresent
                    || prerequisites.passwordManagerPrerequisiteSummary
                    .actionPopupPresent
                    || prerequisites.passwordManagerPrerequisiteSummary
                    .nativeMessagingPermissionPresent,
            storagePermissionDetected:
                prerequisites.passwordManagerPrerequisiteSummary
                .storagePermissionPresent
                    || prerequisites.manifestFacts.storagePermissionPresent,
            nativeMessagingDetected:
                prerequisites.nativeMessagingPrerequisites
                .nativeMessagingDetected
                    || prerequisites.passwordManagerPrerequisiteSummary
                    .nativeMessagingPermissionPresent,
            messagingReportSummary: messagingReportSummary,
            listenerReportSummary: listenerReportSummary,
            storageBrokerReadinessReportSummary:
                storageBrokerReadinessReportSummary,
            storageAPIOperationsReportSummary:
                storageAPIOperationsReportSummary,
            permissionBrokerReadinessReportSummary:
                permissionBrokerReadinessReportSummary,
            permissionLifecycleReportSummary:
                permissionLifecycleReportSummary,
            permissionsAPIContractReportSummary:
                permissionsAPIContractReportSummary
        )
    }

    static func makeReport(
        extensionID: String,
        profileID: String,
        serviceWorkerScriptDeclared: Bool = true,
        objectAcceptedByWebKit: Bool = false,
        passwordManagerLikeFixtureDetected: Bool = false,
        storagePermissionDetected: Bool = false,
        nativeMessagingDetected: Bool = false,
        messagingReportSummary:
            ChromeMV3RuntimeMessagingContractReportSummary? = nil,
        listenerReportSummary:
            ChromeMV3RuntimeListenerContractReportSummary? = nil,
        storageBrokerReadinessReportSummary:
            ChromeMV3StorageBrokerReadinessReportSummary? = nil,
        storageAPIOperationsReportSummary:
            ChromeMV3StorageAPIOperationsReportSummary? = nil,
        permissionBrokerReadinessReportSummary:
            ChromeMV3PermissionBrokerReadinessReportSummary? = nil,
        permissionLifecycleReportSummary:
            ChromeMV3PermissionLifecycleReportSummary? = nil,
        permissionsAPIContractReportSummary:
            ChromeMV3PermissionsAPIContractReportSummary? = nil
    ) -> ChromeMV3ServiceWorkerLifecycleReport {
        var coordinator = ChromeMV3ServiceWorkerLifecycleCoordinator.blocked(
            extensionID: extensionID,
            profileID: profileID,
            serviceWorkerScriptDeclared: serviceWorkerScriptDeclared,
            objectAcceptedByWebKit: objectAcceptedByWebKit
        )
        let requests = wakeRequests(
            extensionID: coordinator.lifecycleState.extensionID,
            profileID: coordinator.lifecycleState.profileID
        )
        let preflights = requests.map(coordinator.wakePreflight)
        for preflight in preflights.prefix(4) {
            _ = coordinator.enqueueModeledEvent(
                preflight: preflight,
                payloadSummary: "report coverage \(preflight.request.reason.rawValue)"
            )
        }
        coordinator.record(
            .nativeMessagingKeepaliveBlocked,
            eventID: nil,
            message: "Native messaging keepalive policy is blocked.",
            blockers: [.nativeMessagingBlocked]
        )
        coordinator.record(
            .alarmWakePlaceholder,
            eventID: nil,
            message: "Alarm wake policy is a placeholder only."
        )
        coordinator.record(
            .extensionDisabledCleanupRequired,
            eventID: nil,
            message: "Disabled extension cleanup requires no worker wake."
        )
        let internalLifecycle = internalFixtureLifecycleSnapshot(
            extensionID: coordinator.lifecycleState.extensionID,
            profileID: coordinator.lifecycleState.profileID,
            passwordManagerLikeFixtureDetected:
                passwordManagerLikeFixtureDetected,
            nativeMessagingDetected: nativeMessagingDetected
        )
        let keepalive = ChromeMV3ServiceWorkerKeepaliveSource.allModeled(
            extensionID: coordinator.lifecycleState.extensionID,
            profileID: coordinator.lifecycleState.profileID
        )
        let password = passwordManagerSummary(
            fixtureDetected: passwordManagerLikeFixtureDetected,
            storagePermissionDetected: storagePermissionDetected,
            nativeMessagingDetected: nativeMessagingDetected,
            internalLifecycle: internalLifecycle
        )
        let blockers = uniqueSorted(
            coordinator.lifecycleState.blockers
                + requests.flatMap { $0.diagnosticMessages }
                + keepalive.flatMap(\.blockers)
                + coordinator.policies.nativeMessagingPort.blockers
                + password.blockers
        )
        let reportID = stableID(
            prefix: "runtime-service-worker-lifecycle",
            parts: [
                coordinator.lifecycleState.profileID,
                coordinator.lifecycleState.extensionID,
                serviceWorkerScriptDeclared.description,
                objectAcceptedByWebKit.description,
                passwordManagerLikeFixtureDetected.description,
            ]
        )

        return ChromeMV3ServiceWorkerLifecycleReport(
            schemaVersion: 1,
            id: reportID,
            reportFileName:
                ChromeMV3ServiceWorkerLifecycleReportWriter.reportFileName,
            extensionID: coordinator.lifecycleState.extensionID,
            profileID: coordinator.lifecycleState.profileID,
            lifecycleStateSummary: coordinator.lifecycleState,
            internalLifecycleSnapshot: internalLifecycle,
            wakeRequestCoverage: requests.sorted { $0.reason < $1.reason },
            wakePreflightCoverage:
                preflights.sorted { $0.request.reason < $1.request.reason },
            pendingEventQueueSnapshot:
                coordinator.pendingEventQueue.snapshot(),
            idleAndTimeoutPolicy: coordinator.policies,
            keepalivePolicy: keepalive,
            nativeMessagingPortBlocker:
                coordinator.policies.nativeMessagingPort,
            alarmWakePlaceholder: coordinator.policies.alarmWake,
            lifecycleDiagnostics: coordinator.diagnostics,
            integrationSummary: ChromeMV3ServiceWorkerIntegrationSummary(
                messagingRoutesReferenceWakePreflight: true,
                listenerResolutionReferencesLifecycle: true,
                storageOnChangedReferencesWakePreflight: true,
                permissionEventsReferenceWakePreflight: true,
                portLifecycleReferencesKeepalivePolicy: true,
                dispatchImplementedNow:
                    internalLifecycle.dispatchedEventCount > 0,
                diagnostics: [
                    "Messaging routes can carry wake preflight diagnostics.",
                    "Listener resolution can reference lifecycle availability.",
                    "storage.onChanged payloads can carry wake preflight diagnostics.",
                    "chrome.permissions events can carry wake preflight diagnostics.",
                    "Port contracts can carry keepalive source diagnostics.",
                    "Internal fixture dispatch is implemented through synthetic/model listener boundaries.",
                ]
            ),
            messagingReportSummary: messagingReportSummary,
            listenerReportSummary: listenerReportSummary,
            storageBrokerReadinessReportSummary:
                storageBrokerReadinessReportSummary,
            storageAPIOperationsReportSummary:
                storageAPIOperationsReportSummary,
            permissionBrokerReadinessReportSummary:
                permissionBrokerReadinessReportSummary,
            permissionLifecycleReportSummary:
                permissionLifecycleReportSummary,
            permissionsAPIContractReportSummary:
                permissionsAPIContractReportSummary,
            passwordManagerServiceWorkerSummary: password,
            canWakeServiceWorkerNow: false,
            canDispatchEventsNow: false,
            canOpenPortNow: false,
            canLoadContextNow: false,
            runtimeLoadable: false,
            serviceWorkerLifecycleAvailableInInternalFixture:
                internalLifecycle
                .serviceWorkerLifecycleAvailableInInternalFixture,
            serviceWorkerWakeAvailableInProduct: false,
            serviceWorkerPermanentBackgroundAvailable: false,
            nativePortKeepaliveAvailableInFixture:
                internalLifecycle.nativePortKeepaliveAvailableInFixture,
            passwordManagerServiceWorkerReadyInFixture:
                password.passwordManagerServiceWorkerReadyInFixture,
            passwordManagerProductRuntimeReady: false,
            documentationSources: documentationSources(),
            diagnostics: [
                "Service-worker lifecycle coordinator keeps product wake unavailable.",
                "Internal lifecycle fixture owner records controlled wakes, queue dispatch, keepalive, idle release, and hard-timeout results.",
                "Synthetic/model dispatch is not product service-worker execution.",
                "Context loading remains blocked.",
                "Runtime support is not claimed.",
            ],
            blockers: blockers
        )
    }

    static func makeReport(
        loadingPrerequisitesReportFrom rootURL: URL,
        fileManager: FileManager = .default
    ) throws -> ChromeMV3ServiceWorkerLifecycleReport {
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

    private static func wakeRequests(
        extensionID: String,
        profileID: String
    ) -> [ChromeMV3ServiceWorkerWakeRequest] {
        [
            .make(
                extensionID: extensionID,
                profileID: profileID,
                reason: .runtimeMessage,
                sourceContext: .contentScript,
                targetListenerSurface: .runtimeOnMessageServiceWorker,
                eventSeed: "runtime-message",
                requiresPermissionOrActiveTab: true
            ),
            .make(
                extensionID: extensionID,
                profileID: profileID,
                reason: .runtimeConnect,
                sourceContext: .contentScript,
                targetListenerSurface: .runtimeOnConnectServiceWorker,
                eventSeed: "runtime-connect",
                requiresPermissionOrActiveTab: true
            ),
            .make(
                extensionID: extensionID,
                profileID: profileID,
                reason: .tabsMessage,
                sourceContext: .serviceWorker,
                targetListenerSurface: .tabsMessageContentScript,
                eventSeed: "tabs-message",
                requiresPermissionOrActiveTab: true
            ),
            .make(
                extensionID: extensionID,
                profileID: profileID,
                reason: .tabsConnect,
                sourceContext: .serviceWorker,
                targetListenerSurface: .tabsConnectContentScript,
                eventSeed: "tabs-connect",
                requiresPermissionOrActiveTab: true
            ),
            .storageChanged(
                extensionID: extensionID,
                profileID: profileID,
                areaName: "local",
                changedKeys: ["example"]
            ),
            .permissionsChanged(
                extensionID: extensionID,
                profileID: profileID,
                eventKind: .onAdded
            ),
            .make(
                extensionID: extensionID,
                profileID: profileID,
                reason: .actionPopupEvent,
                sourceContext: .actionPopup,
                targetListenerSurface: .serviceWorkerLifecycleEventListener,
                eventSeed: "action-popup-event"
            ),
            .make(
                extensionID: extensionID,
                profileID: profileID,
                reason: .alarmPlaceholder,
                sourceContext: .serviceWorker,
                targetListenerSurface: .serviceWorkerLifecycleEventListener,
                eventSeed: "alarm-placeholder"
            ),
            .nativeMessagingConnect(
                extensionID: extensionID,
                profileID: profileID
            ),
            .make(
                extensionID: extensionID,
                profileID: profileID,
                reason: .nativeMessagingMessage,
                sourceContext: .serviceWorker,
                targetListenerSurface: .nativeMessagingPortListener,
                eventSeed: "native-messaging-message"
            ),
            .make(
                extensionID: extensionID,
                profileID: profileID,
                reason: .installOrUpdateEvent,
                sourceContext: .serviceWorker,
                targetListenerSurface: .serviceWorkerLifecycleEventListener,
                eventSeed: "install-update"
            ),
            .make(
                extensionID: extensionID,
                profileID: profileID,
                reason: .testFixture,
                sourceContext: .unknown,
                targetListenerSurface: .serviceWorkerLifecycleEventListener,
                eventSeed: "test-fixture"
            ),
        ].sorted { $0.reason < $1.reason }
    }

    private static func passwordManagerSummary(
        fixtureDetected: Bool,
        storagePermissionDetected: Bool,
        nativeMessagingDetected: Bool,
        internalLifecycle: ChromeMV3ServiceWorkerInternalLifecycleSnapshot
    ) -> ChromeMV3PasswordManagerServiceWorkerSummary {
        let lifecycleReady =
            fixtureDetected
                && internalLifecycle
                    .serviceWorkerLifecycleAvailableInInternalFixture
                && internalLifecycle.wakeResults.contains {
                    $0.reason == .runtimeMessage && $0.wakeAccepted
                }
                && internalLifecycle.wakeResults.contains {
                    $0.reason == .storageChanged && $0.wakeAccepted
                }
                && internalLifecycle.wakeResults.contains {
                    $0.reason == .permissionsChanged && $0.wakeAccepted
                }
                && (nativeMessagingDetected == false
                    || internalLifecycle.wakeResults.contains {
                        $0.reason == .nativeMessagingConnect
                            && $0.wakeAccepted
                    })
        let blockers = uniqueSorted(
            [
                "Password-manager content script message requires service-worker wake.",
                "Password-manager popup message requires service-worker wake.",
                storagePermissionDetected
                    ? "storage.onChanged is routed through the internal lifecycle fixture."
                    : "storage.onChanged remains non-dispatchable.",
                nativeMessagingDetected
                    ? "Native messaging Port keepalive is recorded in the internal fixture."
                    : "Native messaging remains blocked when requested.",
                "Runtime Port keepalive is test-scoped in the internal fixture.",
                "Idle and hard-timeout policy require explicit fixture triggers.",
                lifecycleReady
                    ? "passwordManagerServiceWorkerReadyInFixture is true for synthetic lifecycle flow."
                    : "passwordManagerServiceWorkerReadyInFixture remains false.",
            ] + (fixtureDetected
                ? []
                : [
                    "No password-manager-like fixture was detected, but service-worker readiness remains false.",
                ])
        )
        return ChromeMV3PasswordManagerServiceWorkerSummary(
            contentScriptMessageRequiresServiceWorkerWake: true,
            popupMessageRequiresServiceWorkerWake: true,
            storageOnChangedMayRequireServiceWorkerWake: true,
            nativeMessagingPortWouldAffectKeepaliveButBlocked:
                nativeMessagingDetected
                    && internalLifecycle.nativePortKeepaliveAvailableInFixture
                    == false,
            runtimePortKeepaliveImplemented:
                internalLifecycle.allKeepaliveRecords.contains {
                    $0.kind == .runtimePort
                },
            idleUnloadPolicyModeledButNotActive: false,
            passwordManagerServiceWorkerReady: lifecycleReady,
            passwordManagerServiceWorkerReadyInFixture: lifecycleReady,
            blockers: blockers
        )
    }

    private static func internalFixtureLifecycleSnapshot(
        extensionID: String,
        profileID: String,
        passwordManagerLikeFixtureDetected: Bool,
        nativeMessagingDetected: Bool
    ) -> ChromeMV3ServiceWorkerInternalLifecycleSnapshot {
        let owner = ChromeMV3ServiceWorkerInternalLifecycleRuntimeOwner(
            configuration: .internalFixture(
                extensionID: extensionID,
                profileID: profileID,
                nativePortKeepaliveAvailableInFixture: true
            )
        )
        owner.registerListener(
            event: .runtimeOnMessage,
            listenerID: "runtime-on-message"
        )
        owner.registerListener(
            event: .runtimeOnConnect,
            listenerID: "runtime-on-connect"
        )
        owner.registerListener(
            event: .storageOnChanged,
            listenerID: "storage-on-changed"
        )
        owner.registerListener(
            event: .permissionsOnAdded,
            listenerID: "permissions-on-added"
        )
        owner.registerListener(
            event: .permissionsOnRemoved,
            listenerID: "permissions-on-removed"
        )
        owner.registerListener(
            event: .nativePortOnMessage,
            listenerID: "native-port-on-message"
        )
        owner.registerListener(
            event: .nativePortOnDisconnect,
            listenerID: "native-port-on-disconnect"
        )
        owner.registerListener(
            event: .alarmsOnAlarm,
            listenerID: "alarms-on-alarm"
        )
        owner.registerListener(
            event: .actionPopupEvent,
            listenerID: "action-popup-event"
        )
        owner.registerListener(
            event: .testFixture,
            listenerID: "test-fixture"
        )

        _ = owner.requestWake(
            reason: .runtimeMessage,
            payload: .object(["type": .string("passwordManagerLookup")]),
            payloadSummary: "password manager runtime message",
            sourceContext: .contentScript
        )
        let runtimePort = owner.requestWake(
            reason: .runtimeConnect,
            payloadSummary: "password manager runtime Port",
            sourceContext: .contentScript,
            keepaliveKind: .runtimePort,
            portID: "password-manager-runtime-port"
        )
        if let keepaliveID = runtimePort.keepaliveRecord?.keepaliveID {
            _ = owner.disconnectKeepalive(
                keepaliveID: keepaliveID,
                reason: .reset
            )
        }
        _ = owner.requestWake(
            reason: .storageChanged,
            payload: .object(["areaName": .string("local")]),
            payloadSummary: "password manager storage.onChanged",
            sourceContext: .serviceWorker
        )
        _ = owner.requestWake(
            reason: .permissionsChanged,
            listenerEvent: .permissionsOnAdded,
            payload: .object(["permissions": .array([.string("storage")])]),
            payloadSummary: "password manager permissions.onAdded",
            sourceContext: .serviceWorker
        )
        if nativeMessagingDetected {
            let native = owner.requestWake(
                reason: .nativeMessagingConnect,
                listenerEvent: .nativePortOnMessage,
                payloadSummary: "password manager native Port connect",
                sourceContext: .serviceWorker,
                keepaliveKind: .nativeMessagingPort,
                portID: "password-manager-native-port"
            )
            if let keepaliveID = native.keepaliveRecord?.keepaliveID {
                _ = owner.disconnectKeepalive(
                    keepaliveID: keepaliveID,
                    reason: .reset
                )
            }
            _ = owner.requestWake(
                reason: .nativeMessagingMessage,
                listenerEvent: .nativePortOnMessage,
                payload: .object(["type": .string("nativeResponse")]),
                payloadSummary: "password manager native Port message",
                sourceContext: .serviceWorker
            )
        }
        _ = owner.requestWake(
            reason: .actionPopupEvent,
            listenerEvent: .actionPopupEvent,
            payloadSummary: "action popup event",
            sourceContext: .actionPopup
        )
        _ = owner.requestWake(
            reason: .alarmPlaceholder,
            listenerEvent: .alarmsOnAlarm,
            payloadSummary: "alarm placeholder",
            sourceContext: .serviceWorker
        )
        _ = owner.triggerIdleRelease()
        _ = owner.requestWake(
            reason: .testFixture,
            listenerEvent: .testFixture,
            payloadSummary:
                passwordManagerLikeFixtureDetected
                    ? "password manager lifecycle hard-timeout fixture"
                    : "generic lifecycle hard-timeout fixture",
            sourceContext: .unknown,
            keepaliveKind: .longRunningEvent
        )
        _ = owner.triggerHardTimeout()
        return owner.snapshot
    }

    private static func documentationSources()
        -> [ChromeMV3ManifestRewritePreviewSource]
    {
        [
            source(
                title: "Chrome extension service-worker lifecycle",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle",
                note: "Defines event-driven lifetime, idle shutdown, long request limits, Port lifetime changes, native messaging keepalive, and alarm minimum-period guidance."
            ),
            source(
                title: "Chrome service-worker events",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/events",
                note: "Defines top-level listener registration requirements for extension service-worker events."
            ),
            source(
                title: "Chrome message passing",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/messaging",
                note: "Defines one-time requests, runtime and tabs Port channels, Port lifetime, and native messaging references."
            ),
            source(
                title: "Chrome native messaging",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging",
                note: "Defines native messaging permission, native Port behavior, host launch semantics, and content script restrictions."
            ),
            source(
                title: "Chrome storage API",
                url: "https://developer.chrome.com/docs/extensions/reference/api/storage",
                note: "Defines storage access from extension service workers and storage.onChanged."
            ),
            source(
                title: "Chrome alarms API",
                url: "https://developer.chrome.com/docs/extensions/reference/api/alarms",
                note: "Defines alarm events, persistence caveats, and service-worker examples."
            ),
            ChromeMV3ManifestRewritePreviewSource(
                kind: .currentSumiCode,
                title: "Sumi runtime messaging, listener, storage, permission models",
                url: nil,
                note: "Current contracts are non-executing and keep runtimeLoadable false."
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

private extension Array where Element == ChromeMV3ServiceWorkerWakeReason {
    func uniqueSorted() -> [ChromeMV3ServiceWorkerWakeReason] {
        Array(Set(self)).sorted()
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

private func uniqueSortedBlockers(
    _ values: [ChromeMV3ServiceWorkerWakeBlocker]
) -> [ChromeMV3ServiceWorkerWakeBlocker] {
    Array(Set(values)).sorted()
}
