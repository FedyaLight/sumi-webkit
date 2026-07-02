import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionPermissionsOriginsCompatibilityPreludeInstallationOwner {
    struct PreludeTarget {
        let extensionId: String
        let isLoaded: Bool
        let baseURL: URL
        let installPrelude: @MainActor (WKUserContentController) -> Bool
    }

    struct Dependencies {
        let isPrivateUserScriptSPIAvailable: @MainActor () -> Bool
        let preludeTargets: @MainActor (UUID) -> [PreludeTarget]
        let trace: @MainActor (String) -> Void
    }

    private var installationKeysByControllerIdentifier:
        [ObjectIdentifier: Set<String>] = [:]
    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func installPreludes(
        into userContentController: WKUserContentController,
        profileId: UUID
    ) {
        guard dependencies.isPrivateUserScriptSPIAvailable() else {
            RuntimeDiagnostics.debug(
                "Permissions origins compatibility SPI unavailable",
                category: "Extensions"
            )
            return
        }

        let controllerIdentifier = ObjectIdentifier(userContentController)
        var installedKeys =
            installationKeysByControllerIdentifier[controllerIdentifier] ?? []

        for target in dependencies.preludeTargets(profileId) where target.isLoaded {
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
                dependencies.trace(
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

@available(macOS 15.5, *)
extension ExtensionPermissionsOriginsCompatibilityPreludeInstallationOwner.Dependencies {
    @MainActor
    static func live(manager: ExtensionManager) -> Self {
        Self(
            isPrivateUserScriptSPIAvailable: {
                SafariExtensionPermissionsOriginsCompatibility
                    .isPrivateUserScriptSPIAvailable
            },
            preludeTargets: { [weak manager] profileId in
                guard let manager else { return [] }
                return manager.extensionContexts(for: profileId)
                    .map { extensionId, extensionContext in
                        ExtensionPermissionsOriginsCompatibilityPreludeInstallationOwner
                            .PreludeTarget(
                                extensionId: extensionId,
                                isLoaded: extensionContext.isLoaded,
                                baseURL: extensionContext.baseURL,
                                installPrelude: { userContentController in
                                    SafariExtensionPermissionsOriginsCompatibility
                                        .installPrelude(
                                            into: userContentController,
                                            extensionContext: extensionContext
                                        )
                                }
                            )
                    }
            },
            trace: { [weak manager] message in
                manager?.extensionRuntimeTrace(message)
            }
        )
    }
}

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    func installPermissionsOriginsCompatibilityPreludes(
        into userContentController: WKUserContentController,
        profileId: UUID
    ) {
        permissionsOriginsCompatibilityPreludeInstallationOwner.installPreludes(
            into: userContentController,
            profileId: profileId
        )
    }

    func clearPermissionsOriginsCompatibilityInstallations() {
        permissionsOriginsCompatibilityPreludeInstallationOwner.clearInstallations()
    }
}
