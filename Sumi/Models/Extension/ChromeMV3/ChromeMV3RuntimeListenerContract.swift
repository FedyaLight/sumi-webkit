//
//  ChromeMV3RuntimeListenerContract.swift
//  Sumi
//
//  Pure Chrome MV3 runtime listener and event-surface contract models. This
//  file records future listener registration, capability, resolution, and
//  service-worker event availability semantics only. It does not import WebKit,
//  create or load contexts, register JavaScript listeners, register scripts,
//  wake service workers, dispatch messages, open ports, launch native
//  messaging, or schedule background work.
//

import CryptoKit
import Foundation

enum ChromeMV3RuntimeListenerSurfaceKind:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case actionPopupListener
    case nativeMessagingPortListener
    case optionsPageListener
    case runtimeOnConnectContentScript
    case runtimeOnConnectExtensionPage
    case runtimeOnConnectServiceWorker
    case runtimeOnMessageContentScript
    case runtimeOnMessageExtensionPage
    case runtimeOnMessageServiceWorker
    case serviceWorkerLifecycleEventListener
    case tabsConnectContentScript
    case tabsMessageContentScript

    static func < (
        lhs: ChromeMV3RuntimeListenerSurfaceKind,
        rhs: ChromeMV3RuntimeListenerSurfaceKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3RuntimeListenerSurface:
    Codable,
    Equatable,
    Sendable
{
    var surface: ChromeMV3RuntimeListenerSurfaceKind
    var eventName: String
    var owningContext: ChromeMV3RuntimeMessagingContextKind
    var extensionID: String
    var profileID: String
    var tabID: Int?
    var frameID: Int?
    var requiresServiceWorkerContext: Bool
    var requiresExtensionPageHost: Bool
    var requiresContentScriptInjection: Bool
    var requiresTabFrameTargeting: Bool
    var requiresPermissionActiveTabGate: Bool
    var requiresNativeMessaging: Bool
    var implementedNow: Bool
    var blockers: [String]

    static func make(
        surface: ChromeMV3RuntimeListenerSurfaceKind,
        extensionID: String,
        profileID: String,
        tabID: Int? = nil,
        frameID: Int? = nil
    ) -> ChromeMV3RuntimeListenerSurface {
        let normalizedExtensionID = extensionID.isEmpty
            ? "unknown-extension"
            : extensionID
        let normalizedProfileID = profileID.isEmpty
            ? "unknown-profile"
            : profileID
        let requirements = requirements(for: surface)
        return ChromeMV3RuntimeListenerSurface(
            surface: surface,
            eventName: eventName(for: surface),
            owningContext: owningContext(for: surface),
            extensionID: normalizedExtensionID,
            profileID: normalizedProfileID,
            tabID: requirements.requiresTabFrameTargeting ? tabID : nil,
            frameID: requirements.requiresTabFrameTargeting ? frameID : nil,
            requiresServiceWorkerContext:
                requirements.requiresServiceWorkerContext,
            requiresExtensionPageHost:
                requirements.requiresExtensionPageHost,
            requiresContentScriptInjection:
                requirements.requiresContentScriptInjection,
            requiresTabFrameTargeting:
                requirements.requiresTabFrameTargeting,
            requiresPermissionActiveTabGate:
                requirements.requiresPermissionActiveTabGate,
            requiresNativeMessaging: requirements.requiresNativeMessaging,
            implementedNow: false,
            blockers: blockers(
                for: surface,
                requirements: requirements
            )
        )
    }

    static func allModeledSurfaces(
        extensionID: String,
        profileID: String,
        tabID: Int = 1,
        frameID: Int = 0
    ) -> [ChromeMV3RuntimeListenerSurface] {
        ChromeMV3RuntimeListenerSurfaceKind.allCases
            .sorted()
            .map {
                make(
                    surface: $0,
                    extensionID: extensionID,
                    profileID: profileID,
                    tabID: tabID,
                    frameID: frameID
                )
            }
    }

    private static func eventName(
        for surface: ChromeMV3RuntimeListenerSurfaceKind
    ) -> String {
        switch surface {
        case .runtimeOnMessageServiceWorker,
             .runtimeOnMessageExtensionPage,
             .runtimeOnMessageContentScript:
            return "chrome.runtime.onMessage"
        case .runtimeOnConnectServiceWorker,
             .runtimeOnConnectExtensionPage,
             .runtimeOnConnectContentScript:
            return "chrome.runtime.onConnect"
        case .tabsMessageContentScript:
            return "chrome.runtime.onMessage delivered by chrome.tabs.sendMessage"
        case .tabsConnectContentScript:
            return "chrome.runtime.onConnect delivered by chrome.tabs.connect"
        case .actionPopupListener:
            return "chrome.runtime.onMessage and chrome.runtime.onConnect in action popup"
        case .optionsPageListener:
            return "chrome.runtime.onMessage and chrome.runtime.onConnect in options page"
        case .nativeMessagingPortListener:
            return "native messaging Port listener"
        case .serviceWorkerLifecycleEventListener:
            return "extension service-worker lifecycle event listener"
        }
    }

    private static func owningContext(
        for surface: ChromeMV3RuntimeListenerSurfaceKind
    ) -> ChromeMV3RuntimeMessagingContextKind {
        switch surface {
        case .runtimeOnMessageServiceWorker,
             .runtimeOnConnectServiceWorker,
             .nativeMessagingPortListener,
             .serviceWorkerLifecycleEventListener:
            return .serviceWorker
        case .runtimeOnMessageExtensionPage,
             .runtimeOnConnectExtensionPage:
            return .extensionPage
        case .runtimeOnMessageContentScript,
             .runtimeOnConnectContentScript,
             .tabsMessageContentScript,
             .tabsConnectContentScript:
            return .contentScript
        case .actionPopupListener:
            return .actionPopup
        case .optionsPageListener:
            return .optionsPage
        }
    }

    private static func requirements(
        for surface: ChromeMV3RuntimeListenerSurfaceKind
    ) -> Requirements {
        switch surface {
        case .runtimeOnMessageServiceWorker,
             .runtimeOnConnectServiceWorker,
             .serviceWorkerLifecycleEventListener:
            return Requirements(
                requiresServiceWorkerContext: true,
                requiresExtensionPageHost: false,
                requiresContentScriptInjection: false,
                requiresTabFrameTargeting: false,
                requiresPermissionActiveTabGate: false,
                requiresNativeMessaging: false
            )
        case .runtimeOnMessageExtensionPage,
             .runtimeOnConnectExtensionPage,
             .actionPopupListener,
             .optionsPageListener:
            return Requirements(
                requiresServiceWorkerContext: false,
                requiresExtensionPageHost: true,
                requiresContentScriptInjection: false,
                requiresTabFrameTargeting: false,
                requiresPermissionActiveTabGate: false,
                requiresNativeMessaging: false
            )
        case .runtimeOnMessageContentScript,
             .runtimeOnConnectContentScript,
             .tabsMessageContentScript,
             .tabsConnectContentScript:
            return Requirements(
                requiresServiceWorkerContext: false,
                requiresExtensionPageHost: false,
                requiresContentScriptInjection: true,
                requiresTabFrameTargeting: true,
                requiresPermissionActiveTabGate: true,
                requiresNativeMessaging: false
            )
        case .nativeMessagingPortListener:
            return Requirements(
                requiresServiceWorkerContext: true,
                requiresExtensionPageHost: false,
                requiresContentScriptInjection: false,
                requiresTabFrameTargeting: false,
                requiresPermissionActiveTabGate: false,
                requiresNativeMessaging: true
            )
        }
    }

    private static func blockers(
        for surface: ChromeMV3RuntimeListenerSurfaceKind,
        requirements: Requirements
    ) -> [String] {
        var blockers = [
            "Listener surface \(surface.rawValue) is modeled only.",
            "Listener registration is not implemented.",
            "Runtime dispatch is not implemented.",
            "No extension context is created or loaded.",
        ]
        if requirements.requiresServiceWorkerContext {
            blockers.append("Service-worker context and wake are not implemented.")
        }
        if requirements.requiresExtensionPageHost {
            blockers.append("Extension page, popup, and options hosts are not implemented.")
        }
        if requirements.requiresContentScriptInjection {
            blockers.append("Content-script injection is not implemented.")
        }
        if requirements.requiresTabFrameTargeting {
            blockers.append("Tab and frame targeting are modeled only.")
        }
        if requirements.requiresPermissionActiveTabGate {
            blockers.append("Permission and activeTab gates are not implemented.")
        }
        if requirements.requiresNativeMessaging {
            blockers.append("Native messaging listener support is blocked and deferred.")
        }
        return Array(Set(blockers)).sorted()
    }

    private struct Requirements {
        var requiresServiceWorkerContext: Bool
        var requiresExtensionPageHost: Bool
        var requiresContentScriptInjection: Bool
        var requiresTabFrameTargeting: Bool
        var requiresPermissionActiveTabGate: Bool
        var requiresNativeMessaging: Bool
    }
}

enum ChromeMV3RuntimeEventSurfaceCapabilityStatus:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case blockedByNativeMessagingDeferred
    case blockedByNoContentScriptInjection
    case blockedByNoContext
    case blockedByNoExtensionPageHost
    case blockedByNoPermissionBroker
    case blockedByNoServiceWorkerWake
    case blockedByMissingActiveTabGrant
    case blockedByMissingHostAccess
    case deferred
    case modeled
    case permissionBrokerModeled
    case unsupported

    static func < (
        lhs: ChromeMV3RuntimeEventSurfaceCapabilityStatus,
        rhs: ChromeMV3RuntimeEventSurfaceCapabilityStatus
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3RuntimeEventSurfaceCapability:
    Codable,
    Equatable,
    Sendable
{
    var surface: ChromeMV3RuntimeListenerSurfaceKind
    var statuses: [ChromeMV3RuntimeEventSurfaceCapabilityStatus]
    var requiredFutureComponent: String
    var requiredTests: [String]
    var neededForPasswordManagerSupport: Bool
    var neededBeforeContextLoad: Bool
    var neededBeforeRuntimeLoadable: Bool

    static func matrix(
        surfaces: [ChromeMV3RuntimeListenerSurface],
        permissionBroker: ChromeMV3PermissionBroker? = nil,
        targetURL: String = "https://example.com/login"
    ) -> [ChromeMV3RuntimeEventSurfaceCapability] {
        surfaces
            .map {
                capability(
                    for: $0,
                    permissionBroker: permissionBroker,
                    targetURL: targetURL
                )
            }
            .sorted { $0.surface < $1.surface }
    }

    private static func capability(
        for surface: ChromeMV3RuntimeListenerSurface,
        permissionBroker: ChromeMV3PermissionBroker?,
        targetURL: String
    ) -> ChromeMV3RuntimeEventSurfaceCapability {
        var statuses: [ChromeMV3RuntimeEventSurfaceCapabilityStatus] = [
            .modeled,
        ]
        if surface.requiresServiceWorkerContext {
            statuses.append(.blockedByNoContext)
            statuses.append(.blockedByNoServiceWorkerWake)
        }
        if surface.requiresContentScriptInjection {
            statuses.append(.blockedByNoContext)
            statuses.append(.blockedByNoContentScriptInjection)
        }
        if surface.requiresExtensionPageHost {
            statuses.append(.blockedByNoContext)
            statuses.append(.blockedByNoExtensionPageHost)
        }
        if surface.requiresPermissionActiveTabGate {
            if let permissionBroker {
                statuses.append(.permissionBrokerModeled)
                let hostDecision = permissionBroker.hostAccessDecision(
                    url: targetURL,
                    tabID: surface.tabID
                )
                if hostDecision.hasHostAccess == false {
                    statuses.append(.blockedByMissingHostAccess)
                }
                if permissionBroker.activeTabPermissionDeclared
                    && hostDecision.allowedByActiveTab == false
                {
                    statuses.append(.blockedByMissingActiveTabGrant)
                }
            } else {
                statuses.append(.blockedByNoPermissionBroker)
            }
        }
        if surface.requiresNativeMessaging {
            statuses.append(.blockedByNativeMessagingDeferred)
            statuses.append(.deferred)
        }

        return ChromeMV3RuntimeEventSurfaceCapability(
            surface: surface.surface,
            statuses: Array(Set(statuses)).sorted(),
            requiredFutureComponent:
                requiredFutureComponent(for: surface.surface),
            requiredTests: requiredTests(for: surface.surface),
            neededForPasswordManagerSupport:
                passwordManagerNeeds(surface.surface),
            neededBeforeContextLoad:
                neededBeforeContextLoad(surface.surface),
            neededBeforeRuntimeLoadable: true
        )
    }

    private static func requiredFutureComponent(
        for surface: ChromeMV3RuntimeListenerSurfaceKind
    ) -> String {
        switch surface {
        case .runtimeOnMessageServiceWorker,
             .runtimeOnConnectServiceWorker,
             .serviceWorkerLifecycleEventListener:
            return "Service-worker context, top-level listener registration, wake, idle, and unload coordinator."
        case .runtimeOnMessageExtensionPage,
             .runtimeOnConnectExtensionPage:
            return "Extension page host and runtime listener bridge."
        case .runtimeOnMessageContentScript,
             .runtimeOnConnectContentScript:
            return "Content-script injection gate and isolated listener bridge."
        case .tabsMessageContentScript,
             .tabsConnectContentScript:
            return "Tab/frame targeting, content-script injection gate, and permission broker."
        case .actionPopupListener:
            return "Action popup host and popup listener bridge."
        case .optionsPageListener:
            return "Options page host and options listener bridge."
        case .nativeMessagingPortListener:
            return "Native messaging host policy, permission checks, and Port listener bridge."
        }
    }

    private static func requiredTests(
        for surface: ChromeMV3RuntimeListenerSurfaceKind
    ) -> [String] {
        switch surface {
        case .runtimeOnMessageServiceWorker:
            return [
                "service worker runtime.onMessage listener registration",
                "sendMessage failure when service worker cannot wake",
                "lastError contract for missing service worker listener",
            ]
        case .runtimeOnConnectServiceWorker:
            return [
                "service worker runtime.onConnect listener registration",
                "Port disconnect when service worker becomes unavailable",
                "named Port routing diagnostics",
            ]
        case .runtimeOnMessageExtensionPage,
             .runtimeOnConnectExtensionPage:
            return [
                "extension page host creates listener context",
                "extension page listener cleanup on unload",
                "extension page sender metadata",
            ]
        case .runtimeOnMessageContentScript,
             .tabsMessageContentScript:
            return [
                "content script onMessage listener after authorized injection",
                "tab and frame targeted message routing",
                "no receiving end diagnostic when content script is absent",
            ]
        case .runtimeOnConnectContentScript,
             .tabsConnectContentScript:
            return [
                "content script onConnect listener after authorized injection",
                "tab and frame targeted Port routing",
                "Port disconnect when frame unloads",
            ]
        case .actionPopupListener:
            return [
                "action popup host listener registration",
                "popup listener cleanup when popup closes",
                "popup to service worker message and Port diagnostics",
            ]
        case .optionsPageListener:
            return [
                "options page host listener registration",
                "options page sender metadata without tab for embedded options",
                "options listener cleanup on close",
            ]
        case .nativeMessagingPortListener:
            return [
                "native messaging permission and host policy diagnostics",
                "native messaging Port listener remains blocked while deferred",
                "disabled module cannot start native messaging runtime",
            ]
        case .serviceWorkerLifecycleEventListener:
            return [
                "top-level service worker event listener registration",
                "idle unload diagnostics",
                "no permanent background execution",
            ]
        }
    }

    private static func passwordManagerNeeds(
        _ surface: ChromeMV3RuntimeListenerSurfaceKind
    ) -> Bool {
        switch surface {
        case .runtimeOnMessageServiceWorker,
             .runtimeOnConnectServiceWorker,
             .runtimeOnMessageContentScript,
             .runtimeOnConnectContentScript,
             .tabsMessageContentScript,
             .tabsConnectContentScript,
             .actionPopupListener,
             .nativeMessagingPortListener,
             .serviceWorkerLifecycleEventListener:
            return true
        case .runtimeOnMessageExtensionPage,
             .runtimeOnConnectExtensionPage,
             .optionsPageListener:
            return false
        }
    }

    private static func neededBeforeContextLoad(
        _ surface: ChromeMV3RuntimeListenerSurfaceKind
    ) -> Bool {
        switch surface {
        case .nativeMessagingPortListener:
            return false
        default:
            return true
        }
    }
}

enum ChromeMV3RuntimeListenerRegistrationSource:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case extensionPageScript
    case contentScript
    case actionPopupScript
    case optionsPageScript
    case serviceWorkerTopLevelScript
    case nativeMessagingRuntime
}

enum ChromeMV3RuntimeListenerDuplicateRegistrationPolicy:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case futureChromeCompatibleEventPolicyRequired
}

