//
//  ChromeMV3RuntimeMessagingContract.swift
//  Sumi
//
//  Pure Chrome MV3 runtime messaging contract models. This file records future
//  route, sender metadata, permission, lastError, Port, and report semantics
//  only. It does not import WebKit, create or load contexts, register scripts,
//  execute extension code, wake service workers, launch native messaging, or
//  schedule background work.
//

import CryptoKit
import Foundation

enum ChromeMV3RuntimeMessagingRouteKind:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case actionPopupToServiceWorker
    case contentScriptToServiceWorker
    case extensionPageToServiceWorker
    case nativeMessaging
    case optionsPageToServiceWorker
    case runtimeConnect
    case runtimeSendMessage
    case serviceWorkerToExtensionPage
    case serviceWorkerToFrame
    case serviceWorkerToTab
    case tabsConnect
    case tabsSendMessage

    static func < (
        lhs: ChromeMV3RuntimeMessagingRouteKind,
        rhs: ChromeMV3RuntimeMessagingRouteKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3RuntimeMessagingContextKind:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case actionPopup
    case contentScript
    case extensionPage
    case frame
    case nativeApplication
    case optionsPage
    case serviceWorker
    case tab
    case unknown

    static func < (
        lhs: ChromeMV3RuntimeMessagingContextKind,
        rhs: ChromeMV3RuntimeMessagingContextKind
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3RuntimeMessagingSourceURLExposurePolicy:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case notApplicable
    case exposeExtensionOrigin
    case exposeWhenHostPermissionOrActiveTab
    case redactUntilPermission
}

enum ChromeMV3RuntimeMessagingURLExposureStatus:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case notApplicable
    case exposed
    case redacted
}

struct ChromeMV3RuntimeMessagingEndpoint:
    Codable,
    Equatable,
    Sendable
{
    var context: ChromeMV3RuntimeMessagingContextKind
    var extensionID: String
    var profileID: String
    var tabID: Int?
    var frameID: Int?
    var documentID: String?
    var url: String?
    var origin: String?
    var privateProfile: Bool

    init(
        context: ChromeMV3RuntimeMessagingContextKind,
        extensionID: String,
        profileID: String,
        tabID: Int? = nil,
        frameID: Int? = nil,
        documentID: String? = nil,
        url: String? = nil,
        origin: String? = nil,
        privateProfile: Bool = false
    ) {
        self.context = context
        self.extensionID = extensionID.isEmpty
            ? "unknown-extension"
            : extensionID
        self.profileID = profileID.isEmpty ? "unknown-profile" : profileID
        self.tabID = tabID
        self.frameID = frameID
        self.documentID = documentID
        self.url = url
        self.origin = origin ?? ChromeMV3RuntimeMessagingURL.origin(from: url)
        self.privateProfile = privateProfile
    }
}

