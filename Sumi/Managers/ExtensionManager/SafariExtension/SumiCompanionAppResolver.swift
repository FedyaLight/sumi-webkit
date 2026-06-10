//
//  SumiCompanionAppResolver.swift
//  Sumi
//
//  Generic companion-app identity resolution and bounded launch evaluation.
//

import Foundation

enum SumiCompanionAppResolutionSource: String, Codable, Sendable {
    case containingAppOfImportedAppex
    case publicBundleIdentityAlias
    case explicitApplicationIdentifier
    case appGroupsMetadata
}

struct SumiCompanionAppResolutionDetail: Sendable, Equatable {
    let requestedApplicationIdentifier: String?
    let resolvedBundleIdentifier: String
    let isContainingApp: Bool
    let resolutionSource: SumiCompanionAppResolutionSource
    let appInstalled: Bool
    let protocolAdapterAvailable: Bool
    let launchAllowed: Bool
    let launchDecision: SumiCompanionAppLaunchDecision?
}

enum SumiCompanionAppResolverResult: Sendable, Equatable {
    case notRequested
    case applicationIdentifierMissing
    case containingAppResolved(SumiCompanionAppResolutionDetail)
    case companionAppResolved(SumiCompanionAppResolutionDetail)
    case appNotFound(SumiCompanionAppResolutionDetail)
    case appFoundButProtocolUnknown(SumiCompanionAppResolutionDetail)
    case launchSuppressed(SumiCompanionAppResolutionDetail)
    case launchRateLimited(SumiCompanionAppResolutionDetail)
    case protocolAdapterUnavailable(SumiCompanionAppResolutionDetail)

    var detail: SumiCompanionAppResolutionDetail? {
        switch self {
        case .notRequested, .applicationIdentifierMissing:
            return nil
        case .containingAppResolved(let detail),
             .companionAppResolved(let detail),
             .appNotFound(let detail),
             .appFoundButProtocolUnknown(let detail),
             .launchSuppressed(let detail),
             .launchRateLimited(let detail),
             .protocolAdapterUnavailable(let detail):
            return detail
        }
    }

    var legacyResolverBucket: SumiNativeMessagingResolverBucket {
        guard let detail else { return .noMatch }
        switch detail.resolutionSource {
        case .containingAppOfImportedAppex, .appGroupsMetadata:
            return detail.resolutionSource == .appGroupsMetadata
                ? .appGroupsMetadata
                : .containingAppOfImportedAppex
        case .publicBundleIdentityAlias:
            return .knownCompanionAlias
        case .explicitApplicationIdentifier:
            return .explicitApplicationIdentifier
        }
    }
}

enum SumiCompanionAppResolver {
    struct IdentityResolution: Sendable, Equatable {
        let resolvedBundleIdentifier: String
        let resolutionSource: SumiCompanionAppResolutionSource
        let isContainingApp: Bool
    }

    static func resolveIdentity(
        requestedApplicationIdentifier: String?,
        extensionId: String?,
        installedExtensions: [InstalledExtension],
        importStore: SafariExtensionImportStore
    ) -> IdentityResolution? {
        let trimmedRequest = requestedApplicationIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let trimmedRequest, trimmedRequest.isEmpty == false {
            let normalized = SumiCompanionAppIdentityMetadata
                .normalizedHostBundleIdentifier(trimmedRequest)
            let source: SumiCompanionAppResolutionSource =
                SumiCompanionAppIdentityMetadata.publicHostBundleIdentifierAliases[trimmedRequest] != nil
                ? .publicBundleIdentityAlias
                : .explicitApplicationIdentifier

            let isContaining =
                source == .publicBundleIdentityAlias
                ? false
                : isContainingAppIdentifier(
                    normalized,
                    extensionId: extensionId,
                    installedExtensions: installedExtensions
                )

            return IdentityResolution(
                resolvedBundleIdentifier: normalized,
                resolutionSource: source,
                isContainingApp: isContaining
            )
        }

        guard let extensionId, extensionId.isEmpty == false else {
            return nil
        }

        guard let installed = installedExtensions.first(where: { $0.id == extensionId }),
              installed.sourceKind == .safariAppExtension
        else {
            return nil
        }

        if let containing = containingApplicationBundleIdentifier(
            forAppexPath: installed.sourceBundlePath
        ) {
            return IdentityResolution(
                resolvedBundleIdentifier: SumiCompanionAppIdentityMetadata
                    .normalizedHostBundleIdentifier(containing),
                resolutionSource: .containingAppOfImportedAppex,
                isContainingApp: true
            )
        }

        if let appexBundleID = appexBundleIdentifier(at: installed.sourceBundlePath),
           let discovered = importStore.discoveredCandidates().first(where: {
               $0.extensionBundleIdentifier == appexBundleID
           }),
           let containing = containingApplicationBundleIdentifier(
               forAppexPath: discovered.appexPath
           )
        {
            return IdentityResolution(
                resolvedBundleIdentifier: SumiCompanionAppIdentityMetadata
                    .normalizedHostBundleIdentifier(containing),
                resolutionSource: .containingAppOfImportedAppex,
                isContainingApp: true
            )
        }

        if let metadataHost = resolveFromAppGroupsMetadata(appexPath: installed.sourceBundlePath) {
            return metadataHost
        }

        return nil
    }

