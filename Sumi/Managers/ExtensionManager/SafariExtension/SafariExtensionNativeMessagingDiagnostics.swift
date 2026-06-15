//
//  SafariExtensionNativeMessagingDiagnostics.swift
//  Sumi
//
//  Sanitized native-messaging diagnostics and DEBUG probe reporting.
//  Never logs message bodies or credentials.
//

import AppKit
import Foundation
import WebKit

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

struct SafariExtensionNativeMessagingMessageShape: Equatable, Sendable {
    let container: String
    let topLevelKeys: [String]
    let typeKeys: [String]

    var keysForLog: String {
        topLevelKeys.isEmpty ? "-" : topLevelKeys.joined(separator: ",")
    }

    var typeKeysForLog: String {
        typeKeys.isEmpty ? "-" : typeKeys.joined(separator: ",")
    }
}

@MainActor
enum SafariExtensionNativeMessagingPermissionDiagnostics {
    static func logGrant(
        extensionId: String?,
        profileId: UUID?,
        manifestDeclaresNativeMessaging: Bool,
        permissionGranted: Bool
    ) {
        log(
            phase: "grant",
            extensionId: extensionId,
            profileId: profileId,
            manifestDeclaresNativeMessaging: manifestDeclaresNativeMessaging,
            permissionGranted: permissionGranted,
            unsupportedAPIsContainNativeMessaging: nil
        )
    }

    static func logContextState(
        extensionId: String?,
        profileId: UUID?,
        manifestDeclaresNativeMessaging: Bool,
        permissionGranted: Bool,
        unsupportedAPIsContainNativeMessaging: Bool
    ) {
        log(
            phase: "context",
            extensionId: extensionId,
            profileId: profileId,
            manifestDeclaresNativeMessaging: manifestDeclaresNativeMessaging,
            permissionGranted: permissionGranted,
            unsupportedAPIsContainNativeMessaging: unsupportedAPIsContainNativeMessaging
        )
    }

    private static func log(
        phase: String,
        extensionId: String?,
        profileId: UUID?,
        manifestDeclaresNativeMessaging: Bool,
        permissionGranted: Bool,
        unsupportedAPIsContainNativeMessaging: Bool?
    ) {
        #if DEBUG || SUMI_DIAGNOSTICS
            guard RuntimeDiagnostics.isVerboseEnabled else { return }
            RuntimeDiagnostics.debug(category: "SafariNativeMessagingPermissions") {
                """
                phase=\(phase) \
                extBucket=\(SafariExtensionNativeMessagingRoutingProbe.extensionIdBucket(extensionId)) \
                profile=\(SafariExtensionNativeMessagingRoutingProbe.profileIdBucket(profileId)) \
                manifestNativeMessaging=\(manifestDeclaresNativeMessaging) \
                permissionGranted=\(permissionGranted) \
                unsupportedNativeMessaging=\(unsupportedAPIsContainNativeMessaging.map(String.init) ?? "-")
                """
            }
        #else
            _ = (
                phase,
                extensionId,
                profileId,
                manifestDeclaresNativeMessaging,
                permissionGranted,
                unsupportedAPIsContainNativeMessaging
            )
        #endif
    }
}

@MainActor
enum SafariExtensionNativeMessagingDiagnosticEnrichment {
    static func failureBucket(
        for diagnostic: SafariExtensionNativeMessagingDiagnostic,
        policyDenial: SumiNativeMessagingRelayPolicyDenial? = nil
    ) -> SafariExtensionNativeMessagingErrorBucket {
        if let policyDenial {
            switch policyDenial {
            case .moduleDisabled:
                return .moduleDisabled
            case .extensionNotEnabled:
                return .extensionDisabled
            case .extensionNotSafariImport, .arbitraryNativeMessagingDenied:
                return .extensionNotImported
            case .privateBrowsingDenied:
                return .privateBrowsingDenied
            }
        }

        switch diagnostic.outcome {
        case .policyDenied:
            return .moduleDisabled
        case .hostNotFound:
            return .hostNotFound
        case .hostLaunchFailed:
            return .hostLaunchFailed
        case .nativeHostManifestMissing:
            return .nativeHostManifestMissing
        case .nativeHostExecutableMissing:
            return .nativeHostExecutableMissing
        case .nativeHostPermissionDenied:
            return .permissionDenied
        case .nativeHostUnsupportedKind:
            return .unsupportedHostKind
        case .companionAppProtocolUnknown:
            if diagnostic.protocolAdapterAvailable == false {
                return .adapterUnavailable
            }
            if diagnostic.launchSuppressed == true {
                return .launchSuppressed
            }
            if diagnostic.adapterSelected == true,
               let errorCode = diagnostic.errorCode,
               diagnostic.errorDomain == SumiNativeMessagingRelay.errorDomain,
               let relayCode = SumiNativeMessagingRelay.ErrorCode(rawValue: errorCode)
            {
                switch relayCode {
                case .relayTimeout:
                    return .relayTimeout
                case .relayCancelled:
                    return .relayCancelled
                case .hostLaunchFailed:
                    return .hostLaunchFailed
                case .nativeHostManifestMissing:
                    return .nativeHostManifestMissing
                case .nativeHostExecutableMissing:
                    return .nativeHostExecutableMissing
                case .nativeHostPermissionDenied:
                    return .permissionDenied
                case .nativeHostUnsupportedKind:
                    return .unsupportedHostKind
                case .hostNotFound:
                    return .hostNotFound
                default:
                    return .unknown
                }
            }
            if diagnostic.adapterSelected == true {
                return .unknown
            }
            return .companionAppProtocolUnknown
        case .launchSuppressed, .launchRateLimited:
            return .launchSuppressed
        case .relayTimeout:
            return .relayTimeout
        case .relayCancelled:
            return .relayCancelled
        case .extensionContextMissing:
            return .extensionContextMissing
        case .hostResolved, .hostLaunched, .portConnected, .hostRelayUnavailable:
            return .none
        }
    }

