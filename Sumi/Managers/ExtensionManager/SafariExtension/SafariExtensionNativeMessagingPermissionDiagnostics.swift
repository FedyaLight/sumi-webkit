//
//  SafariExtensionNativeMessagingPermissionDiagnostics.swift
//  Sumi
//
//  Sanitized native-messaging permission diagnostics.
//

import Foundation

@MainActor
enum SafariExtensionNativeMessagingPermissionDiagnostics {
    static func logGrant(
        extensionId: String?,
        profileId: UUID?,
        manifestDeclaresNativeMessaging: Bool,
        permissionGranted: Bool
    ) {
        log(
            phase: "grant",
            extensionId: extensionId,
            profileId: profileId,
            manifestDeclaresNativeMessaging: manifestDeclaresNativeMessaging,
            permissionGranted: permissionGranted,
            unsupportedAPIsContainNativeMessaging: nil
        )
    }

    static func logContextState(
        extensionId: String?,
        profileId: UUID?,
        manifestDeclaresNativeMessaging: Bool,
        permissionGranted: Bool,
        unsupportedAPIsContainNativeMessaging: Bool
    ) {
        log(
            phase: "context",
            extensionId: extensionId,
            profileId: profileId,
            manifestDeclaresNativeMessaging: manifestDeclaresNativeMessaging,
            permissionGranted: permissionGranted,
            unsupportedAPIsContainNativeMessaging: unsupportedAPIsContainNativeMessaging
        )
    }

    private static func log(
        phase: String,
        extensionId: String?,
        profileId: UUID?,
        manifestDeclaresNativeMessaging: Bool,
        permissionGranted: Bool,
        unsupportedAPIsContainNativeMessaging: Bool?
    ) {
        #if DEBUG || SUMI_DIAGNOSTICS
            guard RuntimeDiagnostics.isVerboseEnabled else { return }
            RuntimeDiagnostics.debug(category: "SafariNativeMessagingPermissions") {
                """
                phase=\(phase) \
                extBucket=\(SafariExtensionNativeMessagingRoutingProbe.extensionIdBucket(extensionId)) \
                profile=\(SafariExtensionNativeMessagingRoutingProbe.profileIdBucket(profileId)) \
                manifestNativeMessaging=\(manifestDeclaresNativeMessaging) \
                permissionGranted=\(permissionGranted) \
                unsupportedNativeMessaging=\(unsupportedAPIsContainNativeMessaging.map(String.init) ?? "-")
                """
            }
        #else
            _ = (
                phase,
                extensionId,
                profileId,
                manifestDeclaresNativeMessaging,
                permissionGranted,
                unsupportedAPIsContainNativeMessaging
            )
        #endif
    }
}