    @MainActor
    static func evaluate(
        requestedApplicationIdentifier: String?,
        extensionId: String?,
        installedExtensions: [InstalledExtension],
        importStore: SafariExtensionImportStore,
        launcher: SumiHostApplicationLaunching,
        adapterRegistry: SumiNativeMessagingAdapterRegistry = .shared,
        launchPolicy: SumiCompanionAppLaunchPolicy = .shared
    ) -> SumiCompanionAppResolverResult {
        let trimmedRequest = requestedApplicationIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if (trimmedRequest == nil || trimmedRequest?.isEmpty == true),
           (extensionId == nil || extensionId?.isEmpty == true)
        {
            return .notRequested
        }

        guard let identity = resolveIdentity(
            requestedApplicationIdentifier: requestedApplicationIdentifier,
            extensionId: extensionId,
            installedExtensions: installedExtensions,
            importStore: importStore
        ) else {
            if trimmedRequest == nil || trimmedRequest?.isEmpty == true {
                return .applicationIdentifierMissing
            }
            return .applicationIdentifierMissing
        }

        let hostBundleIdentifier = identity.resolvedBundleIdentifier
        let appInstalled = launcher.urlForApplication(withBundleIdentifier: hostBundleIdentifier) != nil
        let adapterAvailable = adapterRegistry.isAdapterAvailable(
            forApplicationIdentifier: trimmedRequest,
            hostBundleIdentifier: hostBundleIdentifier
        )

        let launchDecision = launchPolicy.evaluateLaunch(
            hostBundleIdentifier: hostBundleIdentifier,
            appInstalled: appInstalled,
            protocolAdapterAvailable: adapterAvailable
        )

        let detail = SumiCompanionAppResolutionDetail(
            requestedApplicationIdentifier: trimmedRequest,
            resolvedBundleIdentifier: hostBundleIdentifier,
            isContainingApp: identity.isContainingApp,
            resolutionSource: identity.resolutionSource,
            appInstalled: appInstalled,
            protocolAdapterAvailable: adapterAvailable,
            launchAllowed: launchDecision == .allowed,
            launchDecision: launchDecision
        )

        guard appInstalled else {
            return .appNotFound(detail)
        }

        switch launchDecision {
        case .suppressedNoProtocolAdapter:
            return .protocolAdapterUnavailable(detail)
        case .suppressedProtocolUnknown,
             .suppressedConnectIfNotRunning,
             .suppressedSessionLaunchAttempted,
             .refusedArbitraryPath:
            return .launchSuppressed(detail)
        case .rateLimited:
            return .launchRateLimited(detail)
        case .appNotInstalled:
            return .appNotFound(detail)
        case .allowed:
            break
        }

        guard adapterAvailable else {
            return .appFoundButProtocolUnknown(detail)
        }

        if identity.isContainingApp {
            return .containingAppResolved(detail)
        }
        return .companionAppResolved(detail)
    }

    static func shouldLaunchApp(for result: SumiCompanionAppResolverResult) -> Bool {
        switch result {
        case .containingAppResolved(let detail), .companionAppResolved(let detail):
            return detail.launchAllowed
        default:
            return false
        }
    }

    static func relayErrorCode(for result: SumiCompanionAppResolverResult) -> SumiNativeMessagingRelay.ErrorCode {
        switch result {
        case .notRequested, .applicationIdentifierMissing:
            return .hostNotFound
        case .appNotFound:
            return .hostNotFound
        case .appFoundButProtocolUnknown, .protocolAdapterUnavailable:
            return .companionAppProtocolUnknown
        case .launchSuppressed, .launchRateLimited:
            return .companionAppProtocolUnknown
        case .containingAppResolved, .companionAppResolved:
            return .companionAppProtocolUnknown
        }
    }

    static func containingApplicationBundleIdentifier(forAppexPath path: String) -> String? {
        var current = URL(fileURLWithPath: path).standardizedFileURL
        while current.path != "/" {
            if current.pathExtension == "app" {
                return Bundle(url: current)?.bundleIdentifier
            }
            current.deleteLastPathComponent()
        }
        return nil
    }

    static func appexBundleIdentifier(at path: String) -> String? {
        Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier
    }

    private static func isContainingAppIdentifier(
        _ bundleIdentifier: String,
        extensionId: String?,
        installedExtensions: [InstalledExtension]
    ) -> Bool {
        guard let extensionId,
              let installed = installedExtensions.first(where: { $0.id == extensionId })
        else {
            return false
        }
        guard let containing = containingApplicationBundleIdentifier(
            forAppexPath: installed.sourceBundlePath
        ) else {
            return false
        }
        return bundleIdentifier == containing
    }

    private static func resolveFromAppGroupsMetadata(
        appexPath: String
    ) -> IdentityResolution? {
        guard let containingPath = containingApplicationURL(forAppexPath: appexPath) else {
            return nil
        }

        let entitlementsURL = containingPath
            .appendingPathComponent("Contents/Library/Preferences")
        guard FileManager.default.fileExists(atPath: entitlementsURL.path) else {
            return nil
        }

        guard let bundleID = Bundle(url: containingPath)?.bundleIdentifier else {
            return nil
        }

        return IdentityResolution(
            resolvedBundleIdentifier: SumiCompanionAppIdentityMetadata
                .normalizedHostBundleIdentifier(bundleID),
            resolutionSource: .appGroupsMetadata,
            isContainingApp: true
        )
    }

    private static func containingApplicationURL(forAppexPath path: String) -> URL? {
        var current = URL(fileURLWithPath: path).standardizedFileURL
        while current.path != "/" {
            if current.pathExtension == "app" {
                return current
            }
            current.deleteLastPathComponent()
        }
        return nil
    }
}