enum ChromeMV3RuntimeListenerLifetimePolicy:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case contentScriptDocumentBound
    case extensionPageDocumentBound
    case nativeMessagingPortBound
    case serviceWorkerTopLevelEventBound
}

enum ChromeMV3RuntimeListenerCleanupPolicy:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case requiredOnContextUnload
    case requiredOnExtensionDisable
}

enum ChromeMV3RuntimeListenerServiceWorkerIdleRelationship:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case notServiceWorkerOwned
    case serviceWorkerCanUnloadAndMustReregisterOnFutureWake
}

struct ChromeMV3RuntimeListenerRegistrationContract:
    Codable,
    Equatable,
    Sendable
{
    var listenerID: String
    var listenerSurface: ChromeMV3RuntimeListenerSurface
    var eventName: String
    var owningContext: ChromeMV3RuntimeMessagingContextKind
    var registrationSource: ChromeMV3RuntimeListenerRegistrationSource
    var duplicateRegistrationBehaviorPolicy:
        ChromeMV3RuntimeListenerDuplicateRegistrationPolicy
    var listenerLifetimePolicy:
        ChromeMV3RuntimeListenerLifetimePolicy
    var extensionDisableCleanupPolicy:
        ChromeMV3RuntimeListenerCleanupPolicy
    var contextUnloadCleanupPolicy:
        ChromeMV3RuntimeListenerCleanupPolicy
    var serviceWorkerIdleUnloadRelationship:
        ChromeMV3RuntimeListenerServiceWorkerIdleRelationship
    var registrationAllowedNow: Bool
    var registersRealListenerNow: Bool
    var blockedReasons: [String]

    static func make(
        surface: ChromeMV3RuntimeListenerSurface
    ) -> ChromeMV3RuntimeListenerRegistrationContract {
        ChromeMV3RuntimeListenerRegistrationContract(
            listenerID: ChromeMV3RuntimeListenerStableID.make(
                prefix: "listener",
                parts: [
                    surface.surface.rawValue,
                    surface.extensionID,
                    surface.profileID,
                    surface.tabID.map(String.init) ?? "no-tab",
                    surface.frameID.map(String.init) ?? "no-frame",
                ]
            ),
            listenerSurface: surface,
            eventName: surface.eventName,
            owningContext: surface.owningContext,
            registrationSource: registrationSource(for: surface.surface),
            duplicateRegistrationBehaviorPolicy:
                .futureChromeCompatibleEventPolicyRequired,
            listenerLifetimePolicy: lifetimePolicy(for: surface.surface),
            extensionDisableCleanupPolicy: .requiredOnExtensionDisable,
            contextUnloadCleanupPolicy: .requiredOnContextUnload,
            serviceWorkerIdleUnloadRelationship:
                serviceWorkerIdleRelationship(for: surface.surface),
            registrationAllowedNow: false,
            registersRealListenerNow: false,
            blockedReasons: Array(Set(
                surface.blockers
                    + [
                        "Listener registration contract is non-executing.",
                        "No JavaScript listener is registered.",
                        "No WebKit script handler or user script is installed.",
                    ]
            )).sorted()
        )
    }

    private static func registrationSource(
        for surface: ChromeMV3RuntimeListenerSurfaceKind
    ) -> ChromeMV3RuntimeListenerRegistrationSource {
        switch surface {
        case .runtimeOnMessageServiceWorker,
             .runtimeOnConnectServiceWorker,
             .serviceWorkerLifecycleEventListener:
            return .serviceWorkerTopLevelScript
        case .runtimeOnMessageExtensionPage,
             .runtimeOnConnectExtensionPage:
            return .extensionPageScript
        case .runtimeOnMessageContentScript,
             .runtimeOnConnectContentScript,
             .tabsMessageContentScript,
             .tabsConnectContentScript:
            return .contentScript
        case .actionPopupListener:
            return .actionPopupScript
        case .optionsPageListener:
            return .optionsPageScript
        case .nativeMessagingPortListener:
            return .nativeMessagingRuntime
        }
    }

    private static func lifetimePolicy(
        for surface: ChromeMV3RuntimeListenerSurfaceKind
    ) -> ChromeMV3RuntimeListenerLifetimePolicy {
        switch surface {
        case .runtimeOnMessageServiceWorker,
             .runtimeOnConnectServiceWorker,
             .serviceWorkerLifecycleEventListener:
            return .serviceWorkerTopLevelEventBound
        case .runtimeOnMessageExtensionPage,
             .runtimeOnConnectExtensionPage,
             .actionPopupListener,
             .optionsPageListener:
            return .extensionPageDocumentBound
        case .runtimeOnMessageContentScript,
             .runtimeOnConnectContentScript,
             .tabsMessageContentScript,
             .tabsConnectContentScript:
            return .contentScriptDocumentBound
        case .nativeMessagingPortListener:
            return .nativeMessagingPortBound
        }
    }

    private static func serviceWorkerIdleRelationship(
        for surface: ChromeMV3RuntimeListenerSurfaceKind
    ) -> ChromeMV3RuntimeListenerServiceWorkerIdleRelationship {
        switch surface {
        case .runtimeOnMessageServiceWorker,
             .runtimeOnConnectServiceWorker,
             .serviceWorkerLifecycleEventListener,
             .nativeMessagingPortListener:
            return .serviceWorkerCanUnloadAndMustReregisterOnFutureWake
        default:
            return .notServiceWorkerOwned
        }
    }
}

