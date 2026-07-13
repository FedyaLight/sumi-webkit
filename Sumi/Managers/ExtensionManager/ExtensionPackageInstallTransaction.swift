import Foundation

/// Owns the reversible filesystem part of installing a directory-backed extension.
/// Persistence and WebKit activation are deliberately outside this transaction.
@available(macOS 15.5, *)
@MainActor
final class ExtensionPackageInstallTransaction {
    struct RollbackFailure: LocalizedError {
        let failures: [String]

        var errorDescription: String? {
            "Extension package rollback was incomplete: "
                + failures.joined(separator: "; ")
        }
    }

    let stagedPackageRoot: URL

    private let layout: ExtensionPackageLayout
    private let activeGenerations: ExtensionPackageGenerationRegistry
    private var stagingClaim: ExtensionPackageGenerationRegistry.Claim?
    private var generationClaim: ExtensionPackageGenerationRegistry.Claim?
    private var installedPackageRoot: URL?
    private var isCommitted = false
    private var isRolledBack = false

    init(
        extensionsDirectory: URL,
        activeGenerations: ExtensionPackageGenerationRegistry = .init()
    ) {
        let layout = ExtensionPackageLayout(extensionsRoot: extensionsDirectory)
        self.layout = layout
        self.activeGenerations = activeGenerations
        self.stagedPackageRoot = layout.makeStagingRoot()
    }

    func stage(resourcesAt source: URL) throws {
        try layout.createTransactionDirectories()
        guard try source.resourceValues(forKeys: [.isSymbolicLinkKey])
                .isSymbolicLink != true else {
            throw ExtensionError.installationFailed(
                "Extension package roots cannot be symbolic links"
            )
        }
        guard let stagingClaim = activeGenerations.begin(stagedPackageRoot) else {
            throw ExtensionError.installationFailed(
                "The generated extension staging destination is already active"
            )
        }
        self.stagingClaim = stagingClaim
        removeArtifactIfPresent(
            stagedPackageRoot,
            reason: "removing stale extension staging directory"
        )
        try FileManager.default.copyItem(at: source, to: stagedPackageRoot)
        try rejectSymbolicLinks(in: stagedPackageRoot)
    }

    func installStagedPackage() throws -> URL {
        try layout.createTransactionDirectories()
        try rejectSymbolicLinks(in: stagedPackageRoot)
        let destination = layout.makeGenerationRoot()
        guard FileManager.default.fileExists(atPath: destination.path) == false
        else {
            throw ExtensionError.installationFailed(
                "A generated extension package destination already exists"
            )
        }
        guard let claim = activeGenerations.begin(destination) else {
            throw ExtensionError.installationFailed(
                "The generated extension package destination is already active"
            )
        }
        generationClaim = claim

        try FileManager.default.moveItem(at: stagedPackageRoot, to: destination)
        installedPackageRoot = destination
        guard layout.packageRootKind(destination) == .managedGeneration else {
            throw ExtensionError.installationFailed(
                "The generated extension package escaped browser-owned storage"
            )
        }
        return destination
    }

    func commit() {
        guard isCommitted == false, isRolledBack == false else { return }
        isCommitted = true
        removeArtifactIfPresent(
            stagedPackageRoot,
            reason: "removing extension staging directory after commit"
        )
        finishGenerationClaim()
    }

    func rollback() throws {
        guard isCommitted == false, isRolledBack == false else { return }

        var failures: [String] = []
        if let installedPackageRoot {
            do {
                try removeArtifactIfPresent(installedPackageRoot)
                self.installedPackageRoot = nil
            } catch {
                failures.append(
                    "failed to remove candidate package: "
                        + error.localizedDescription
                )
            }
        }
        do {
            try removeArtifactIfPresent(stagedPackageRoot)
        } catch {
            failures.append(
                "failed to remove staging package: "
                    + error.localizedDescription
            )
        }

        guard failures.isEmpty else {
            throw RollbackFailure(failures: failures)
        }
        finishGenerationClaim()
        isRolledBack = true
    }

    private func finishGenerationClaim() {
        if let stagingClaim {
            _ = activeGenerations.finish(stagingClaim)
            self.stagingClaim = nil
        }
        guard let generationClaim else { return }
        _ = activeGenerations.finish(generationClaim)
        self.generationClaim = nil
    }

    private func rejectSymbolicLinks(in packageRoot: URL) throws {
        let keys: [URLResourceKey] = [.isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: packageRoot,
            includingPropertiesForKeys: keys,
            options: []
        ) else {
            throw ExtensionError.installationFailed(
                "The extension package could not be enumerated safely"
            )
        }
        for case let entry as URL in enumerator {
            if try entry.resourceValues(forKeys: Set(keys)).isSymbolicLink
                == true {
                throw ExtensionError.installationFailed(
                    "Extension packages cannot contain symbolic links"
                )
            }
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

    private func removeArtifactIfPresent(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
