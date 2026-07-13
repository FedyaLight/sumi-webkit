import Foundation
import OSLog

/// Quarantines unreferenced package generations during catalog startup. The
/// atomic move happens before catalog load returns; recursive deletion happens
/// off-main only after the package is no longer addressable by its old path.
@available(macOS 15.5, *)
@MainActor
final class ExtensionPackageMaintenance {
    nonisolated private static let logger = Logger.sumi(category: "Extensions")

    private let layout: ExtensionPackageLayout
    private let activeGenerations: ExtensionPackageGenerationRegistry

    init(
        layout: ExtensionPackageLayout,
        activeGenerations: ExtensionPackageGenerationRegistry
    ) {
        self.layout = layout
        self.activeGenerations = activeGenerations
    }

    func quarantineOrphans(referencedPackagePaths: Set<String>) -> [URL] {
        let referenced = Set(referencedPackagePaths.map {
            URL(fileURLWithPath: $0).resolvingSymlinksInPath()
                .standardizedFileURL.path
        })
        do {
            try layout.createQuarantineDirectory()
        } catch {
            Self.logger.error(
                "Failed to create extension package quarantine: \(error.localizedDescription, privacy: .public)"
            )
            return []
        }

        var quarantined = existingQuarantinePackages()
        for candidate in packageCandidates() {
            let resolvedPath = candidate.resolvingSymlinksInPath()
                .standardizedFileURL.path
            guard referenced.contains(resolvedPath) == false,
                  activeGenerations.isActive(candidate) == false else {
                continue
            }
            do {
                quarantined.append(try quarantinePackage(candidate))
            } catch {
                Self.logger.error(
                    "Failed to quarantine orphaned extension package \(candidate.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
        return quarantined
    }

    func quarantinePackage(_ package: URL) throws -> URL {
        guard layout.packageRootKind(package) != .outsideLayout else {
            throw ExtensionError.installationFailed(
                "Refused to remove an extension package outside browser-owned storage"
            )
        }
        guard activeGenerations.isActive(package) == false else {
            throw ExtensionError.installationFailed(
                "Refused to remove an extension package used by an active transaction"
            )
        }
        try layout.createQuarantineDirectory()
        let quarantineURL = layout.quarantineRoot.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.moveItem(at: package, to: quarantineURL)
        return quarantineURL
    }

    nonisolated func deleteQuarantinedPackages(_ packages: [URL]) {
        guard packages.isEmpty == false else { return }
        DispatchQueue.global(qos: .utility).async {
            for package in packages {
                do {
                    try FileManager.default.removeItem(at: package)
                } catch {
                    Self.logger.error(
                        "Failed to delete quarantined extension package \(package.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
        }
    }

    private func packageCandidates() -> [URL] {
        var candidates: [URL] = []
        let generations = directoryContents(at: layout.packagesRoot)
        candidates += generations.filter {
            layout.packageRootKind($0) == .managedGeneration
        }
        let staging = directoryContents(at: layout.stagingRoot)
        candidates += staging.filter {
            layout.packageRootKind($0) == .stagingTransaction
        }
        let legacy = directoryContents(at: layout.extensionsRoot)
        candidates += legacy.filter {
            (layout.packageRootKind($0) == .legacyDirect
                && $0.lastPathComponent.hasPrefix("backup_") == false)
                || layout.packageRootKind($0) == .stagingTransaction
        }
        return candidates.filter(isDirectory)
    }

    private func existingQuarantinePackages() -> [URL] {
        directoryContents(at: layout.quarantineRoot).filter(isDirectory)
    }

    private func directoryContents(at directory: URL) -> [URL] {
        do {
            return try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        do {
            return try url.resourceValues(forKeys: [.isDirectoryKey])
                .isDirectory == true
        } catch {
            return false
        }
    }
}
