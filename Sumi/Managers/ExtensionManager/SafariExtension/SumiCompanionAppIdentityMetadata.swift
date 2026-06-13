//
//  SumiCompanionAppIdentityMetadata.swift
//  Sumi
//
//  Public bundle identifier mappings for companion-app identity resolution.
//  Metadata only — never used for extension-specific runtime behavior branches.
//

import Foundation

enum SumiCompanionAppIdentityMetadata {
    /// Extension-requested identifiers that differ from the containing `.app` bundle ID.
    static var publicHostBundleIdentifierAliases: [String: String] {
        var aliases = [
            "com.8bit.bitwarden": "com.bitwarden.desktop",
            "com.8bit.bitwarden.desktop": "com.bitwarden.desktop",
        ]

        for mapping in StandardNativeMessagingHostCompatibilityRecords.all {
            guard let resolvedIdentifier = mapping.registryHostBundleIdentifiers.first else {
                continue
            }
            for requestedIdentifier in mapping.requestedApplicationIdentifiers
            where requestedIdentifier != resolvedIdentifier {
                aliases[requestedIdentifier] = resolvedIdentifier
            }
        }

        return aliases
    }

    /// Stable public host bundle identifiers (diagnostics / resolution tables only).
    static var knownPublicHostBundleIdentifiers: Set<String> {
        Set([
            "com.bitwarden.desktop",
            "com.1password.safari",
            "io.raindrop.safari",
        ]).union(StandardNativeMessagingHostCompatibilityRecords.registryHostBundleKeys)
    }

    static func normalizedHostBundleIdentifier(_ identifier: String) -> String {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return publicHostBundleIdentifierAliases[trimmed] ?? trimmed
    }

    /// Whether `bundleIdentifier` appears in the public identity metadata tables.
    static func isRecognizedPublicIdentity(_ bundleIdentifier: String) -> Bool {
        let normalized = normalizedHostBundleIdentifier(bundleIdentifier)
        if knownPublicHostBundleIdentifiers.contains(normalized) {
            return true
        }
        if publicHostBundleIdentifierAliases.keys.contains(bundleIdentifier) {
            return true
        }
        return publicHostBundleIdentifierAliases.values.contains(normalized)
    }
}
