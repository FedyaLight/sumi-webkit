import Foundation

/// Owns the reversible filesystem part of installing a directory-backed extension.
/// Persistence and WebKit activation are deliberately outside this transaction.
@available(macOS 15.5, *)
@MainActor
final class ExtensionPackageInstallTransaction {
    let stagedPackageRoot: URL

    private let extensionsDirectory: URL
    private var installedPackageRoot: URL?
    private var replacedPackageBackup: URL?
    private var isCommitted = false

    init(extensionsDirectory: URL) {
        self.extensionsDirectory = extensionsDirectory
        self.stagedPackageRoot = extensionsDirectory.appendingPathComponent(
            "temp_\(UUID().uuidString)",
            isDirectory: true
        )
    }

    func stage(resourcesAt source: URL) throws {
        removeArtifactIfPresent(
            stagedPackageRoot,
            reason: "removing stale extension staging directory"
        )
        try FileManager.default.copyItem(at: source, to: stagedPackageRoot)
    }

    func installStagedPackage(extensionID: String) throws -> URL {
        let destination = try ExtensionUtils.extensionDirectory(
            forExtensionID: extensionID,
            under: extensionsDirectory
        )
        installedPackageRoot = destination

        if FileManager.default.fileExists(atPath: destination.path) {
            let backup = extensionsDirectory.appendingPathComponent(
                "backup_\(extensionID)_\(UUID().uuidString)",
                isDirectory: true
            )
            try FileManager.default.moveItem(at: destination, to: backup)
            replacedPackageBackup = backup
        }

        try FileManager.default.moveItem(at: stagedPackageRoot, to: destination)
        return destination
    }

    func commit() {
        guard isCommitted == false else { return }
        isCommitted = true
        if let replacedPackageBackup {
            removeArtifactIfPresent(
                replacedPackageBackup,
                reason: "discarding extension package backup after successful install"
            )
        }
        removeArtifactIfPresent(
            stagedPackageRoot,
            reason: "removing extension staging directory after commit"
        )
    }

    func rollback() {
        guard isCommitted == false else { return }

        if let installedPackageRoot {
            removeArtifactIfPresent(
                installedPackageRoot,
                reason: "removing failed extension install destination"
            )
        }
        removeArtifactIfPresent(
            stagedPackageRoot,
            reason: "removing failed extension install staging directory"
        )

        guard let replacedPackageBackup, let installedPackageRoot else { return }
        do {
            try FileManager.default.moveItem(
                at: replacedPackageBackup,
                to: installedPackageRoot
            )
        } catch {
            ExtensionManager.logger.error(
                "Failed to restore extension package backup from \(replacedPackageBackup.path, privacy: .public) to \(installedPackageRoot.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func removeArtifactIfPresent(_ url: URL, reason: String) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            ExtensionManager.logger.error(
                "Failed \(reason, privacy: .public) at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