struct ChromeMV3RuntimeListenerRegistrySnapshot:
    Codable,
    Equatable,
    Sendable
{
    var registrations: [ChromeMV3RuntimeListenerRegistrationContract]
    var listenerRegistrationImplementedNow: Bool
    var dispatchImplementedNow: Bool
    var diagnostics: [String]

    static func modeled(
        extensionID: String,
        profileID: String,
        tabID: Int = 1,
        frameID: Int = 0
    ) -> ChromeMV3RuntimeListenerRegistrySnapshot {
        let registrations = ChromeMV3RuntimeListenerSurface
            .allModeledSurfaces(
                extensionID: extensionID,
                profileID: profileID,
                tabID: tabID,
                frameID: frameID
            )
            .map(ChromeMV3RuntimeListenerRegistrationContract.make)
            .sorted { $0.listenerID < $1.listenerID }
        return ChromeMV3RuntimeListenerRegistrySnapshot(
            registrations: registrations,
            listenerRegistrationImplementedNow: false,
            dispatchImplementedNow: false,
            diagnostics: [
                "Listener registry snapshot is modeled only.",
                "No listeners are registered.",
                "No messages are dispatched.",
            ]
        )
    }

    static let empty = ChromeMV3RuntimeListenerRegistrySnapshot(
        registrations: [],
        listenerRegistrationImplementedNow: false,
        dispatchImplementedNow: false,
        diagnostics: [
            "Listener registry snapshot is empty.",
            "No receiving listener is modeled.",
        ]
    )

    func registrations(
        matching surfaces: [ChromeMV3RuntimeListenerSurfaceKind]
    ) -> [ChromeMV3RuntimeListenerRegistrationContract] {
        let wanted = Set(surfaces)
        return registrations.filter {
            wanted.contains($0.listenerSurface.surface)
        }
        .sorted { $0.listenerID < $1.listenerID }
    }
}