struct ChromeMV3RuntimeMessagingRoute:
    Codable,
    Equatable,
    Sendable
{
    var kind: ChromeMV3RuntimeMessagingRouteKind
    var source: ChromeMV3RuntimeMessagingEndpoint
    var target: ChromeMV3RuntimeMessagingEndpoint
    var extensionID: String
    var profileID: String
    var tabID: Int?
    var frameID: Int?
    var documentID: String?
    var sourceURLExposurePolicy:
        ChromeMV3RuntimeMessagingSourceURLExposurePolicy
    var requiresServiceWorkerWake: Bool
    var requiresTabPermission: Bool
    var requiresHostPermission: Bool
    var requiresActiveTab: Bool
    var requiresNativeMessaging: Bool
    var implementedNow: Bool
    var blockers: [String]

    static func make(
        kind: ChromeMV3RuntimeMessagingRouteKind,
        extensionID: String,
        profileID: String,
        tabID: Int? = nil,
        frameID: Int? = nil,
        documentID: String? = nil,
        sourceURL: String? = nil,
        targetURL: String? = nil,
        privateProfile: Bool = false
    ) -> ChromeMV3RuntimeMessagingRoute {
        let sourceContext = Self.sourceContext(for: kind)
        let targetContext = Self.targetContext(for: kind)
        let source = ChromeMV3RuntimeMessagingEndpoint(
            context: sourceContext,
            extensionID: extensionID,
            profileID: profileID,
            tabID: Self.sourceUsesTab(kind) ? tabID : nil,
            frameID: Self.sourceUsesFrame(kind) ? frameID : nil,
            documentID: Self.sourceUsesFrame(kind) ? documentID : nil,
            url: sourceURL,
            privateProfile: privateProfile
        )
        let target = ChromeMV3RuntimeMessagingEndpoint(
            context: targetContext,
            extensionID: extensionID,
            profileID: profileID,
            tabID: Self.targetUsesTab(kind) ? tabID : nil,
            frameID: Self.targetUsesFrame(kind) ? frameID : nil,
            documentID: Self.targetUsesFrame(kind) ? documentID : nil,
            url: targetURL,
            privateProfile: privateProfile
        )

        return ChromeMV3RuntimeMessagingRoute(
            kind: kind,
            source: source,
            target: target,
            extensionID: source.extensionID,
            profileID: source.profileID,
            tabID: tabID,
            frameID: frameID,
            documentID: documentID,
            sourceURLExposurePolicy: Self.urlExposurePolicy(for: kind),
            requiresServiceWorkerWake:
                Self.requiresServiceWorkerWake(kind),
            requiresTabPermission: Self.requiresTabPermission(kind),
            requiresHostPermission: Self.requiresHostPermission(kind),
            requiresActiveTab: Self.requiresActiveTab(kind),
            requiresNativeMessaging: kind == .nativeMessaging,
            implementedNow: false,
            blockers: [
                "Route is a contract only; runtime dispatch is not implemented.",
                "Listener registration and delivery are not implemented.",
            ] + (kind == .nativeMessaging
                ? [
                    "Native messaging is blocked and deferred.",
                ]
                : [])
        )
    }

    static func allModeledRoutes(
        extensionID: String,
        profileID: String,
        tabID: Int = 1,
        frameID: Int = 0,
        documentID: String = "document-0",
        pageURL: String = "https://example.com/login"
    ) -> [ChromeMV3RuntimeMessagingRoute] {
        ChromeMV3RuntimeMessagingRouteKind.allCases
            .sorted()
            .map {
                make(
                    kind: $0,
                    extensionID: extensionID,
                    profileID: profileID,
                    tabID: tabID,
                    frameID: frameID,
                    documentID: documentID,
                    sourceURL: pageURL,
                    targetURL: pageURL
                )
            }
    }

    private static func sourceContext(
        for kind: ChromeMV3RuntimeMessagingRouteKind
    ) -> ChromeMV3RuntimeMessagingContextKind {
        switch kind {
        case .contentScriptToServiceWorker:
            return .contentScript
        case .extensionPageToServiceWorker, .runtimeSendMessage,
             .runtimeConnect:
            return .extensionPage
        case .actionPopupToServiceWorker:
            return .actionPopup
        case .optionsPageToServiceWorker:
            return .optionsPage
        case .serviceWorkerToTab, .serviceWorkerToFrame,
             .serviceWorkerToExtensionPage, .tabsSendMessage, .tabsConnect,
             .nativeMessaging:
            return .serviceWorker
        }
    }

    private static func targetContext(
        for kind: ChromeMV3RuntimeMessagingRouteKind
    ) -> ChromeMV3RuntimeMessagingContextKind {
        switch kind {
        case .contentScriptToServiceWorker, .extensionPageToServiceWorker,
             .actionPopupToServiceWorker, .optionsPageToServiceWorker,
             .runtimeSendMessage, .runtimeConnect:
            return .serviceWorker
        case .serviceWorkerToTab, .tabsSendMessage, .tabsConnect:
            return .contentScript
        case .serviceWorkerToFrame:
            return .frame
        case .serviceWorkerToExtensionPage:
            return .extensionPage
        case .nativeMessaging:
            return .nativeApplication
        }
    }

    private static func sourceUsesTab(
        _ kind: ChromeMV3RuntimeMessagingRouteKind
    ) -> Bool {
        kind == .contentScriptToServiceWorker
    }

    private static func sourceUsesFrame(
        _ kind: ChromeMV3RuntimeMessagingRouteKind
    ) -> Bool {
        kind == .contentScriptToServiceWorker
    }

    private static func targetUsesTab(
        _ kind: ChromeMV3RuntimeMessagingRouteKind
    ) -> Bool {
        switch kind {
        case .serviceWorkerToTab, .serviceWorkerToFrame, .tabsSendMessage,
             .tabsConnect:
            return true
        default:
            return false
        }
    }

    private static func targetUsesFrame(
        _ kind: ChromeMV3RuntimeMessagingRouteKind
    ) -> Bool {
        switch kind {
        case .serviceWorkerToFrame, .tabsSendMessage, .tabsConnect:
            return true
        default:
            return false
        }
    }

    private static func urlExposurePolicy(
        for kind: ChromeMV3RuntimeMessagingRouteKind
    ) -> ChromeMV3RuntimeMessagingSourceURLExposurePolicy {
        switch kind {
        case .contentScriptToServiceWorker:
            return .exposeWhenHostPermissionOrActiveTab
        case .serviceWorkerToTab, .serviceWorkerToFrame, .tabsSendMessage,
             .tabsConnect:
            return .redactUntilPermission
        case .extensionPageToServiceWorker, .actionPopupToServiceWorker,
             .optionsPageToServiceWorker, .runtimeSendMessage,
             .runtimeConnect, .serviceWorkerToExtensionPage:
            return .exposeExtensionOrigin
        case .nativeMessaging:
            return .notApplicable
        }
    }

    private static func requiresServiceWorkerWake(
        _ kind: ChromeMV3RuntimeMessagingRouteKind
    ) -> Bool {
        switch kind {
        case .contentScriptToServiceWorker, .extensionPageToServiceWorker,
             .actionPopupToServiceWorker, .optionsPageToServiceWorker,
             .runtimeSendMessage, .runtimeConnect:
            return true
        case .serviceWorkerToTab, .serviceWorkerToFrame,
             .serviceWorkerToExtensionPage, .tabsSendMessage, .tabsConnect,
             .nativeMessaging:
            return false
        }
    }

    private static func requiresTabPermission(
        _ kind: ChromeMV3RuntimeMessagingRouteKind
    ) -> Bool {
        switch kind {
        case .contentScriptToServiceWorker, .serviceWorkerToTab,
             .serviceWorkerToFrame, .tabsSendMessage, .tabsConnect:
            return true
        default:
            return false
        }
    }

    private static func requiresHostPermission(
        _ kind: ChromeMV3RuntimeMessagingRouteKind
    ) -> Bool {
        switch kind {
        case .contentScriptToServiceWorker, .serviceWorkerToTab,
             .serviceWorkerToFrame, .tabsSendMessage, .tabsConnect:
            return true
        default:
            return false
        }
    }

    private static func requiresActiveTab(
        _ kind: ChromeMV3RuntimeMessagingRouteKind
    ) -> Bool {
        switch kind {
        case .serviceWorkerToTab, .serviceWorkerToFrame, .tabsSendMessage,
             .tabsConnect:
            return true
        default:
            return false
        }
    }
}

enum ChromeMV3RuntimeMessagingPayloadClassification:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case jsonLike
    case nativeMessagingJSON
    case portConnectionRequest
    case structuredCloneLike
    case unknown
}

enum ChromeMV3RuntimeMessagingResponseMode:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case callback
    case promise
    case none
}

enum ChromeMV3RuntimeMessagingTimeoutPolicy:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case noRuntimeSchedule
    case futureOneTimeMessageResponse
    case futurePortHandshake
}

struct ChromeMV3RuntimeMessagingSenderMetadata:
    Codable,
    Equatable,
    Sendable
{
    var tabID: Int?
    var frameID: Int?
    var documentID: String?
    var url: String?
    var origin: String?
    var urlExposureStatus: ChromeMV3RuntimeMessagingURLExposureStatus
    var privateProfile: Bool
    var redactionReason: String?
}

