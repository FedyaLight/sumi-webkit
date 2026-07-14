import Foundation

/// Reconciles the crash window left by the former in-place package installer.
/// Durable SwiftData metadata remains authoritative; ambiguous filesystem state
/// is left untouched and withheld from catalog publication.
struct LegacyExtensionBackupRecovery {
    enum ValidationDisposition: Equatable {
        case proceed
        case deferUntilNextLaunch
    }

    struct Result: Equatable {
        let validationDisposition: ValidationDisposition
        let quarantinedURLs: [URL]

        static let proceed = Result(
            validationDisposition: .proceed,
            quarantinedURLs: []
        )

        static let deferred = Result(
            validationDisposition: .deferUntilNextLaunch,
            quarantinedURLs: []
        )
    }

    struct DurablePackage {
        let extensionID: String
        let packagePath: String
        let manifestRootFingerprint: String
        let sourceKind: WebExtensionSourceKind
    }

    private let layout: ExtensionPackageLayout
    private let fileManager: FileManager

    init(
        layout: ExtensionPackageLayout,
        fileManager: FileManager = .default
    ) {
        self.layout = layout
        self.fileManager = fileManager
    }

    func recover(_ package: DurablePackage) -> Result {
        guard package.sourceKind == .directory,
              let durableRoot = legacyRoot(for: package) else {
            return .proceed
        }

        let backups = matchingBackupNames(for: package.extensionID).filter {
            isSafeDirectChildDirectory($0)
        }
        let matchingBackups = backups.filter {
            manifestFingerprint(at: $0) == package.manifestRootFingerprint
        }
        let durableRootExists = fileManager.fileExists(atPath: durableRoot.path)
        let durableRootIsSafe = durableRootExists
            && isSafeDirectChildDirectory(durableRoot)
        let durableRootMatches = durableRootIsSafe
            && manifestFingerprint(at: durableRoot)
                == package.manifestRootFingerprint

        if durableRootMatches {
            return Result(
                validationDisposition: .proceed,
                quarantinedURLs: quarantine(backups)
            )
        }

        guard durableRootExists == false || durableRootIsSafe,
              matchingBackups.count == 1,
              let matchingBackup = matchingBackups.first else {
            return .deferred
        }

        return restore(
            matchingBackup,
            to: durableRoot,
            replacingMismatchedRoot: durableRootExists
        )
    }

    private func legacyRoot(for package: DurablePackage) -> URL? {
        let extensionsRoot = layout.extensionsRoot.standardizedFileURL
        guard isDirectoryWithoutSymlink(extensionsRoot) else { return nil }

        let expected = extensionsRoot.appendingPathComponent(
            package.extensionID,
            isDirectory: true
        ).standardizedFileURL
        let persisted = URL(
            fileURLWithPath: package.packagePath,
            isDirectory: true
        ).standardizedFileURL
        guard expected.deletingLastPathComponent() == extensionsRoot,
              expected.lastPathComponent == package.extensionID,
              persisted == expected else {
            return nil
        }
        return expected
    }

    private func matchingBackupNames(for extensionID: String) -> [URL] {
        let prefix = "backup_\(extensionID)_"
        let children: [URL]
        do {
            children = try fileManager.contentsOfDirectory(
                at: layout.extensionsRoot,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                ],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return []
        }

        return children.filter { candidate in
            let name = candidate.lastPathComponent
            guard name.hasPrefix(prefix) else { return false }
            return UUID(uuidString: String(name.dropFirst(prefix.count))) != nil
        }
    }

    private func isSafeDirectChildDirectory(_ candidate: URL) -> Bool {
        let standardized = candidate.standardizedFileURL
        let standardizedRoot = layout.extensionsRoot.standardizedFileURL
        guard standardized.deletingLastPathComponent() == standardizedRoot,
              isDirectoryWithoutSymlink(standardized) else {
            return false
        }

        return standardized.resolvingSymlinksInPath()
            .deletingLastPathComponent().standardizedFileURL
            == standardizedRoot.resolvingSymlinksInPath().standardizedFileURL
    }

    private func isDirectoryWithoutSymlink(_ url: URL) -> Bool {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
        } catch {
            return false
        }
        return values.isDirectory == true && values.isSymbolicLink != true
    }

    private func manifestFingerprint(at packageRoot: URL) -> String? {
        let manifest = packageRoot.appendingPathComponent("manifest.json")
        guard manifest.standardizedFileURL.deletingLastPathComponent()
            == packageRoot.standardizedFileURL else {
            return nil
        }

        do {
            let values = try manifest.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  manifest.resolvingSymlinksInPath().deletingLastPathComponent()
                    .standardizedFileURL
                    == packageRoot.resolvingSymlinksInPath()
                        .standardizedFileURL else {
                return nil
            }
            let data = try Data(
                contentsOf: manifest,
                options: [.mappedIfSafe]
            )
            return ExtensionPackageFingerprint.data(data)
        } catch {
            return nil
        }
    }

    private func restore(
        _ backup: URL,
        to durableRoot: URL,
        replacingMismatchedRoot: Bool
    ) -> Result {
        var quarantinedRoot: URL?
        if replacingMismatchedRoot {
            guard let quarantined = quarantineOne(durableRoot) else {
                return .deferred
            }
            quarantinedRoot = quarantined
        }

        do {
            try fileManager.moveItem(at: backup, to: durableRoot)
            return Result(
                validationDisposition: .proceed,
                quarantinedURLs: quarantinedRoot.map { [$0] } ?? []
            )
        } catch {
            if let quarantinedRoot {
                do {
                    try fileManager.moveItem(
                        at: quarantinedRoot,
                        to: durableRoot
                    )
                } catch {
                    // The durable candidate remains untrusted. Leave the
                    // quarantined bytes untouched for a later startup audit.
                }
            }
            return .deferred
        }
    }

    private func quarantine(_ packages: [URL]) -> [URL] {
        packages.compactMap(quarantineOne)
    }

    private func quarantineOne(_ package: URL) -> URL? {
        guard isSafeDirectChildDirectory(package) else { return nil }
        do {
            try layout.createQuarantineDirectory()
            let destination = layout.quarantineRoot.appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
            try fileManager.moveItem(at: package, to: destination)
            return destination
        } catch {
            return nil
        }
    }
}
