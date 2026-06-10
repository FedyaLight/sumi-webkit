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
    static let publicHostBundleIdentifierAliases: [String: String] = [
        "com.8bit.bitwarden": "com.bitwarden.desktop",
        "me.proton.pass.nm": "me.proton.pass.catalyst",
    ]

    /// Stable public host bundle identifiers (diagnostics / resolution tables only).
    static let knownPublicHostBundleIdentifiers: Set<String> = [
        "com.bitwarden.desktop",
        "com.1password.safari",
        "me.proton.pass.catalyst",
        "io.raindrop.safari",
    ]

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
