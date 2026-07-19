import Foundation

enum UserscriptsNativeMessagingIdentifiers {
    static let applicationIdentifier = "app"
    static let containingAppBundleIdentifier = "com.userscripts.macos"
    static let extensionBundleIdentifier = "com.userscripts.macos.Userscripts-Extension"
    static let protocolIdentifier = "userscripts-safari-native"

    static func isUserscriptsExtension(
        extensionId: String?,
        installedExtensions: [InstalledExtension]
    ) -> Bool {
        guard let extensionId,
              let installed = installedExtensions.first(where: { $0.id == extensionId }),
              isUserscriptsExtension(installed)
        else {
            return false
        }

        return true
    }

    static func isUserscriptsExtension(_ installed: InstalledExtension) -> Bool {
        guard installed.sourceKind == .safariAppExtension else { return false }

        if SumiCompanionAppResolver.appexBundleIdentifier(at: installed.sourceBundlePath)
            == extensionBundleIdentifier {
            return true
        }

        return SumiCompanionAppResolver.containingApplicationBundleIdentifier(
            forAppexPath: installed.sourceBundlePath
        ) == containingAppBundleIdentifier
    }
}