    static func protocolStatus(
        adapter: SumiNativeMessagingProtocolAdapter?,
        evaluation: SumiCompanionAppResolverResult?,
        diagnostic: SafariExtensionNativeMessagingDiagnostic
    ) -> SumiNativeMessagingProtocolStatus {
        if adapter != nil {
            switch diagnostic.outcome {
            case .portConnected:
                return .relayActive
            case .hostLaunched:
                return .relayPending
            case .launchSuppressed, .launchRateLimited:
                return .suppressed
            case .relayTimeout, .relayCancelled, .hostLaunchFailed,
                 .nativeHostManifestMissing, .nativeHostExecutableMissing,
                 .nativeHostPermissionDenied, .nativeHostUnsupportedKind:
                return .failed
            default:
                return .adapterReady
            }
        }

        if let evaluation {
            switch evaluation {
            case .launchSuppressed, .launchRateLimited:
                return .suppressed
            case .appFoundButProtocolUnknown, .protocolAdapterUnavailable:
                return .adapterUnavailable
            case .appNotFound:
                return .failed
            default:
                break
            }
        }

        if diagnostic.protocolAdapterAvailable == true {
            return .adapterReady
        }
        return .protocolUnknown
    }

    static func handshakeStatus(
        for diagnostic: SafariExtensionNativeMessagingDiagnostic
    ) -> SumiNativeMessagingHandshakeStatus {
        switch diagnostic.direction {
        case .connect:
            switch diagnostic.outcome {
            case .portConnected:
                return .completed
            case .launchSuppressed, .launchRateLimited:
                return .suppressed
            case .hostResolved:
                return .pending
            case .hostLaunchFailed, .companionAppProtocolUnknown, .relayCancelled, .relayTimeout,
                 .nativeHostManifestMissing, .nativeHostExecutableMissing,
                 .nativeHostPermissionDenied, .nativeHostUnsupportedKind:
                return .failed
            default:
                return .notAttempted
            }
        case .send:
            switch diagnostic.outcome {
            case .portConnected, .hostLaunched:
                return .completed
            case .launchSuppressed, .launchRateLimited:
                return .suppressed
            case .hostLaunchFailed, .companionAppProtocolUnknown, .relayCancelled, .relayTimeout,
                 .nativeHostManifestMissing, .nativeHostExecutableMissing,
                 .nativeHostPermissionDenied, .nativeHostUnsupportedKind:
                return .failed
            default:
                return .notAttempted
            }
        case .portReceive, .portRelay:
            switch diagnostic.outcome {
            case .portConnected:
                return .completed
            case .companionAppProtocolUnknown, .relayCancelled:
                return .failed
            default:
                return .pending
            }
        }
    }

    static func autofillPathStatus(
        extensionId: String,
        evaluation: SumiCompanionAppResolverResult?
    ) -> SumiNativeMessagingAutofillPathStatus {
        guard evaluation?.detail != nil else { return .notApplicable }
        if SafariExtensionContentScriptProbe.isTabReconcilePathWiredInSources() {
            return .contentScriptsWired
        }
        return .pendingManualVerification
    }

    static func enrich(
        _ diagnostic: SafariExtensionNativeMessagingDiagnostic,
        adapter: SumiNativeMessagingProtocolAdapter? = nil,
        adapterIdentifier: String? = nil,
        evaluation: SumiCompanionAppResolverResult? = nil,
        policyDenial: SumiNativeMessagingRelayPolicyDenial? = nil,
        sessionState: SumiNativeMessagingSessionState? = nil
    ) -> SafariExtensionNativeMessagingDiagnostic {
        let adapterSelected = adapter != nil || diagnostic.adapterSelected == true
        let resolvedAdapterIdentifier = adapterIdentifier ?? diagnostic.adapterIdentifier
        let appResolved = diagnostic.appResolved
            ?? (diagnostic.hostBundleIdentifier != nil || evaluation?.detail != nil)
        let appLaunched = diagnostic.appLaunched ?? diagnostic.launchAttempted

        return SafariExtensionNativeMessagingDiagnostic(
            extensionId: diagnostic.extensionId,
            direction: diagnostic.direction,
            requestedApplicationIdentifier: diagnostic.requestedApplicationIdentifier,
            hostBundleIdentifier: diagnostic.hostBundleIdentifier,
            resolverBucket: diagnostic.resolverBucket,
            outcome: diagnostic.outcome,
            errorDomain: diagnostic.errorDomain,
            errorCode: diagnostic.errorCode,
            launchAttempted: diagnostic.launchAttempted,
            launchSuppressed: diagnostic.launchSuppressed,
            retryCountBucket: diagnostic.retryCountBucket,
            launchReason: diagnostic.launchReason,
            launchRequestedByAdapter: diagnostic.launchRequestedByAdapter,
            launchCooldownBucket: diagnostic.launchCooldownBucket,
            extensionContextActive: diagnostic.extensionContextActive,
            isContainingApp: diagnostic.isContainingApp,
            protocolAdapterAvailable: diagnostic.protocolAdapterAvailable
                ?? (adapter != nil),
            launchAllowed: diagnostic.launchAllowed,
            sessionState: sessionState ?? diagnostic.sessionState,
            adapterSelected: adapterSelected,
            adapterIdentifier: resolvedAdapterIdentifier,
            appResolved: appResolved,
            appLaunched: appLaunched,
            protocolStatus: diagnostic.protocolStatus
                ?? protocolStatus(
                    adapter: adapter,
                    evaluation: evaluation,
                    diagnostic: diagnostic
                ),
            handshakeStatus: diagnostic.handshakeStatus
                ?? handshakeStatus(for: diagnostic),
            autofillPathStatus: diagnostic.autofillPathStatus
                ?? autofillPathStatus(extensionId: diagnostic.extensionId, evaluation: evaluation),
            failureBucket: diagnostic.failureBucket
                ?? failureBucket(for: diagnostic, policyDenial: policyDenial)
        )
    }
}

