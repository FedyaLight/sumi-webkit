//
//  SafariWebExtensionRuntimeIdentity.swift
//  Sumi
//
//  Computes the Safari-style web extension runtime identifier used by
//  `browser.runtime.id` and `externally_connectable` message routing.
//
//  Safari exposes an app extension to web pages and to itself as
//  "<appexBundleIdentifier> (<teamIdentifier>)" (e.g.
//  "me.proton.pass.catalyst.safari-extension (2SB5Z68H26)"). Web apps such as
//  account.proton.me hardcode this composed identifier when calling
//  `browser.runtime.sendMessage(extensionId, …)`, so WebKit's
//  `WKWebExtensionContext.uniqueIdentifier` must match it for the message to be
//  delivered. This helper derives the composed identifier generically from the
//  imported `.appex` bundle and its code signature, without any per-vendor
//  branching.
//

import Foundation
import Security

enum SafariWebExtensionRuntimeIdentity {
    /// Composed identifiers cached by standardized appex path — code-signature
    /// reads are not free and callers resolve identity on hot lifecycle paths.
    @MainActor
    private static var cachedComposedIdentifiersByPath: [String: String?] = [:]

    /// The identifier WebKit uses for the context and its on-disk storage
    /// directory: the composed Safari identifier for `.appex` imports, the
    /// internal extension id for everything else. Cached per bundle path.
    @MainActor
    static func webKitStorageIdentifier(
        extensionId: String,
        sourceKind: WebExtensionSourceKind,
        sourceBundlePath: String?
    ) -> String {
        guard sourceKind == .safariAppExtension, let sourceBundlePath else {
            return extensionId
        }
        let cacheKey = URL(fileURLWithPath: sourceBundlePath, isDirectory: true)
            .standardizedFileURL.path
        if let cached = cachedComposedIdentifiersByPath[cacheKey] {
            return cached ?? extensionId
        }
        let composed = composedIdentifier(
            sourceKind: sourceKind,
            sourceBundlePath: sourceBundlePath
        )
        cachedComposedIdentifiersByPath[cacheKey] = composed
        return composed ?? extensionId
    }

    /// Returns the Safari-style composed runtime identifier for an imported
    /// Safari app extension, or `nil` when the source is not a Safari app
    /// extension or the bundle identity / team identifier cannot be resolved.
    static func composedIdentifier(
        sourceKind: WebExtensionSourceKind,
        sourceBundlePath: String
    ) -> String? {
        guard sourceKind == .safariAppExtension else { return nil }
        let appexURL = SafariAppExtensionResources.installedAppexBundleURL(
            sourceKind: sourceKind,
            sourceBundlePath: sourceBundlePath
        ) ?? URL(fileURLWithPath: sourceBundlePath, isDirectory: true)

        guard let bundleIdentifier = Bundle(url: appexURL)?.bundleIdentifier,
              bundleIdentifier.isEmpty == false,
              let teamIdentifier = teamIdentifier(forBundleAt: appexURL),
              teamIdentifier.isEmpty == false
        else {
            return nil
        }
        return composedIdentifier(
            bundleIdentifier: bundleIdentifier,
            teamIdentifier: teamIdentifier
        )
    }

    static func composedIdentifier(
        bundleIdentifier: String,
        teamIdentifier: String
    ) -> String {
        "\(bundleIdentifier) (\(teamIdentifier))"
    }

    /// Reads the code-signing team identifier from a signed bundle.
    static func teamIdentifier(forBundleAt bundleURL: URL) -> String? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(
            bundleURL as CFURL,
            SecCSFlags(),
            &staticCode
        ) == errSecSuccess,
            let staticCode
        else {
            return nil
        }

        var informationCF: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &informationCF
        ) == errSecSuccess,
            let information = informationCF as? [String: Any]
        else {
            return nil
        }

        return information[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
