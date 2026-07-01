//
//  SumiNativeMessagingAdapterTransport.swift
//  Sumi
//
//  Transport contract and capability model for public companion-app protocol adapters.
//  Generic runtime owns timeout, cancellation, disconnect, and error mapping; adapters
//  implement protocol-specific relay only.
//

import Foundation

/// Adapter-facing capability outcomes surfaced to diagnostics and relay policy.
enum SumiNativeMessagingAdapterCapability: String, Codable, Sendable, Equatable {
    case adapterAvailable
    case adapterUnavailable
    case appNotInstalled
    case desktopIntegrationDisabled
    case protocolVersionUnsupported
    case userActionRequired
    case nativeHostManifestMissing
    case nativeHostExecutableMissing
    case permissionDenied
    case unsupportedHostKind
    case timeout
    case portDisconnected
}

enum SumiNativeMessagingCapabilityDecision: String, Codable, Sendable, Equatable {
    case supportedByAdapter
    case supportedByPrivateSPIBackend
    case supportedByDocumentedFallback
    case fallbackObservedFailed
    case unsupportedNoBackend
    case deniedByUserOrPolicy
    case unknownNeedsDiagnostics
}

enum SumiNativeMessagingSourceKind: String, Codable, Sendable, Equatable {
    case appExtensionBundle
    case resourceBaseURL
    case unknown
}

struct SumiNativeMessagingCapabilityPolicyInput: Sendable, Equatable {
    let extensionId: String?
    let extensionBundleIdentifier: String?
    let appExtensionBundleIdentifier: String?
    let applicationIdentifier: String?
    let sourceKind: SumiNativeMessagingSourceKind
    let manifestRequestsNativeMessaging: Bool
    let nativeMessagingPermissionGranted: Bool?
    let adapterAvailable: Bool
    let privateSPIBackendAvailable: Bool
    let documentedFallbackAvailable: Bool
    let fallbackObservedFailure: Bool
    let isNativeMacBundle: Bool?
    let isMacCatalystBundle: Bool?
    let isPrivateProfile: Bool
    let deniedByPolicy: Bool

    init(
        extensionId: String? = nil,
        extensionBundleIdentifier: String? = nil,
        appExtensionBundleIdentifier: String? = nil,
        applicationIdentifier: String? = nil,
        sourceKind: SumiNativeMessagingSourceKind = .unknown,
        manifestRequestsNativeMessaging: Bool,
        nativeMessagingPermissionGranted: Bool? = nil,
        adapterAvailable: Bool = false,
        privateSPIBackendAvailable: Bool = false,
        documentedFallbackAvailable: Bool = false,
        fallbackObservedFailure: Bool = false,
        isNativeMacBundle: Bool? = nil,
        isMacCatalystBundle: Bool? = nil,
        isPrivateProfile: Bool = false,
        deniedByPolicy: Bool = false
    ) {
        self.extensionId = extensionId
        self.extensionBundleIdentifier = extensionBundleIdentifier
        self.appExtensionBundleIdentifier = appExtensionBundleIdentifier
        self.applicationIdentifier = applicationIdentifier
        self.sourceKind = sourceKind
        self.manifestRequestsNativeMessaging = manifestRequestsNativeMessaging
        self.nativeMessagingPermissionGranted = nativeMessagingPermissionGranted
        self.adapterAvailable = adapterAvailable
        self.privateSPIBackendAvailable = privateSPIBackendAvailable
        self.documentedFallbackAvailable = documentedFallbackAvailable
        self.fallbackObservedFailure = fallbackObservedFailure
        self.isNativeMacBundle = isNativeMacBundle
        self.isMacCatalystBundle = isMacCatalystBundle
        self.isPrivateProfile = isPrivateProfile
        self.deniedByPolicy = deniedByPolicy
    }
}

enum SumiNativeMessagingCapabilityPolicy {
    static func decide(
        _ input: SumiNativeMessagingCapabilityPolicyInput
    ) -> SumiNativeMessagingCapabilityDecision {
        if input.deniedByPolicy || input.isPrivateProfile {
            return .deniedByUserOrPolicy
        }

        guard input.manifestRequestsNativeMessaging else {
            return .unsupportedNoBackend
        }

        if input.nativeMessagingPermissionGranted == false {
            return .deniedByUserOrPolicy
        }

        if input.adapterAvailable {
            return .supportedByAdapter
        }

        if input.privateSPIBackendAvailable {
            return .supportedByPrivateSPIBackend
        }

        if input.documentedFallbackAvailable && input.fallbackObservedFailure == false {
            return .supportedByDocumentedFallback
        }

        if input.fallbackObservedFailure {
            return .fallbackObservedFailed
        }

        let hasIdentity =
            input.extensionId?.isEmpty == false
                || input.extensionBundleIdentifier?.isEmpty == false
                || input.appExtensionBundleIdentifier?.isEmpty == false
                || input.applicationIdentifier?.isEmpty == false

        if hasIdentity || input.sourceKind != .unknown
            || input.isNativeMacBundle != nil || input.isMacCatalystBundle != nil {
            return .unsupportedNoBackend
        }

        return .unknownNeedsDiagnostics
    }
}

@MainActor
enum SumiNativeMessagingAdapterTransport {
    static func capability(
        for evaluation: SumiCompanionAppResolverResult?,
        adapterAvailable: Bool,
        relayErrorCode: SumiNativeMessagingRelay.ErrorCode? = nil
    ) -> SumiNativeMessagingAdapterCapability {
        if let relayErrorCode {
            switch relayErrorCode {
            case .relayTimeout:
                return .timeout
            case .relayCancelled:
                return .portDisconnected
            case .hostNotFound:
                return .appNotInstalled
            case .nativeHostManifestMissing:
                return .nativeHostManifestMissing
            case .nativeHostExecutableMissing:
                return .nativeHostExecutableMissing
            case .nativeHostPermissionDenied:
                return .permissionDenied
            case .nativeHostUnsupportedKind:
                return .unsupportedHostKind
            case .policyDenied:
                return .desktopIntegrationDisabled
            default:
                break
            }
        }

        guard let evaluation else {
            return adapterAvailable ? .adapterAvailable : .adapterUnavailable
        }

        switch evaluation {
        case .appNotFound:
            return .appNotInstalled
        case .protocolAdapterUnavailable, .appFoundButProtocolUnknown:
            return .adapterUnavailable
        case .launchSuppressed, .launchRateLimited:
            return .desktopIntegrationDisabled
        case .containingAppResolved, .companionAppResolved:
            return adapterAvailable ? .adapterAvailable : .adapterUnavailable
        case .notRequested, .applicationIdentifierMissing:
            return .adapterUnavailable
        }
    }

    static func mapRelayError(_ error: NSError) -> SumiNativeMessagingAdapterCapability {
        guard error.domain == SumiNativeMessagingRelay.errorDomain,
              let code = SumiNativeMessagingRelay.ErrorCode(rawValue: error.code)
        else {
            return .adapterUnavailable
        }
        return capability(for: nil, adapterAvailable: false, relayErrorCode: code)
    }
}
