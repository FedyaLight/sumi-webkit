import Foundation

/// Exact product capability for settings/import flows. Persistence, lifecycle,
/// and installer services remain private so callers cannot reorder one
/// transaction by pulling its internal authorities apart.
@available(macOS 15.5, *)
@MainActor
final class ExtensionSettingsCatalogBinding {
    private let installed: InstalledExtensionCollection
    private let lifecycle: InstalledExtensionLifecycleService
    private let installer: ExtensionInstallationService

    init(
        installed: InstalledExtensionCollection,
        lifecycle: InstalledExtensionLifecycleService,
        installer: ExtensionInstallationService
    ) {
        self.installed = installed
        self.lifecycle = lifecycle
        self.installer = installer
    }

    var installedExtensions: [InstalledExtension] { installed.records }

    func enable(_ extensionID: String) async throws -> InstalledExtension {
        try await lifecycle.enable(extensionID)
    }

    func disable(_ extensionID: String) async throws {
        try await lifecycle.disable(extensionID)
    }

    func uninstall(_ extensionID: String) async throws {
        try await lifecycle.uninstall(extensionID)
    }

    func install(
        from sourceURL: URL,
        enableOnInstall: Bool
    ) async throws -> InstalledExtension {
        try await installer.install(
            from: sourceURL,
            enableOnInstall: enableOnInstall
        )
    }
}
