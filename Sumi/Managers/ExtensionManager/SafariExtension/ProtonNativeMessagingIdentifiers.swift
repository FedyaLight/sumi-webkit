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
    static let desktopHostBundleIdentifier = "me.proton.pass.electron"
    static let nativeHostManifestName = requestedApplicationIdentifier + ".json"
    static let nativeHostExecutableName = "proton_pass_nm_host"

    static let registryHostBundleKeys: [String] = [
        safariHostBundleIdentifier,
    ]

    static let standardNativeHostMapping = StandardNativeMessagingHostMapping(
        nativeHostName: requestedApplicationIdentifier,
        displayName: "Proton Pass",
        requestedApplicationIdentifiers: [
            requestedApplicationIdentifier,
            safariHostBundleIdentifier,
        ],
        registryHostBundleIdentifiers: registryHostBundleKeys,
        appBundleIdentifiers: [
            desktopHostBundleIdentifier,
            safariHostBundleIdentifier,
        ],
        manifestFileName: nativeHostManifestName,
        embeddedHostExecutableRelativePaths: [
            "Contents/Resources/assets/\(nativeHostExecutableName)",
            "Contents/Resources/app.asar.unpacked/assets/\(nativeHostExecutableName)",
        ],
        explicitApplicationBundleURLs: [
            URL(fileURLWithPath: "/Applications/Proton Pass.app"),
            URL(fileURLWithPath: "/Applications/Proton Pass for Safari.app"),
        ]
    )

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

enum StandardNativeMessagingHostCompatibilityRecords {
    static let protonPass = ProtonNativeMessagingIdentifiers.standardNativeHostMapping

    static let all: [StandardNativeMessagingHostMapping] = [
        protonPass,
    ]

    static let registryHostBundleKeys: [String] = all.flatMap(\.registryHostBundleIdentifiers)
}
