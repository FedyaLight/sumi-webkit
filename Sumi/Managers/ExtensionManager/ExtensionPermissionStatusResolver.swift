import Foundation
import WebKit

/// Resolves context-wide and tab-scoped WebKit permission state without
/// mutating the extension context.
@available(macOS 15.5, *)
@MainActor
enum ExtensionPermissionStatusResolver {
    static func isGranted(
        _ status: WKWebExtensionContext.PermissionStatus
    ) -> Bool {
        status == .grantedExplicitly || status == .grantedImplicitly
    }

    static func effectiveStatus(
        for permission: WKWebExtension.Permission,
        in context: WKWebExtensionContext,
        tab: (any WKWebExtensionTab)?
    ) -> WKWebExtensionContext.PermissionStatus {
        guard let tab else { return context.permissionStatus(for: permission) }
        return context.permissionStatus(for: permission, in: tab)
    }

    static func effectiveStatus(
        for matchPattern: WKWebExtension.MatchPattern,
        in context: WKWebExtensionContext,
        tab: (any WKWebExtensionTab)?
    ) -> WKWebExtensionContext.PermissionStatus {
        guard let tab else { return context.permissionStatus(for: matchPattern) }
        return context.permissionStatus(for: matchPattern, in: tab)
    }

    static func effectiveStatus(
        for url: URL,
        in context: WKWebExtensionContext,
        tab: (any WKWebExtensionTab)?
    ) -> WKWebExtensionContext.PermissionStatus {
        guard let tab else { return context.permissionStatus(for: url) }
        return context.permissionStatus(for: url, in: tab)
    }

}
