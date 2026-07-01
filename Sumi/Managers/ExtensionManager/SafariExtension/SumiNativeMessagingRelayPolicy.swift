//
//  SumiNativeMessagingRelayPolicy.swift
//  Sumi
//
//  Gate native messaging relay to enabled Safari imports only.
//

import Foundation

enum SumiNativeMessagingRelayPolicyDenial: String, Error, Sendable, Equatable {
    case moduleDisabled
    case extensionNotEnabled
    case extensionNotSafariImport
    case privateBrowsingDenied
    case arbitraryNativeMessagingDenied
}

struct SumiNativeMessagingRelayPolicyContext {
    let extensionsModuleEnabled: Bool
    let extensionId: String
    let installedExtension: InstalledExtension?
    let isPrivateBrowsing: Bool
    let privateAccessAllowed: Bool?
    let requestedApplicationIdentifier: String?

    init(
        extensionsModuleEnabled: Bool,
        extensionId: String,
        installedExtension: InstalledExtension?,
        isPrivateBrowsing: Bool,
        privateAccessAllowed: Bool? = nil,
        requestedApplicationIdentifier: String?
    ) {
        self.extensionsModuleEnabled = extensionsModuleEnabled
        self.extensionId = extensionId
        self.installedExtension = installedExtension
        self.isPrivateBrowsing = isPrivateBrowsing
        self.privateAccessAllowed = privateAccessAllowed
        self.requestedApplicationIdentifier = requestedApplicationIdentifier
    }
}

enum SumiNativeMessagingRelayPolicy {
    static func evaluate(
        _ context: SumiNativeMessagingRelayPolicyContext
    ) -> Result<Void, SumiNativeMessagingRelayPolicyDenial> {
        guard context.extensionsModuleEnabled else {
            return .failure(.moduleDisabled)
        }

        guard let installed = context.installedExtension else {
            return .failure(.extensionNotSafariImport)
        }

        guard installed.isEnabled else {
            return .failure(.extensionNotEnabled)
        }

        guard installed.sourceKind == .safariAppExtension else {
            return .failure(.extensionNotSafariImport)
        }

        if context.isPrivateBrowsing {
            guard installed.incognitoMode.allowsPrivateAccess,
                  context.privateAccessAllowed == true
            else {
                return .failure(.privateBrowsingDenied)
            }
        }

        if isUnauthorizedNativeMessagingRequest(
            requestedApplicationIdentifier: context.requestedApplicationIdentifier,
            installed: installed
        ) {
            return .failure(.arbitraryNativeMessagingDenied)
        }

        return .success(())
    }

    /// Reject open-ended native messaging to bundle IDs unrelated to the imported Safari extension.
    /// Public compatibility aliases are diagnostics metadata, not authorization input.
    private static func isUnauthorizedNativeMessagingRequest(
        requestedApplicationIdentifier: String?,
        installed: InstalledExtension
    ) -> Bool {
        guard let requested = requestedApplicationIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            requested.isEmpty == false
        else {
            return false
        }

        if SafariExtensionNativeMessagingRoutingProbe
            .isSafariContainingApplicationRequest(requested) {
            return false
        }

        if let containing = SumiNativeMessagingAppResolver.containingApplicationBundleIdentifier(
            forAppexPath: installed.sourceBundlePath
        ),
            requested == containing {
            return false
        }

        if let appexBundleID = SumiNativeMessagingAppResolver.appexBundleIdentifier(
            at: installed.sourceBundlePath
        ),
            requested == appexBundleID {
            return false
        }

        return true
    }
}