struct ChromeMV3RuntimeMessageEnvelope:
    Codable,
    Equatable,
    Sendable
{
    var messageID: String
    var extensionID: String
    var source: ChromeMV3RuntimeMessagingEndpoint
    var target: ChromeMV3RuntimeMessagingEndpoint
    var payloadClassification:
        ChromeMV3RuntimeMessagingPayloadClassification
    var senderMetadata: ChromeMV3RuntimeMessagingSenderMetadata
    var expectsResponse: Bool
    var responseMode: ChromeMV3RuntimeMessagingResponseMode
    var timeoutPolicy: ChromeMV3RuntimeMessagingTimeoutPolicy
    var diagnosticTraceID: String

    static func make(
        route: ChromeMV3RuntimeMessagingRoute,
        payloadClassification:
            ChromeMV3RuntimeMessagingPayloadClassification = .jsonLike,
        expectsResponse: Bool = true,
        responseMode: ChromeMV3RuntimeMessagingResponseMode = .promise,
        timeoutPolicy: ChromeMV3RuntimeMessagingTimeoutPolicy =
            .futureOneTimeMessageResponse,
        permissionDecision:
            ChromeMV3RuntimeMessagingPermissionDecision? = nil,
        seed: String = "runtime-message"
    ) -> ChromeMV3RuntimeMessageEnvelope {
        let messageID = ChromeMV3RuntimeMessagingStableID.make(
            prefix: "message",
            parts: [
                seed,
                route.kind.rawValue,
                route.extensionID,
                route.profileID,
                route.tabID.map(String.init) ?? "no-tab",
                route.frameID.map(String.init) ?? "no-frame",
                route.documentID ?? "no-document",
            ]
        )
        let traceID = ChromeMV3RuntimeMessagingStableID.make(
            prefix: "trace",
            parts: [messageID, route.kind.rawValue]
        )
        let metadata = ChromeMV3RuntimeMessagingSenderMetadata.make(
            route: route,
            permissionDecision: permissionDecision
        )

        return ChromeMV3RuntimeMessageEnvelope(
            messageID: messageID,
            extensionID: route.extensionID,
            source: route.source,
            target: route.target,
            payloadClassification: payloadClassification,
            senderMetadata: metadata,
            expectsResponse: expectsResponse,
            responseMode: responseMode,
            timeoutPolicy: timeoutPolicy,
            diagnosticTraceID: traceID
        )
    }
}

extension ChromeMV3RuntimeMessagingSenderMetadata {
    static func make(
        route: ChromeMV3RuntimeMessagingRoute,
        permissionDecision:
            ChromeMV3RuntimeMessagingPermissionDecision? = nil
    ) -> ChromeMV3RuntimeMessagingSenderMetadata {
        let redaction =
            permissionDecision?.senderMetadataRedaction
            ?? ChromeMV3RuntimeMessagingMetadataRedaction
                .redactURLAndOrigin
        let shouldExpose: Bool
        switch route.sourceURLExposurePolicy {
        case .notApplicable:
            shouldExpose = false
        case .exposeExtensionOrigin:
            shouldExpose = true
        case .exposeWhenHostPermissionOrActiveTab,
             .redactUntilPermission:
            shouldExpose = redaction == .preserveURLAndOrigin
        }
        let exposureStatus:
            ChromeMV3RuntimeMessagingURLExposureStatus
        switch route.sourceURLExposurePolicy {
        case .notApplicable:
            exposureStatus = .notApplicable
        default:
            exposureStatus = shouldExpose ? .exposed : .redacted
        }

        return ChromeMV3RuntimeMessagingSenderMetadata(
            tabID: route.source.tabID ?? route.tabID,
            frameID: route.source.frameID ?? route.frameID,
            documentID: route.source.documentID ?? route.documentID,
            url: shouldExpose ? route.source.url : nil,
            origin: shouldExpose ? route.source.origin : nil,
            urlExposureStatus: exposureStatus,
            privateProfile: route.source.privateProfile,
            redactionReason:
                shouldExpose ? nil : permissionDecision?.diagnosticReason
        )
    }
}

enum ChromeMV3RuntimeMessagingRequiredGrant:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case none
    case activeTab
    case hostPermission
    case nativeMessaging
    case tabPermission
}

enum ChromeMV3RuntimeMessagingMissingGrantReason:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case none
    case activeTabGrantExpired
    case missingActiveTabGrant
    case missingHostPermission
    case missingTabPermission
    case nativeMessagingBlocked
    case permissionDenied
    case userGestureRequired
}

enum ChromeMV3RuntimeMessagingMetadataRedaction:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case none
    case preserveURLAndOrigin
    case redactURLAndOrigin
}

struct ChromeMV3RuntimeMessagingActiveTabGrant:
    Codable,
    Equatable,
    Sendable
{
    var tabID: Int
    var origin: String
    var createdByUserGesture: Bool
    var expiresOnTabClose: Bool
    var expiresOnNavigation: Bool
    var expiredByTabClose: Bool
    var expiredByNavigation: Bool

    var isValid: Bool {
        createdByUserGesture
            && expiredByTabClose == false
            && expiredByNavigation == false
    }
}

struct ChromeMV3RuntimeMessagingPermissionSnapshot:
    Codable,
    Equatable,
    Sendable
{
    var grantedHostPermissions: [String]
    var optionalPermissions: [String]
    var optionalHostPermissions: [String]
    var tabPermissionGranted: Bool
    var activeTabPermissionDeclared: Bool
    var activeTabGrants: [ChromeMV3RuntimeMessagingActiveTabGrant]
    var deniedPermissions: [String]
    var userGestureAvailable: Bool

    static let empty = ChromeMV3RuntimeMessagingPermissionSnapshot(
        grantedHostPermissions: [],
        optionalPermissions: [],
        optionalHostPermissions: [],
        tabPermissionGranted: false,
        activeTabPermissionDeclared: false,
        activeTabGrants: [],
        deniedPermissions: [],
        userGestureAvailable: false
    )

    func grantsHostAccess(to url: String?) -> Bool {
        guard let url else { return false }
        return grantedHostPermissions.contains {
            ChromeMV3HostMatchPattern($0).matches(url: url)
        }
    }

    func optionalHostCouldGrantAccess(to url: String?) -> Bool {
        guard let url else { return false }
        return optionalHostPermissions.contains {
            ChromeMV3HostMatchPattern($0).matches(url: url)
        }
    }

    func activeTabGrant(
        tabID: Int?,
        url: String?
    ) -> ChromeMV3RuntimeMessagingActiveTabGrant? {
        guard let tabID,
              let origin = ChromeMV3RuntimeMessagingURL.origin(from: url)
        else { return nil }
        return activeTabGrants.first {
            $0.tabID == tabID
                && $0.origin == origin
                && $0.isValid
        }
    }

    func permissionBroker(
        extensionID: String,
        profileID: String
    ) -> ChromeMV3PermissionBroker {
        let mappedGrants = activeTabGrants.enumerated().map { index, grant in
            ChromeMV3ActiveTabGrant(
                extensionID: extensionID,
                profileID: profileID,
                tabID: grant.tabID,
                scope: .origin(grant.origin),
                reason: .testFixture,
                userGestureModeled: grant.createdByUserGesture,
                createdSequence: index,
                expiryTriggers: [
                    .tabClose,
                    .tabNavigation,
                    .extensionDisable,
                    .permissionRevoke,
                    .profileClose,
                ],
                expiryRecord: expiryRecord(for: grant, sequence: index),
                diagnostics: [
                    "Imported from runtime messaging permission snapshot.",
                ]
            )
        }
        let state = ChromeMV3PermissionBrokerState(
            extensionID: extensionID,
            profileID: profileID,
            requiredPermissions:
                (tabPermissionGranted ? ["tabs"] : [])
                    + (activeTabPermissionDeclared ? ["activeTab"] : []),
            optionalPermissions: optionalPermissions,
            hostPermissions: grantedHostPermissions,
            optionalHostPermissions: optionalHostPermissions,
            deniedPermissions: deniedPermissions,
            activeTabGrants: mappedGrants,
            diagnostics: [
                "Permission broker state was adapted from a legacy messaging snapshot.",
            ]
        )
        return ChromeMV3PermissionBroker(state: state)
    }

    private func expiryRecord(
        for grant: ChromeMV3RuntimeMessagingActiveTabGrant,
        sequence: Int
    ) -> ChromeMV3ActiveTabExpiryRecord? {
        if grant.expiredByTabClose {
            return ChromeMV3ActiveTabExpiryRecord(
                trigger: .tabClose,
                sequence: sequence,
                reason: "Snapshot marked the activeTab grant expired by tab close."
            )
        }
        if grant.expiredByNavigation {
            return ChromeMV3ActiveTabExpiryRecord(
                trigger: .tabNavigation,
                sequence: sequence,
                reason: "Snapshot marked the activeTab grant expired by navigation."
            )
        }
        return nil
    }
}

