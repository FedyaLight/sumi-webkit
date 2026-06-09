//
//  SumiNativeMessagingAppResolver.swift
//  Sumi
//
//  Resolves companion host `.app` bundle identifiers for Safari native messaging.
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
    /// Stable public companion-app bundle IDs (no extension-specific runtime hacks).
    static let knownCompanionAliasBundleIdentifiers: Set<String> = [
        "com.bitwarden.desktop",
        "com.1password.safari",
        "me.proton.pass.catalyst",
        "io.raindrop.safari",
    ]

    /// Extension-requested identifiers that differ from the containing `.app` bundle ID.
    static let hostApplicationIdentifierAliases: [String: String] = [
        "com.8bit.bitwarden": "com.bitwarden.desktop",
        "me.proton.pass.nm": "me.proton.pass.catalyst",
    ]

    static func resolve(
        requestedApplicationIdentifier: String?,
        extensionId: String?,
        installedExtensions: [InstalledExtension],
        importStore: SafariExtensionImportStore
    ) -> SumiNativeMessagingAppResolution? {
        let trimmedRequest = requestedApplicationIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let trimmedRequest, trimmedRequest.isEmpty == false {
            let normalized = normalizedHostBundleIdentifier(trimmedRequest)
            let bucket: SumiNativeMessagingResolverBucket =
                hostApplicationIdentifierAliases[trimmedRequest] != nil
                ? .knownCompanionAlias
                : .explicitApplicationIdentifier
            return SumiNativeMessagingAppResolution(
                hostBundleIdentifier: normalized,
                bucket: bucket
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
            return SumiNativeMessagingAppResolution(
                hostBundleIdentifier: containing,
                bucket: .containingAppOfImportedAppex
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
            return SumiNativeMessagingAppResolution(
                hostBundleIdentifier: containing,
                bucket: .containingAppOfImportedAppex
            )
        }

        if let metadataHost = resolveFromAppGroupsMetadata(
            appexPath: installed.sourceBundlePath
        ) {
            return metadataHost
        }

        return nil
    }

    static func normalizedHostBundleIdentifier(_ identifier: String) -> String {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return hostApplicationIdentifierAliases[trimmed] ?? trimmed
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

    private static func resolveFromAppGroupsMetadata(
        appexPath: String
    ) -> SumiNativeMessagingAppResolution? {
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

        return SumiNativeMessagingAppResolution(
            hostBundleIdentifier: bundleID,
            bucket: .appGroupsMetadata
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
