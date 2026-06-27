//
//  SafariExtensionNativeMessagingDiagnostics.swift
//  Sumi
//
//  Sanitized native-messaging diagnostic data models.
//  Never logs message bodies or credentials.
//

import Foundation

enum SafariExtensionNativeMessagingDirection: String, Codable, Sendable {
    case send
    case connect
    case portReceive
    case portRelay
}

enum SafariExtensionNativeMessagingOutcome: String, Codable, Sendable {
    case policyDenied
    case hostResolved
    case hostNotFound
    case hostLaunched
    case hostLaunchFailed
    case portConnected
    case companionAppProtocolUnknown
    case launchSuppressed
    case launchRateLimited
    case relayTimeout
    case relayCancelled
    case nativeHostManifestMissing
    case nativeHostExecutableMissing
    case nativeHostPermissionDenied
    case nativeHostUnsupportedKind
    case extensionContextMissing
    /// Legacy diagnostic bucket retained for decode compatibility in persisted logs.
    case hostRelayUnavailable
}

struct SafariExtensionNativeMessagingDiagnostic: Sendable, Equatable, Codable {
    let extensionId: String
    let direction: SafariExtensionNativeMessagingDirection
    let requestedApplicationIdentifier: String?
    let hostBundleIdentifier: String?
    let resolverBucket: SumiNativeMessagingResolverBucket?
    let outcome: SafariExtensionNativeMessagingOutcome
    let errorDomain: String?
    let errorCode: Int?
    let launchAttempted: Bool?
    let launchSuppressed: Bool?
    let retryCountBucket: SumiNativeMessagingRetryCountBucket?
    let launchReason: SumiCompanionAppLaunchReason?
    let launchRequestedByAdapter: Bool?
    let launchCooldownBucket: SumiNativeMessagingRetryCountBucket?
    let extensionContextActive: Bool?
    let isContainingApp: Bool?
    let protocolAdapterAvailable: Bool?
    let launchAllowed: Bool?
    let sessionState: SumiNativeMessagingSessionState?
    let adapterSelected: Bool?
    let adapterIdentifier: String?
    let appResolved: Bool?
    let appLaunched: Bool?
    let protocolStatus: SumiNativeMessagingProtocolStatus?
    let handshakeStatus: SumiNativeMessagingHandshakeStatus?
    let autofillPathStatus: SumiNativeMessagingAutofillPathStatus?
    let failureBucket: SafariExtensionNativeMessagingErrorBucket?

    init(
        extensionId: String,
        direction: SafariExtensionNativeMessagingDirection,
        requestedApplicationIdentifier: String?,
        hostBundleIdentifier: String?,
        resolverBucket: SumiNativeMessagingResolverBucket?,
        outcome: SafariExtensionNativeMessagingOutcome,
        errorDomain: String?,
        errorCode: Int?,
        launchAttempted: Bool? = nil,
        launchSuppressed: Bool? = nil,
        retryCountBucket: SumiNativeMessagingRetryCountBucket? = nil,
        launchReason: SumiCompanionAppLaunchReason? = nil,
        launchRequestedByAdapter: Bool? = nil,
        launchCooldownBucket: SumiNativeMessagingRetryCountBucket? = nil,
        extensionContextActive: Bool? = nil,
        isContainingApp: Bool? = nil,
        protocolAdapterAvailable: Bool? = nil,
        launchAllowed: Bool? = nil,
        sessionState: SumiNativeMessagingSessionState? = nil,
        adapterSelected: Bool? = nil,
        adapterIdentifier: String? = nil,
        appResolved: Bool? = nil,
        appLaunched: Bool? = nil,
        protocolStatus: SumiNativeMessagingProtocolStatus? = nil,
        handshakeStatus: SumiNativeMessagingHandshakeStatus? = nil,
        autofillPathStatus: SumiNativeMessagingAutofillPathStatus? = nil,
        failureBucket: SafariExtensionNativeMessagingErrorBucket? = nil
    ) {
        self.extensionId = extensionId
        self.direction = direction
        self.requestedApplicationIdentifier = requestedApplicationIdentifier
        self.hostBundleIdentifier = hostBundleIdentifier
        self.resolverBucket = resolverBucket
        self.outcome = outcome
        self.errorDomain = errorDomain
        self.errorCode = errorCode
        self.launchAttempted = launchAttempted
        self.launchSuppressed = launchSuppressed
        self.retryCountBucket = retryCountBucket
        self.launchReason = launchReason
        self.launchRequestedByAdapter = launchRequestedByAdapter
        self.launchCooldownBucket = launchCooldownBucket
        self.extensionContextActive = extensionContextActive
        self.isContainingApp = isContainingApp
        self.protocolAdapterAvailable = protocolAdapterAvailable
        self.launchAllowed = launchAllowed
        self.sessionState = sessionState
        self.adapterSelected = adapterSelected
        self.adapterIdentifier = adapterIdentifier
        self.appResolved = appResolved
        self.appLaunched = appLaunched
        self.protocolStatus = protocolStatus
        self.handshakeStatus = handshakeStatus
        self.autofillPathStatus = autofillPathStatus
        self.failureBucket = failureBucket
    }

    /// Sanitized alias for delegate `applicationIdentifier` in diagnostics output.
    var applicationIdentifier: String? { requestedApplicationIdentifier }
}

enum SafariExtensionNativeMessagingErrorBucket: String, Codable, Sendable {
    case none
    case moduleDisabled
    case extensionDisabled
    case extensionNotImported
    case privateBrowsingDenied
    case hostNotFound
    case hostLaunchFailed
    case companionAppProtocolUnknown
    case relayTimeout
    case relayCancelled
    case extensionContextMissing
    case nativeHostManifestMissing
    case nativeHostExecutableMissing
    case permissionDenied
    case unsupportedHostKind
    case adapterUnavailable
    case launchSuppressed
    case unknown
}

enum SumiNativeMessagingProtocolStatus: String, Codable, Sendable, Equatable {
    case notApplicable
    case adapterUnavailable
    case adapterReady
    case relayPending
    case relayActive
    case protocolUnknown
    case suppressed
    case failed
}

enum SumiNativeMessagingHandshakeStatus: String, Codable, Sendable, Equatable {
    case notApplicable
    case notAttempted
    case pending
    case completed
    case failed
    case suppressed
}

enum SumiNativeMessagingAutofillPathStatus: String, Codable, Sendable, Equatable {
    case notApplicable
    case contentScriptsWired
    case unknown
    case pendingManualVerification
}
