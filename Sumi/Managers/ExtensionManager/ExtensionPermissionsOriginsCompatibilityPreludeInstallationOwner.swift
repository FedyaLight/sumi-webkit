import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
protocol ExtensionPreludeInstalling: AnyObject {
    func installPreludes(
        into userContentController: WKUserContentController,
        profileId: UUID
    )
}

@available(macOS 15.5, *)
@MainActor
final class ExtensionPermissionsOriginsCompatibilityPreludeInstallationOwner:
    ExtensionPreludeInstalling {
    struct PreludeTarget {
        let extensionId: String
        let isLoaded: Bool
        let baseURL: URL
        let installPrelude: @MainActor (WKUserContentController) -> Bool
    }

    private let isPrivateUserScriptSPIAvailable: @MainActor () -> Bool
    private let preludeTargets: @MainActor (UUID) -> [PreludeTarget]
    private let trace: @MainActor (String) -> Void
    private var installationKeysByControllerIdentifier:
        [ObjectIdentifier: Set<String>] = [:]

    init(
        isPrivateUserScriptSPIAvailable: @escaping @MainActor () -> Bool,
        preludeTargets: @escaping @MainActor (UUID) -> [PreludeTarget],
        trace: @escaping @MainActor (String) -> Void
    ) {
        self.isPrivateUserScriptSPIAvailable = isPrivateUserScriptSPIAvailable
        self.preludeTargets = preludeTargets
        self.trace = trace
    }

    func installPreludes(
        into userContentController: WKUserContentController,
        profileId: UUID
    ) {
        guard isPrivateUserScriptSPIAvailable() else {
            RuntimeDiagnostics.debug(
                "Permissions origins compatibility SPI unavailable",
                category: "Extensions"
            )
            return
        }

        let controllerIdentifier = ObjectIdentifier(userContentController)
        var installedKeys =
            installationKeysByControllerIdentifier[controllerIdentifier] ?? []

        for target in preludeTargets(profileId) where target.isLoaded {
            let installKey = Self.installationKey(
                profileId: profileId,
                extensionId: target.extensionId,
                baseURL: target.baseURL
            )
            guard installedKeys.contains(installKey) == false else {
                continue
            }

            if target.installPrelude(userContentController) {
                installedKeys.insert(installKey)
                trace(
                    "permissionsOriginsCompatibility installed extensionId=\(target.extensionId) profileId=\(profileId.uuidString)"
                )
            }
        }

        if installedKeys.isEmpty {
            installationKeysByControllerIdentifier.removeValue(
                forKey: controllerIdentifier
            )
        } else {
            installationKeysByControllerIdentifier[controllerIdentifier] = installedKeys
        }
    }

    func clearInstallations() {
        installationKeysByControllerIdentifier.removeAll()
    }

    private static func installationKey(
        profileId: UUID,
        extensionId: String,
        baseURL: URL
    ) -> String {
        [
            SafariExtensionPermissionsOriginsCompatibility.installationSourceIdentifier,
            profileId.uuidString,
            extensionId,
            baseURL.absoluteString,
        ].joined(separator: ":")
    }
}
