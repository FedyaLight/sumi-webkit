//
//  ProtonNativeMessagingIdentifiers.swift
//  Sumi
//
//  Proton Pass native messaging identity constants and compatibility metadata.
//

import Foundation
import Security

enum ProtonNativeMessagingIdentifiers {
    static let requestedApplicationIdentifier = "me.proton.pass.nm"
    static let safariHostBundleIdentifier = "me.proton.pass.catalyst"
    static let safariExtensionBundleIdentifier = "me.proton.pass.catalyst.safari-extension"
    static let signingTeamIdentifier = "2SB5Z68H26"
    static let safariExtensionApplicationIdentifier =
        "\(signingTeamIdentifier).\(safariExtensionBundleIdentifier)"

    static func isSafariExtensionIdentity(sourceBundlePath: String) -> Bool {
        if SumiCompanionAppResolver.appexBundleIdentifier(at: sourceBundlePath)
            == safariExtensionBundleIdentifier
        {
            return true
        }
        return SumiCompanionAppResolver.containingApplicationBundleIdentifier(
            forAppexPath: sourceBundlePath
        ) == safariHostBundleIdentifier
    }

    static func isTrustedSafariExtensionIdentity(sourceBundlePath: String) -> Bool {
        guard isSafariExtensionIdentity(sourceBundlePath: sourceBundlePath) else {
            return false
        }

        let appexURL = URL(fileURLWithPath: sourceBundlePath, isDirectory: true)
            .standardizedFileURL
        return satisfiesSigningRequirement(
            bundleURL: appexURL,
            requirementText: safariExtensionSigningRequirement
        )
    }

    private static var safariExtensionSigningRequirement: String {
        """
        anchor apple generic \
        and identifier "\(safariExtensionBundleIdentifier)" \
        and entitlement["com.apple.developer.team-identifier"] = "\(signingTeamIdentifier)" \
        and entitlement["application-identifier"] = "\(safariExtensionApplicationIdentifier)" \
        and entitlement["com.apple.application-identifier"] = "\(safariExtensionApplicationIdentifier)" \
        and (certificate leaf[field.1.2.840.113635.100.6.1.9] exists \
        or certificate 1[field.1.2.840.113635.100.6.2.6] exists \
        and certificate leaf[field.1.2.840.113635.100.6.1.13] exists \
        and certificate leaf[subject.OU] = "\(signingTeamIdentifier)")
        """
    }

    private static func satisfiesSigningRequirement(
        bundleURL: URL,
        requirementText: String
    ) -> Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(
            bundleURL as CFURL,
            SecCSFlags(),
            &staticCode
        ) == errSecSuccess,
            let staticCode
        else {
            return false
        }

        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(
            requirementText as CFString,
            SecCSFlags(),
            &requirement
        ) == errSecSuccess,
            let requirement
        else {
            return false
        }

        return SecStaticCodeCheckValidity(staticCode, SecCSFlags(), requirement)
            == errSecSuccess
    }
}