enum SafariExtensionNativeMessagingConnectionBucket: String, Codable, Sendable {
    case notAttempted
    case sendDelegateObserved
    case connectDelegateObserved
    case portSessionActive
    case portDisconnected
    case policyDenied
    case resolverNoMatch
    case companionProtocolUnknown
}

/// Real-runtime routing classification for delegate → relay → registry → adapter probes.
enum SafariExtensionNativeMessagingRoutingBucket: String, Codable, Sendable, Equatable {
    case adapterSelectedRealSendMessage
    case adapterSelectedRealConnectNative
    case adapterNotSelectedIdentifierMismatch
    case adapterRegistryBypassed
    case fallbackBeforeRegistry
    case fallbackAfterRegistry
    case identifierUnknown
}

@MainActor
enum SafariExtensionNativeMessagingRoutingProbe {
    nonisolated static let safariContainingApplicationIdentifier = "application.id"

    nonisolated static func isSafariContainingApplicationRequest(
        _ applicationIdentifier: String?
    ) -> Bool {
        applicationIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines) == safariContainingApplicationIdentifier
    }

    nonisolated static func extensionIdBucket(_ extensionId: String?) -> String {
        SafariExtensionPermissionLifecycleDiagnostics.bucket(extensionId) ?? "unknown"
    }

    nonisolated static func profileIdBucket(_ profileId: UUID?) -> String {
        guard let profileId else { return "none" }
        return String(profileId.uuidString.prefix(8))
    }

    nonisolated static func sanitizedExtensionLabel(_ label: String?) -> String {
        guard let label = label?.trimmingCharacters(in: .whitespacesAndNewlines),
              label.isEmpty == false
        else { return "-" }

        let allowed = CharacterSet.alphanumerics
            .union(.whitespaces)
            .union(CharacterSet(charactersIn: "._-"))
        let sanitized = String(
            label.unicodeScalars.map { scalar in
                allowed.contains(scalar) ? String(scalar) : "_"
            }.joined()
        )
        return String(sanitized.prefix(64))
    }

    nonisolated static func sanitizedMessageShape(
        for message: Any?
    ) -> SafariExtensionNativeMessagingMessageShape {
        guard let message else {
            return SafariExtensionNativeMessagingMessageShape(
                container: "nil",
                topLevelKeys: [],
                typeKeys: []
            )
        }

        if let object = message as? [String: Any] {
            return shape(forObjectKeys: Array(object.keys), container: "object")
        }

        if let object = message as? [AnyHashable: Any] {
            return shape(
                forObjectKeys: object.keys.compactMap { $0 as? String },
                container: "object"
            )
        }

        if let string = message as? String {
            return shapeForJSONString(string)
        }

        if message is [Any] {
            return SafariExtensionNativeMessagingMessageShape(
                container: "array",
                topLevelKeys: [],
                typeKeys: []
            )
        }

        return SafariExtensionNativeMessagingMessageShape(
            container: String(describing: type(of: message)),
            topLevelKeys: [],
            typeKeys: []
        )
    }

    static func classify(
        direction: SafariExtensionNativeMessagingDirection,
        applicationIdentifier: String?,
        resolvedHostBundleIdentifier: String?,
        adapter: SumiNativeMessagingProtocolAdapter?,
        adapterByApplicationIdentifier: SumiNativeMessagingProtocolAdapter?,
        registryLookupAttempted: Bool,
        fallbackReason: String?
    ) -> SafariExtensionNativeMessagingRoutingBucket {
        if adapter != nil {
            switch direction {
            case .send:
                return .adapterSelectedRealSendMessage
            case .connect, .portReceive, .portRelay:
                return .adapterSelectedRealConnectNative
            }
        }

        if registryLookupAttempted == false {
            if isIdentifierUnknown(applicationIdentifier: applicationIdentifier, resolvedHostBundleIdentifier: resolvedHostBundleIdentifier) {
                return .identifierUnknown
            }
            return .fallbackBeforeRegistry
        }

        if adapterByApplicationIdentifier != nil {
            return .adapterNotSelectedIdentifierMismatch
        }

        if isIdentifierUnknown(applicationIdentifier: applicationIdentifier, resolvedHostBundleIdentifier: resolvedHostBundleIdentifier) {
            return .identifierUnknown
        }

        return .fallbackAfterRegistry
    }

    static func logDelegateObserved(
        delegateMethod: String,
        direction: SafariExtensionNativeMessagingDirection,
        extensionId: String?,
        extensionDisplayName: String?,
        applicationIdentifier: String?,
        profileId: UUID?,
        messageShape: SafariExtensionNativeMessagingMessageShape? = nil
    ) {
        #if DEBUG || SUMI_DIAGNOSTICS
            guard RuntimeDiagnostics.isVerboseEnabled else { return }
            RuntimeDiagnostics.debug(category: "SafariNativeMessagingRouting") {
                """
                delegate=\(delegateMethod) observed \
                dir=\(direction.rawValue) \
                extBucket=\(extensionIdBucket(extensionId)) \
                extLabel=\(sanitizedExtensionLabel(extensionDisplayName)) \
                profile=\(profileIdBucket(profileId)) \
                appId=\(applicationIdentifier ?? "(nil)") \
                messageShape=\(messageShape?.container ?? "-") \
                messageKeys=\(messageShape?.keysForLog ?? "-") \
                messageTypeKeys=\(messageShape?.typeKeysForLog ?? "-") \
                relayEntered=true
                """
            }
        #else
            _ = (
                delegateMethod,
                direction,
                extensionId,
                extensionDisplayName,
                applicationIdentifier,
                profileId,
                messageShape
            )
        #endif
    }

    static func log(
        delegateMethod: String,
        direction: SafariExtensionNativeMessagingDirection,
        extensionId: String?,
        applicationIdentifier: String?,
        profileId: UUID?,
        resolvedHostBundleIdentifier: String?,
        registryLookupAttempted: Bool,
        registryLookupResult: Bool,
        adapter: SumiNativeMessagingProtocolAdapter?,
        routingBucket: SafariExtensionNativeMessagingRoutingBucket,
        fallbackReason: String?
    ) {
        #if DEBUG || SUMI_DIAGNOSTICS
            guard RuntimeDiagnostics.isVerboseEnabled else { return }
            RuntimeDiagnostics.debug(category: "SafariNativeMessagingRouting") {
                """
                delegate=\(delegateMethod) \
                dir=\(direction.rawValue) \
                extBucket=\(extensionIdBucket(extensionId)) \
                profile=\(profileIdBucket(profileId)) \
                appId=\(applicationIdentifier ?? "(nil)") \
                host=\(resolvedHostBundleIdentifier ?? "(nil)") \
                registryAttempted=\(registryLookupAttempted) \
                registryHit=\(registryLookupResult) \
                adapterSelected=\(adapter != nil) \
                adapterId=\(adapter?.protocolIdentifier ?? "-") \
                bucket=\(routingBucket.rawValue) \
                fallback=\(fallbackReason ?? "-")
                """
            }
        #else
            _ = (
                delegateMethod,
                direction,
                extensionId,
                applicationIdentifier,
                profileId,
                resolvedHostBundleIdentifier,
                registryLookupAttempted,
                registryLookupResult,
                adapter,
                routingBucket,
                fallbackReason
            )
        #endif
    }

    private static func isIdentifierUnknown(
        applicationIdentifier: String?,
        resolvedHostBundleIdentifier: String?
    ) -> Bool {
        let trimmed = applicationIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty && resolvedHostBundleIdentifier == nil {
            return true
        }
        if trimmed.isEmpty == false,
           SumiCompanionAppIdentityMetadata.isRecognizedPublicIdentity(trimmed) == false,
           resolvedHostBundleIdentifier == nil
        {
            return true
        }
        return false
    }

    private nonisolated static func shapeForJSONString(
        _ string: String
    ) -> SafariExtensionNativeMessagingMessageShape {
        guard let data = string.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
        else {
            return SafariExtensionNativeMessagingMessageShape(
                container: "string",
                topLevelKeys: [],
                typeKeys: []
            )
        }

        if let dictionary = object as? [String: Any] {
            return shape(forObjectKeys: Array(dictionary.keys), container: "jsonStringObject")
        }
        if object is [Any] {
            return SafariExtensionNativeMessagingMessageShape(
                container: "jsonStringArray",
                topLevelKeys: [],
                typeKeys: []
            )
        }
        return SafariExtensionNativeMessagingMessageShape(
            container: "jsonStringScalar",
            topLevelKeys: [],
            typeKeys: []
        )
    }

    private nonisolated static func shape(
        forObjectKeys keys: [String],
        container: String
    ) -> SafariExtensionNativeMessagingMessageShape {
        let safeKeys = keys
            .map(sanitizedKey)
            .filter { $0.isEmpty == false }
            .sorted()
        let limitedKeys = Array(safeKeys.prefix(12))
        let typeKeys = limitedKeys.filter(isTypeLikeKey)
        return SafariExtensionNativeMessagingMessageShape(
            container: container,
            topLevelKeys: limitedKeys,
            typeKeys: typeKeys
        )
    }

    private nonisolated static func sanitizedKey(_ key: String) -> String {
        let allowed = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "._-"))
        let sanitized = String(
            key.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.map {
                allowed.contains($0) ? String($0) : "_"
            }.joined()
        )
        return String(sanitized.prefix(48))
    }

    private nonisolated static func isTypeLikeKey(_ key: String) -> Bool {
        switch key.lowercased() {
        case "type", "kind", "command", "action", "method", "request", "event", "operation":
            return true
        default:
            return false
        }
    }
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