struct ChromeMV3RuntimeServiceWorkerEventAvailabilityContract:
    Codable,
    Equatable,
    Sendable
{
    var serviceWorkerScriptDeclared: Bool
    var serviceWorkerObjectAcceptedByWebKit: Bool
    var serviceWorkerContextCreated: Bool
    var serviceWorkerEventListenerRegistrationImplemented: Bool
    var serviceWorkerWakeImplemented: Bool
    var serviceWorkerIdleLifecycleImplemented: Bool
    var permanentBackgroundForbidden: Bool
    var serviceWorkerListenersModeled: Bool
    var serviceWorkerListenersAvailableNow: Bool
    var serviceWorkerWakeAvailableNow: Bool
    var requiredBeforeRuntimeDispatch: Bool
    var blockers: [String]

    static func make(
        serviceWorkerScriptDeclared: Bool,
        serviceWorkerObjectAcceptedByWebKit: Bool = false
    ) -> ChromeMV3RuntimeServiceWorkerEventAvailabilityContract {
        ChromeMV3RuntimeServiceWorkerEventAvailabilityContract(
            serviceWorkerScriptDeclared: serviceWorkerScriptDeclared,
            serviceWorkerObjectAcceptedByWebKit:
                serviceWorkerObjectAcceptedByWebKit,
            serviceWorkerContextCreated: false,
            serviceWorkerEventListenerRegistrationImplemented: false,
            serviceWorkerWakeImplemented: false,
            serviceWorkerIdleLifecycleImplemented: false,
            permanentBackgroundForbidden: true,
            serviceWorkerListenersModeled: true,
            serviceWorkerListenersAvailableNow: false,
            serviceWorkerWakeAvailableNow: false,
            requiredBeforeRuntimeDispatch: true,
            blockers: uniqueSorted(
                [
                    serviceWorkerScriptDeclared
                        ? nil
                        : "No background service-worker script is declared.",
                    "Service-worker context is not created.",
                    "Service-worker event listener registration is not implemented.",
                    "Service-worker wake is not implemented.",
                    "Service-worker idle lifecycle is not implemented.",
                    "Permanent background execution is forbidden.",
                ].compactMap { $0 }
            )
        )
    }

    static func diagnosticFixture(
        serviceWorkerScriptDeclared: Bool = true
    ) -> ChromeMV3RuntimeServiceWorkerEventAvailabilityContract {
        var contract = make(
            serviceWorkerScriptDeclared: serviceWorkerScriptDeclared,
            serviceWorkerObjectAcceptedByWebKit: true
        )
        contract.serviceWorkerContextCreated = true
        return contract
    }

    private static func uniqueSorted(_ values: [String]) -> [String] {
        Array(Set(values.filter { $0.isEmpty == false })).sorted()
    }
}

