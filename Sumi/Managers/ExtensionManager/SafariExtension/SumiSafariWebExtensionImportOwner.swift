import Foundation

/// Owns Safari Web Extension discovery sync, install-from-candidate, and import-store access.
@MainActor
final class SumiSafariWebExtensionImportOwner {
    typealias ManagerProvider = @MainActor () -> ExtensionManager?

    private let importStore: any SafariExtensionImportStoring & SafariExtensionImportRecordProviding
    private let managerIfEnabled: ManagerProvider

    init(
        importStore: any SafariExtensionImportStoring & SafariExtensionImportRecordProviding,
        managerIfEnabled: @escaping ManagerProvider
    ) {
        self.importStore = importStore
        self.managerIfEnabled = managerIfEnabled
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

    func syncDiscoveredWebExtensions(
        _ candidates: [DiscoveredSafariExtensionCandidate]
    ) async -> SafariWebExtensionSyncResult {
        refreshDiscoveredCandidates(candidates)

        guard let manager = managerIfEnabled() else {
            return SafariWebExtensionSyncResult(
                addedExtensions: [],
                failedMessages: [ExtensionError.unsupportedOS.localizedDescription],
                skippedUnreadableCount: 0
            )
        }

        var installedSourcePaths = Set(
            manager.installedExtensions.map {
                Self.standardizedFilePath($0.sourceBundlePath)
            }
        )
        let installedExtensionIDs = Set(manager.installedExtensions.map(\.id))
        let installedImportedBundleIDs = Set(
            importStore.importedRecords()
                .filter { installedExtensionIDs.contains($0.installedExtensionId) }
                .map(\.extensionBundleIdentifier)
        )
        var knownSafariBundleIDs = installedExtensionIDs.union(installedImportedBundleIDs)

        var addedExtensions: [InstalledExtension] = []
        var failedMessages: [String] = []
        var skippedUnreadableCount = 0

        for candidate in candidates where candidate.bundleKind == .webExtension {
            guard candidate.isReadable else {
                skippedUnreadableCount += 1
                continue
            }

            let sourcePath = Self.standardizedFilePath(candidate.appexURL.path)
            guard installedSourcePaths.contains(sourcePath) == false,
                  knownSafariBundleIDs.contains(candidate.extensionBundleIdentifier) == false
            else {
                continue
            }

            do {
                let installed = try await install(
                    from: candidate,
                    enableOnInstall: false
                )
                addedExtensions.append(installed)
                installedSourcePaths.insert(Self.standardizedFilePath(installed.sourceBundlePath))
                knownSafariBundleIDs.insert(installed.id)
                knownSafariBundleIDs.insert(candidate.extensionBundleIdentifier)
            } catch {
                failedMessages.append("\(candidate.displayName): \(error.localizedDescription)")
            }
        }

        return SafariWebExtensionSyncResult(
            addedExtensions: addedExtensions,
            failedMessages: failedMessages,
            skippedUnreadableCount: skippedUnreadableCount
        )
    }

    func enableAppExtension(
        from candidate: DiscoveredSafariExtensionCandidate
    ) async throws -> InstalledExtension {
        try await install(from: candidate, enableOnInstall: true)
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
        guard let manager = managerIfEnabled() else {
            throw ExtensionError.unsupportedOS
        }

        let installed = try await manager.installationFlowOwner.performInstallation(
            from: candidate.appexURL,
            enableOnInstall: enableOnInstall
        )
        importStore.markImported(
            candidate: candidate,
            installedExtensionId: installed.id
        )
        return installed
    }

    private static func standardizedFilePath(_ path: String) -> String {
        URL(fileURLWithPath: path, isDirectory: true)
            .standardizedFileURL
            .path
    }
}