/// Static or runtime biometrics probe status for adapter routing reports (no credential data).
enum SumiNativeMessagingBiometricsStatusProbe: String, Codable, Sendable, Equatable {
    case notApplicable
    case notAttempted
    case available
    case unavailable
    case probeOnly
}

struct SafariExtensionNativeMessagingProbeEntry: Codable, Equatable, Sendable, Identifiable {
    var id: String { extensionId ?? targetKey }

    let targetKey: String
    let displayName: String
    let extensionId: String?
    let isImported: Bool
    let isEnabled: Bool
    let popupStatus: SafariExtensionPopupLoadStatus
    let delegateCallbackObserved: Bool
    let applicationIdentifier: String?
    let resolverBucket: SumiNativeMessagingResolverBucket?
    let connectionBucket: SafariExtensionNativeMessagingConnectionBucket
    let errorBucket: SafariExtensionNativeMessagingErrorBucket
    let classifications: [SafariExtensionNativeMessagingClassification]
    let launchSuppressionExpected: Bool
    let expectedSessionState: SumiNativeMessagingSessionState?
    let adapterSelected: Bool
    let adapterIdentifier: String?
    let appResolved: Bool
    let appLaunched: Bool
    let protocolStatus: SumiNativeMessagingProtocolStatus
    let handshakeStatus: SumiNativeMessagingHandshakeStatus
    let autofillPathStatus: SumiNativeMessagingAutofillPathStatus
    let failureBucket: SafariExtensionNativeMessagingErrorBucket
}