struct ChromeMV3RuntimeContentScriptListenerAvailabilityState:
    Codable,
    Equatable,
    Sendable
{
    var contentScriptsDeclared: Bool
    var hostAccessRequired: Bool
    var hostAccessGrantedByBroker: Bool
    var activeTabGrantAvailable: Bool
    var permissionBrokerModeled: Bool
    var contentScriptInjectionImplemented: Bool
    var contentScriptListenersModeled: Bool
    var contentScriptListenersAvailableNow: Bool
    var blockers: [String]

    static func blocked(
        contentScriptsDeclared: Bool,
        permissionBroker: ChromeMV3PermissionBroker? = nil,
        targetURL: String = "https://example.com/login",
        tabID: Int = 1
    ) -> ChromeMV3RuntimeContentScriptListenerAvailabilityState {
        let decision = permissionBroker?.hostAccessDecision(
            url: targetURL,
            tabID: tabID
        )
        let permissionBlockers: [String]
        if let decision, decision.hasHostAccess == false {
            permissionBlockers = [
                "Content-script listener surface requires host access; broker decision is \(decision.status.rawValue).",
            ] + decision.diagnostics
        } else {
            permissionBlockers = []
        }
        return ChromeMV3RuntimeContentScriptListenerAvailabilityState(
            contentScriptsDeclared: contentScriptsDeclared,
            hostAccessRequired: contentScriptsDeclared,
            hostAccessGrantedByBroker: decision?.hasHostAccess ?? false,
            activeTabGrantAvailable:
                decision?.allowedByActiveTab ?? false,
            permissionBrokerModeled: permissionBroker != nil,
            contentScriptInjectionImplemented: false,
            contentScriptListenersModeled: true,
            contentScriptListenersAvailableNow: false,
            blockers: Array(Set(
                [
                    "Content-script injection is not implemented.",
                    "Content-script listeners are not registered.",
                ] + permissionBlockers
            )).sorted()
        )
    }

    static func diagnosticFixture(
        contentScriptsDeclared: Bool = true
    ) -> ChromeMV3RuntimeContentScriptListenerAvailabilityState {
        ChromeMV3RuntimeContentScriptListenerAvailabilityState(
            contentScriptsDeclared: contentScriptsDeclared,
            hostAccessRequired: contentScriptsDeclared,
            hostAccessGrantedByBroker: true,
            activeTabGrantAvailable: false,
            permissionBrokerModeled: true,
            contentScriptInjectionImplemented: true,
            contentScriptListenersModeled: true,
            contentScriptListenersAvailableNow: false,
            blockers: [
                "Content-script listeners are modeled but registration remains disabled.",
            ]
        )
    }
}

struct ChromeMV3RuntimeExtensionPageListenerAvailabilityState:
    Codable,
    Equatable,
    Sendable
{
    var extensionPageHostRequired: Bool
    var extensionPageHostImplemented: Bool
    var extensionPageListenersModeled: Bool
    var extensionPageListenersAvailableNow: Bool
    var blockers: [String]

    static func blocked(
        extensionPageHostRequired: Bool
    ) -> ChromeMV3RuntimeExtensionPageListenerAvailabilityState {
        ChromeMV3RuntimeExtensionPageListenerAvailabilityState(
            extensionPageHostRequired: extensionPageHostRequired,
            extensionPageHostImplemented: false,
            extensionPageListenersModeled: true,
            extensionPageListenersAvailableNow: false,
            blockers: [
                "Extension page, popup, and options hosts are not implemented.",
                "Extension page listeners are not registered.",
            ]
        )
    }

    static func diagnosticFixture(
        extensionPageHostRequired: Bool = true
    ) -> ChromeMV3RuntimeExtensionPageListenerAvailabilityState {
        ChromeMV3RuntimeExtensionPageListenerAvailabilityState(
            extensionPageHostRequired: extensionPageHostRequired,
            extensionPageHostImplemented: true,
            extensionPageListenersModeled: true,
            extensionPageListenersAvailableNow: false,
            blockers: [
                "Extension page listeners are modeled but registration remains disabled.",
            ]
        )
    }
}

struct ChromeMV3RuntimeListenerResolutionResult:
    Codable,
    Equatable,
    Sendable
{
    var routeKind: ChromeMV3RuntimeMessagingRouteKind
    var expectedListenerSurfaces: [ChromeMV3RuntimeListenerSurfaceKind]
    var modeledListenerIDs: [String]
    var receivingListenerModeled: Bool
    var receivingListenerAvailableNow: Bool
    var wouldNeedServiceWorkerWake: Bool
    var wouldNeedContentScriptInjection: Bool
    var wouldNeedExtensionPageHost: Bool
    var errorContract: ChromeMV3RuntimeLastErrorContract?
    var diagnostics: [String]
}

enum ChromeMV3RuntimeListenerResolver {
    static func resolve(
        route: ChromeMV3RuntimeMessagingRoute,
        listenerRegistrySnapshot registry:
            ChromeMV3RuntimeListenerRegistrySnapshot,
        permissionDecision:
            ChromeMV3RuntimeMessagingPermissionDecision,
        serviceWorkerAvailability:
            ChromeMV3RuntimeServiceWorkerEventAvailabilityContract,
        contentScriptAvailability:
            ChromeMV3RuntimeContentScriptListenerAvailabilityState,
        extensionPageAvailability:
            ChromeMV3RuntimeExtensionPageListenerAvailabilityState
    ) -> ChromeMV3RuntimeListenerResolutionResult {
        let expected = expectedReceivingSurfaces(for: route.kind)
        let registrations = registry.registrations(matching: expected)
        let receivingListenerModeled = registrations.isEmpty == false
        let surfaceValues = registrations.map(\.listenerSurface)
        let needsServiceWorker = route.requiresServiceWorkerWake
            || surfaceValues.contains { $0.requiresServiceWorkerContext }
        let needsContentScript = surfaceValues.contains {
            $0.requiresContentScriptInjection
        } || expected.contains(.tabsMessageContentScript)
            || expected.contains(.tabsConnectContentScript)
        let needsExtensionPage = surfaceValues.contains {
            $0.requiresExtensionPageHost
        } || expected.contains(.actionPopupListener)
            || expected.contains(.optionsPageListener)
        let error = firstBlockingError(
            route: route,
            receivingListenerModeled: receivingListenerModeled,
            registry: registry,
            permissionDecision: permissionDecision,
            serviceWorkerAvailability: serviceWorkerAvailability,
            contentScriptAvailability: contentScriptAvailability,
            extensionPageAvailability: extensionPageAvailability,
            needsServiceWorker: needsServiceWorker,
            needsContentScript: needsContentScript,
            needsExtensionPage: needsExtensionPage
        )

        return ChromeMV3RuntimeListenerResolutionResult(
            routeKind: route.kind,
            expectedListenerSurfaces: expected.sorted(),
            modeledListenerIDs: registrations.map(\.listenerID).sorted(),
            receivingListenerModeled: receivingListenerModeled,
            receivingListenerAvailableNow: false,
            wouldNeedServiceWorkerWake: needsServiceWorker,
            wouldNeedContentScriptInjection: needsContentScript,
            wouldNeedExtensionPageHost: needsExtensionPage,
            errorContract:
                ChromeMV3RuntimeLastErrorContract.contract(for: error),
            diagnostics: diagnostics(
                route: route,
                expected: expected,
                receivingListenerModeled: receivingListenerModeled,
                error: error,
                registry: registry,
                permissionDecision: permissionDecision
            )
        )
    }

