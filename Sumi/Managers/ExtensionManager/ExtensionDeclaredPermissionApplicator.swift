import Foundation
import WebKit

/// Applies required manifest permissions while a new, unpublished extension
/// context is being prepared. Optional and site permissions are handled by
/// their own policies.
@available(macOS 15.5, *)
@MainActor
struct ExtensionDeclaredPermissionApplicator {
    func apply(
        to context: WKWebExtensionContext,
        webExtension: WKWebExtension,
        extensionID: String,
        profileID: UUID,
        manifest: [String: Any]
    ) {
        var permissions = webExtension.requestedPermissions
        permissions.formUnion(requiredPermissions(from: manifest))

        for permission in permissions {
            context.setPermissionStatus(.grantedExplicitly, for: permission)
        }

        guard WebExtensionRuntimeCompatibilityPolicy
            .declaresNativeMessaging(manifest)
        else {
            return
        }
        SafariExtensionNativeMessagingPermissionDiagnostics.logGrant(
            extensionId: extensionID,
            profileId: profileID,
            manifestDeclaresNativeMessaging: true,
            permissionGranted: ExtensionPermissionStatusResolver.isGranted(
                context.permissionStatus(for: .nativeMessaging)
            )
        )
    }

    private func requiredPermissions(
        from manifest: [String: Any]
    ) -> Set<WKWebExtension.Permission> {
        Set(
            (manifest["permissions"] as? [String] ?? [])
                .filter(Self.isPermissionName)
                .map(WKWebExtension.Permission.init(rawValue:))
        )
    }

    private static func isPermissionName(_ value: String) -> Bool {
        do {
            _ = try WKWebExtension.MatchPattern(string: value)
            return false
        } catch {
            return true
        }
    }
}
