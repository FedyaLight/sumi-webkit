//
//  ChromeMV3ServiceWorkerEventRouting.swift
//  Sumi
//
//  Local-experimental Chrome MV3 service-worker event routing models. These
//  records are explicit-gate diagnostics and internal fixture routing only:
//  no permanent background runtime, timers, scheduled loops, Web Store install, remote
//  CRX download, arbitrary native host discovery, or product DNR enforcement.
//

import CryptoKit
import Foundation

enum ChromeMV3ServiceWorkerLocalExperimentalGateState:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case allowed
    case extensionDisabled
    case moduleDisabled
    case runtimeGateBlocked

    static func < (
        lhs: ChromeMV3ServiceWorkerLocalExperimentalGateState,
        rhs: ChromeMV3ServiceWorkerLocalExperimentalGateState
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3ServiceWorkerReadinessBlocker:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case backgroundServiceWorkerMissing
    case generatedBundleRootMissing
    case listenerDiscoveryUnavailable
    case localExperimentalGateBlocked
    case runtimeLoadableFalse
    case serviceWorkerFileMissing
    case serviceWorkerPathUnsafe
    case serviceWorkerWrapperMissing
    case unsupportedServiceWorkerType
    case wrapperShimMissing

    static func < (
        lhs: ChromeMV3ServiceWorkerReadinessBlocker,
        rhs: ChromeMV3ServiceWorkerReadinessBlocker
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3ServiceWorkerListenerCoverage:
    Codable,
    Equatable,
    Sendable
{
    var event: ChromeMV3ServiceWorkerSyntheticListenerEvent
    var listenerSurface: ChromeMV3RuntimeListenerSurfaceKind
    var listenerDetected: Bool
    var detectionPattern: String?
    var diagnostics: [String]
}

struct ChromeMV3ServiceWorkerDeclarationReadiness:
    Codable,
    Equatable,
    Sendable
{
    var schemaVersion: Int
    var extensionID: String
    var profileID: String
    var backgroundServiceWorkerPath: String?
    var serviceWorkerType: String?
    var generatedBundleRootPath: String?
    var generatedServiceWorkerResourcePath: String?
    var serviceWorkerFileAvailable: Bool
    var serviceWorkerPathSafe: Bool
    var serviceWorkerWrapperPath: String?
    var serviceWorkerWrapperAvailable: Bool
    var wrapperShimPath: String?
    var wrapperShimAvailable: Bool
    var listenerDiscoveryStrategy: String
    var listenerCoverage: [ChromeMV3ServiceWorkerListenerCoverage]
    var eventRoutingAvailable: Bool
    var localExperimentalGateState:
        ChromeMV3ServiceWorkerLocalExperimentalGateState
    var runtimeLoadable: Bool
    var blockers: [ChromeMV3ServiceWorkerReadinessBlocker]
    var diagnostics: [String]

    var declaresBackgroundServiceWorker: Bool {
        backgroundServiceWorkerPath?.isEmpty == false
    }

    var readyForLocalExperimentalRouting: Bool {
        eventRoutingAvailable
    }

    func coverage(
        for event: ChromeMV3ServiceWorkerSyntheticListenerEvent
    ) -> ChromeMV3ServiceWorkerListenerCoverage? {
        listenerCoverage.first { $0.event == event }
    }

    func listenerDetected(
        for event: ChromeMV3ServiceWorkerSyntheticListenerEvent
    ) -> Bool {
        coverage(for: event)?.listenerDetected == true
    }
}

enum ChromeMV3ServiceWorkerDeclarationReadinessEvaluator {
    static func evaluate(
        manifest: ChromeMV3Manifest,
        generatedBundleRootURL: URL?,
        extensionID: String,
        profileID: String,
        moduleState: ChromeMV3ProfileHostModuleState = .enabled,
        extensionEnabled: Bool = true,
        localExperimentalGateAllowed: Bool = false
    ) -> ChromeMV3ServiceWorkerDeclarationReadiness {
        let path = normalizedOptional(manifest.background?.serviceWorker)
        let type = normalizedOptional(manifest.background?.type) ?? "classic"
        let gateState = gateState(
            moduleState: moduleState,
            extensionEnabled: extensionEnabled,
            localExperimentalGateAllowed: localExperimentalGateAllowed
        )
        let supportedType = type == "classic" || type == "module"
        let pathSafe = path.map(isSafeRelativePath) ?? false
        let root = generatedBundleRootURL?.standardizedFileURL
        let serviceWorkerURL = path.flatMap { pathSafe ? root?.appendingPathComponent($0) : nil }
        let serviceWorkerAvailable = serviceWorkerURL.map(fileExists) ?? false
        let wrapperModule: ChromeMV3RuntimeTemplateModuleName =
            type == "module"
                ? .serviceWorkerWrapperModule
                : .serviceWorkerWrapperClassic
        let wrapperPath = ChromeMV3RuntimeResourceTemplateCatalog
            .template(named: wrapperModule)
            .outputRelativePath
        let shimPath = ChromeMV3RuntimeResourceTemplateCatalog
            .template(named: .chromeShimServiceWorker)
            .outputRelativePath
        let wrapperAvailable = root.map {
            fileExists($0.appendingPathComponent(wrapperPath))
        } ?? false
        let shimAvailable = root.map {
            fileExists($0.appendingPathComponent(shimPath))
        } ?? false
        let source = serviceWorkerURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        let detectedListenerPatterns = source.map(detectedListenerPatterns)
        let coverageRecords = listenerEvents.map {
            listenerCoverage(for: $0, detectedPatterns: detectedListenerPatterns)
        }
        var blockers: [ChromeMV3ServiceWorkerReadinessBlocker] = []
        if path == nil {
            blockers.append(.backgroundServiceWorkerMissing)
        }
        if root == nil {
            blockers.append(.generatedBundleRootMissing)
        }
        if path != nil, pathSafe == false {
            blockers.append(.serviceWorkerPathUnsafe)
        }
        if pathSafe, serviceWorkerAvailable == false {
            blockers.append(.serviceWorkerFileMissing)
        }
        if supportedType == false {
            blockers.append(.unsupportedServiceWorkerType)
        }
        if wrapperAvailable == false {
            blockers.append(.serviceWorkerWrapperMissing)
        }
        if shimAvailable == false {
            blockers.append(.wrapperShimMissing)
        }
        if gateState != .allowed {
            blockers.append(.localExperimentalGateBlocked)
        }
        if source == nil {
            blockers.append(.listenerDiscoveryUnavailable)
        }
        blockers.append(.runtimeLoadableFalse)
        blockers = uniqueSorted(blockers)
        let routingAvailable =
            path != nil
            && pathSafe
            && serviceWorkerAvailable
            && supportedType
            && wrapperAvailable
            && shimAvailable
            && source != nil
            && gateState == .allowed
        return ChromeMV3ServiceWorkerDeclarationReadiness(
            schemaVersion: 1,
            extensionID: normalized(extensionID, fallback: "unknown-extension"),
            profileID: normalized(profileID, fallback: "unknown-profile"),
            backgroundServiceWorkerPath: path,
            serviceWorkerType: type,
            generatedBundleRootPath: root?.path,
            generatedServiceWorkerResourcePath: serviceWorkerURL?.path,
            serviceWorkerFileAvailable: serviceWorkerAvailable,
            serviceWorkerPathSafe: pathSafe,
            serviceWorkerWrapperPath: root?.appendingPathComponent(wrapperPath).path,
            serviceWorkerWrapperAvailable: wrapperAvailable,
            wrapperShimPath: root?.appendingPathComponent(shimPath).path,
            wrapperShimAvailable: shimAvailable,
            listenerDiscoveryStrategy:
                source == nil
                    ? "blocked: service-worker source unavailable"
                    : "static direct listener token scan",
            listenerCoverage: coverageRecords,
            eventRoutingAvailable: routingAvailable,
            localExperimentalGateState: gateState,
            runtimeLoadable: false,
            blockers: blockers,
            diagnostics: uniqueSorted(
                [
                    "background.service_worker readiness is evaluated for local experimental routing only.",
                    "Listener discovery is conservative and direct-token based; indirect imports remain a documented gap.",
                    "Generated wrapper and service-worker shim must already be present.",
                    "runtimeLoadable remains false.",
                    "No service worker is loaded by this readiness evaluator.",
                ]
                    + blockers.map { "Blocker: \($0.rawValue)." }
            )
        )
    }

    private static let listenerEvents:
        [ChromeMV3ServiceWorkerSyntheticListenerEvent] = [
            .runtimeOnMessage,
            .runtimeOnConnect,
            .runtimeOnInstalled,
            .runtimeOnMessageExternal,
            .runtimeOnStartup,
            .runtimeOnUpdateAvailable,
            .storageOnChanged,
            .permissionsOnAdded,
            .permissionsOnRemoved,
            .tabsOnActivated,
            .tabsOnRemoved,
            .tabsOnUpdated,
            .contextMenusOnClicked,
            .alarmsOnAlarm,
            .commandsOnCommand,
            .webNavigationOnBeforeNavigate,
            .webNavigationOnCommitted,
            .webNavigationOnCompleted,
            .webNavigationOnDOMContentLoaded,
            .webNavigationOnErrorOccurred,
            .webNavigationOnHistoryStateUpdated,
            .webNavigationOnReferenceFragmentUpdated,
            .nativePortOnMessage,
            .nativePortOnDisconnect,
            .webRequestOnAuthRequired,
            .webRequestOnBeforeRequest,
            .webRequestOnBeforeSendHeaders,
            .webRequestOnCompleted,
            .webRequestOnErrorOccurred,
            .webRequestOnHeadersReceived,
            .webRequestOnResponseStarted,
            .webRequestOnSendHeaders,
        ]

    private static func listenerCoverage(
        for event: ChromeMV3ServiceWorkerSyntheticListenerEvent,
        detectedPatterns: Set<String>?
    ) -> ChromeMV3ServiceWorkerListenerCoverage {
        let patterns = listenerPatterns(for: event)
        let detected = patterns.first {
            detectedPatterns?.contains($0) == true
        }
        return ChromeMV3ServiceWorkerListenerCoverage(
            event: event,
            listenerSurface: event.listenerSurface,
            listenerDetected: detected != nil,
            detectionPattern: detected,
            diagnostics: uniqueSorted(
                [
                    detected == nil
                        ? "No direct token detected for \(event.rawValue)."
                        : "Detected direct listener token for \(event.rawValue).",
                    "This does not execute service-worker JavaScript.",
                ]
            )
        )
    }

    private static func detectedListenerPatterns(in source: String) -> Set<String> {
        guard source.contains(".addListener") else { return [] }
        let range = NSRange(source.startIndex..., in: source)
        return Set(
            listenerPatternRegex?.matches(in: source, range: range).compactMap {
                match -> String? in
                guard let matchRange = Range(match.range, in: source)
                else { return nil }
                return String(source[matchRange])
            } ?? []
        )
    }

    private static let allListenerPatterns: [String] = {
        var seen = Set<String>()
        return listenerEvents.flatMap { listenerPatterns(for: $0) }.filter {
            seen.insert($0).inserted
        }
    }()

    private static let listenerPatternRegex: NSRegularExpression? = {
        let pattern = allListenerPatterns
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        return try? NSRegularExpression(pattern: pattern)
    }()

    private static func listenerPatterns(
        for event: ChromeMV3ServiceWorkerSyntheticListenerEvent
    ) -> [String] {
        switch event {
        case .runtimeOnMessage:
            return [
                "chrome.runtime.onMessage.addListener",
                "browser.runtime.onMessage.addListener",
                "runtime.onMessage.addListener",
            ]
        case .runtimeOnConnect:
            return [
                "chrome.runtime.onConnect.addListener",
                "browser.runtime.onConnect.addListener",
                "runtime.onConnect.addListener",
            ]
        case .runtimeOnInstalled:
            return runtimePatterns("onInstalled")
        case .runtimeOnMessageExternal:
            return runtimePatterns("onMessageExternal")
        case .runtimeOnStartup:
            return runtimePatterns("onStartup")
        case .runtimeOnUpdateAvailable:
            return runtimePatterns("onUpdateAvailable")
        case .storageOnChanged:
            return [
                "chrome.storage.onChanged.addListener",
                "browser.storage.onChanged.addListener",
                "storage.onChanged.addListener",
            ]
        case .permissionsOnAdded:
            return [
                "chrome.permissions.onAdded.addListener",
                "browser.permissions.onAdded.addListener",
                "permissions.onAdded.addListener",
            ]
        case .permissionsOnRemoved:
            return [
                "chrome.permissions.onRemoved.addListener",
                "browser.permissions.onRemoved.addListener",
                "permissions.onRemoved.addListener",
            ]
        case .contextMenusOnClicked:
            return [
                "chrome.contextMenus.onClicked.addListener",
                "browser.contextMenus.onClicked.addListener",
                "contextMenus.onClicked.addListener",
            ]
        case .alarmsOnAlarm:
            return [
                "chrome.alarms.onAlarm.addListener",
                "browser.alarms.onAlarm.addListener",
                "alarms.onAlarm.addListener",
            ]
        case .commandsOnCommand:
            return [
                "chrome.commands.onCommand.addListener",
                "browser.commands.onCommand.addListener",
                "commands.onCommand.addListener",
            ]
        case .tabsOnActivated:
            return tabsPatterns("onActivated")
        case .tabsOnRemoved:
            return tabsPatterns("onRemoved")
        case .tabsOnUpdated:
            return tabsPatterns("onUpdated")
        case .webNavigationOnBeforeNavigate:
            return webNavigationPatterns("onBeforeNavigate")
        case .webNavigationOnCommitted:
            return webNavigationPatterns("onCommitted")
        case .webNavigationOnCompleted:
            return webNavigationPatterns("onCompleted")
        case .webNavigationOnDOMContentLoaded:
            return webNavigationPatterns("onDOMContentLoaded")
        case .webNavigationOnErrorOccurred:
            return webNavigationPatterns("onErrorOccurred")
        case .webNavigationOnHistoryStateUpdated:
            return webNavigationPatterns("onHistoryStateUpdated")
        case .webNavigationOnReferenceFragmentUpdated:
            return webNavigationPatterns("onReferenceFragmentUpdated")
        case .nativePortOnMessage:
            return [
                "chrome.runtime.connect" + "Native",
                "browser.runtime.connect" + "Native",
                "runtime.connect" + "Native",
                "port.onMessage.addListener",
            ]
        case .nativePortOnDisconnect:
            return [
                "port.onDisconnect.addListener",
                "nativePort.onDisconnect.addListener",
            ]
        case .webRequestOnAuthRequired:
            return webRequestPatterns("onAuthRequired")
        case .webRequestOnBeforeRequest:
            return webRequestPatterns("onBeforeRequest")
        case .webRequestOnBeforeSendHeaders:
            return webRequestPatterns("onBeforeSendHeaders")
        case .webRequestOnCompleted:
            return webRequestPatterns("onCompleted")
        case .webRequestOnErrorOccurred:
            return webRequestPatterns("onErrorOccurred")
        case .webRequestOnHeadersReceived:
            return webRequestPatterns("onHeadersReceived")
        case .webRequestOnResponseStarted:
            return webRequestPatterns("onResponseStarted")
        case .webRequestOnSendHeaders:
            return webRequestPatterns("onSendHeaders")
        case .actionPopupEvent, .passwordManagerDetectFields,
             .passwordManagerFillFields, .tabsOnMessage, .tabsOnConnect,
             .testFixture:
            return []
        }
    }

    private static func runtimePatterns(_ event: String) -> [String] {
        [
            "chrome.runtime.\(event).addListener",
            "browser.runtime.\(event).addListener",
            "runtime.\(event).addListener",
        ]
    }

    private static func tabsPatterns(_ event: String) -> [String] {
        [
            "chrome.tabs.\(event).addListener",
            "browser.tabs.\(event).addListener",
            "tabs.\(event).addListener",
        ]
    }

    private static func webNavigationPatterns(_ event: String) -> [String] {
        [
            "chrome.webNavigation.\(event).addListener",
            "browser.webNavigation.\(event).addListener",
            "webNavigation.\(event).addListener",
        ]
    }

    private static func webRequestPatterns(_ event: String) -> [String] {
        [
            "chrome.webRequest.\(event).addListener",
            "browser.webRequest.\(event).addListener",
            "webRequest.\(event).addListener",
        ]
    }

    private static func gateState(
        moduleState: ChromeMV3ProfileHostModuleState,
        extensionEnabled: Bool,
        localExperimentalGateAllowed: Bool
    ) -> ChromeMV3ServiceWorkerLocalExperimentalGateState {
        if moduleState != .enabled {
            return .moduleDisabled
        }
        if extensionEnabled == false {
            return .extensionDisabled
        }
        return localExperimentalGateAllowed ? .allowed : .runtimeGateBlocked
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.isEmpty == false
        else { return nil }
        return trimmed
    }
}

enum ChromeMV3ServiceWorkerEventSource:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case alarmTriggered
    case contentScriptRuntimeConnect
    case contentScriptRuntimeMessage
    case contextMenuClicked
    case nativeMessagingConnect
    case nativeMessagingMessage
    case permissionsAdded
    case permissionsRemoved
    case popupOptionsRuntimeConnect
    case popupOptionsRuntimeMessage
    case runtimeInstalled
    case runtimeStartup
    case storageChanged
    case testFixtureEvent
    case webNavigationSyntheticEvent

    static func < (
        lhs: ChromeMV3ServiceWorkerEventSource,
        rhs: ChromeMV3ServiceWorkerEventSource
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var wakeReason: ChromeMV3ServiceWorkerWakeReason {
        switch self {
        case .popupOptionsRuntimeMessage, .contentScriptRuntimeMessage:
            return .runtimeMessage
        case .popupOptionsRuntimeConnect, .contentScriptRuntimeConnect:
            return .runtimeConnect
        case .storageChanged:
            return .storageChanged
        case .permissionsAdded, .permissionsRemoved:
            return .permissionsChanged
        case .contextMenuClicked:
            return .contextMenusClicked
        case .alarmTriggered:
            return .alarm
        case .webNavigationSyntheticEvent:
            return .webNavigationEvent
        case .nativeMessagingConnect:
            return .nativeMessagingConnect
        case .nativeMessagingMessage:
            return .nativeMessagingMessage
        case .runtimeInstalled:
            return .installOrUpdateEvent
        case .runtimeStartup:
            return .startupEvent
        case .testFixtureEvent:
            return .testFixture
        }
    }

    var listenerEvent: ChromeMV3ServiceWorkerSyntheticListenerEvent {
        switch self {
        case .popupOptionsRuntimeMessage, .contentScriptRuntimeMessage:
            return .runtimeOnMessage
        case .popupOptionsRuntimeConnect, .contentScriptRuntimeConnect:
            return .runtimeOnConnect
        case .storageChanged:
            return .storageOnChanged
        case .permissionsAdded:
            return .permissionsOnAdded
        case .permissionsRemoved:
            return .permissionsOnRemoved
        case .contextMenuClicked:
            return .contextMenusOnClicked
        case .alarmTriggered:
            return .alarmsOnAlarm
        case .webNavigationSyntheticEvent:
            return .webNavigationOnCommitted
        case .nativeMessagingConnect, .nativeMessagingMessage:
            return .nativePortOnMessage
        case .runtimeInstalled:
            return .runtimeOnInstalled
        case .runtimeStartup:
            return .runtimeOnStartup
        case .testFixtureEvent:
            return .testFixture
        }
    }

    var sourceContext: ChromeMV3RuntimeMessagingContextKind {
        switch self {
        case .contentScriptRuntimeMessage, .contentScriptRuntimeConnect:
            return .contentScript
        case .popupOptionsRuntimeMessage, .popupOptionsRuntimeConnect:
            return .extensionPage
        case .storageChanged, .permissionsAdded, .permissionsRemoved,
             .contextMenuClicked, .alarmTriggered,
             .webNavigationSyntheticEvent, .nativeMessagingConnect,
             .nativeMessagingMessage, .runtimeInstalled, .runtimeStartup,
             .testFixtureEvent:
            return .serviceWorker
        }
    }
}

enum ChromeMV3ServiceWorkerEventRoutingResultKind:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case blockedByGate
    case blockedByPermission
    case blockedByUnsupportedListener
    case delivered
    case failed
    case listenerError
    case noListener
    case noReceiver
    case promiseRejected
    case sendResponseTimeoutDiagnostic
    case timeoutDiagnostic
    case unsupportedListenerMode

    static func < (
        lhs: ChromeMV3ServiceWorkerEventRoutingResultKind,
        rhs: ChromeMV3ServiceWorkerEventRoutingResultKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3ServiceWorkerEventSenderMetadata:
    Codable,
    Equatable,
    Sendable
{
    var tabID: Int?
    var frameID: Int?
    var documentID: String?
    var sourceURL: String?
    var urlRedacted: Bool
    var redactionState: String

    static let none = ChromeMV3ServiceWorkerEventSenderMetadata(
        tabID: nil,
        frameID: nil,
        documentID: nil,
        sourceURL: nil,
        urlRedacted: true,
        redactionState: "no sender metadata"
    )
}

struct ChromeMV3ServiceWorkerEventRoutingRecord:
    Codable,
    Equatable,
    Sendable
{
    var eventID: String
    var sequence: Int
    var extensionID: String
    var profileID: String
    var source: ChromeMV3ServiceWorkerEventSource
    var sender: ChromeMV3ServiceWorkerEventSenderMetadata
    var lifecycleSessionID: String?
    var payloadSummary: String
    var sourceSurface: String
    var targetListener: ChromeMV3ServiceWorkerSyntheticListenerEvent
    var resultKind: ChromeMV3ServiceWorkerEventRoutingResultKind
    var wakeResult: ChromeMV3ServiceWorkerInternalWakeResult?
    var responsePayload: ChromeMV3StorageValue?
    var lastErrorMessage: String?
    var diagnostics: [String]
}

enum ChromeMV3ServiceWorkerEventRouter {
    static func route(
        source: ChromeMV3ServiceWorkerEventSource,
        readiness: ChromeMV3ServiceWorkerDeclarationReadiness?,
        sharedLifecycleSession:
            ChromeMV3ServiceWorkerSharedLifecycleSession?,
        sequence: Int = 1,
        payload: ChromeMV3StorageValue? = nil,
        payloadSummary: String,
        sender: ChromeMV3ServiceWorkerEventSenderMetadata = .none,
        sourceComponentID: String,
        sourceComponentKind:
            ChromeMV3ServiceWorkerSharedLifecycleComponentKind,
        keepaliveKind: ChromeMV3ServiceWorkerInternalKeepaliveKind? = nil,
        portID: String? = nil
    ) -> ChromeMV3ServiceWorkerEventRoutingRecord {
        let extensionID =
            readiness?.extensionID
            ?? sharedLifecycleSession?.key.extensionID
            ?? "unknown-extension"
        let profileID =
            readiness?.profileID
            ?? sharedLifecycleSession?.key.profileID
            ?? "unknown-profile"
        let eventID = stableID(
            prefix: "sw-event-route",
            parts: [
                extensionID,
                profileID,
                source.rawValue,
                String(sequence),
                payloadSummary,
            ]
        )
        if let readiness, readiness.eventRoutingAvailable == false {
            return record(
                eventID: eventID,
                sequence: sequence,
                extensionID: extensionID,
                profileID: profileID,
                source: source,
                sender: sender,
                lifecycleSessionID:
                    sharedLifecycleSession?.key.lifecycleSessionID,
                payloadSummary: payloadSummary,
                resultKind: .blockedByGate,
                wakeResult: nil,
                responsePayload: nil,
                lastErrorMessage: "Service-worker routing is blocked by local experimental readiness.",
                diagnostics: readiness.diagnostics
            )
        }
        if let readiness,
           readiness.listenerDetected(for: source.listenerEvent) == false
        {
            let kind: ChromeMV3ServiceWorkerEventRoutingResultKind =
                source.listenerEvent == .runtimeOnMessage
                    || source.listenerEvent == .runtimeOnConnect
                    ? .noReceiver
                    : .noListener
            return record(
                eventID: eventID,
                sequence: sequence,
                extensionID: extensionID,
                profileID: profileID,
                source: source,
                sender: sender,
                lifecycleSessionID:
                    sharedLifecycleSession?.key.lifecycleSessionID,
                payloadSummary: payloadSummary,
                resultKind: kind,
                wakeResult: nil,
                responsePayload: nil,
                lastErrorMessage:
                    "Could not establish connection. Receiving end does not exist.",
                diagnostics: [
                    "Static listener discovery did not find \(source.listenerEvent.rawValue).",
                ] + readiness.diagnostics
            )
        }
        guard let sharedLifecycleSession else {
            return record(
                eventID: eventID,
                sequence: sequence,
                extensionID: extensionID,
                profileID: profileID,
                source: source,
                sender: sender,
                lifecycleSessionID: nil,
                payloadSummary: payloadSummary,
                resultKind: .blockedByGate,
                wakeResult: nil,
                responsePayload: nil,
                lastErrorMessage:
                    "No shared local experimental lifecycle session is available.",
                diagnostics: [
                    "Routing requires an explicitly provided shared lifecycle session.",
                ]
            )
        }
        let wake = sharedLifecycleSession.routeEvent(
            reason: source.wakeReason,
            listenerEvent: source.listenerEvent,
            sourceComponentID: sourceComponentID,
            sourceComponentKind: sourceComponentKind,
            payload: payload,
            payloadSummary: payloadSummary,
            sourceContext: source.sourceContext,
            keepaliveKind: keepaliveKind,
            portID: portID
        )
        let kind: ChromeMV3ServiceWorkerEventRoutingResultKind
        if wake.dispatched {
            kind = .delivered
        } else if wake.blocked,
                  wake.blockers.contains("No synthetic/model listener is registered.")
        {
            kind = source.listenerEvent == .runtimeOnMessage
                || source.listenerEvent == .runtimeOnConnect
                ? .noReceiver
                : .noListener
        } else if wake.blocked {
            kind = .blockedByGate
        } else if wake.dropped {
            kind = .timeoutDiagnostic
        } else {
            kind = .failed
        }
        return record(
            eventID: eventID,
            sequence: sequence,
            extensionID: extensionID,
            profileID: profileID,
            source: source,
            sender: sender,
            lifecycleSessionID:
                wake.sessionID ?? sharedLifecycleSession.key.lifecycleSessionID,
            payloadSummary: payloadSummary,
            resultKind: kind,
            wakeResult: wake,
            responsePayload: wake.responsePayload,
            lastErrorMessage: wake.lastErrorMessage,
            diagnostics:
                wake.diagnostics
                + [
                    "Event routed through the local experimental shared lifecycle owner.",
                    "Product runtimeLoadable remains false.",
                ]
        )
    }

    private static func record(
        eventID: String,
        sequence: Int,
        extensionID: String,
        profileID: String,
        source: ChromeMV3ServiceWorkerEventSource,
        sender: ChromeMV3ServiceWorkerEventSenderMetadata,
        lifecycleSessionID: String?,
        payloadSummary: String,
        resultKind: ChromeMV3ServiceWorkerEventRoutingResultKind,
        wakeResult: ChromeMV3ServiceWorkerInternalWakeResult?,
        responsePayload: ChromeMV3StorageValue?,
        lastErrorMessage: String?,
        diagnostics: [String]
    ) -> ChromeMV3ServiceWorkerEventRoutingRecord {
        ChromeMV3ServiceWorkerEventRoutingRecord(
            eventID: eventID,
            sequence: sequence,
            extensionID: extensionID,
            profileID: profileID,
            source: source,
            sender: sender,
            lifecycleSessionID: lifecycleSessionID,
            payloadSummary: payloadSummary,
            sourceSurface: source.sourceContext.rawValue,
            targetListener: source.listenerEvent,
            resultKind: resultKind,
            wakeResult: wakeResult,
            responsePayload: responsePayload,
            lastErrorMessage: lastErrorMessage,
            diagnostics: uniqueSorted(diagnostics)
        )
    }
}

private func isSafeRelativePath(_ path: String) -> Bool {
    guard path.isEmpty == false,
          path.hasPrefix("/") == false,
          path.hasPrefix("~") == false,
          path.contains("\\") == false
    else { return false }
    let components = path.split(separator: "/", omittingEmptySubsequences: false)
    guard components.isEmpty == false else { return false }
    return components.allSatisfy { component in
        component != "." && component != ".." && component.isEmpty == false
    }
}

private func fileExists(_ url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    return FileManager.default.fileExists(
        atPath: url.standardizedFileURL.path,
        isDirectory: &isDirectory
    ) && isDirectory.boolValue == false
}

private func normalized(_ value: String, fallback: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? fallback : trimmed
}

private func stableID(prefix: String, parts: [String]) -> String {
    let joined = parts.joined(separator: "\u{1F}")
    let digest = SHA256.hash(data: Data(joined.utf8))
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    return "\(prefix)-\(String(hex.prefix(32)))"
}

private func uniqueSorted<T: Comparable & Hashable>(_ values: [T]) -> [T] {
    Array(Set(values)).sorted()
}

private func uniqueSorted(_ values: [String]) -> [String] {
    Array(Set(values.filter { $0.isEmpty == false })).sorted()
}