    static func expectedReceivingSurfaces(
        for route: ChromeMV3RuntimeMessagingRouteKind
    ) -> [ChromeMV3RuntimeListenerSurfaceKind] {
        switch route {
        case .contentScriptToServiceWorker,
             .extensionPageToServiceWorker,
             .actionPopupToServiceWorker,
             .optionsPageToServiceWorker,
             .runtimeSendMessage:
            return [.runtimeOnMessageServiceWorker]
        case .runtimeConnect:
            return [.runtimeOnConnectServiceWorker]
        case .serviceWorkerToTab,
             .serviceWorkerToFrame,
             .tabsSendMessage:
            return [
                .runtimeOnMessageContentScript,
                .tabsMessageContentScript,
            ]
        case .tabsConnect:
            return [
                .runtimeOnConnectContentScript,
                .tabsConnectContentScript,
            ]
        case .serviceWorkerToExtensionPage:
            return [.runtimeOnMessageExtensionPage]
        case .nativeMessaging:
            return [.nativeMessagingPortListener]
        }
    }

    private static func firstBlockingError(
        route: ChromeMV3RuntimeMessagingRoute,
        receivingListenerModeled: Bool,
        registry: ChromeMV3RuntimeListenerRegistrySnapshot,
        permissionDecision:
            ChromeMV3RuntimeMessagingPermissionDecision,
        serviceWorkerAvailability:
            ChromeMV3RuntimeServiceWorkerEventAvailabilityContract,
        contentScriptAvailability:
            ChromeMV3RuntimeContentScriptListenerAvailabilityState,
        extensionPageAvailability:
            ChromeMV3RuntimeExtensionPageListenerAvailabilityState,
        needsServiceWorker: Bool,
        needsContentScript: Bool,
        needsExtensionPage: Bool
    ) -> ChromeMV3RuntimeLastErrorCase {
        guard receivingListenerModeled else {
            return .noReceivingEnd
        }
        if route.requiresNativeMessaging {
            return .nativeMessagingBlocked
        }
        if permissionDecision.allowedForFutureDispatch == false {
            switch permissionDecision.missingGrantReason {
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
        if needsContentScript
            && contentScriptAvailability
                .contentScriptInjectionImplemented == false
        {
            return .noReceivingEnd
        }
        if needsExtensionPage
            && extensionPageAvailability.extensionPageHostImplemented == false
        {
            return .contextNotLoaded
        }
        if needsServiceWorker
            && serviceWorkerAvailability.serviceWorkerContextCreated == false
        {
            return .contextNotLoaded
        }
        if route.requiresServiceWorkerWake
            && serviceWorkerAvailability.serviceWorkerWakeAvailableNow == false
        {
            return .serviceWorkerUnavailable
        }
        if registry.listenerRegistrationImplementedNow == false {
            return .listenerRegistrationNotImplemented
        }
        return .routeNotImplemented
    }

    private static func diagnostics(
        route: ChromeMV3RuntimeMessagingRoute,
        expected: [ChromeMV3RuntimeListenerSurfaceKind],
        receivingListenerModeled: Bool,
        error: ChromeMV3RuntimeLastErrorCase?,
        registry: ChromeMV3RuntimeListenerRegistrySnapshot,
        permissionDecision:
            ChromeMV3RuntimeMessagingPermissionDecision
    ) -> [String] {
        var diagnostics = [
            "Route \(route.kind.rawValue) listener resolution is modeled only.",
            "Expected listener surfaces: \(expected.sorted().map(\.rawValue).joined(separator: ","))",
            "receivingListenerAvailableNow remains false.",
            "canRegisterListenersNow remains false.",
            "canDispatchMessagesNow remains false.",
            "canWakeServiceWorkerNow remains false.",
            permissionDecision.diagnosticReason,
        ]
        diagnostics.append(
            receivingListenerModeled
                ? "A receiving listener surface is modeled."
                : "No receiving listener surface is modeled."
        )
        if let error {
            diagnostics.append(
                "Future listener resolution error contract: \(error.rawValue)."
            )
        }
        diagnostics.append(contentsOf: registry.diagnostics)
        diagnostics.append(contentsOf: permissionDecision.brokerDiagnostics)
        return Array(Set(diagnostics)).sorted()
    }
}

struct ChromeMV3PasswordManagerListenerSummary:
    Codable,
    Equatable,
    Sendable
{
    var contentScriptListenerRequired: Bool
    var serviceWorkerOnMessageRequired: Bool
    var popupOnMessageOnConnectRequired: Bool
    var portListenerRequiredForUnlockFillFlow: Bool
    var nativeMessagingListenerRequiredButBlocked: Bool
    var contentScriptInjectionImplemented: Bool
    var serviceWorkerWakeImplemented: Bool
    var extensionPageHostImplemented: Bool
    var passwordManagerListenerReady: Bool
    var blockers: [String]
}

struct ChromeMV3RuntimeListenerContractReportSummary:
    Codable,
    Equatable,
    Sendable
{
    var reportID: String
    var reportFileName: String
    var listenerSurfaceKindsModeled: [ChromeMV3RuntimeListenerSurfaceKind]
    var canRegisterListenersNow: Bool
    var canResolveReceivingListenersNow: Bool
    var canDispatchMessagesNow: Bool
    var canWakeServiceWorkerNow: Bool
    var canCreateContextNow: Bool
    var canLoadContextNow: Bool
    var runtimeLoadable: Bool
    var passwordManagerListenerReady: Bool
    var permissionBrokerReadinessReportSummary:
        ChromeMV3PermissionBrokerReadinessReportSummary? = nil
}

struct ChromeMV3RuntimeListenerContractReport:
    Codable,
    Equatable,
    Sendable
{
    var schemaVersion: Int
    var id: String
    var reportFileName: String
    var candidateID: String
    var extensionID: String
    var profileID: String
    var listenerSurfaceCoverage: [ChromeMV3RuntimeListenerSurface]
    var eventSurfaceCapabilityMatrix:
        [ChromeMV3RuntimeEventSurfaceCapability]
    var listenerRegistrationContractCoverage:
        [ChromeMV3RuntimeListenerRegistrationContract]
    var listenerResolutionContractCoverage:
        [ChromeMV3RuntimeListenerResolutionResult]
    var serviceWorkerEventAvailabilityContract:
        ChromeMV3RuntimeServiceWorkerEventAvailabilityContract
    var passwordManagerListenerSummary:
        ChromeMV3PasswordManagerListenerSummary
    var permissionBrokerReadinessReportSummary:
        ChromeMV3PermissionBrokerReadinessReportSummary? = nil
    var canRegisterListenersNow: Bool
    var canResolveReceivingListenersNow: Bool
    var canDispatchMessagesNow: Bool
    var canWakeServiceWorkerNow: Bool
    var canCreateContextNow: Bool
    var canLoadContextNow: Bool
    var runtimeLoadable: Bool
    var documentationSources: [ChromeMV3ManifestRewritePreviewSource]
    var diagnostics: [String]

    var summary: ChromeMV3RuntimeListenerContractReportSummary {
        ChromeMV3RuntimeListenerContractReportSummary(
            reportID: id,
            reportFileName: reportFileName,
            listenerSurfaceKindsModeled:
                listenerSurfaceCoverage.map(\.surface).sorted(),
            canRegisterListenersNow: false,
            canResolveReceivingListenersNow: false,
            canDispatchMessagesNow: false,
            canWakeServiceWorkerNow: false,
            canCreateContextNow: false,
            canLoadContextNow: false,
            runtimeLoadable: false,
            passwordManagerListenerReady: false,
            permissionBrokerReadinessReportSummary:
                permissionBrokerReadinessReportSummary
        )
    }
}

enum ChromeMV3RuntimeListenerContractReportWriter {
    static let reportFileName = "runtime-listener-contract-report.json"

    @discardableResult
    static func write(
        _ report: ChromeMV3RuntimeListenerContractReport,
        toRewrittenBundleRoot rootURL: URL
    ) throws -> ChromeMV3RuntimeListenerContractReport {
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

enum ChromeMV3RuntimeListenerContractReportGenerator {
    static func makeReport(
        prerequisitesReport prerequisites:
            ChromeMV3RuntimeBridgePrerequisitesReport,
        contextReadinessReport contextReport:
            ChromeMV3ContextReadinessReport? = nil,
        profileID: String = "diagnostic-profile"
    ) -> ChromeMV3RuntimeListenerContractReport {
        let extensionID = prerequisites.candidateID
        let permissionReport =
            ChromeMV3PermissionBrokerReadinessReportGenerator.makeReport(
                prerequisitesReport: prerequisites,
                profileID: profileID
            )
        let permissionBroker = ChromeMV3PermissionBroker(
            state: ChromeMV3PermissionBrokerState.from(
                manifestFacts: prerequisites.manifestFacts,
                extensionID: extensionID,
                profileID: profileID
            )
        )
        let surfaces = ChromeMV3RuntimeListenerSurface.allModeledSurfaces(
            extensionID: extensionID,
            profileID: profileID
        )
        let matrix = ChromeMV3RuntimeEventSurfaceCapability.matrix(
            surfaces: surfaces,
            permissionBroker: permissionBroker
        )
        let registrations = surfaces
            .map(ChromeMV3RuntimeListenerRegistrationContract.make)
            .sorted { $0.listenerID < $1.listenerID }
        let registry = ChromeMV3RuntimeListenerRegistrySnapshot(
            registrations: registrations,
            listenerRegistrationImplementedNow: false,
            dispatchImplementedNow: false,
            diagnostics: [
                "Listener registry snapshot is report-local and non-executing.",
                "No listeners are registered.",
            ]
        )
        let serviceWorkerAvailability =
            ChromeMV3RuntimeServiceWorkerEventAvailabilityContract.make(
                serviceWorkerScriptDeclared:
                    prerequisites.manifestFacts
                    .backgroundServiceWorkerPresent,
                serviceWorkerObjectAcceptedByWebKit:
                    contextReport?.objectAcceptedByWebKit ?? false
            )
        let contentAvailability =
            ChromeMV3RuntimeContentScriptListenerAvailabilityState.blocked(
                contentScriptsDeclared:
                    prerequisites.manifestFacts.contentScriptsPresent,
                permissionBroker: permissionBroker
            )
        let pageAvailability =
            ChromeMV3RuntimeExtensionPageListenerAvailabilityState.blocked(
                extensionPageHostRequired:
                    prerequisites.manifestFacts.actionPopupPresent
            )
        let resolution = ChromeMV3RuntimeMessagingRoute
            .allModeledRoutes(
                extensionID: extensionID,
                profileID: profileID
            )
            .map { route in
                let permission =
                    ChromeMV3RuntimeMessagingPermissionDecision.evaluate(
                        route: route,
                        permissionBroker: permissionBroker
                    )
                return ChromeMV3RuntimeListenerResolver.resolve(
                    route: route,
                    listenerRegistrySnapshot: registry,
                    permissionDecision: permission,
                    serviceWorkerAvailability: serviceWorkerAvailability,
                    contentScriptAvailability: contentAvailability,
                    extensionPageAvailability: pageAvailability
                )
            }
            .sorted { $0.routeKind < $1.routeKind }
        let passwordSummary = passwordManagerSummary(
            prerequisites: prerequisites,
            matrix: matrix
        )

        return ChromeMV3RuntimeListenerContractReport(
            schemaVersion: 1,
            id: id(
                candidateID: prerequisites.candidateID,
                prerequisiteReportID: prerequisites.id,
                surfaces: surfaces.map(\.surface)
            ),
            reportFileName:
                ChromeMV3RuntimeListenerContractReportWriter.reportFileName,
            candidateID: prerequisites.candidateID,
            extensionID: extensionID,
            profileID: profileID,
            listenerSurfaceCoverage: surfaces.sorted {
                $0.surface < $1.surface
            },
            eventSurfaceCapabilityMatrix: matrix,
            listenerRegistrationContractCoverage: registrations,
            listenerResolutionContractCoverage: resolution,
            serviceWorkerEventAvailabilityContract:
                serviceWorkerAvailability,
            passwordManagerListenerSummary: passwordSummary,
            permissionBrokerReadinessReportSummary:
                permissionReport.summary,
            canRegisterListenersNow: false,
            canResolveReceivingListenersNow: false,
            canDispatchMessagesNow: false,
            canWakeServiceWorkerNow: false,
            canCreateContextNow: false,
            canLoadContextNow: false,
            runtimeLoadable: false,
            documentationSources: documentationSources(),
            diagnostics: [
                "Runtime listener contracts exist for future bridge implementation.",
                "Event-surface capability matrix is deterministic.",
                "Listener registration remains disabled.",
                "Receiving listener resolution remains diagnostic-only.",
                "Message dispatch remains disabled.",
                "Service-worker wake remains disabled.",
                "Context creation and loading remain disabled.",
                "Sumi does not claim Chrome MV3 runtime support.",
            ]
        )
    }

    static func makeReport(
        loadingPrerequisitesReportFrom rootURL: URL,
        fileManager: FileManager = .default
    ) throws -> ChromeMV3RuntimeListenerContractReport {
        let rootURL = rootURL.standardizedFileURL
        let prerequisitesURL = rootURL.appendingPathComponent(
            ChromeMV3RuntimeBridgePrerequisitesReportWriter.reportFileName
        )
        let data = try Data(contentsOf: prerequisitesURL)
        let prerequisites = try JSONDecoder().decode(
            ChromeMV3RuntimeBridgePrerequisitesReport.self,
            from: data
        )
        let contextReport = loadContextReport(
            prerequisites: prerequisites,
            fileManager: fileManager
        )
        return makeReport(
            prerequisitesReport: prerequisites,
            contextReadinessReport: contextReport
        )
    }

    private static func loadContextReport(
        prerequisites: ChromeMV3RuntimeBridgePrerequisitesReport,
        fileManager: FileManager
    ) -> ChromeMV3ContextReadinessReport? {
        let url = URL(
            fileURLWithPath: prerequisites.contextReadinessReportPath
        ).standardizedFileURL
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(
            ChromeMV3ContextReadinessReport.self,
            from: data
        )
    }

    private static func passwordManagerSummary(
        prerequisites: ChromeMV3RuntimeBridgePrerequisitesReport,
        matrix: [ChromeMV3RuntimeEventSurfaceCapability]
    ) -> ChromeMV3PasswordManagerListenerSummary {
        let summary = prerequisites.passwordManagerPrerequisiteSummary
        let nativeRequired =
            summary.nativeMessagingPermissionPresent
                || prerequisites.nativeMessagingPrerequisites
                .nativeMessagingDetected
        let matrixBlockers = matrix
            .filter(\.neededForPasswordManagerSupport)
            .flatMap { capability in
                capability.statuses
                    .filter { $0 != .modeled }
                    .map {
                        "\(capability.surface.rawValue): \($0.rawValue)"
                    }
            }
        return ChromeMV3PasswordManagerListenerSummary(
            contentScriptListenerRequired: summary.contentScriptsPresent,
            serviceWorkerOnMessageRequired: true,
            popupOnMessageOnConnectRequired: summary.actionPopupPresent,
            portListenerRequiredForUnlockFillFlow:
                summary.contentScriptsPresent || summary.actionPopupPresent,
            nativeMessagingListenerRequiredButBlocked: nativeRequired,
            contentScriptInjectionImplemented: false,
            serviceWorkerWakeImplemented: false,
            extensionPageHostImplemented: false,
            passwordManagerListenerReady: false,
            blockers: Array(Set(
                summary.blockers
                    + matrixBlockers
                    + [
                        "Password-manager content script listener is required but content-script injection is not implemented.",
                        "Password-manager service worker onMessage listener is required but service-worker wake is not implemented.",
                        "Password-manager popup onMessage/onConnect listener is required but extension page host is not implemented.",
                        "Password-manager Port listener is required for unlock/fill flow but Port dispatch is not implemented.",
                        "Native messaging listener is required but blocked and deferred.",
                    ]
            )).sorted()
        )
    }

    private static func documentationSources()
        -> [ChromeMV3ManifestRewritePreviewSource]
    {
        [
            source(
                title: "Chrome message passing",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/messaging",
                note: "Defines one-time requests, runtime and tabs messaging, long-lived Port channels, and content script messaging boundaries."
            ),
            source(
                title: "Chrome runtime API",
                url: "https://developer.chrome.com/docs/extensions/reference/api/runtime",
                note: "Defines runtime message and connection events, MessageSender metadata, Port behavior, and lastError reporting."
            ),
            source(
                title: "Chrome tabs API",
                url: "https://developer.chrome.com/docs/extensions/reference/api/tabs",
                note: "Defines tab-targeted message and connection delivery to content scripts, including frame and document targeting."
            ),
            source(
                title: "Chrome service-worker events",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/events",
                note: "Defines top-level event listener registration for extension service workers."
            ),
            source(
                title: "Chrome extension service-worker lifecycle",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle",
                note: "Defines event-driven service-worker lifetime, idle unload, and wake behavior."
            ),
            source(
                title: "Chrome action popup",
                url: "https://developer.chrome.com/docs/extensions/develop/ui/add-popup",
                note: "Defines action popup hosting and popup script behavior."
            ),
            source(
                title: "Chrome options pages",
                url: "https://developer.chrome.com/docs/extensions/develop/ui/options-page",
                note: "Defines options page hosting, tab differences, and messaging metadata."
            ),
            source(
                title: "Chrome content scripts",
                url: "https://developer.chrome.com/docs/extensions/develop/concepts/content-scripts",
                note: "Defines content script API access and messaging restrictions."
            ),
            ChromeMV3ManifestRewritePreviewSource(
                kind: .currentSumiCode,
                title: "Sumi user-script broker",
                url: nil,
                note: "Existing user-script systems are reference only and are not used by listener contracts."
            ),
            ChromeMV3ManifestRewritePreviewSource(
                kind: .currentSumiCode,
                title: "Sumi module gates and profile diagnostics",
                url: nil,
                note: "Disabled extension module paths return nil and do not write listener reports."
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

    private static func id(
        candidateID: String,
        prerequisiteReportID: String,
        surfaces: [ChromeMV3RuntimeListenerSurfaceKind]
    ) -> String {
        ChromeMV3RuntimeListenerStableID.make(
            prefix: "runtime-listener-contract",
            parts: [
                candidateID,
                prerequisiteReportID,
                surfaces.sorted().map(\.rawValue).joined(separator: ","),
            ]
        )
    }
}

private enum ChromeMV3RuntimeListenerStableID {
    static func make(prefix: String, parts: [String]) -> String {
        let seed = parts.joined(separator: "|")
        return "\(prefix)-\(sha256Hex(Data(seed.utf8)).prefix(32))"
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
