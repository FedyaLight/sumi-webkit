import Foundation

@available(macOS 15.5, *)
@MainActor
final class ExtensionInstallationRetirementLifetimeOwner {
    private let metadataStore: ExtensionInstallationMetadataStore
    private let catalog: InstalledExtensionCatalog
    private let lifecycle: InstalledExtensionLifecycleService
    private let installer: ExtensionInstallationService
    private let runtimeRetirement: ExtensionRuntimeRetirement
    private let runtimeTermination: ExtensionRuntimeTermination
    private let storageCleanup: WebExtensionStorageCleanupOwner

    init(
        metadataStore: ExtensionInstallationMetadataStore,
        catalog: InstalledExtensionCatalog,
        lifecycle: InstalledExtensionLifecycleService,
        installer: ExtensionInstallationService,
        runtimeRetirement: ExtensionRuntimeRetirement,
        runtimeTermination: ExtensionRuntimeTermination,
        storageCleanup: WebExtensionStorageCleanupOwner
    ) {
        self.metadataStore = metadataStore
        self.catalog = catalog
        self.lifecycle = lifecycle
        self.installer = installer
        self.runtimeRetirement = runtimeRetirement
        self.runtimeTermination = runtimeTermination
        self.storageCleanup = storageCleanup
    }
}
