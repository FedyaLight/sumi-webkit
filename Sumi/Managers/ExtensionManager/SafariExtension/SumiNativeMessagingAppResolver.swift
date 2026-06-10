//
//  SumiNativeMessagingAppResolver.swift
//  Sumi
//
//  Legacy resolver surface — delegates to SumiCompanionAppResolver.
//

import Foundation

enum SumiNativeMessagingResolverBucket: String, Codable, Sendable {
    case containingAppOfImportedAppex
    case knownCompanionAlias
    case appGroupsMetadata
    case explicitApplicationIdentifier
    case noMatch
}

struct SumiNativeMessagingAppResolution: Sendable, Equatable {
    let hostBundleIdentifier: String
    let bucket: SumiNativeMessagingResolverBucket
}

enum SumiNativeMessagingAppResolver {
    static var knownCompanionAliasBundleIdentifiers: Set<String> {
        SumiCompanionAppIdentityMetadata.knownPublicHostBundleIdentifiers
    }

    static var hostApplicationIdentifierAliases: [String: String] {
        SumiCompanionAppIdentityMetadata.publicHostBundleIdentifierAliases
    }

    static func resolve(
        requestedApplicationIdentifier: String?,
        extensionId: String?,
        installedExtensions: [InstalledExtension],
        importStore: SafariExtensionImportStore
    ) -> SumiNativeMessagingAppResolution? {
        guard let identity = SumiCompanionAppResolver.resolveIdentity(
            requestedApplicationIdentifier: requestedApplicationIdentifier,
            extensionId: extensionId,
            installedExtensions: installedExtensions,
            importStore: importStore
        ) else {
            return nil
        }

        return SumiNativeMessagingAppResolution(
            hostBundleIdentifier: identity.resolvedBundleIdentifier,
            bucket: legacyBucket(for: identity.resolutionSource)
        )
    }

    static func normalizedHostBundleIdentifier(_ identifier: String) -> String {
        SumiCompanionAppIdentityMetadata.normalizedHostBundleIdentifier(identifier)
    }

    static func containingApplicationBundleIdentifier(forAppexPath path: String) -> String? {
        SumiCompanionAppResolver.containingApplicationBundleIdentifier(forAppexPath: path)
    }

    static func appexBundleIdentifier(at path: String) -> String? {
        SumiCompanionAppResolver.appexBundleIdentifier(at: path)
    }

    private static func legacyBucket(
        for source: SumiCompanionAppResolutionSource
    ) -> SumiNativeMessagingResolverBucket {
        switch source {
        case .containingAppOfImportedAppex:
            return .containingAppOfImportedAppex
        case .publicBundleIdentityAlias:
            return .knownCompanionAlias
        case .explicitApplicationIdentifier:
            return .explicitApplicationIdentifier
        case .appGroupsMetadata:
            return .appGroupsMetadata
        }
    }
}

// MARK: - Legacy resolver surface

enum SafariExtensionNativeMessagingResolver {
    static let hostApplicationIdentifierAliases = SumiNativeMessagingAppResolver
        .hostApplicationIdentifierAliases

    static func resolveHostApplicationBundleIdentifier(
        requestedApplicationIdentifier: String?,
        extensionId: String?,
        installedExtensions: [InstalledExtension],
        importStore: SafariExtensionImportStore
    ) -> String? {
        SumiNativeMessagingAppResolver.resolve(
            requestedApplicationIdentifier: requestedApplicationIdentifier,
            extensionId: extensionId,
            installedExtensions: installedExtensions,
            importStore: importStore
        )?.hostBundleIdentifier
    }

    static func normalizedHostBundleIdentifier(_ identifier: String) -> String {
        SumiNativeMessagingAppResolver.normalizedHostBundleIdentifier(identifier)
    }

    static func containingApplicationBundleIdentifier(forAppexPath path: String) -> String? {
        SumiNativeMessagingAppResolver.containingApplicationBundleIdentifier(forAppexPath: path)
    }

    static func appexBundleIdentifier(at path: String) -> String? {
        SumiNativeMessagingAppResolver.appexBundleIdentifier(at: path)
    }
}
