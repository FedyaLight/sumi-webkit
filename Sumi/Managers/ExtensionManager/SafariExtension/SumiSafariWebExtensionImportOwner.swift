import Foundation

/// Owns Safari Web Extension discovery sync, install-from-candidate, and import-store access.
@MainActor
final class SumiSafariWebExtensionImportOwner {
    typealias RuntimeProvider = @MainActor () -> ExtensionSettingsCatalogBinding?

    private let importStore: any SafariExtensionImportStoring & SafariExtensionImportRecordProviding
    private let runtimeIfEnabled: RuntimeProvider

    init(
        importStore: any SafariExtensionImportStoring & SafariExtensionImportRecordProviding,
        runtimeIfEnabled: @escaping RuntimeProvider
    ) {
        self.importStore = importStore
        self.runtimeIfEnabled = runtimeIfEnabled
    }

    func recordsForDiagnostics() -> any SafariExtensionImportRecordProviding {
        importStore
    }

    func removeImportedRecord(forInstalledExtensionId extensionId: String) {
        importStore.removeImportedRecord(forInstalledExtensionId: extensionId)
    }

    func refreshDiscoveredCandidates(
        _ candidates: [DiscoveredSafariExtensionCandidate]
    ) {
        importStore.refreshDiscoveredCandidates(
            candidates.filter { $0.bundleKind == .webExtension }
        )
    }

    func addAppExtension(
        from candidate: DiscoveredSafariExtensionCandidate
    ) async throws -> InstalledExtension {
        try await install(from: candidate, enableOnInstall: false)
    }

    func install(
        from candidate: DiscoveredSafariExtensionCandidate,
        enableOnInstall: Bool
    ) async throws -> InstalledExtension {
        guard candidate.bundleKind == .webExtension else {
            throw ExtensionError.installationFailed(
                "Only Safari Web Extensions can be enabled in the WebExtension runtime."
            )
        }
        guard let runtime = runtimeIfEnabled() else {
            throw ExtensionError.unsupportedOS
        }

        let installed = try await runtime.install(
            from: candidate.appexURL,
            enableOnInstall: enableOnInstall
        )
        importStore.markImported(
            candidate: candidate,
            installedExtensionId: installed.id
        )
        return installed
    }
}