struct ChromeMV3RuntimeMessagingPermissionDecision:
    Codable,
    Equatable,
    Sendable
{
    var allowedForFutureDispatch: Bool
    var requiredGrant: ChromeMV3RuntimeMessagingRequiredGrant
    var missingGrantReason:
        ChromeMV3RuntimeMessagingMissingGrantReason
    var senderMetadataRedaction:
        ChromeMV3RuntimeMessagingMetadataRedaction
    var futurePromptRequired: Bool
    var diagnosticReason: String
    var hostAccessDecision: ChromeMV3HostAccessDecision? = nil
    var activeTabDecision: ChromeMV3ActiveTabAccessDecision? = nil
    var brokerDiagnostics: [String] = []

    static func evaluate(
        route: ChromeMV3RuntimeMessagingRoute,
        envelope: ChromeMV3RuntimeMessageEnvelope? = nil,
        snapshot: ChromeMV3RuntimeMessagingPermissionSnapshot
    ) -> ChromeMV3RuntimeMessagingPermissionDecision {
        evaluate(
            route: route,
            envelope: envelope,
            permissionBroker: snapshot.permissionBroker(
                extensionID: route.extensionID,
                profileID: route.profileID
            ),
            userGestureAvailable: snapshot.userGestureAvailable
        )
    }

    static func evaluate(
        route: ChromeMV3RuntimeMessagingRoute,
        envelope: ChromeMV3RuntimeMessageEnvelope? = nil,
        permissionBroker: ChromeMV3PermissionBroker,
        userGestureAvailable: Bool = false
    ) -> ChromeMV3RuntimeMessagingPermissionDecision {
        if route.requiresNativeMessaging {
            return ChromeMV3RuntimeMessagingPermissionDecision(
                allowedForFutureDispatch: false,
                requiredGrant: .nativeMessaging,
                missingGrantReason: .nativeMessagingBlocked,
                senderMetadataRedaction: .none,
                futurePromptRequired: false,
                diagnosticReason:
                    "Native messaging is detected but blocked and deferred."
            )
        }

        let url = route.source.url ?? route.target.url
            ?? envelope?.source.url
            ?? envelope?.target.url
        let tabID = route.tabID ?? route.source.tabID ?? route.target.tabID
        let hostDecision = permissionBroker.hostAccessDecision(
            url: url,
            tabID: tabID,
            userGestureAvailable: userGestureAvailable
        )
        let activeDecision = permissionBroker.activeTabDecision(
            tabID: tabID,
            url: url,
            userGestureAvailable: userGestureAvailable
        )
        let hostGranted = hostDecision.allowedByHostPermission
            || hostDecision.allowedByOptionalHostPermission
        let activeTabGranted = hostDecision.allowedByActiveTab
        let hostOrActive = hostDecision.hasHostAccess

        if route.requiresHostPermission && hostOrActive == false {
            if hostDecision.deniedByPattern {
                return ChromeMV3RuntimeMessagingPermissionDecision(
                    allowedForFutureDispatch: false,
                    requiredGrant: .hostPermission,
                    missingGrantReason: .permissionDenied,
                    senderMetadataRedaction: .redactURLAndOrigin,
                    futurePromptRequired: false,
                    diagnosticReason:
                        "Route is blocked by an explicit modeled permission denial.",
                    hostAccessDecision: hostDecision,
                    activeTabDecision: activeDecision,
                    brokerDiagnostics: hostDecision.diagnostics
                )
            }

            if route.requiresActiveTab
                && permissionBroker.activeTabPermissionDeclared
            {
                return ChromeMV3RuntimeMessagingPermissionDecision(
                    allowedForFutureDispatch: false,
                    requiredGrant: .activeTab,
                    missingGrantReason:
                        activeDecision.missingReason,
                    senderMetadataRedaction: .redactURLAndOrigin,
                    futurePromptRequired: hostDecision.wouldNeedPrompt,
                    diagnosticReason:
                        "Route needs host access or a temporary activeTab grant for the target tab and origin.",
                    hostAccessDecision: hostDecision,
                    activeTabDecision: activeDecision,
                    brokerDiagnostics: hostDecision.diagnostics
                )
            }

            return ChromeMV3RuntimeMessagingPermissionDecision(
                allowedForFutureDispatch: false,
                requiredGrant: .hostPermission,
                missingGrantReason:
                    hostDecision.missingReason == .permissionDenied
                        ? .permissionDenied
                        : .missingHostPermission,
                senderMetadataRedaction: .redactURLAndOrigin,
                futurePromptRequired: hostDecision.wouldNeedPrompt,
                diagnosticReason:
                    "Route needs host permission before sender URL and origin metadata can be exposed.",
                hostAccessDecision: hostDecision,
                activeTabDecision: activeDecision,
                brokerDiagnostics: hostDecision.diagnostics
            )
        }

        if route.requiresTabPermission
            && permissionBroker.hasAPIPermission("tabs") == false
            && route.requiresHostPermission == false
        {
            let tabDecision = permissionBroker.apiPermissionDecision("tabs")
            return ChromeMV3RuntimeMessagingPermissionDecision(
                allowedForFutureDispatch: false,
                requiredGrant: .tabPermission,
                missingGrantReason: .missingTabPermission,
                senderMetadataRedaction: .redactURLAndOrigin,
                futurePromptRequired: tabDecision.wouldNeedPrompt,
                diagnosticReason:
                    "Route needs tab metadata permission for future dispatch.",
                hostAccessDecision: hostDecision,
                activeTabDecision: activeDecision,
                brokerDiagnostics: tabDecision.diagnostics
            )
        }

        let exposesURL: Bool
        switch route.sourceURLExposurePolicy {
        case .notApplicable:
            exposesURL = false
        case .exposeExtensionOrigin:
            exposesURL = true
        case .exposeWhenHostPermissionOrActiveTab,
             .redactUntilPermission:
            exposesURL = route.requiresHostPermission ? hostOrActive : true
        }

        return ChromeMV3RuntimeMessagingPermissionDecision(
            allowedForFutureDispatch: true,
            requiredGrant: .none,
            missingGrantReason: .none,
            senderMetadataRedaction:
                exposesURL ? .preserveURLAndOrigin : .redactURLAndOrigin,
            futurePromptRequired: false,
            diagnosticReason:
                hostGranted
                    ? "Permission broker host access allows future metadata exposure."
                    : (activeTabGranted
                        ? "Permission broker activeTab grant allows future metadata exposure."
                        : "No route permission grant is required by this contract."),
            hostAccessDecision: hostDecision,
            activeTabDecision: activeDecision,
            brokerDiagnostics: hostDecision.diagnostics
        )
    }
}