/// Per-target adapter boundary status for DEBUG compatibility reports (Raindrop / PM targets).
struct SafariExtensionNativeMessagingAdapterCompatibilityStatus: Codable, Equatable, Sendable,
    Identifiable
{
    var id: String { targetKey }

    let targetKey: String
    let displayName: String
    let applicationIdentifier: String?
    let hostBundleIdentifier: String?
    let adapterSelected: Bool
    let adapterIdentifier: String?
    let appResolved: Bool
    let appInstalled: Bool
    let launchSuppressionExpected: Bool
    let protocolStatus: SumiNativeMessagingProtocolStatus
    let handshakeStatus: SumiNativeMessagingHandshakeStatus
    let autofillPathStatus: SumiNativeMessagingAutofillPathStatus
    let failureBucket: SafariExtensionNativeMessagingErrorBucket
    let registeredAdapterIdentifiers: [String]
    let realTransportAttempted: Bool
    let desktopResolved: Bool
    let desktopRunning: Bool
    let desktopLaunchAttempted: Bool
    let desktopLaunchSuppressed: Bool
    let biometricsStatusProbe: SumiNativeMessagingBiometricsStatusProbe
    let repeatedCallCountBucket: SumiNativeMessagingRetryCountBucket
}

struct SafariExtensionNativeMessagingProbeReport: Codable, Equatable, Sendable {
    let generatedAt: Date
    let entries: [SafariExtensionNativeMessagingProbeEntry]
    let adapterCompatibility: [SafariExtensionNativeMessagingAdapterCompatibilityStatus]
    let globalClassifications: [SafariExtensionNativeMessagingClassification]
    let suppressionReport: SafariExtensionNativeMessagingSuppressionReport
    let sdkProbeNote: String
    let delegateMethodsRegistered: Bool
    let registeredAdapterIdentifiers: [String]
}

