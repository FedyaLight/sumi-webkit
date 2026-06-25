//
//  ProtonNativeMessagingIdentifiers.swift
//  Sumi
//
//  Proton Pass native messaging identity constants and compatibility metadata.
//

import Foundation

enum ProtonNativeMessagingIdentifiers {
    static let requestedApplicationIdentifier = "me.proton.pass.nm"
    static let safariHostBundleIdentifier = "me.proton.pass.catalyst"
    static let safariExtensionBundleIdentifier = "me.proton.pass.catalyst.safari-extension"

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
}