enum ChromeMV3RuntimeLastErrorCase:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case activeTabMissing
    case contextNotLoaded
    case extensionDisabled
    case hostPermissionMissing
    case listenerRegistrationNotImplemented
    case nativeMessagingBlocked
    case noReceivingEnd
    case permissionDenied
    case routeNotImplemented
    case serviceWorkerUnavailable
    case targetFrameMissing
    case targetTabMissing
    case timeout
    case unsupportedAPI

    static func < (
        lhs: ChromeMV3RuntimeLastErrorCase,
        rhs: ChromeMV3RuntimeLastErrorCase
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ChromeMV3RuntimeLastErrorClassification:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case permanent
    case permissionGated
    case retryable
}

enum ChromeMV3RuntimePromiseBehavior:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case notImplemented
    case wouldReject
    case wouldResolveUndefined
}

enum ChromeMV3RuntimeCallbackBehavior:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case noCallback
    case notImplemented
    case wouldInvokeWithNoArgumentsAndSetLastError
    case wouldInvokeWithUndefinedAndSetLastError
}

struct ChromeMV3RuntimeLastErrorContract:
    Codable,
    Equatable,
    Sendable
{
    var error: ChromeMV3RuntimeLastErrorCase
    var futureLastErrorMessage: String
    var promiseBehavior: ChromeMV3RuntimePromiseBehavior
    var callbackBehavior: ChromeMV3RuntimeCallbackBehavior
    var classification: ChromeMV3RuntimeLastErrorClassification
    var diagnostics: [String]

    static func contract(
        for error: ChromeMV3RuntimeLastErrorCase
    ) -> ChromeMV3RuntimeLastErrorContract {
        ChromeMV3RuntimeLastErrorContract(
            error: error,
            futureLastErrorMessage: message(for: error),
            promiseBehavior: .wouldReject,
            callbackBehavior: .wouldInvokeWithUndefinedAndSetLastError,
            classification: classification(for: error),
            diagnostics: diagnostics(for: error)
        )
    }

    static var allContracts: [ChromeMV3RuntimeLastErrorContract] {
        ChromeMV3RuntimeLastErrorCase.allCases
            .sorted()
            .map(contract(for:))
    }

    private static func message(
        for error: ChromeMV3RuntimeLastErrorCase
    ) -> String {
        switch error {
        case .noReceivingEnd:
            return "Could not establish connection. Receiving end does not exist."
        case .extensionDisabled:
            return "Extension is disabled."
        case .contextNotLoaded:
            return "Extension context is not loaded."
        case .targetTabMissing:
            return "No tab with the specified id."
        case .targetFrameMissing:
            return "No frame with the specified id in the target tab."
        case .permissionDenied:
            return "Permission denied."
        case .hostPermissionMissing:
            return "Missing host permission for the target URL."
        case .activeTabMissing:
            return "Missing activeTab grant for the target tab."
        case .serviceWorkerUnavailable:
            return "Extension service worker is unavailable."
        case .routeNotImplemented:
            return "Runtime messaging route is not implemented."
        case .listenerRegistrationNotImplemented:
            return "Runtime listener registration is not implemented."
        case .timeout:
            return "The message channel timed out before a response was received."
        case .nativeMessagingBlocked:
            return "Native messaging is blocked."
        case .unsupportedAPI:
            return "Unsupported Chrome extension API."
        }
    }

    private static func classification(
        for error: ChromeMV3RuntimeLastErrorCase
    ) -> ChromeMV3RuntimeLastErrorClassification {
        switch error {
        case .hostPermissionMissing, .activeTabMissing, .permissionDenied:
            return .permissionGated
        case .serviceWorkerUnavailable, .timeout, .noReceivingEnd:
            return .retryable
        case .extensionDisabled, .contextNotLoaded, .targetTabMissing,
             .targetFrameMissing, .routeNotImplemented,
             .listenerRegistrationNotImplemented, .nativeMessagingBlocked,
             .unsupportedAPI:
            return .permanent
        }
    }

    private static func diagnostics(
        for error: ChromeMV3RuntimeLastErrorCase
    ) -> [String] {
        switch error {
        case .hostPermissionMissing:
            return ["Sender URL and origin metadata must be redacted."]
        case .activeTabMissing:
            return ["No real user gesture creates an activeTab grant here."]
        case .nativeMessagingBlocked:
            return ["No native host lookup or launch is performed."]
        case .routeNotImplemented, .listenerRegistrationNotImplemented:
            return ["Contract exists but dispatch remains disabled."]
        case .serviceWorkerUnavailable:
            return ["Service-worker wake remains disabled."]
        default:
            return ["Diagnostic contract only; runtime lastError is not set."]
        }
    }
}

struct ChromeMV3RuntimeMessagingReadinessSnapshot:
    Codable,
    Equatable,
    Sendable
{
    var extensionModuleEnabled: Bool
    var contextLoaded: Bool
    var targetTabExists: Bool
    var targetFrameExists: Bool
    var receiverListenerRegistered: Bool
    var serviceWorkerLifecycleReady: Bool
    var canCreateContextNow: Bool
    var canLoadContextNow: Bool
    var runtimeLoadable: Bool

    static let blocked = ChromeMV3RuntimeMessagingReadinessSnapshot(
        extensionModuleEnabled: true,
        contextLoaded: false,
        targetTabExists: true,
        targetFrameExists: true,
        receiverListenerRegistered: false,
        serviceWorkerLifecycleReady: false,
        canCreateContextNow: false,
        canLoadContextNow: false,
        runtimeLoadable: false
    )
}