@MainActor
enum SafariExtensionNativeMessagingProbeBuilder {
    static func build(
        targets: [SafariExtensionCompatibilityTargets.Target] = SafariExtensionCompatibilityTargets.all,
        discovered: [DiscoveredSafariExtensionCandidate],
        importStore: SafariExtensionImportStore = .shared,
        installedExtensions: [InstalledExtension] = [],
        extensionManager: ExtensionManager? = nil,
        extensionsModuleEnabled: Bool = true,
        adapterRegistry: SumiNativeMessagingAdapterRegistry = .shared
    ) -> SafariExtensionNativeMessagingProbeReport {
        let registeredAdapterIdentifiers = adapterRegistry.registeredProtocolIdentifiers
        let compatibility = SafariExtensionCompatibilityReportBuilder.build(
            targets: targets,
            discovered: discovered,
            importStore: importStore,
            installedExtensions: installedExtensions,
            extensionManager: extensionManager,
            extensionsModuleEnabled: extensionsModuleEnabled
        )
        let compatibilityByKey = Dictionary(
            uniqueKeysWithValues: compatibility.entries.map { ($0.targetKey, $0) }
        )

        let entries = targets.map { target in
            let compatibilityEntry = compatibilityByKey[target.key]
            let installed = installedExtensions.first {
                $0.id == compatibilityEntry?.installedExtensionId
            }
            let resolverBucket = previewResolverBucket(
                target: target,
                installed: installed,
                importStore: importStore
            )
            let isPasswordManager = SafariExtensionNativeMessagingClassificationCatalog
                .passwordManagerTargetKeys.contains(target.key)

            let errorBucket: SafariExtensionNativeMessagingErrorBucket = {
                guard extensionsModuleEnabled else { return .moduleDisabled }
                guard compatibilityEntry?.isImported == true else { return .extensionNotImported }
                guard compatibilityEntry?.isEnabled == true else { return .extensionDisabled }
                if isPasswordManager {
                    return passwordManagerPreviewErrorBucket(
                        targetKey: target.key,
                        hostBundleIdentifier: previewHostBundleIdentifier(
                            target: target,
                            installed: installed,
                            importStore: importStore
                        ),
                        adapterRegistry: adapterRegistry
                    )
                }
                return .none
            }()

            let connectionBucket: SafariExtensionNativeMessagingConnectionBucket = {
                guard extensionsModuleEnabled else { return .policyDenied }
                guard compatibilityEntry?.isImported == true else { return .notAttempted }
                if isPasswordManager {
                    let hostBundleIdentifier = previewHostBundleIdentifier(
                        target: target,
                        installed: installed,
                        importStore: importStore
                    )
                    if hostBundleIdentifier.flatMap({
                        adapterRegistry.adapter(forHostBundleIdentifier: $0)
                    }) != nil {
                        return .notAttempted
                    }
                    return .companionProtocolUnknown
                }
                return .notAttempted
            }()

            let applicationIdentifier = previewApplicationIdentifier(for: target)
            let adapterPreview = previewAdapterStatus(
                target: target,
                installed: installed,
                importStore: importStore,
                adapterRegistry: adapterRegistry,
                extensionsModuleEnabled: extensionsModuleEnabled,
                compatibilityImported: compatibilityEntry?.isImported ?? false,
                compatibilityEnabled: compatibilityEntry?.isEnabled ?? false,
                isPasswordManager: isPasswordManager,
                errorBucket: errorBucket
            )

            return SafariExtensionNativeMessagingProbeEntry(
                targetKey: target.key,
                displayName: target.displayName,
                extensionId: compatibilityEntry?.installedExtensionId,
                isImported: compatibilityEntry?.isImported ?? false,
                isEnabled: compatibilityEntry?.isEnabled ?? false,
                popupStatus: compatibilityEntry?.popupLoadStatus ?? .unavailable,
                delegateCallbackObserved: SumiNativeMessagingRelay.delegateMethodsRegistered,
                applicationIdentifier: applicationIdentifier,
                resolverBucket: resolverBucket,
                connectionBucket: connectionBucket,
                errorBucket: errorBucket,
                classifications: SafariExtensionNativeMessagingClassificationCatalog
                    .classifications(forTargetKey: target.key),
                launchSuppressionExpected: isPasswordManager,
                expectedSessionState: isPasswordManager ? .unknownProtocolInitial : nil,
                adapterSelected: adapterPreview.adapterSelected,
                adapterIdentifier: adapterPreview.adapterIdentifier,
                appResolved: adapterPreview.appResolved,
                appLaunched: false,
                protocolStatus: adapterPreview.protocolStatus,
                handshakeStatus: adapterPreview.handshakeStatus,
                autofillPathStatus: adapterPreview.autofillPathStatus,
                failureBucket: adapterPreview.failureBucket
            )
        }

        let adapterCompatibility = targets.map { target in
            let compatibilityEntry = compatibilityByKey[target.key]
            let installed = installedExtensions.first {
                $0.id == compatibilityEntry?.installedExtensionId
            }
            let isPasswordManager = SafariExtensionNativeMessagingClassificationCatalog
                .passwordManagerTargetKeys.contains(target.key)
            let hostBundleIdentifier = previewHostBundleIdentifier(
                target: target,
                installed: installed,
                importStore: importStore
            )
            let errorBucket: SafariExtensionNativeMessagingErrorBucket = {
                guard extensionsModuleEnabled else { return .moduleDisabled }
                guard compatibilityEntry?.isImported == true else { return .extensionNotImported }
                guard compatibilityEntry?.isEnabled == true else { return .extensionDisabled }
                if isPasswordManager {
                    return passwordManagerPreviewErrorBucket(
                        targetKey: target.key,
                        hostBundleIdentifier: hostBundleIdentifier,
                        adapterRegistry: adapterRegistry
                    )
                }
                return .none
            }()
            let preview = previewAdapterStatus(
                target: target,
                installed: installed,
                importStore: importStore,
                adapterRegistry: adapterRegistry,
                extensionsModuleEnabled: extensionsModuleEnabled,
                compatibilityImported: compatibilityEntry?.isImported ?? false,
                compatibilityEnabled: compatibilityEntry?.isEnabled ?? false,
                isPasswordManager: isPasswordManager,
                errorBucket: errorBucket
            )
            let routingDiagnostics = routingDiagnosticsPreview(
                preview: preview,
                isPasswordManager: isPasswordManager,
                launchSuppressionExpected: isPasswordManager
            )
            return SafariExtensionNativeMessagingAdapterCompatibilityStatus(
                targetKey: target.key,
                displayName: target.displayName,
                applicationIdentifier: preview.applicationIdentifier,
                hostBundleIdentifier: preview.hostBundleIdentifier,
                adapterSelected: preview.adapterSelected,
                adapterIdentifier: preview.adapterIdentifier,
                appResolved: preview.appResolved,
                appInstalled: preview.appInstalled,
                launchSuppressionExpected: isPasswordManager,
                protocolStatus: preview.protocolStatus,
                handshakeStatus: preview.handshakeStatus,
                autofillPathStatus: preview.autofillPathStatus,
                failureBucket: preview.failureBucket,
                registeredAdapterIdentifiers: registeredAdapterIdentifiers,
                realTransportAttempted: routingDiagnostics.realTransportAttempted,
                desktopResolved: routingDiagnostics.desktopResolved,
                desktopRunning: routingDiagnostics.desktopRunning,
                desktopLaunchAttempted: routingDiagnostics.desktopLaunchAttempted,
                desktopLaunchSuppressed: routingDiagnostics.desktopLaunchSuppressed,
                biometricsStatusProbe: routingDiagnostics.biometricsStatusProbe,
                repeatedCallCountBucket: routingDiagnostics.repeatedCallCountBucket
            )
        }

        return SafariExtensionNativeMessagingProbeReport(
            generatedAt: Date(),
            entries: entries,
            adapterCompatibility: adapterCompatibility,
            globalClassifications: SafariExtensionNativeMessagingClassificationCatalog
                .globalReportClassifications(sumiRelayImplemented: true),
            suppressionReport: SafariExtensionNativeMessagingSuppressionProbe.evaluate(),
            sdkProbeNote: SafariExtensionHostRelaySDKProbeMetadata.sdkProbeNote,
            delegateMethodsRegistered: SumiNativeMessagingRelay.delegateMethodsRegistered,
            registeredAdapterIdentifiers: registeredAdapterIdentifiers
        )
    }

