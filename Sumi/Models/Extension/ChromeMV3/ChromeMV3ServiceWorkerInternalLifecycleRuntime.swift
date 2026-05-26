//
//  ChromeMV3ServiceWorkerInternalLifecycleRuntime.swift
//  Sumi
//
//  DEBUG/internal synthetic Chrome MV3 service-worker lifecycle owner. This is
//  fixture state only: no WebKit context is created or loaded, no product
//  browsing event wakes a worker, no native host is launched here, and no
//  permanent background runtime is created.
//

import CryptoKit
import Foundation

enum ChromeMV3ServiceWorkerLifecycleExecutionScope:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case internalFixture
    case product

    static func < (
        lhs: ChromeMV3ServiceWorkerLifecycleExecutionScope,
        rhs: ChromeMV3ServiceWorkerLifecycleExecutionScope
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3ServiceWorkerInternalLifecycleState:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case blocked
    case failed
    case idleEligible
    case runningInSyntheticFixture
    case starting
    case stopped
    case stoppedAfterHardTimeout
    case stoppedAfterIdle
    case stopping
    case wakeRequested

    static func < (
        lhs: ChromeMV3ServiceWorkerInternalLifecycleState,
        rhs: ChromeMV3ServiceWorkerInternalLifecycleState
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3ServiceWorkerSyntheticListenerEvent:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case actionPopupEvent
    case alarmsOnAlarm
    case nativePortOnDisconnect
    case nativePortOnMessage
    case permissionsOnAdded
    case permissionsOnRemoved
    case runtimeOnConnect
    case runtimeOnMessage
    case storageOnChanged
    case tabsOnConnect
    case tabsOnMessage
    case testFixture

    static func < (
        lhs: ChromeMV3ServiceWorkerSyntheticListenerEvent,
        rhs: ChromeMV3ServiceWorkerSyntheticListenerEvent
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var listenerSurface: ChromeMV3RuntimeListenerSurfaceKind {
        switch self {
        case .runtimeOnMessage:
            return .runtimeOnMessageServiceWorker
        case .runtimeOnConnect:
            return .runtimeOnConnectServiceWorker
        case .tabsOnMessage:
            return .tabsMessageContentScript
        case .tabsOnConnect:
            return .tabsConnectContentScript
        case .nativePortOnMessage, .nativePortOnDisconnect:
            return .nativeMessagingPortListener
        case .actionPopupEvent, .alarmsOnAlarm, .permissionsOnAdded,
             .permissionsOnRemoved, .storageOnChanged, .testFixture:
            return .serviceWorkerLifecycleEventListener
        }
    }
}

enum ChromeMV3ServiceWorkerInternalEventStatus:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case blocked
    case dispatched
    case dropped
    case queued

    static func < (
        lhs: ChromeMV3ServiceWorkerInternalEventStatus,
        rhs: ChromeMV3ServiceWorkerInternalEventStatus
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3ServiceWorkerSyntheticListenerOutcomeKind:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case longRunningEvent
    case modeledError
    case modelDispatched
    case noResponse
    case pendingResponse

    static func < (
        lhs: ChromeMV3ServiceWorkerSyntheticListenerOutcomeKind,
        rhs: ChromeMV3ServiceWorkerSyntheticListenerOutcomeKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3ServiceWorkerSyntheticListenerOutcome:
    Codable,
    Equatable,
    Sendable
{
    var kind: ChromeMV3ServiceWorkerSyntheticListenerOutcomeKind
    var responsePayload: ChromeMV3StorageValue?
    var lastErrorMessage: String?
    var diagnostics: [String]

    static func modelDispatched(
        _ payload: ChromeMV3StorageValue? = .object(["ok": .bool(true)]),
        diagnostics: [String] = []
    ) -> ChromeMV3ServiceWorkerSyntheticListenerOutcome {
        ChromeMV3ServiceWorkerSyntheticListenerOutcome(
            kind: .modelDispatched,
            responsePayload: payload,
            lastErrorMessage: nil,
            diagnostics:
                uniqueSortedInternalLifecycle(
                    [
                        "Synthetic/model listener accepted the event.",
                        "No product JavaScript execution is implied.",
                    ] + diagnostics
                )
        )
    }

    static func noResponse(
        diagnostics: [String] = []
    ) -> ChromeMV3ServiceWorkerSyntheticListenerOutcome {
        ChromeMV3ServiceWorkerSyntheticListenerOutcome(
            kind: .noResponse,
            responsePayload: nil,
            lastErrorMessage: nil,
            diagnostics:
                uniqueSortedInternalLifecycle(
                    ["Synthetic/model listener returned no response."]
                        + diagnostics
                )
        )
    }

    static func pendingResponse(
        diagnostics: [String] = []
    ) -> ChromeMV3ServiceWorkerSyntheticListenerOutcome {
        ChromeMV3ServiceWorkerSyntheticListenerOutcome(
            kind: .pendingResponse,
            responsePayload: nil,
            lastErrorMessage: nil,
            diagnostics:
                uniqueSortedInternalLifecycle(
                    ["Synthetic/model listener left a pending response."]
                        + diagnostics
                )
        )
    }

    static func longRunningEvent(
        diagnostics: [String] = []
    ) -> ChromeMV3ServiceWorkerSyntheticListenerOutcome {
        ChromeMV3ServiceWorkerSyntheticListenerOutcome(
            kind: .longRunningEvent,
            responsePayload: nil,
            lastErrorMessage: nil,
            diagnostics:
                uniqueSortedInternalLifecycle(
                    ["Synthetic/model listener marked a long-running event."]
                        + diagnostics
                )
        )
    }

    static func modeledError(
        _ message: String,
        diagnostics: [String] = []
    ) -> ChromeMV3ServiceWorkerSyntheticListenerOutcome {
        ChromeMV3ServiceWorkerSyntheticListenerOutcome(
            kind: .modeledError,
            responsePayload: nil,
            lastErrorMessage: message,
            diagnostics:
                uniqueSortedInternalLifecycle(
                    ["Synthetic/model listener produced a deterministic error."]
                        + diagnostics
                )
        )
    }
}

struct ChromeMV3ServiceWorkerSyntheticListenerRegistration:
    Codable,
    Equatable,
    Sendable
{
    var listenerID: String
    var event: ChromeMV3ServiceWorkerSyntheticListenerEvent
    var extensionID: String
    var profileID: String
    var registeredSequence: Int
    var outcome: ChromeMV3ServiceWorkerSyntheticListenerOutcome
    var diagnostics: [String]
}

struct ChromeMV3ServiceWorkerSyntheticListenerRegistrySummary:
    Codable,
    Equatable,
    Sendable
{
    var extensionID: String
    var profileID: String
    var totalListenerCount: Int
    var listenerCountsByEvent: [String: Int]
    var registeredEvents: [ChromeMV3ServiceWorkerSyntheticListenerEvent]
    var registeredListenerIDs: [String]
    var listenerRegistryScopedToInternalFixture: Bool
    var productListenersRegistered: Bool
    var diagnostics: [String]
}

final class ChromeMV3ServiceWorkerSyntheticListenerRegistry {
    let extensionID: String
    let profileID: String
    private var registrations:
        [ChromeMV3ServiceWorkerSyntheticListenerEvent:
            [String: ChromeMV3ServiceWorkerSyntheticListenerRegistration]]
    private var nextSequence = 0

    init(extensionID: String, profileID: String) {
        self.extensionID = normalizedInternalLifecycle(
            extensionID,
            fallback: "synthetic-extension"
        )
        self.profileID = normalizedInternalLifecycle(
            profileID,
            fallback: "synthetic-profile"
        )
        self.registrations = [:]
    }

    @discardableResult
    func register(
        event: ChromeMV3ServiceWorkerSyntheticListenerEvent,
        listenerID: String,
        outcome: ChromeMV3ServiceWorkerSyntheticListenerOutcome =
            .modelDispatched()
    ) -> ChromeMV3ServiceWorkerSyntheticListenerRegistration {
        nextSequence += 1
        let normalizedListenerID = normalizedInternalLifecycle(
            listenerID,
            fallback:
                stableIDInternalLifecycle(
                    prefix: "sw-listener",
                    parts: [
                        profileID,
                        extensionID,
                        event.rawValue,
                        String(nextSequence),
                    ]
                )
        )
        let registration =
            ChromeMV3ServiceWorkerSyntheticListenerRegistration(
                listenerID: normalizedListenerID,
                event: event,
                extensionID: extensionID,
                profileID: profileID,
                registeredSequence: nextSequence,
                outcome: outcome,
                diagnostics:
                    uniqueSortedInternalLifecycle(
                        outcome.diagnostics
                            + [
                                "Listener registration is internal fixture state.",
                                "No product listener or WebKit service-worker listener is registered.",
                            ]
                    )
            )
        registrations[event, default: [:]][normalizedListenerID] =
            registration
        return registration
    }

    @discardableResult
    func remove(
        event: ChromeMV3ServiceWorkerSyntheticListenerEvent,
        listenerID: String
    ) -> Bool {
        registrations[event]?.removeValue(forKey: listenerID) != nil
    }

    func hasListeners(
        for event: ChromeMV3ServiceWorkerSyntheticListenerEvent
    ) -> Bool {
        registrations[event]?.isEmpty == false
    }

    func listeners(
        for event: ChromeMV3ServiceWorkerSyntheticListenerEvent
    ) -> [ChromeMV3ServiceWorkerSyntheticListenerRegistration] {
        Array(registrations[event]?.values ?? [:].values).sorted {
            if $0.registeredSequence != $1.registeredSequence {
                return $0.registeredSequence < $1.registeredSequence
            }
            return $0.listenerID < $1.listenerID
        }
    }

    func tearDown() {
        registrations.removeAll()
        nextSequence = 0
    }

    var summary: ChromeMV3ServiceWorkerSyntheticListenerRegistrySummary {
        let all = registrations.values.flatMap(\.values).sorted {
            if $0.event != $1.event {
                return $0.event < $1.event
            }
            return $0.listenerID < $1.listenerID
        }
        let counts = Dictionary(
            uniqueKeysWithValues:
                ChromeMV3ServiceWorkerSyntheticListenerEvent.allCases
                .compactMap { event in
                    let count = registrations[event]?.count ?? 0
                    return count > 0 ? (event.rawValue, count) : nil
                }
        )
        return ChromeMV3ServiceWorkerSyntheticListenerRegistrySummary(
            extensionID: extensionID,
            profileID: profileID,
            totalListenerCount: all.count,
            listenerCountsByEvent: counts,
            registeredEvents: all.map(\.event).uniqueSortedInternalLifecycle(),
            registeredListenerIDs:
                all.map(\.listenerID).uniqueSortedInternalLifecycle(),
            listenerRegistryScopedToInternalFixture: true,
            productListenersRegistered: false,
            diagnostics: [
                "Synthetic service-worker listener registry is profile and extension scoped.",
                "The registry records model listener availability only.",
            ]
        )
    }
}

enum ChromeMV3ServiceWorkerInternalKeepaliveKind:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case longRunningEvent
    case nativeMessagingPort
    case pendingResponse
    case runtimePort
    case tabsPort

    static func < (
        lhs: ChromeMV3ServiceWorkerInternalKeepaliveKind,
        rhs: ChromeMV3ServiceWorkerInternalKeepaliveKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3ServiceWorkerInternalStopReason:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case extensionDisabled
    case hardTimeout
    case idleRelease
    case profileClosed
    case reset

    static func < (
        lhs: ChromeMV3ServiceWorkerInternalStopReason,
        rhs: ChromeMV3ServiceWorkerInternalStopReason
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3ServiceWorkerInternalKeepaliveRecord:
    Codable,
    Equatable,
    Sendable
{
    var keepaliveID: String
    var kind: ChromeMV3ServiceWorkerInternalKeepaliveKind
    var extensionID: String
    var profileID: String
    var sessionID: String?
    var sourceEventID: String?
    var portID: String?
    var active: Bool
    var disconnected: Bool
    var disconnectReason: ChromeMV3ServiceWorkerInternalStopReason?
    var nativeHostLaunchOwnedElsewhere: Bool
    var nativeHostTerminationRequiredOnTeardown: Bool
    var diagnostics: [String]
}

struct ChromeMV3ServiceWorkerInternalEventEnvelope:
    Codable,
    Equatable,
    Sendable
{
    var sequence: Int
    var eventID: String
    var extensionID: String
    var profileID: String
    var sessionID: String?
    var reason: ChromeMV3ServiceWorkerWakeReason
    var listenerEvent: ChromeMV3ServiceWorkerSyntheticListenerEvent
    var listenerSurface: ChromeMV3RuntimeListenerSurfaceKind
    var sourceContext: ChromeMV3RuntimeMessagingContextKind
    var payloadSummary: String
    var payload: ChromeMV3StorageValue?
    var status: ChromeMV3ServiceWorkerInternalEventStatus
    var dispatchedListenerID: String?
    var outcome: ChromeMV3ServiceWorkerSyntheticListenerOutcome?
    var lastErrorMessage: String?
    var diagnostics: [String]
}

struct ChromeMV3ServiceWorkerInternalLifecycleTransition:
    Codable,
    Equatable,
    Sendable
{
    var sequence: Int
    var fromState: ChromeMV3ServiceWorkerInternalLifecycleState
    var toState: ChromeMV3ServiceWorkerInternalLifecycleState
    var reason: String
    var sessionID: String?
}

struct ChromeMV3ServiceWorkerInternalWakeResult:
    Codable,
    Equatable,
    Sendable
{
    var wakeID: String
    var eventID: String
    var extensionID: String
    var profileID: String
    var sessionID: String?
    var scope: ChromeMV3ServiceWorkerLifecycleExecutionScope
    var reason: ChromeMV3ServiceWorkerWakeReason
    var listenerEvent: ChromeMV3ServiceWorkerSyntheticListenerEvent
    var wakeAccepted: Bool
    var queued: Bool
    var dispatched: Bool
    var blocked: Bool
    var dropped: Bool
    var stateAfter: ChromeMV3ServiceWorkerInternalLifecycleState
    var lastErrorMessage: String?
    var keepaliveRecord: ChromeMV3ServiceWorkerInternalKeepaliveRecord?
    var diagnostics: [String]
    var blockers: [String]
}

struct ChromeMV3ServiceWorkerInternalLifecycleConfiguration:
    Codable,
    Equatable,
    Sendable
{
    var extensionID: String
    var profileID: String
    var moduleState: ChromeMV3ProfileHostModuleState
    var explicitInternalLifecycleAllowed: Bool
    var serviceWorkerLifecycleAvailableInInternalFixture: Bool
    var serviceWorkerWakeAvailableInProduct: Bool
    var serviceWorkerPermanentBackgroundAvailable: Bool
    var nativePortKeepaliveAvailableInFixture: Bool
    var runtimeLoadable: Bool
    var diagnostics: [String]

    static func internalFixture(
        extensionID: String = "synthetic-extension",
        profileID: String = "synthetic-profile",
        moduleState: ChromeMV3ProfileHostModuleState = .enabled,
        explicitInternalLifecycleAllowed: Bool = true,
        nativePortKeepaliveAvailableInFixture: Bool = true
    ) -> ChromeMV3ServiceWorkerInternalLifecycleConfiguration {
        let normalizedExtensionID = normalizedInternalLifecycle(
            extensionID,
            fallback: "synthetic-extension"
        )
        let normalizedProfileID = normalizedInternalLifecycle(
            profileID,
            fallback: "synthetic-profile"
        )
        let internalAvailable =
            moduleState == .enabled && explicitInternalLifecycleAllowed
        return ChromeMV3ServiceWorkerInternalLifecycleConfiguration(
            extensionID: normalizedExtensionID,
            profileID: normalizedProfileID,
            moduleState: moduleState,
            explicitInternalLifecycleAllowed:
                explicitInternalLifecycleAllowed,
            serviceWorkerLifecycleAvailableInInternalFixture:
                internalAvailable,
            serviceWorkerWakeAvailableInProduct: false,
            serviceWorkerPermanentBackgroundAvailable: false,
            nativePortKeepaliveAvailableInFixture:
                internalAvailable && nativePortKeepaliveAvailableInFixture,
            runtimeLoadable: false,
            diagnostics:
                uniqueSortedInternalLifecycle([
                    "Internal lifecycle fixture is explicit-gate and module-state controlled.",
                    "Product service-worker wake remains unavailable.",
                    "Permanent background runtime remains unavailable.",
                    "runtimeLoadable remains false.",
                ])
        )
    }
}

struct ChromeMV3ServiceWorkerInternalLifecycleSnapshot:
    Codable,
    Equatable,
    Sendable
{
    var extensionID: String
    var profileID: String
    var currentState: ChromeMV3ServiceWorkerInternalLifecycleState
    var currentSessionID: String?
    var sessionCount: Int
    var listenerRegistrySummary:
        ChromeMV3ServiceWorkerSyntheticListenerRegistrySummary
    var transitions: [ChromeMV3ServiceWorkerInternalLifecycleTransition]
    var wakeResults: [ChromeMV3ServiceWorkerInternalWakeResult]
    var events: [ChromeMV3ServiceWorkerInternalEventEnvelope]
    var queuedEventCount: Int
    var dispatchedEventCount: Int
    var blockedEventCount: Int
    var droppedEventCount: Int
    var activeKeepaliveRecords:
        [ChromeMV3ServiceWorkerInternalKeepaliveRecord]
    var allKeepaliveRecords:
        [ChromeMV3ServiceWorkerInternalKeepaliveRecord]
    var idleReleaseResults: [ChromeMV3ServiceWorkerInternalWakeResult]
    var hardTimeoutResults: [ChromeMV3ServiceWorkerInternalWakeResult]
    var serviceWorkerLifecycleAvailableInInternalFixture: Bool
    var serviceWorkerWakeAvailableInProduct: Bool
    var serviceWorkerPermanentBackgroundAvailable: Bool
    var nativePortKeepaliveAvailableInFixture: Bool
    var runtimeLoadable: Bool
    var diagnostics: [String]
}

final class ChromeMV3ServiceWorkerInternalLifecycleRuntimeOwner {
    let configuration:
        ChromeMV3ServiceWorkerInternalLifecycleConfiguration
    let listenerRegistry: ChromeMV3ServiceWorkerSyntheticListenerRegistry
    private(set) var state: ChromeMV3ServiceWorkerInternalLifecycleState =
        .stopped
    private(set) var currentSessionID: String?
    private var sessionSequence = 0
    private var nextEventSequence = 1
    private var nextTransitionSequence = 1
    private var transitions:
        [ChromeMV3ServiceWorkerInternalLifecycleTransition] = []
    private var wakeResults: [ChromeMV3ServiceWorkerInternalWakeResult] = []
    private var events: [ChromeMV3ServiceWorkerInternalEventEnvelope] = []
    private var keepalives:
        [String: ChromeMV3ServiceWorkerInternalKeepaliveRecord] = [:]
    private var idleReleaseResults:
        [ChromeMV3ServiceWorkerInternalWakeResult] = []
    private var hardTimeoutResults:
        [ChromeMV3ServiceWorkerInternalWakeResult] = []

    init(
        configuration:
            ChromeMV3ServiceWorkerInternalLifecycleConfiguration
    ) {
        self.configuration = configuration
        self.listenerRegistry =
            ChromeMV3ServiceWorkerSyntheticListenerRegistry(
                extensionID: configuration.extensionID,
                profileID: configuration.profileID
            )
        transition(to: .stopped, reason: "ownerInitialized")
    }

    var snapshot: ChromeMV3ServiceWorkerInternalLifecycleSnapshot {
        let sortedEvents = events.sorted { $0.sequence < $1.sequence }
        let allKeepalives = keepalives.values.sorted {
            $0.keepaliveID < $1.keepaliveID
        }
        return ChromeMV3ServiceWorkerInternalLifecycleSnapshot(
            extensionID: configuration.extensionID,
            profileID: configuration.profileID,
            currentState: state,
            currentSessionID: currentSessionID,
            sessionCount: sessionSequence,
            listenerRegistrySummary: listenerRegistry.summary,
            transitions: transitions.sorted { $0.sequence < $1.sequence },
            wakeResults: wakeResults,
            events: sortedEvents,
            queuedEventCount:
                sortedEvents.filter { $0.status == .queued }.count,
            dispatchedEventCount:
                sortedEvents.filter { $0.status == .dispatched }.count,
            blockedEventCount:
                sortedEvents.filter { $0.status == .blocked }.count,
            droppedEventCount:
                sortedEvents.filter { $0.status == .dropped }.count,
            activeKeepaliveRecords:
                allKeepalives.filter(\.active),
            allKeepaliveRecords: allKeepalives,
            idleReleaseResults: idleReleaseResults,
            hardTimeoutResults: hardTimeoutResults,
            serviceWorkerLifecycleAvailableInInternalFixture:
                configuration
                .serviceWorkerLifecycleAvailableInInternalFixture,
            serviceWorkerWakeAvailableInProduct: false,
            serviceWorkerPermanentBackgroundAvailable: false,
            nativePortKeepaliveAvailableInFixture:
                configuration.nativePortKeepaliveAvailableInFixture,
            runtimeLoadable: false,
            diagnostics:
                uniqueSortedInternalLifecycle(
                    configuration.diagnostics
                        + [
                            "Lifecycle owner uses explicit calls for wake, idle release, hard timeout, and teardown.",
                            "No scheduled background work is created.",
                        ]
                )
        )
    }

    @discardableResult
    func registerListener(
        event: ChromeMV3ServiceWorkerSyntheticListenerEvent,
        listenerID: String,
        outcome: ChromeMV3ServiceWorkerSyntheticListenerOutcome =
            .modelDispatched()
    ) -> ChromeMV3ServiceWorkerSyntheticListenerRegistration {
        listenerRegistry.register(
            event: event,
            listenerID: listenerID,
            outcome: outcome
        )
    }

    @discardableResult
    func requestWake(
        reason: ChromeMV3ServiceWorkerWakeReason,
        listenerEvent: ChromeMV3ServiceWorkerSyntheticListenerEvent? = nil,
        payload: ChromeMV3StorageValue? = nil,
        payloadSummary: String = "synthetic event",
        sourceContext: ChromeMV3RuntimeMessagingContextKind = .unknown,
        scope: ChromeMV3ServiceWorkerLifecycleExecutionScope =
            .internalFixture,
        extensionID: String? = nil,
        profileID: String? = nil,
        keepaliveKind: ChromeMV3ServiceWorkerInternalKeepaliveKind? = nil,
        portID: String? = nil
    ) -> ChromeMV3ServiceWorkerInternalWakeResult {
        let targetExtensionID = extensionID ?? configuration.extensionID
        let targetProfileID = profileID ?? configuration.profileID
        let event = listenerEvent ?? Self.defaultListenerEvent(for: reason)
        let eventID = stableIDInternalLifecycle(
            prefix: "sw-internal-event",
            parts: [
                targetProfileID,
                targetExtensionID,
                reason.rawValue,
                event.rawValue,
                payloadSummary,
                String(nextEventSequence),
            ]
        )
        let wakeID = stableIDInternalLifecycle(
            prefix: "sw-internal-wake",
            parts: [eventID, scope.rawValue]
        )

        var blockers: [String] = []
        if targetExtensionID != configuration.extensionID
            || targetProfileID != configuration.profileID
        {
            blockers.append("Wake namespace does not match owner namespace.")
        }
        if configuration.moduleState != .enabled {
            blockers.append("Extensions module is disabled.")
        }
        if configuration.explicitInternalLifecycleAllowed == false {
            blockers.append("Internal lifecycle fixture gate is disabled.")
        }
        if scope == .product {
            blockers.append("Product service-worker wake remains unavailable.")
        }
        if listenerRegistry.hasListeners(for: event) == false {
            blockers.append("No synthetic/model listener is registered.")
        }

        guard blockers.isEmpty else {
            transition(to: .blocked, reason: "wakeBlocked")
            let envelope = makeEnvelope(
                eventID: eventID,
                reason: reason,
                listenerEvent: event,
                sourceContext: sourceContext,
                payload: payload,
                payloadSummary: payloadSummary,
                status: .blocked,
                diagnostics: blockers
            )
            events.append(envelope)
            nextEventSequence += 1
            let result = makeWakeResult(
                wakeID: wakeID,
                eventID: eventID,
                reason: reason,
                listenerEvent: event,
                scope: scope,
                wakeAccepted: false,
                queued: false,
                dispatched: false,
                blocked: true,
                dropped: false,
                lastErrorMessage:
                    blockers.contains("No synthetic/model listener is registered.")
                    ? "Could not establish connection. Receiving end does not exist."
                    : blockers.first,
                keepaliveRecord: nil,
                diagnostics:
                    uniqueSortedInternalLifecycle(
                        blockers
                            + [
                                "Wake request was blocked before dispatch.",
                                "No product dispatch was attempted.",
                            ]
                    ),
                blockers: blockers
            )
            wakeResults.append(result)
            return result
        }

        ensureRunningSession(reason: reason.rawValue)
        var envelope = makeEnvelope(
            eventID: eventID,
            reason: reason,
            listenerEvent: event,
            sourceContext: sourceContext,
            payload: payload,
            payloadSummary: payloadSummary,
            status: .queued,
            diagnostics: ["Event queued at the internal fixture boundary."]
        )
        events.append(envelope)
        nextEventSequence += 1

        let listeners = listenerRegistry.listeners(for: event)
        let listener = listeners[0]
        envelope.status = .dispatched
        envelope.sessionID = currentSessionID
        envelope.dispatchedListenerID = listener.listenerID
        envelope.outcome = listener.outcome
        envelope.lastErrorMessage = listener.outcome.lastErrorMessage
        envelope.diagnostics =
            uniqueSortedInternalLifecycle(
                envelope.diagnostics
                    + listener.diagnostics
                    + [
                        "Event crossed the controlled synthetic/model dispatch boundary.",
                    ]
            )
        updateEvent(envelope)

        var keepalive = keepaliveKind.map {
            makeKeepalive(
                kind: $0,
                sourceEventID: eventID,
                portID: portID
            )
        }
        if keepalive == nil, listener.outcome.kind == .pendingResponse {
            keepalive = makeKeepalive(
                kind: .pendingResponse,
                sourceEventID: eventID,
                portID: nil
            )
        } else if keepalive == nil,
                  listener.outcome.kind == .longRunningEvent
        {
            keepalive = makeKeepalive(
                kind: .longRunningEvent,
                sourceEventID: eventID,
                portID: nil
            )
        }
        if let keepalive {
            keepalives[keepalive.keepaliveID] = keepalive
        }
        markIdleEligibleIfReady()

        let result = makeWakeResult(
            wakeID: wakeID,
            eventID: eventID,
            reason: reason,
            listenerEvent: event,
            scope: scope,
            wakeAccepted: true,
            queued: true,
            dispatched: true,
            blocked: false,
            dropped: false,
            lastErrorMessage: listener.outcome.lastErrorMessage,
            keepaliveRecord: keepalive,
            diagnostics:
                uniqueSortedInternalLifecycle(
                    listener.outcome.diagnostics
                        + [
                            "Wake accepted in internal fixture scope.",
                            "Event was model-dispatched; Chrome parity is not claimed.",
                            "Product service-worker wake remains unavailable.",
                        ]
                ),
            blockers: []
        )
        wakeResults.append(result)
        return result
    }

    @discardableResult
    func disconnectKeepalive(
        keepaliveID: String? = nil,
        portID: String? = nil,
        reason: ChromeMV3ServiceWorkerInternalStopReason = .reset
    ) -> Bool {
        let match = keepalives.keys.sorted().first { key in
            guard let record = keepalives[key] else { return false }
            if let keepaliveID {
                return record.keepaliveID == keepaliveID
            }
            if let portID {
                return record.portID == portID
            }
            return false
        }
        guard let match, var record = keepalives[match] else {
            return false
        }
        record.active = false
        record.disconnected = true
        record.disconnectReason = reason
        record.nativeHostTerminationRequiredOnTeardown = false
        record.diagnostics =
            uniqueSortedInternalLifecycle(
                record.diagnostics
                    + ["Keepalive was disconnected by explicit fixture call."]
            )
        keepalives[match] = record
        markIdleEligibleIfReady()
        return true
    }

    @discardableResult
    func triggerIdleRelease(
        reason: String = "explicitIdleRelease"
    ) -> ChromeMV3ServiceWorkerInternalWakeResult {
        let eventID = stableIDInternalLifecycle(
            prefix: "sw-internal-idle",
            parts: [
                configuration.profileID,
                configuration.extensionID,
                currentSessionID ?? "no-session",
                reason,
                String(idleReleaseResults.count + 1),
            ]
        )
        let active = activeKeepalives()
        let blocked = active.isEmpty == false || state != .idleEligible
        if blocked {
            let result = makeWakeResult(
                wakeID: stableIDInternalLifecycle(
                    prefix: "sw-internal-idle-result",
                    parts: [eventID]
                ),
                eventID: eventID,
                reason: .testFixture,
                listenerEvent: .testFixture,
                scope: .internalFixture,
                wakeAccepted: false,
                queued: false,
                dispatched: false,
                blocked: true,
                dropped: false,
                lastErrorMessage:
                    "Idle release deferred; lifecycle is not eligible.",
                keepaliveRecord: nil,
                diagnostics:
                    uniqueSortedInternalLifecycle([
                        "Idle release requires empty queue and no active keepalive.",
                        "Idle release was explicitly triggered by the fixture.",
                    ]),
                blockers: active.map(\.keepaliveID)
            )
            idleReleaseResults.append(result)
            return result
        }

        transition(to: .stopping, reason: reason)
        disconnectAllKeepalives(reason: .idleRelease)
        currentSessionID = nil
        transition(to: .stoppedAfterIdle, reason: reason)
        let result = makeWakeResult(
            wakeID: stableIDInternalLifecycle(
                prefix: "sw-internal-idle-result",
                parts: [eventID]
            ),
            eventID: eventID,
            reason: .testFixture,
            listenerEvent: .testFixture,
            scope: .internalFixture,
            wakeAccepted: true,
            queued: false,
            dispatched: false,
            blocked: false,
            dropped: false,
            lastErrorMessage: nil,
            keepaliveRecord: nil,
            diagnostics: [
                "Idle release stopped the internal lifecycle after explicit fixture trigger.",
                "Static synthetic listener availability is retained for future controlled wake attempts.",
            ],
            blockers: []
        )
        idleReleaseResults.append(result)
        return result
    }

    @discardableResult
    func triggerHardTimeout(
        reason: String = "explicitHardTimeout"
    ) -> ChromeMV3ServiceWorkerInternalWakeResult {
        let eventID = stableIDInternalLifecycle(
            prefix: "sw-internal-hard-timeout",
            parts: [
                configuration.profileID,
                configuration.extensionID,
                currentSessionID ?? "no-session",
                reason,
                String(hardTimeoutResults.count + 1),
            ]
        )
        transition(to: .stopping, reason: reason)
        disconnectAllKeepalives(reason: .hardTimeout)
        events = events.map { event in
            guard event.status == .queued else { return event }
            var copy = event
            copy.status = .dropped
            copy.diagnostics =
                uniqueSortedInternalLifecycle(
                    copy.diagnostics
                        + [
                            "Queued event dropped by explicit hard-timeout trigger.",
                        ]
                )
            return copy
        }
        currentSessionID = nil
        transition(to: .stoppedAfterHardTimeout, reason: reason)
        let result = makeWakeResult(
            wakeID: stableIDInternalLifecycle(
                prefix: "sw-internal-hard-timeout-result",
                parts: [eventID]
            ),
            eventID: eventID,
            reason: .testFixture,
            listenerEvent: .testFixture,
            scope: .internalFixture,
            wakeAccepted: true,
            queued: false,
            dispatched: false,
            blocked: false,
            dropped: true,
            lastErrorMessage: nil,
            keepaliveRecord: nil,
            diagnostics: [
                "Hard-timeout trigger stopped the internal lifecycle even with keepalive state.",
                "Ports and native Port records were disconnected in fixture state.",
            ],
            blockers: []
        )
        hardTimeoutResults.append(result)
        return result
    }

    func tearDownForExtensionDisable() {
        tearDown(reason: .extensionDisabled)
    }

    func tearDownForProfileClose() {
        tearDown(reason: .profileClosed)
    }

    func reset() {
        tearDown(reason: .reset)
        transitions.removeAll()
        nextTransitionSequence = 1
        transition(to: .stopped, reason: "ownerReset")
    }

    private static func defaultListenerEvent(
        for reason: ChromeMV3ServiceWorkerWakeReason
    ) -> ChromeMV3ServiceWorkerSyntheticListenerEvent {
        switch reason {
        case .runtimeMessage:
            return .runtimeOnMessage
        case .runtimeConnect:
            return .runtimeOnConnect
        case .tabsMessage:
            return .tabsOnMessage
        case .tabsConnect:
            return .tabsOnConnect
        case .storageChanged:
            return .storageOnChanged
        case .permissionsChanged:
            return .permissionsOnAdded
        case .nativeMessagingConnect, .nativeMessagingMessage:
            return .nativePortOnMessage
        case .actionClicked, .actionPopupEvent:
            return .actionPopupEvent
        case .alarm, .alarmPlaceholder:
            return .alarmsOnAlarm
        case .installOrUpdateEvent, .testFixture:
            return .testFixture
        }
    }

    private func ensureRunningSession(reason: String) {
        switch state {
        case .runningInSyntheticFixture:
            return
        case .idleEligible:
            transition(to: .runningInSyntheticFixture, reason: reason)
        case .stopped, .stoppedAfterIdle, .stoppedAfterHardTimeout,
             .blocked, .failed:
            sessionSequence += 1
            currentSessionID = stableIDInternalLifecycle(
                prefix: "sw-session",
                parts: [
                    configuration.profileID,
                    configuration.extensionID,
                    String(sessionSequence),
                ]
            )
            transition(to: .wakeRequested, reason: reason)
            transition(to: .starting, reason: reason)
            transition(to: .runningInSyntheticFixture, reason: reason)
        case .wakeRequested, .starting, .stopping:
            transition(to: .runningInSyntheticFixture, reason: reason)
        }
    }

    private func transition(
        to newState: ChromeMV3ServiceWorkerInternalLifecycleState,
        reason: String
    ) {
        let transition = ChromeMV3ServiceWorkerInternalLifecycleTransition(
            sequence: nextTransitionSequence,
            fromState: state,
            toState: newState,
            reason: reason,
            sessionID: currentSessionID
        )
        transitions.append(transition)
        nextTransitionSequence += 1
        state = newState
    }

    private func makeEnvelope(
        eventID: String,
        reason: ChromeMV3ServiceWorkerWakeReason,
        listenerEvent: ChromeMV3ServiceWorkerSyntheticListenerEvent,
        sourceContext: ChromeMV3RuntimeMessagingContextKind,
        payload: ChromeMV3StorageValue?,
        payloadSummary: String,
        status: ChromeMV3ServiceWorkerInternalEventStatus,
        diagnostics: [String]
    ) -> ChromeMV3ServiceWorkerInternalEventEnvelope {
        ChromeMV3ServiceWorkerInternalEventEnvelope(
            sequence: nextEventSequence,
            eventID: eventID,
            extensionID: configuration.extensionID,
            profileID: configuration.profileID,
            sessionID: currentSessionID,
            reason: reason,
            listenerEvent: listenerEvent,
            listenerSurface: listenerEvent.listenerSurface,
            sourceContext: sourceContext,
            payloadSummary: payloadSummary,
            payload: payload,
            status: status,
            dispatchedListenerID: nil,
            outcome: nil,
            lastErrorMessage: nil,
            diagnostics: uniqueSortedInternalLifecycle(diagnostics)
        )
    }

    private func updateEvent(
        _ updated: ChromeMV3ServiceWorkerInternalEventEnvelope
    ) {
        events = events.map {
            $0.eventID == updated.eventID ? updated : $0
        }.sorted { $0.sequence < $1.sequence }
    }

    private func makeKeepalive(
        kind: ChromeMV3ServiceWorkerInternalKeepaliveKind,
        sourceEventID: String,
        portID: String?
    ) -> ChromeMV3ServiceWorkerInternalKeepaliveRecord {
        let keepaliveID = stableIDInternalLifecycle(
            prefix: "sw-keepalive",
            parts: [
                configuration.profileID,
                configuration.extensionID,
                currentSessionID ?? "no-session",
                kind.rawValue,
                sourceEventID,
                portID ?? "no-port",
            ]
        )
        return ChromeMV3ServiceWorkerInternalKeepaliveRecord(
            keepaliveID: keepaliveID,
            kind: kind,
            extensionID: configuration.extensionID,
            profileID: configuration.profileID,
            sessionID: currentSessionID,
            sourceEventID: sourceEventID,
            portID: portID,
            active: true,
            disconnected: false,
            disconnectReason: nil,
            nativeHostLaunchOwnedElsewhere: kind == .nativeMessagingPort,
            nativeHostTerminationRequiredOnTeardown:
                kind == .nativeMessagingPort,
            diagnostics:
                uniqueSortedInternalLifecycle([
                    "Keepalive record is scoped to the internal lifecycle fixture.",
                    kind == .nativeMessagingPort
                        ? "Native Port keepalive diagnostics are recorded without launching a host from lifecycle code."
                        : "Port/pending-response keepalive affects fixture idle eligibility.",
                ])
        )
    }

    private func makeWakeResult(
        wakeID: String,
        eventID: String,
        reason: ChromeMV3ServiceWorkerWakeReason,
        listenerEvent: ChromeMV3ServiceWorkerSyntheticListenerEvent,
        scope: ChromeMV3ServiceWorkerLifecycleExecutionScope,
        wakeAccepted: Bool,
        queued: Bool,
        dispatched: Bool,
        blocked: Bool,
        dropped: Bool,
        lastErrorMessage: String?,
        keepaliveRecord: ChromeMV3ServiceWorkerInternalKeepaliveRecord?,
        diagnostics: [String],
        blockers: [String]
    ) -> ChromeMV3ServiceWorkerInternalWakeResult {
        ChromeMV3ServiceWorkerInternalWakeResult(
            wakeID: wakeID,
            eventID: eventID,
            extensionID: configuration.extensionID,
            profileID: configuration.profileID,
            sessionID: currentSessionID,
            scope: scope,
            reason: reason,
            listenerEvent: listenerEvent,
            wakeAccepted: wakeAccepted,
            queued: queued,
            dispatched: dispatched,
            blocked: blocked,
            dropped: dropped,
            stateAfter: state,
            lastErrorMessage: lastErrorMessage,
            keepaliveRecord: keepaliveRecord,
            diagnostics: uniqueSortedInternalLifecycle(diagnostics),
            blockers: uniqueSortedInternalLifecycle(blockers)
        )
    }

    private func activeKeepalives()
        -> [ChromeMV3ServiceWorkerInternalKeepaliveRecord]
    {
        keepalives.values.filter(\.active).sorted {
            $0.keepaliveID < $1.keepaliveID
        }
    }

    private func markIdleEligibleIfReady() {
        guard activeKeepalives().isEmpty else { return }
        guard events.contains(where: { $0.status == .queued }) == false
        else { return }
        guard state == .runningInSyntheticFixture else { return }
        transition(to: .idleEligible, reason: "queueEmptyNoKeepalive")
    }

    private func disconnectAllKeepalives(
        reason: ChromeMV3ServiceWorkerInternalStopReason
    ) {
        for key in keepalives.keys {
            guard var record = keepalives[key], record.active else {
                continue
            }
            record.active = false
            record.disconnected = true
            record.disconnectReason = reason
            record.nativeHostTerminationRequiredOnTeardown = false
            record.diagnostics =
                uniqueSortedInternalLifecycle(
                    record.diagnostics
                        + [
                            "Keepalive was disconnected during lifecycle teardown.",
                        ]
                )
            keepalives[key] = record
        }
    }

    private func tearDown(reason: ChromeMV3ServiceWorkerInternalStopReason) {
        transition(to: .stopping, reason: reason.rawValue)
        disconnectAllKeepalives(reason: reason)
        keepalives.removeAll()
        events.removeAll()
        wakeResults.removeAll()
        idleReleaseResults.removeAll()
        hardTimeoutResults.removeAll()
        listenerRegistry.tearDown()
        currentSessionID = nil
        nextEventSequence = 1
        sessionSequence = 0
        transition(to: .stopped, reason: reason.rawValue)
    }
}

private extension Array
where Element == ChromeMV3ServiceWorkerSyntheticListenerEvent {
    func uniqueSortedInternalLifecycle()
        -> [ChromeMV3ServiceWorkerSyntheticListenerEvent]
    {
        Array(Set(self)).sorted()
    }
}

private extension Array where Element == String {
    func uniqueSortedInternalLifecycle() -> [String] {
        Array(Set(filter { $0.isEmpty == false })).sorted()
    }
}

private func normalizedInternalLifecycle(
    _ value: String,
    fallback: String
) -> String {
    value.isEmpty ? fallback : value
}

private func stableIDInternalLifecycle(
    prefix: String,
    parts: [String]
) -> String {
    let seed = parts.joined(separator: "|")
    return "\(prefix)-\(sha256HexInternalLifecycle(Data(seed.utf8)).prefix(32))"
}

private func sha256HexInternalLifecycle(_ data: Data) -> String {
    SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }
        .joined()
}

private func uniqueSortedInternalLifecycle(_ values: [String]) -> [String] {
    values.uniqueSortedInternalLifecycle()
}
