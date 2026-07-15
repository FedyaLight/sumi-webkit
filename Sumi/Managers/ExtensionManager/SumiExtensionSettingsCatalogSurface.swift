import Foundation

struct SafariWebExtensionSyncResult {
    let addedExtensions: [InstalledExtension]
    let failedMessages: [String]
    let skippedUnreadableCount: Int
}

@MainActor
final class SumiExtensionSettingsCatalogSurface {
    private let lifetime: SumiExtensionManagerLifetime
    private let safariImport: SumiSafariWebExtensionImportOwner

    init(
        lifetime: SumiExtensionManagerLifetime,
        importStore: any SafariExtensionImportStoring & SafariExtensionImportRecordProviding
    ) {
        self.lifetime = lifetime
        safariImport = SumiSafariWebExtensionImportOwner(
            importStore: importStore,
            runtimeIfEnabled: { [weak lifetime] in
                lifetime?.settingsCatalogIfEnabled()
            }
        )
    }

    var surfaceStore: BrowserExtensionSurfaceStore { lifetime.surfaceStore }

    func runtimeIsAvailable() -> Bool {
        lifetime.settingsCatalogIfEnabled() != nil
    }

    func installedExtensionsIfLoaded() -> [InstalledExtension] {
        lifetime.loadedSettingsCatalogIfEnabled()?.installedExtensions ?? []
    }

    func enableExtension(_ extensionID: String) async throws -> InstalledExtension {
        guard let runtime = lifetime.settingsCatalogIfEnabled() else {
            throw ExtensionError.unsupportedOS
        }
        return try await runtime.enable(extensionID)
    }

    func disableExtension(_ extensionID: String) async throws {
        guard let runtime = lifetime.settingsCatalogIfEnabled() else { return }
        try await runtime.disable(extensionID)
    }

    func uninstallExtension(_ extensionID: String) async throws {
        guard let runtime = lifetime.settingsCatalogIfEnabled() else { return }
        safariImport.removeImportedRecord(forInstalledExtensionId: extensionID)
        try await runtime.uninstall(extensionID)
    }

    func enableSafariAppExtension(from candidate: DiscoveredSafariExtensionCandidate) async throws -> InstalledExtension {
        try await safariImport.enableAppExtension(from: candidate)
    }

    func syncDiscoveredSafariWebExtensions(_ candidates: [DiscoveredSafariExtensionCandidate]) async -> SafariWebExtensionSyncResult {
        await safariImport.syncDiscoveredWebExtensions(candidates)
    }

    func refreshDiscoveredSafariWebExtensionCandidates(_ candidates: [DiscoveredSafariExtensionCandidate]) {
        safariImport.refreshDiscoveredCandidates(candidates)
    }

    func importRecordsForDiagnostics() -> any SafariExtensionImportRecordProviding {
        safariImport.recordsForDiagnostics()
    }
}

@MainActor
extension SumiExtensionsModule {
    func extensionRuntimeIsAvailable() -> Bool {
        settingsCatalog.runtimeIsAvailable()
    }

    func installedExtensionsIfLoaded() -> [InstalledExtension] {
        settingsCatalog.installedExtensionsIfLoaded()
    }

    func enableExtension(_ extensionId: String) async throws -> InstalledExtension {
        let enabled = try await settingsCatalog.enableExtension(extensionId)
        _ = compatibilityDiagnostics.compatibilityReport()
        return enabled
    }

    func disableExtension(_ extensionId: String) async throws {
        try await settingsCatalog.disableExtension(extensionId)
    }

    func uninstallExtension(_ extensionId: String) async throws {
        try await settingsCatalog.uninstallExtension(extensionId)
    }

    func enableSafariAppExtension(
        from candidate: DiscoveredSafariExtensionCandidate
    ) async throws -> InstalledExtension {
        try await settingsCatalog.enableSafariAppExtension(from: candidate)
    }

    func syncDiscoveredSafariWebExtensions(
        _ candidates: [DiscoveredSafariExtensionCandidate]
    ) async -> SafariWebExtensionSyncResult {
        await settingsCatalog.syncDiscoveredSafariWebExtensions(candidates)
    }

    func refreshDiscoveredSafariWebExtensionCandidates(
        _ candidates: [DiscoveredSafariExtensionCandidate]
    ) {
        settingsCatalog.refreshDiscoveredSafariWebExtensionCandidates(candidates)
    }

    func safariExtensionImportRecordsForDiagnostics()
        -> any SafariExtensionImportRecordProviding {
        settingsCatalog.importRecordsForDiagnostics()
    }
}