    static func logIfDiagnosticsEnabled(_ report: SafariExtensionNativeMessagingProbeReport) {
        #if DEBUG || SUMI_DIAGNOSTICS
            guard RuntimeDiagnostics.isVerboseEnabled else { return }

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            guard let data = try? encoder.encode(report),
                  let json = String(data: data, encoding: .utf8)
            else {
                RuntimeDiagnostics.debug(
                    "SafariExtensionNativeMessagingProbe encode failed",
                    category: "SafariNativeMessaging"
                )
                return
            }

            RuntimeDiagnostics.debug(
                "SafariExtensionNativeMessagingProbe \(json)",
                category: "SafariNativeMessaging"
            )
        #else
            _ = report
        #endif
    }

    private static func previewApplicationIdentifier(
        for target: SafariExtensionCompatibilityTargets.Target
    ) -> String? {
        target.nativeMessagingApplicationIdentifier
    }

    private static func previewResolverBucket(
        target: SafariExtensionCompatibilityTargets.Target,
        installed: InstalledExtension?,
        importStore: SafariExtensionImportStore
    ) -> SumiNativeMessagingResolverBucket? {
        guard let installed else { return nil }
        let resolution = SumiNativeMessagingAppResolver.resolve(
            requestedApplicationIdentifier: previewApplicationIdentifier(for: target),
            extensionId: installed.id,
            installedExtensions: [installed],
            importStore: importStore
        )
        return resolution?.bucket
    }

    private struct AdapterPreviewStatus {
        let applicationIdentifier: String?
        let hostBundleIdentifier: String?
        let adapterSelected: Bool
        let adapterIdentifier: String?
        let appResolved: Bool
        let appInstalled: Bool
        let protocolStatus: SumiNativeMessagingProtocolStatus
        let handshakeStatus: SumiNativeMessagingHandshakeStatus
        let autofillPathStatus: SumiNativeMessagingAutofillPathStatus
        let failureBucket: SafariExtensionNativeMessagingErrorBucket
    }

    private static func previewAdapterStatus(
        target: SafariExtensionCompatibilityTargets.Target,
        installed: InstalledExtension?,
        importStore: SafariExtensionImportStore,
        adapterRegistry: SumiNativeMessagingAdapterRegistry,
        extensionsModuleEnabled: Bool,
        compatibilityImported: Bool,
        compatibilityEnabled: Bool,
        isPasswordManager: Bool,
        errorBucket: SafariExtensionNativeMessagingErrorBucket
    ) -> AdapterPreviewStatus {
        let applicationIdentifier = previewApplicationIdentifier(for: target)
        let hostBundleIdentifier = previewHostBundleIdentifier(
            target: target,
            installed: installed,
            importStore: importStore
        )
        let adapter = hostBundleIdentifier.flatMap {
            adapterRegistry.adapter(forHostBundleIdentifier: $0)
        }
        let appResolved = hostBundleIdentifier != nil
        let appInstalled = hostBundleIdentifier.map {
            SumiNSWorkspaceHostApplicationLauncher().urlForApplication(withBundleIdentifier: $0) != nil
        } ?? false

        let protocolStatus: SumiNativeMessagingProtocolStatus = {
            guard extensionsModuleEnabled, compatibilityImported, compatibilityEnabled else {
                return .notApplicable
            }
            if target.key == "raindrop" { return .notApplicable }
            if adapter != nil { return .adapterReady }
            if isPasswordManager { return .protocolUnknown }
            return .adapterUnavailable
        }()

        let handshakeStatus: SumiNativeMessagingHandshakeStatus = {
            guard isPasswordManager else { return .notApplicable }
            return adapter != nil ? .notAttempted : .suppressed
        }()

        let autofillPathStatus: SumiNativeMessagingAutofillPathStatus = {
            guard isPasswordManager else { return .notApplicable }
            if SafariExtensionContentScriptProbe.isTabReconcilePathWiredInSources() {
                return .contentScriptsWired
            }
            return .pendingManualVerification
        }()

        let resolvedFailureBucket: SafariExtensionNativeMessagingErrorBucket = {
            switch errorBucket {
            case .moduleDisabled, .extensionNotImported, .extensionDisabled:
                return errorBucket
            default:
                return adapter != nil ? .none : errorBucket
            }
        }()

        return AdapterPreviewStatus(
            applicationIdentifier: applicationIdentifier,
            hostBundleIdentifier: hostBundleIdentifier,
            adapterSelected: adapter != nil,
            adapterIdentifier: adapter?.protocolIdentifier,
            appResolved: appResolved,
            appInstalled: appInstalled,
            protocolStatus: protocolStatus,
            handshakeStatus: handshakeStatus,
            autofillPathStatus: autofillPathStatus,
            failureBucket: resolvedFailureBucket
        )
    }