struct ChromeMV3RuntimeMessagingRouteEvaluation:
    Codable,
    Equatable,
    Sendable
{
    var routeKind: ChromeMV3RuntimeMessagingRouteKind
    var routeAcceptedByContract: Bool
    var canDispatchNow: Bool
    var canRegisterListenersNow: Bool
    var canWakeServiceWorkerNow: Bool
    var canOpenPortNow: Bool
    var canLoadContextNow: Bool
    var runtimeLoadable: Bool
    var permissionDecision:
        ChromeMV3RuntimeMessagingPermissionDecision
    var errorContract: ChromeMV3RuntimeLastErrorContract?
    var diagnostics: [String]
}

enum ChromeMV3RuntimeMessagingRouteEvaluator {
    static func evaluate(
        route: ChromeMV3RuntimeMessagingRoute,
        envelope: ChromeMV3RuntimeMessageEnvelope,
        permissionBroker: ChromeMV3PermissionBroker,
        readiness: ChromeMV3RuntimeMessagingReadinessSnapshot,
        userGestureAvailable: Bool = false
    ) -> ChromeMV3RuntimeMessagingRouteEvaluation {
        let permissionDecision =
            ChromeMV3RuntimeMessagingPermissionDecision.evaluate(
                route: route,
                envelope: envelope,
                permissionBroker: permissionBroker,
                userGestureAvailable: userGestureAvailable
            )
        return evaluate(
            route: route,
            permissionDecision: permissionDecision,
            readiness: readiness
        )
    }

    static func evaluate(
        route: ChromeMV3RuntimeMessagingRoute,
        envelope: ChromeMV3RuntimeMessageEnvelope,
        permissionSnapshot:
            ChromeMV3RuntimeMessagingPermissionSnapshot,
        readiness: ChromeMV3RuntimeMessagingReadinessSnapshot
    ) -> ChromeMV3RuntimeMessagingRouteEvaluation {
        let permissionDecision =
            ChromeMV3RuntimeMessagingPermissionDecision.evaluate(
                route: route,
                envelope: envelope,
                snapshot: permissionSnapshot
            )
        return evaluate(
            route: route,
            permissionDecision: permissionDecision,
            readiness: readiness
        )
    }

    private static func evaluate(
        route: ChromeMV3RuntimeMessagingRoute,
        permissionDecision:
            ChromeMV3RuntimeMessagingPermissionDecision,
        readiness: ChromeMV3RuntimeMessagingReadinessSnapshot
    ) -> ChromeMV3RuntimeMessagingRouteEvaluation {
        let error = firstBlockingError(
            route: route,
            permissionDecision: permissionDecision,
            readiness: readiness
        )
        let accepted =
            readiness.extensionModuleEnabled
            && readiness.targetTabExists
            && readiness.targetFrameExists
            && permissionDecision.allowedForFutureDispatch
            && route.requiresNativeMessaging == false
            && error == nil

        return ChromeMV3RuntimeMessagingRouteEvaluation(
            routeKind: route.kind,
            routeAcceptedByContract: accepted,
            canDispatchNow: false,
            canRegisterListenersNow: false,
            canWakeServiceWorkerNow: false,
            canOpenPortNow: false,
            canLoadContextNow: false,
            runtimeLoadable: false,
            permissionDecision: permissionDecision,
            errorContract: error.map {
                ChromeMV3RuntimeLastErrorContract.contract(for: $0)
            },
            diagnostics: diagnostics(
                route: route,
                permissionDecision: permissionDecision,
                readiness: readiness,
                error: error
            )
        )
    }

    private static func firstBlockingError(
        route: ChromeMV3RuntimeMessagingRoute,
        permissionDecision:
            ChromeMV3RuntimeMessagingPermissionDecision,
        readiness: ChromeMV3RuntimeMessagingReadinessSnapshot
    ) -> ChromeMV3RuntimeLastErrorCase? {
        guard readiness.extensionModuleEnabled else {
            return .extensionDisabled
        }
        if route.requiresNativeMessaging {
            return .nativeMessagingBlocked
        }
        if route.requiresTabPermission && route.tabID == nil {
            return .targetTabMissing
        }
        if route.kind == .serviceWorkerToFrame && route.frameID == nil {
            return .targetFrameMissing
        }
        if readiness.targetTabExists == false {
            return .targetTabMissing
        }
        if readiness.targetFrameExists == false {
            return .targetFrameMissing
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
        if readiness.contextLoaded == false {
            return .contextNotLoaded
        }
        if route.requiresServiceWorkerWake
            && readiness.serviceWorkerLifecycleReady == false
        {
            return .serviceWorkerUnavailable
        }
        if readiness.receiverListenerRegistered == false {
            return .noReceivingEnd
        }
        return .routeNotImplemented
    }

    private static func diagnostics(
        route: ChromeMV3RuntimeMessagingRoute,
        permissionDecision:
            ChromeMV3RuntimeMessagingPermissionDecision,
        readiness: ChromeMV3RuntimeMessagingReadinessSnapshot,
        error: ChromeMV3RuntimeLastErrorCase?
    ) -> [String] {
        var diagnostics = [
            "Route \(route.kind.rawValue) is modeled but not dispatched.",
            permissionDecision.diagnosticReason,
            "canDispatchNow remains false.",
            "canRegisterListenersNow remains false.",
            "canWakeServiceWorkerNow remains false.",
            "canOpenPortNow remains false.",
            "runtimeLoadable remains false.",
        ]
        if readiness.contextLoaded == false {
            diagnostics.append("No extension context is loaded.")
        }
        if let error {
            diagnostics.append(
                "Future error contract: \(error.rawValue)."
            )
        }
        diagnostics.append(contentsOf: route.blockers)
        return Array(Set(diagnostics)).sorted()
    }
}

enum ChromeMV3RuntimePortKind:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case runtimeConnect
    case tabsConnect
    case nativeMessaging
}

