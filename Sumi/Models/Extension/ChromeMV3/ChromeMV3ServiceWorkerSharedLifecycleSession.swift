//
//  ChromeMV3ServiceWorkerSharedLifecycleSession.swift
//  Sumi
//
//  DEBUG/internal shared synthetic Chrome MV3 lifecycle session registry.
//  This is fixture state only: no WebKit context is created or loaded, no
//  product browsing event wakes a worker, no native host is launched here, and
//  no permanent background runtime is created.
//

import CryptoKit
import Foundation

enum ChromeMV3ServiceWorkerSharedLifecycleComponentKind:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case contentScriptSyntheticEndpoint
    case alarmsHarness
    case contextMenusHarness
    case extensionPageHostHarness
    case nativeMessagingFixtureRuntime
    case passwordManagerCombinedFixture
    case permissionsHarness
    case runtimeJSHarness
    case storageLocalHarness
    case tabsScriptingHarness
    case webNavigationHarness

    static func < (
        lhs: ChromeMV3ServiceWorkerSharedLifecycleComponentKind,
        rhs: ChromeMV3ServiceWorkerSharedLifecycleComponentKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3ServiceWorkerSharedLifecycleSessionKey:
    Hashable,
    Codable,
    Equatable,
    Sendable
{
    var profileID: String
    var extensionID: String
    var lifecycleSessionID: String

    static func make(
        profileID: String,
        extensionID: String,
        lifecycleSessionID: String? = nil
    ) -> ChromeMV3ServiceWorkerSharedLifecycleSessionKey {
        let normalizedProfileID = normalizedSharedLifecycle(
            profileID,
            fallback: "synthetic-profile"
        )
        let normalizedExtensionID = normalizedSharedLifecycle(
            extensionID,
            fallback: "synthetic-extension"
        )
        let sessionID =
            normalizedSharedLifecycle(
                lifecycleSessionID ?? "",
                fallback:
                    stableIDSharedLifecycle(
                        prefix: "sw-shared-session",
                        parts: [normalizedProfileID, normalizedExtensionID]
                    )
            )
        return ChromeMV3ServiceWorkerSharedLifecycleSessionKey(
            profileID: normalizedProfileID,
            extensionID: normalizedExtensionID,
            lifecycleSessionID: sessionID
        )
    }
}

struct ChromeMV3ServiceWorkerSharedLifecycleComponentRecord:
    Codable,
    Equatable,
    Sendable
{
    var componentID: String
    var componentKind: ChromeMV3ServiceWorkerSharedLifecycleComponentKind
    var attachedSessionID: String
    var extensionID: String
    var profileID: String
    var attachSequence: Int
    var eventSurfacesProvided: [ChromeMV3ServiceWorkerSyntheticListenerEvent]
    var keepaliveSourcesProvided:
        [ChromeMV3ServiceWorkerInternalKeepaliveKind]
    var detached: Bool
    var detachReason: ChromeMV3ServiceWorkerInternalStopReason?
    var diagnostics: [String]
}

struct ChromeMV3ServiceWorkerSharedLifecycleSessionSummary:
    Codable,
    Equatable,
    Sendable
{
    var sessionID: String
    var extensionID: String
    var profileID: String
    var attachedComponents:
        [ChromeMV3ServiceWorkerSharedLifecycleComponentRecord]
    var activeComponentIDs: [String]
    var detachedComponentIDs: [String]
    var listenerRegistrySummary:
        ChromeMV3ServiceWorkerSyntheticListenerRegistrySummary
    var lifecycleSnapshot: ChromeMV3ServiceWorkerInternalLifecycleSnapshot
    var sharedLifecycleSessionAvailableInInternalFixture: Bool
    var serviceWorkerWakeAvailableInProduct: Bool
    var serviceWorkerPermanentBackgroundAvailable: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
    var diagnostics: [String]
}

final class ChromeMV3ServiceWorkerSharedLifecycleSession {
    let key: ChromeMV3ServiceWorkerSharedLifecycleSessionKey
    let runtimeOwner: ChromeMV3ServiceWorkerInternalLifecycleRuntimeOwner
    private var componentRecords:
        [String: ChromeMV3ServiceWorkerSharedLifecycleComponentRecord] = [:]
    private var nextAttachSequence = 1

    init(
        key: ChromeMV3ServiceWorkerSharedLifecycleSessionKey,
        configuration:
            ChromeMV3ServiceWorkerInternalLifecycleConfiguration
    ) {
        self.key = key
        self.runtimeOwner =
            ChromeMV3ServiceWorkerInternalLifecycleRuntimeOwner(
                configuration: configuration
            )
    }

    @discardableResult
    func attachComponent(
        kind: ChromeMV3ServiceWorkerSharedLifecycleComponentKind,
        componentID: String,
        eventSurfaces:
            [ChromeMV3ServiceWorkerSyntheticListenerEvent] = [],
        keepaliveSources:
            [ChromeMV3ServiceWorkerInternalKeepaliveKind] = [],
        diagnostics: [String] = []
    ) -> ChromeMV3ServiceWorkerSharedLifecycleComponentRecord {
        let normalizedComponentID = normalizedSharedLifecycle(
            componentID,
            fallback:
                stableIDSharedLifecycle(
                    prefix: "sw-shared-component",
                    parts: [
                        key.profileID,
                        key.extensionID,
                        kind.rawValue,
                        String(nextAttachSequence),
                    ]
                )
        )
        let record =
            ChromeMV3ServiceWorkerSharedLifecycleComponentRecord(
                componentID: normalizedComponentID,
                componentKind: kind,
                attachedSessionID: key.lifecycleSessionID,
                extensionID: key.extensionID,
                profileID: key.profileID,
                attachSequence: nextAttachSequence,
                eventSurfacesProvided:
                    eventSurfaces.uniqueSortedSharedLifecycle(),
                keepaliveSourcesProvided:
                    keepaliveSources.uniqueSortedSharedLifecycle(),
                detached: false,
                detachReason: nil,
                diagnostics:
                    uniqueSortedSharedLifecycle(
                        diagnostics
                            + [
                                "Component attached to the shared internal lifecycle session.",
                                "Attachment is DEBUG/internal fixture state only.",
                            ]
                    )
            )
        nextAttachSequence += 1
        componentRecords[normalizedComponentID] = record
        return record
    }

    @discardableResult
    func detachComponent(
        componentID: String,
        reason: ChromeMV3ServiceWorkerInternalStopReason = .reset
    ) -> Bool {
        guard var record = componentRecords[componentID] else {
            return false
        }
        record.detached = true
        record.detachReason = reason
        record.diagnostics =
            uniqueSortedSharedLifecycle(
                record.diagnostics
                    + [
                        "Component detached from the shared internal lifecycle session.",
                    ]
            )
        componentRecords[componentID] = record
        return true
    }

    @discardableResult
    func registerListener(
        event: ChromeMV3ServiceWorkerSyntheticListenerEvent,
        listenerID: String,
        outcome: ChromeMV3ServiceWorkerSyntheticListenerOutcome =
            .modelDispatched()
    ) -> ChromeMV3ServiceWorkerSyntheticListenerRegistration {
        runtimeOwner.registerListener(
            event: event,
            listenerID: listenerID,
            outcome: outcome
        )
    }

    @discardableResult
    func routeEvent(
        reason: ChromeMV3ServiceWorkerWakeReason,
        listenerEvent: ChromeMV3ServiceWorkerSyntheticListenerEvent? = nil,
        sourceComponentID: String,
        sourceComponentKind:
            ChromeMV3ServiceWorkerSharedLifecycleComponentKind,
        payload: ChromeMV3StorageValue? = nil,
        payloadSummary: String = "shared synthetic event",
        sourceContext: ChromeMV3RuntimeMessagingContextKind = .unknown,
        keepaliveKind: ChromeMV3ServiceWorkerInternalKeepaliveKind? = nil,
        portID: String? = nil
    ) -> ChromeMV3ServiceWorkerInternalWakeResult {
        runtimeOwner.requestWake(
            reason: reason,
            listenerEvent: listenerEvent,
            payload: payload,
            payloadSummary: payloadSummary,
            sourceContext: sourceContext,
            keepaliveKind: keepaliveKind,
            portID: portID,
            sourceComponentID: sourceComponentID,
            sourceComponentKind: sourceComponentKind
        )
    }

    @discardableResult
    func disconnectKeepalive(
        keepaliveID: String? = nil,
        portID: String? = nil,
        reason: ChromeMV3ServiceWorkerInternalStopReason = .reset
    ) -> Bool {
        runtimeOwner.disconnectKeepalive(
            keepaliveID: keepaliveID,
            portID: portID,
            reason: reason
        )
    }

    @discardableResult
    func triggerIdleRelease(
        reason: String = "explicitSharedIdleRelease"
    ) -> ChromeMV3ServiceWorkerInternalWakeResult {
        runtimeOwner.triggerIdleRelease(reason: reason)
    }

    @discardableResult
    func triggerHardTimeout(
        reason: String = "explicitSharedHardTimeout"
    ) -> ChromeMV3ServiceWorkerInternalWakeResult {
        let result = runtimeOwner.triggerHardTimeout(reason: reason)
        detachAll(reason: .hardTimeout)
        runtimeOwner.listenerRegistry.tearDown()
        return result
    }

    func tearDownForExtensionDisable() {
        detachAll(reason: .extensionDisabled)
        runtimeOwner.tearDownForExtensionDisable()
    }

    func tearDownForProfileClose() {
        detachAll(reason: .profileClosed)
        runtimeOwner.tearDownForProfileClose()
    }

    func reset() {
        detachAll(reason: .reset)
        runtimeOwner.reset()
        componentRecords.removeAll()
        nextAttachSequence = 1
    }

    var summary: ChromeMV3ServiceWorkerSharedLifecycleSessionSummary {
        let records = componentRecords.values.sorted {
            if $0.attachSequence != $1.attachSequence {
                return $0.attachSequence < $1.attachSequence
            }
            return $0.componentID < $1.componentID
        }
        let active = records.filter { $0.detached == false }
            .map(\.componentID)
            .uniqueSortedSharedLifecycle()
        let detached = records.filter(\.detached)
            .map(\.componentID)
            .uniqueSortedSharedLifecycle()
        return ChromeMV3ServiceWorkerSharedLifecycleSessionSummary(
            sessionID: key.lifecycleSessionID,
            extensionID: key.extensionID,
            profileID: key.profileID,
            attachedComponents: records,
            activeComponentIDs: active,
            detachedComponentIDs: detached,
            listenerRegistrySummary: runtimeOwner.listenerRegistry.summary,
            lifecycleSnapshot: runtimeOwner.snapshot,
            sharedLifecycleSessionAvailableInInternalFixture:
                runtimeOwner
                .snapshot
                .serviceWorkerLifecycleAvailableInInternalFixture,
            serviceWorkerWakeAvailableInProduct: false,
            serviceWorkerPermanentBackgroundAvailable: false,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false,
            diagnostics:
                uniqueSortedSharedLifecycle([
                    "Shared lifecycle session owns one internal runtime owner for a profile and extension.",
                    "All attached harness components route events through the same synthetic queue.",
                    "Product service-worker wake remains unavailable.",
                    "Permanent background runtime remains unavailable.",
                    "runtimeLoadable remains false.",
                ])
        )
    }

    private func detachAll(
        reason: ChromeMV3ServiceWorkerInternalStopReason
    ) {
        for componentID in componentRecords.keys.sorted() {
            _ = detachComponent(componentID: componentID, reason: reason)
        }
    }
}

struct ChromeMV3ServiceWorkerSharedLifecycleRegistrySummary:
    Codable,
    Equatable,
    Sendable
{
    var sessionCount: Int
    var sessionKeys: [ChromeMV3ServiceWorkerSharedLifecycleSessionKey]
    var sharedLifecycleSessionAvailableInInternalFixture: Bool
    var serviceWorkerWakeAvailableInProduct: Bool
    var serviceWorkerPermanentBackgroundAvailable: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
    var diagnostics: [String]
}

final class ChromeMV3ServiceWorkerSharedLifecycleSessionRegistry {
    private var sessions:
        [ChromeMV3ServiceWorkerSharedLifecycleSessionKey:
            ChromeMV3ServiceWorkerSharedLifecycleSession] = [:]

    @discardableResult
    func session(
        profileID: String,
        extensionID: String,
        lifecycleSessionID: String? = nil,
        moduleState: ChromeMV3ProfileHostModuleState = .enabled,
        explicitInternalLifecycleAllowed: Bool = true,
        nativePortKeepaliveAvailableInFixture: Bool = true
    ) -> ChromeMV3ServiceWorkerSharedLifecycleSession? {
        guard moduleState == .enabled, explicitInternalLifecycleAllowed else {
            return nil
        }
        let key = ChromeMV3ServiceWorkerSharedLifecycleSessionKey.make(
            profileID: profileID,
            extensionID: extensionID,
            lifecycleSessionID: lifecycleSessionID
        )
        if let existing = sessions[key] {
            return existing
        }
        let configuration =
            ChromeMV3ServiceWorkerInternalLifecycleConfiguration
            .internalFixture(
                extensionID: key.extensionID,
                profileID: key.profileID,
                moduleState: moduleState,
                explicitInternalLifecycleAllowed:
                    explicitInternalLifecycleAllowed,
                nativePortKeepaliveAvailableInFixture:
                    nativePortKeepaliveAvailableInFixture,
                fixedLifecycleSessionID: key.lifecycleSessionID
            )
        let created = ChromeMV3ServiceWorkerSharedLifecycleSession(
            key: key,
            configuration: configuration
        )
        sessions[key] = created
        return created
    }

    func summary()
        -> ChromeMV3ServiceWorkerSharedLifecycleRegistrySummary
    {
        let keys = sessions.keys.sorted {
            if $0.profileID != $1.profileID {
                return $0.profileID < $1.profileID
            }
            if $0.extensionID != $1.extensionID {
                return $0.extensionID < $1.extensionID
            }
            return $0.lifecycleSessionID < $1.lifecycleSessionID
        }
        return ChromeMV3ServiceWorkerSharedLifecycleRegistrySummary(
            sessionCount: keys.count,
            sessionKeys: keys,
            sharedLifecycleSessionAvailableInInternalFixture:
                sessions.isEmpty == false,
            serviceWorkerWakeAvailableInProduct: false,
            serviceWorkerPermanentBackgroundAvailable: false,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false,
            diagnostics: [
                "Shared lifecycle session registry is explicit DEBUG/internal fixture state.",
                "Registry keys include profile id, extension id, and lifecycle session id.",
            ]
        )
    }

    func tearDownExtension(profileID: String, extensionID: String) {
        let normalizedProfileID = normalizedSharedLifecycle(
            profileID,
            fallback: "synthetic-profile"
        )
        let normalizedExtensionID = normalizedSharedLifecycle(
            extensionID,
            fallback: "synthetic-extension"
        )
        for key in sessions.keys.sorted(by: sortKey) {
            guard key.profileID == normalizedProfileID,
                  key.extensionID == normalizedExtensionID
            else { continue }
            sessions[key]?.tearDownForExtensionDisable()
            sessions.removeValue(forKey: key)
        }
    }

    func tearDownProfile(profileID: String) {
        let normalizedProfileID = normalizedSharedLifecycle(
            profileID,
            fallback: "synthetic-profile"
        )
        for key in sessions.keys.sorted(by: sortKey) {
            guard key.profileID == normalizedProfileID else { continue }
            sessions[key]?.tearDownForProfileClose()
            sessions.removeValue(forKey: key)
        }
    }

    func reset() {
        for key in sessions.keys.sorted(by: sortKey) {
            sessions[key]?.reset()
        }
        sessions.removeAll()
    }

    private func sortKey(
        _ lhs: ChromeMV3ServiceWorkerSharedLifecycleSessionKey,
        _ rhs: ChromeMV3ServiceWorkerSharedLifecycleSessionKey
    ) -> Bool {
        if lhs.profileID != rhs.profileID {
            return lhs.profileID < rhs.profileID
        }
        if lhs.extensionID != rhs.extensionID {
            return lhs.extensionID < rhs.extensionID
        }
        return lhs.lifecycleSessionID < rhs.lifecycleSessionID
    }
}

struct ChromeMV3ServiceWorkerSharedLifecycleSessionReport:
    Codable,
    Equatable,
    Sendable
{
    var schemaVersion: Int
    var id: String
    var reportFileName: String
    var sessionID: String
    var extensionID: String
    var profileID: String
    var attachedComponents:
        [ChromeMV3ServiceWorkerSharedLifecycleComponentRecord]
    var sharedListenerSummary:
        ChromeMV3ServiceWorkerSyntheticListenerRegistrySummary
    var sharedEventQueueResults:
        [ChromeMV3ServiceWorkerInternalEventEnvelope]
    var sharedDispatchResults:
        [ChromeMV3ServiceWorkerInternalWakeResult]
    var sharedKeepaliveResults:
        [ChromeMV3ServiceWorkerInternalKeepaliveRecord]
    var idleReleaseResults: [ChromeMV3ServiceWorkerInternalWakeResult]
    var hardTimeoutResults: [ChromeMV3ServiceWorkerInternalWakeResult]
    var passwordManagerSharedLifecycleReadyInFixture: Bool
    var passwordManagerProductRuntimeReady: Bool
    var nativeMessagingSessionParticipation: Bool
    var sharedLifecycleSessionAvailableInInternalFixture: Bool
    var serviceWorkerWakeAvailableInProduct: Bool
    var serviceWorkerPermanentBackgroundAvailable: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
    var diagnostics: [String]
}

struct ChromeMV3ServiceWorkerSharedLifecycleSessionReportSummary:
    Codable,
    Equatable,
    Sendable
{
    var reportID: String
    var reportFileName: String
    var sessionID: String
    var attachedComponentCount: Int
    var activeComponentCount: Int
    var sharedEventCount: Int
    var sharedDispatchCount: Int
    var activeKeepaliveCount: Int
    var passwordManagerSharedLifecycleReadyInFixture: Bool
    var passwordManagerProductRuntimeReady: Bool
    var nativeMessagingSessionParticipation: Bool
    var sharedLifecycleSessionAvailableInInternalFixture: Bool
    var serviceWorkerWakeAvailableInProduct: Bool
    var serviceWorkerPermanentBackgroundAvailable: Bool
    var normalTabRuntimeBridgeAvailable: Bool
    var runtimeLoadable: Bool
}

extension ChromeMV3ServiceWorkerSharedLifecycleSessionReport {
    var summary: ChromeMV3ServiceWorkerSharedLifecycleSessionReportSummary {
        ChromeMV3ServiceWorkerSharedLifecycleSessionReportSummary(
            reportID: id,
            reportFileName: reportFileName,
            sessionID: sessionID,
            attachedComponentCount: attachedComponents.count,
            activeComponentCount:
                attachedComponents.filter { $0.detached == false }.count,
            sharedEventCount: sharedEventQueueResults.count,
            sharedDispatchCount:
                sharedDispatchResults.filter(\.dispatched).count,
            activeKeepaliveCount:
                sharedKeepaliveResults.filter(\.active).count,
            passwordManagerSharedLifecycleReadyInFixture:
                passwordManagerSharedLifecycleReadyInFixture,
            passwordManagerProductRuntimeReady: false,
            nativeMessagingSessionParticipation:
                nativeMessagingSessionParticipation,
            sharedLifecycleSessionAvailableInInternalFixture:
                sharedLifecycleSessionAvailableInInternalFixture,
            serviceWorkerWakeAvailableInProduct: false,
            serviceWorkerPermanentBackgroundAvailable: false,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false
        )
    }
}

enum ChromeMV3ServiceWorkerSharedLifecycleSessionReportWriter {
    static let reportFileName =
        "runtime-service-worker-shared-lifecycle-session-report.json"

    @discardableResult
    static func write(
        _ report: ChromeMV3ServiceWorkerSharedLifecycleSessionReport,
        toRewrittenBundleRoot rootURL: URL
    ) throws -> ChromeMV3ServiceWorkerSharedLifecycleSessionReport {
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

enum ChromeMV3ServiceWorkerSharedLifecycleSessionReportGenerator {
    static func makeReport(
        extensionID: String = "password-manager-synthetic-extension",
        profileID: String = "password-manager-synthetic-profile",
        moduleState: ChromeMV3ProfileHostModuleState = .enabled,
        explicitInternalLifecycleAllowed: Bool = true
    ) -> ChromeMV3ServiceWorkerSharedLifecycleSessionReport? {
        let registry = ChromeMV3ServiceWorkerSharedLifecycleSessionRegistry()
        guard let session = registry.session(
            profileID: profileID,
            extensionID: extensionID,
            moduleState: moduleState,
            explicitInternalLifecycleAllowed:
                explicitInternalLifecycleAllowed,
            nativePortKeepaliveAvailableInFixture: true
        ) else {
            return nil
        }

        let runtime = session.attachComponent(
            kind: .runtimeJSHarness,
            componentID: "runtime-js-harness",
            eventSurfaces: [.runtimeOnMessage, .runtimeOnConnect],
            keepaliveSources: [.runtimePort, .pendingResponse]
        )
        let contextMenus = session.attachComponent(
            kind: .contextMenusHarness,
            componentID: "context-menus-harness",
            eventSurfaces: [.contextMenusOnClicked]
        )
        let alarms = session.attachComponent(
            kind: .alarmsHarness,
            componentID: "alarms-harness",
            eventSurfaces: [.alarmsOnAlarm]
        )
        let webNavigation = session.attachComponent(
            kind: .webNavigationHarness,
            componentID: "web-navigation-harness",
            eventSurfaces: [
                .webNavigationOnBeforeNavigate,
                .webNavigationOnCommitted,
                .webNavigationOnCompleted,
                .webNavigationOnDOMContentLoaded,
                .webNavigationOnErrorOccurred,
                .webNavigationOnHistoryStateUpdated,
                .webNavigationOnReferenceFragmentUpdated,
            ]
        )
        let tabs = session.attachComponent(
            kind: .tabsScriptingHarness,
            componentID: "tabs-scripting-harness",
            eventSurfaces: [.tabsOnMessage, .tabsOnConnect],
            keepaliveSources: [.tabsPort]
        )
        let storage = session.attachComponent(
            kind: .storageLocalHarness,
            componentID: "storage-local-harness",
            eventSurfaces: [.storageOnChanged]
        )
        let permissions = session.attachComponent(
            kind: .permissionsHarness,
            componentID: "permissions-harness",
            eventSurfaces: [.permissionsOnAdded, .permissionsOnRemoved]
        )
        let native = session.attachComponent(
            kind: .nativeMessagingFixtureRuntime,
            componentID: "native-messaging-fixture-runtime",
            eventSurfaces: [.nativePortOnMessage, .nativePortOnDisconnect],
            keepaliveSources: [.nativeMessagingPort]
        )
        let password = session.attachComponent(
            kind: .passwordManagerCombinedFixture,
            componentID: "password-manager-combined-fixture",
            eventSurfaces: [
                .passwordManagerDetectFields,
                .passwordManagerFillFields,
            ],
            keepaliveSources: [.longRunningEvent]
        )
        _ = session.attachComponent(
            kind: .extensionPageHostHarness,
            componentID: "extension-page-host-harness",
            eventSurfaces: [.actionPopupEvent]
        )
        _ = session.attachComponent(
            kind: .contentScriptSyntheticEndpoint,
            componentID: "content-script-synthetic-endpoint",
            eventSurfaces: [.tabsOnMessage, .tabsOnConnect]
        )

        for event in [
            ChromeMV3ServiceWorkerSyntheticListenerEvent.runtimeOnMessage,
            .runtimeOnConnect,
            .tabsOnMessage,
            .tabsOnConnect,
            .storageOnChanged,
            .permissionsOnAdded,
            .permissionsOnRemoved,
            .nativePortOnMessage,
            .nativePortOnDisconnect,
            .actionPopupEvent,
            .alarmsOnAlarm,
            .contextMenusOnClicked,
            .webNavigationOnCommitted,
            .webNavigationOnCompleted,
            .passwordManagerDetectFields,
            .passwordManagerFillFields,
        ] {
            session.registerListener(
                event: event,
                listenerID: "shared-\(event.rawValue)"
            )
        }

        _ = session.routeEvent(
            reason: .runtimeMessage,
            sourceComponentID: runtime.componentID,
            sourceComponentKind: .runtimeJSHarness,
            payload: .object(["type": .string("sharedRuntimeMessage")]),
            payloadSummary: "runtime.sendMessage",
            sourceContext: .extensionPage
        )
        let runtimePort = session.routeEvent(
            reason: .runtimeConnect,
            sourceComponentID: runtime.componentID,
            sourceComponentKind: .runtimeJSHarness,
            payloadSummary: "runtime.connect",
            sourceContext: .extensionPage,
            keepaliveKind: .runtimePort,
            portID: "shared-runtime-port"
        )
        _ = session.routeEvent(
            reason: .tabsMessage,
            sourceComponentID: tabs.componentID,
            sourceComponentKind: .tabsScriptingHarness,
            payload: .object(["type": .string("detectFields")]),
            payloadSummary: "tabs.sendMessage",
            sourceContext: .extensionPage
        )
        let tabsPort = session.routeEvent(
            reason: .tabsConnect,
            sourceComponentID: tabs.componentID,
            sourceComponentKind: .tabsScriptingHarness,
            payloadSummary: "tabs.connect",
            sourceContext: .extensionPage,
            keepaliveKind: .tabsPort,
            portID: "shared-tabs-port"
        )
        _ = session.routeEvent(
            reason: .storageChanged,
            sourceComponentID: storage.componentID,
            sourceComponentKind: .storageLocalHarness,
            payloadSummary: "storage.onChanged",
            sourceContext: .serviceWorker
        )
        _ = session.routeEvent(
            reason: .permissionsChanged,
            listenerEvent: .permissionsOnAdded,
            sourceComponentID: permissions.componentID,
            sourceComponentKind: .permissionsHarness,
            payloadSummary: "permissions.onAdded",
            sourceContext: .serviceWorker
        )
        _ = session.routeEvent(
            reason: .permissionsChanged,
            listenerEvent: .permissionsOnRemoved,
            sourceComponentID: permissions.componentID,
            sourceComponentKind: .permissionsHarness,
            payloadSummary: "permissions.onRemoved",
            sourceContext: .serviceWorker
        )
        _ = session.routeEvent(
            reason: .contextMenusClicked,
            listenerEvent: .contextMenusOnClicked,
            sourceComponentID: contextMenus.componentID,
            sourceComponentKind: .contextMenusHarness,
            payloadSummary: "contextMenus.onClicked",
            sourceContext: .serviceWorker
        )
        _ = session.routeEvent(
            reason: .alarm,
            listenerEvent: .alarmsOnAlarm,
            sourceComponentID: alarms.componentID,
            sourceComponentKind: .alarmsHarness,
            payloadSummary: "alarms.onAlarm",
            sourceContext: .serviceWorker
        )
        _ = session.routeEvent(
            reason: .webNavigationEvent,
            listenerEvent: .webNavigationOnCommitted,
            sourceComponentID: webNavigation.componentID,
            sourceComponentKind: .webNavigationHarness,
            payloadSummary: "webNavigation.onCommitted",
            sourceContext: .serviceWorker
        )
        _ = session.routeEvent(
            reason: .webNavigationEvent,
            listenerEvent: .webNavigationOnCompleted,
            sourceComponentID: webNavigation.componentID,
            sourceComponentKind: .webNavigationHarness,
            payloadSummary: "webNavigation.onCompleted",
            sourceContext: .serviceWorker
        )
        let nativePort = session.routeEvent(
            reason: .nativeMessagingConnect,
            sourceComponentID: native.componentID,
            sourceComponentKind: .nativeMessagingFixtureRuntime,
            payloadSummary: "runtime.connect" + "Native",
            sourceContext: .serviceWorker,
            keepaliveKind: .nativeMessagingPort,
            portID: "shared-native-port"
        )
        _ = session.routeEvent(
            reason: .nativeMessagingMessage,
            sourceComponentID: native.componentID,
            sourceComponentKind: .nativeMessagingFixtureRuntime,
            payloadSummary: "NativePort.postMessage",
            sourceContext: .serviceWorker
        )
        _ = session.routeEvent(
            reason: .passwordManagerDetectFields,
            sourceComponentID: password.componentID,
            sourceComponentKind: .passwordManagerCombinedFixture,
            payloadSummary: "passwordManager.detectFields",
            sourceContext: .contentScript
        )
        _ = session.routeEvent(
            reason: .passwordManagerFillFields,
            sourceComponentID: password.componentID,
            sourceComponentKind: .passwordManagerCombinedFixture,
            payloadSummary: "passwordManager.fillFields",
            sourceContext: .contentScript
        )
        let listenerSummaryBeforeHardTimeout =
            session.runtimeOwner.listenerRegistry.summary
        let blockedIdle = session.triggerIdleRelease()
        _ = session.disconnectKeepalive(
            keepaliveID: runtimePort.keepaliveRecord?.keepaliveID,
            reason: .reset
        )
        _ = session.disconnectKeepalive(
            keepaliveID: tabsPort.keepaliveRecord?.keepaliveID,
            reason: .reset
        )
        _ = session.disconnectKeepalive(
            keepaliveID: nativePort.keepaliveRecord?.keepaliveID,
            reason: .reset
        )
        let releasedIdle = session.triggerIdleRelease()
        _ = session.routeEvent(
            reason: .nativeMessagingConnect,
            sourceComponentID: native.componentID,
            sourceComponentKind: .nativeMessagingFixtureRuntime,
            payloadSummary:
                "runtime.connect" + "Native hard-timeout coverage",
            sourceContext: .serviceWorker,
            keepaliveKind: .nativeMessagingPort,
            portID: "shared-native-port-hard-timeout"
        )
        let hardTimeout = session.triggerHardTimeout()

        let summary = session.summary
        let snapshot = summary.lifecycleSnapshot
        let allSessionIDs =
            snapshot.events.compactMap(\.sessionID)
            + snapshot.wakeResults.compactMap(\.sessionID)
        let sameSession =
            allSessionIDs.isEmpty == false
                && Set(allSessionIDs) == Set([summary.sessionID])
        let nativeParticipates =
            snapshot.events.contains {
                $0.sourceComponentKind == .nativeMessagingFixtureRuntime
                    && $0.sessionID == summary.sessionID
            }
        let passwordReady =
            sameSession
                && nativeParticipates
                && blockedIdle.blocked
                && releasedIdle.wakeAccepted
                && hardTimeout.wakeAccepted
                && snapshot.allKeepaliveRecords.contains {
                    $0.kind == .nativeMessagingPort
                }

        let reportID = stableIDSharedLifecycle(
            prefix: "runtime-service-worker-shared-lifecycle-session",
            parts: [
                summary.profileID,
                summary.extensionID,
                summary.sessionID,
                String(snapshot.events.count),
            ]
        )
        return ChromeMV3ServiceWorkerSharedLifecycleSessionReport(
            schemaVersion: 1,
            id: reportID,
            reportFileName:
                ChromeMV3ServiceWorkerSharedLifecycleSessionReportWriter
                .reportFileName,
            sessionID: summary.sessionID,
            extensionID: summary.extensionID,
            profileID: summary.profileID,
            attachedComponents: summary.attachedComponents,
            sharedListenerSummary: listenerSummaryBeforeHardTimeout,
            sharedEventQueueResults: snapshot.events,
            sharedDispatchResults: snapshot.wakeResults,
            sharedKeepaliveResults: snapshot.allKeepaliveRecords,
            idleReleaseResults: snapshot.idleReleaseResults,
            hardTimeoutResults: snapshot.hardTimeoutResults,
            passwordManagerSharedLifecycleReadyInFixture:
                passwordReady,
            passwordManagerProductRuntimeReady: false,
            nativeMessagingSessionParticipation: nativeParticipates,
            sharedLifecycleSessionAvailableInInternalFixture:
                summary.sharedLifecycleSessionAvailableInInternalFixture,
            serviceWorkerWakeAvailableInProduct: false,
            serviceWorkerPermanentBackgroundAvailable: false,
            normalTabRuntimeBridgeAvailable: false,
            runtimeLoadable: false,
            diagnostics:
                uniqueSortedSharedLifecycle(
                    summary.diagnostics
                        + [
                            "Shared lifecycle report routed runtime, tabs, storage, permissions, native messaging, contextMenus, alarms, webNavigation, and password-manager events through one queue.",
                            "Idle release and hard-timeout transitions were triggered explicitly by tests/fixtures.",
                            "Native Port keepalive was recorded as shared session state; lifecycle code did not launch a process.",
                        ]
                )
        )
    }
}

private extension Array
where Element == ChromeMV3ServiceWorkerSyntheticListenerEvent {
    func uniqueSortedSharedLifecycle()
        -> [ChromeMV3ServiceWorkerSyntheticListenerEvent]
    {
        Array(Set(self)).sorted()
    }
}

private extension Array
where Element == ChromeMV3ServiceWorkerInternalKeepaliveKind {
    func uniqueSortedSharedLifecycle()
        -> [ChromeMV3ServiceWorkerInternalKeepaliveKind]
    {
        Array(Set(self)).sorted()
    }
}

private extension Array where Element == String {
    func uniqueSortedSharedLifecycle() -> [String] {
        Array(Set(filter { $0.isEmpty == false })).sorted()
    }
}

private func normalizedSharedLifecycle(
    _ value: String,
    fallback: String
) -> String {
    value.isEmpty ? fallback : value
}

private func stableIDSharedLifecycle(
    prefix: String,
    parts: [String]
) -> String {
    let seed = parts.joined(separator: "|")
    return "\(prefix)-\(sha256HexSharedLifecycle(Data(seed.utf8)).prefix(32))"
}

private func sha256HexSharedLifecycle(_ data: Data) -> String {
    SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }
        .joined()
}

private func uniqueSortedSharedLifecycle(_ values: [String]) -> [String] {
    values.uniqueSortedSharedLifecycle()
}