    private struct RoutingDiagnosticsPreview {
        let realTransportAttempted: Bool
        let desktopResolved: Bool
        let desktopRunning: Bool
        let desktopLaunchAttempted: Bool
        let desktopLaunchSuppressed: Bool
        let biometricsStatusProbe: SumiNativeMessagingBiometricsStatusProbe
        let repeatedCallCountBucket: SumiNativeMessagingRetryCountBucket
    }

    private static func routingDiagnosticsPreview(
        preview: AdapterPreviewStatus,
        isPasswordManager: Bool,
        launchSuppressionExpected: Bool
    ) -> RoutingDiagnosticsPreview {
        guard isPasswordManager else {
            return RoutingDiagnosticsPreview(
                realTransportAttempted: false,
                desktopResolved: false,
                desktopRunning: false,
                desktopLaunchAttempted: false,
                desktopLaunchSuppressed: false,
                biometricsStatusProbe: .notApplicable,
                repeatedCallCountBucket: .none
            )
        }

        let biometricsProbe: SumiNativeMessagingBiometricsStatusProbe = {
            guard preview.adapterSelected else { return .notApplicable }
            return .notAttempted
        }()

        return RoutingDiagnosticsPreview(
            realTransportAttempted: false,
            desktopResolved: preview.appResolved,
            desktopRunning: isDesktopRunning(bundleIdentifier: preview.hostBundleIdentifier),
            desktopLaunchAttempted: false,
            desktopLaunchSuppressed: launchSuppressionExpected && preview.adapterSelected == false,
            biometricsStatusProbe: biometricsProbe,
            repeatedCallCountBucket: .none
        )
    }

    private static func passwordManagerPreviewErrorBucket(
        targetKey: String,
        hostBundleIdentifier: String?,
        adapterRegistry: SumiNativeMessagingAdapterRegistry
    ) -> SafariExtensionNativeMessagingErrorBucket {
        if let hostBundleIdentifier,
           adapterRegistry.adapter(forHostBundleIdentifier: hostBundleIdentifier) != nil
        {
            return .none
        }
        return .companionAppProtocolUnknown
    }

    private static func isDesktopRunning(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .isEmpty == false
    }

    private static func previewHostBundleIdentifier(
        target: SafariExtensionCompatibilityTargets.Target,
        installed: InstalledExtension?,
        importStore: SafariExtensionImportStore
    ) -> String? {
        if let installed,
           let identity = SumiCompanionAppResolver.resolveIdentity(
               requestedApplicationIdentifier: previewApplicationIdentifier(for: target),
               extensionId: installed.id,
               installedExtensions: [installed],
               importStore: importStore
           )
        {
            return identity.resolvedBundleIdentifier
        }
        return target.nativeMessagingHostBundleIdentifier
    }
}

@MainActor
extension SumiExtensionsModule {
    func safariExtensionNativeMessagingProbe() -> SafariExtensionNativeMessagingProbeReport {
        var issues: [SafariExtensionScannerIssue] = []
        let discovered = SafariExtensionScanner().scanInstalledExtensions(issues: &issues)
        SafariExtensionImportStore.shared.refreshDiscoveredCandidates(discovered)

        let manager = managerIfLoadedAndEnabled()
        let report = SafariExtensionNativeMessagingProbeBuilder.build(
            discovered: discovered,
            installedExtensions: manager?.installedExtensions ?? [],
            extensionManager: manager,
            extensionsModuleEnabled: isEnabled
        )
        SafariExtensionNativeMessagingProbeBuilder.logIfDiagnosticsEnabled(report)
        return report
    }

    #if DEBUG
    func printSafariExtensionNativeMessagingProbeToConsole() {
        guard isEnabled else {
            print("SafariExtensionNativeMessagingProbe: skipped — Extensions module is disabled")
            return
        }

        let report = safariExtensionNativeMessagingProbe()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        guard let data = try? encoder.encode(report),
              let json = String(data: data, encoding: .utf8)
        else {
            print("SafariExtensionNativeMessagingProbe: encode failed")
            return
        }

        print("SafariExtensionNativeMessagingProbe:\n\(json)")
        SafariExtensionNativeMessagingProbeBuilder.logIfDiagnosticsEnabled(report)
    }
    #endif
}