enum ChromeMV3RuntimePortDisconnectReason:
    String,
    Codable,
    CaseIterable,
    Comparable,
    Sendable
{
    case contextUnloaded
    case extensionDisabled
    case frameUnloaded
    case nativeHostExited
    case permissionRevoked
    case routeUnsupported
    case serviceWorkerIdle
    case tabClosed
    case timeout

    static func < (
        lhs: ChromeMV3RuntimePortDisconnectReason,
        rhs: ChromeMV3RuntimePortDisconnectReason
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct ChromeMV3RuntimePortContract:
    Codable,
    Equatable,
    Sendable
{
    var portKind: ChromeMV3RuntimePortKind
    var portID: String
    var source: ChromeMV3RuntimeMessagingEndpoint
    var target: ChromeMV3RuntimeMessagingEndpoint
    var routeEvaluation: ChromeMV3RuntimeMessagingRouteEvaluation
    var connectAllowedByContract: Bool
    var canOpenPortNow: Bool
    var portLifecycleImplemented: Bool
    var disconnectReasons: [ChromeMV3RuntimePortDisconnectReason]
    var serviceWorkerKeepaliveImplication: String
    var nativeMessagingPortBlockedSeparately: Bool
    var diagnostics: [String]

    static func model(
        route: ChromeMV3RuntimeMessagingRoute,
        envelope: ChromeMV3RuntimeMessageEnvelope,
        permissionSnapshot:
            ChromeMV3RuntimeMessagingPermissionSnapshot,
        readiness: ChromeMV3RuntimeMessagingReadinessSnapshot
    ) -> ChromeMV3RuntimePortContract {
        let evaluation = ChromeMV3RuntimeMessagingRouteEvaluator.evaluate(
            route: route,
            envelope: envelope,
            permissionSnapshot: permissionSnapshot,
            readiness: readiness
        )
        let kind: ChromeMV3RuntimePortKind
        switch route.kind {
        case .tabsConnect:
            kind = .tabsConnect
        case .nativeMessaging:
            kind = .nativeMessaging
        default:
            kind = .runtimeConnect
        }

        return ChromeMV3RuntimePortContract(
            portKind: kind,
            portID: ChromeMV3RuntimeMessagingStableID.make(
                prefix: "port",
                parts: [
                    route.kind.rawValue,
                    envelope.messageID,
                    route.extensionID,
                    route.profileID,
                ]
            ),
            source: route.source,
            target: route.target,
            routeEvaluation: evaluation,
            connectAllowedByContract:
                evaluation.routeAcceptedByContract
                    && route.kind != .nativeMessaging,
            canOpenPortNow: false,
            portLifecycleImplemented: false,
            disconnectReasons:
                ChromeMV3RuntimePortDisconnectReason.allCases.sorted(),
            serviceWorkerKeepaliveImplication:
                "Future long-lived ports may affect service-worker lifetime, but this contract starts no keepalive work.",
            nativeMessagingPortBlockedSeparately:
                route.kind == .nativeMessaging,
            diagnostics: Array(Set(
                evaluation.diagnostics
                    + [
                        "Port lifecycle is deterministic and non-executing.",
                        "No Port object is opened.",
                    ]
            )).sorted()
        )
    }
}

struct ChromeMV3RuntimeMessagingRouteCoverage:
    Codable,
    Equatable,
    Sendable
{
    var routeKind: ChromeMV3RuntimeMessagingRouteKind
    var modeled: Bool
    var implementedNow: Bool
    var requiresServiceWorkerWake: Bool
    var requiresTabPermission: Bool
    var requiresHostPermission: Bool
    var requiresActiveTab: Bool
    var requiresNativeMessaging: Bool
}

struct ChromeMV3PasswordManagerMessagingSummary:
    Codable,
    Equatable,
    Sendable
{
    var contentScriptToServiceWorkerRouteRequired: Bool
    var popupToServiceWorkerRouteRequired: Bool
    var serviceWorkerToTabContentRouteRequired: Bool
    var portLifecycleRequiredForUnlockFillFlow: Bool
    var hostPermissionRequired: Bool
    var activeTabMayBeRequiredDependingOnUserAction: Bool
    var nativeMessagingRouteDetectedButBlocked: Bool
    var controlledInputPageWorldBehaviorVerified: Bool
    var passwordManagerMessagingReady: Bool
    var blockers: [String]
}

struct ChromeMV3RuntimeMessagingContractReportSummary:
    Codable,
    Equatable,
    Sendable
{
    var reportID: String
    var reportFileName: String
    var routeKindsModeled: [ChromeMV3RuntimeMessagingRouteKind]
    var canDispatchMessagesNow: Bool
    var canRegisterListenersNow: Bool
    var canWakeServiceWorkerNow: Bool
    var canOpenPortNow: Bool
    var canCreateContextNow: Bool
    var canLoadContextNow: Bool
    var runtimeLoadable: Bool
    var passwordManagerMessagingReady: Bool
    var listenerContractReportSummary:
        ChromeMV3RuntimeListenerContractReportSummary? = nil
    var permissionBrokerReadinessReportSummary:
        ChromeMV3PermissionBrokerReadinessReportSummary? = nil
}

struct ChromeMV3RuntimeMessagingContractReport:
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
    var routeContractCoverage: [ChromeMV3RuntimeMessagingRouteCoverage]
    var envelopeContractCoverage: [String]
    var permissionDecisionCoverage: [String]
    var lastErrorCoverage: [ChromeMV3RuntimeLastErrorContract]
    var portLifecycleCoverage: [ChromeMV3RuntimePortDisconnectReason]
    var passwordManagerMessagingSummary:
        ChromeMV3PasswordManagerMessagingSummary
    var listenerContractReportSummary:
        ChromeMV3RuntimeListenerContractReportSummary? = nil
    var permissionBrokerReadinessReportSummary:
        ChromeMV3PermissionBrokerReadinessReportSummary? = nil
    var permissionBrokerRouteDecisions:
        [ChromeMV3PermissionBrokerRouteScenario] = []
    var canDispatchMessagesNow: Bool
    var canRegisterListenersNow: Bool
    var canWakeServiceWorkerNow: Bool
    var canOpenPortNow: Bool
    var canCreateContextNow: Bool
    var canLoadContextNow: Bool
    var runtimeLoadable: Bool
    var diagnostics: [String]

    var summary: ChromeMV3RuntimeMessagingContractReportSummary {
        ChromeMV3RuntimeMessagingContractReportSummary(
            reportID: id,
            reportFileName: reportFileName,
            routeKindsModeled:
                routeContractCoverage.map(\.routeKind).sorted(),
            canDispatchMessagesNow: false,
            canRegisterListenersNow: false,
            canWakeServiceWorkerNow: false,
            canOpenPortNow: false,
            canCreateContextNow: false,
            canLoadContextNow: false,
            runtimeLoadable: false,
            passwordManagerMessagingReady: false,
            listenerContractReportSummary: listenerContractReportSummary,
            permissionBrokerReadinessReportSummary:
                permissionBrokerReadinessReportSummary
        )
    }
}

enum ChromeMV3RuntimeMessagingContractReportWriter {
    static let reportFileName = "runtime-messaging-contract-report.json"

    @discardableResult
    static func write(
        _ report: ChromeMV3RuntimeMessagingContractReport,
        toRewrittenBundleRoot rootURL: URL
    ) throws -> ChromeMV3RuntimeMessagingContractReport {
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

enum ChromeMV3RuntimeMessagingContractReportGenerator {
    static func makeReport(
        prerequisitesReport prerequisites:
            ChromeMV3RuntimeBridgePrerequisitesReport,
        profileID: String = "diagnostic-profile"
    ) -> ChromeMV3RuntimeMessagingContractReport {
        let extensionID = prerequisites.candidateID
        let routes = ChromeMV3RuntimeMessagingRoute.allModeledRoutes(
            extensionID: extensionID,
            profileID: profileID
        )
        let coverage = routes.map {
            ChromeMV3RuntimeMessagingRouteCoverage(
                routeKind: $0.kind,
                modeled: true,
                implementedNow: false,
                requiresServiceWorkerWake:
                    $0.requiresServiceWorkerWake,
                requiresTabPermission: $0.requiresTabPermission,
                requiresHostPermission: $0.requiresHostPermission,
                requiresActiveTab: $0.requiresActiveTab,
                requiresNativeMessaging: $0.requiresNativeMessaging
            )
        }.sorted { $0.routeKind < $1.routeKind }
        let passwordSummary = passwordManagerSummary(
            prerequisites: prerequisites
        )
        let permissionReport =
            ChromeMV3PermissionBrokerReadinessReportGenerator.makeReport(
                prerequisitesReport: prerequisites,
                profileID: profileID
            )
        let listenerSummary = ChromeMV3RuntimeListenerContractReportGenerator
            .makeReport(
                prerequisitesReport: prerequisites,
                profileID: profileID
            )
            .summary

        return ChromeMV3RuntimeMessagingContractReport(
            schemaVersion: 1,
            id: id(
                candidateID: prerequisites.candidateID,
                prerequisiteReportID: prerequisites.id,
                routeKinds: coverage.map(\.routeKind)
            ),
            reportFileName:
                ChromeMV3RuntimeMessagingContractReportWriter
                .reportFileName,
            candidateID: prerequisites.candidateID,
            extensionID: extensionID,
            profileID: profileID,
            routeContractCoverage: coverage,
            envelopeContractCoverage: [
                "message id",
                "extension id",
                "source endpoint",
                "target endpoint",
                "payload classification",
                "sender metadata",
                "callback mode",
                "Promise mode",
                "timeout policy without scheduling",
                "diagnostic trace id",
            ],
            permissionDecisionCoverage: [
                "granted host permissions",
                "optional permissions",
                "optional host permissions",
                "activeTab temporary grant",
                "user gesture requirement",
                "grant expiry on tab close or navigation",
                "permission denied",
                "missing host permission",
                "missing activeTab grant",
                "permission broker host access decision",
                "permission broker activeTab decision",
                "URL and origin redaction",
            ],
            lastErrorCoverage:
                ChromeMV3RuntimeLastErrorContract.allContracts,
            portLifecycleCoverage:
                ChromeMV3RuntimePortDisconnectReason.allCases.sorted(),
            passwordManagerMessagingSummary: passwordSummary,
            listenerContractReportSummary: listenerSummary,
            permissionBrokerReadinessReportSummary:
                permissionReport.summary,
            permissionBrokerRouteDecisions:
                permissionReport.permissionDecisionsForKeyRoutes,
            canDispatchMessagesNow: false,
            canRegisterListenersNow: false,
            canWakeServiceWorkerNow: false,
            canOpenPortNow: false,
            canCreateContextNow: false,
            canLoadContextNow: false,
            runtimeLoadable: false,
            diagnostics: [
                "Runtime messaging contracts exist for future bridge implementation.",
                "Message dispatch remains disabled.",
                "Listener registration remains disabled.",
                "Service-worker wake remains disabled.",
                "Port opening remains disabled.",
                "Context creation and loading remain disabled.",
                "Sumi does not claim Chrome MV3 runtime support.",
            ]
        )
    }

    static func makeReport(
        loadingPrerequisitesReportFrom rootURL: URL,
        fileManager: FileManager = .default
    ) throws -> ChromeMV3RuntimeMessagingContractReport {
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
        return makeReport(prerequisitesReport: prerequisites)
    }

    private static func passwordManagerSummary(
        prerequisites: ChromeMV3RuntimeBridgePrerequisitesReport
    ) -> ChromeMV3PasswordManagerMessagingSummary {
        let summary = prerequisites.passwordManagerPrerequisiteSummary
        let nativeDetected =
            summary.nativeMessagingPermissionPresent
                || prerequisites.nativeMessagingPrerequisites
                .nativeMessagingDetected
        return ChromeMV3PasswordManagerMessagingSummary(
            contentScriptToServiceWorkerRouteRequired:
                summary.contentScriptsPresent,
            popupToServiceWorkerRouteRequired:
                summary.actionPopupPresent,
            serviceWorkerToTabContentRouteRequired:
                summary.contentScriptsPresent,
            portLifecycleRequiredForUnlockFillFlow:
                summary.contentScriptsPresent || summary.actionPopupPresent,
            hostPermissionRequired:
                summary.hostPermissionsPresent
                    || (prerequisites.manifestFacts.hostPermissions
                        .isEmpty == false),
            activeTabMayBeRequiredDependingOnUserAction: true,
            nativeMessagingRouteDetectedButBlocked: nativeDetected,
            controlledInputPageWorldBehaviorVerified: false,
            passwordManagerMessagingReady: false,
            blockers: Array(Set(
                summary.blockers
                    + [
                        "Password-manager content script to service worker route is modeled only.",
                        "Password-manager popup to service worker route is modeled only.",
                        "Password-manager service worker to tab/content route is modeled only.",
                        "Port lifecycle for unlock/fill flow is modeled only.",
                        "Native messaging route is blocked and deferred.",
                        "Controlled input and page-world behavior is not verified.",
                    ]
            )).sorted()
        )
    }

    private static func id(
        candidateID: String,
        prerequisiteReportID: String,
        routeKinds: [ChromeMV3RuntimeMessagingRouteKind]
    ) -> String {
        ChromeMV3RuntimeMessagingStableID.make(
            prefix: "runtime-messaging-contract",
            parts: [
                candidateID,
                prerequisiteReportID,
                routeKinds.sorted().map(\.rawValue).joined(separator: ","),
            ]
        )
    }
}

private enum ChromeMV3RuntimeMessagingStableID {
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

enum ChromeMV3RuntimeMessagingURL {
    static func origin(from urlString: String?) -> String? {
        ChromeMV3PermissionBrokerURL.origin(from: urlString)
    }
}
