import Foundation

/// Canonical filesystem layout for browser-owned extension packages.
/// The extension database record's `packagePath` is the durable pointer to a generation.
struct ExtensionPackageLayout: Sendable {
    enum PackageRootKind: Equatable, Sendable {
        case managedGeneration
        case stagingTransaction
        case legacyDirect
        case outsideLayout
    }

    let extensionsRoot: URL

    private var applicationSupportRoot: URL {
        extensionsRoot.deletingLastPathComponent()
    }

    var packagesRoot: URL {
        applicationSupportRoot.appendingPathComponent(
            "ExtensionPackageGenerations-v1",
            isDirectory: true
        )
    }

    var stagingRoot: URL {
        applicationSupportRoot.appendingPathComponent(
            "ExtensionPackageStaging-v1",
            isDirectory: true
        )
    }

    var quarantineRoot: URL {
        applicationSupportRoot.appendingPathComponent(
            "ExtensionPackageQuarantine-v1",
            isDirectory: true
        )
    }

    func makeStagingRoot() -> URL {
        stagingRoot.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
    }

    func makeGenerationRoot() -> URL {
        packagesRoot.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
    }

    func packageRootKind(_ url: URL) -> PackageRootKind {
        let standardized = url.standardizedFileURL
        guard let values = directoryValues(standardized),
        values.isDirectory == true,
        values.isSymbolicLink != true else {
            return .outsideLayout
        }
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        if standardized.deletingLastPathComponent()
            == packagesRoot.standardizedFileURL {
            guard isSafeReservedDirectory(packagesRoot) else {
                return .outsideLayout
            }
            let resolvedPackages = packagesRoot.resolvingSymlinksInPath()
                .standardizedFileURL
            if resolved.deletingLastPathComponent() == resolvedPackages,
               UUID(uuidString: resolved.lastPathComponent) != nil {
                return .managedGeneration
            }
            return .outsideLayout
        }

        if standardized.deletingLastPathComponent()
            == stagingRoot.standardizedFileURL {
            guard isSafeReservedDirectory(stagingRoot) else {
                return .outsideLayout
            }
            let resolvedStaging = stagingRoot.resolvingSymlinksInPath()
                .standardizedFileURL
            if resolved.deletingLastPathComponent() == resolvedStaging,
               UUID(uuidString: resolved.lastPathComponent) != nil {
                return .stagingTransaction
            }
            return .outsideLayout
        }

        let resolvedRoot = extensionsRoot.resolvingSymlinksInPath()
            .standardizedFileURL
        if resolved.deletingLastPathComponent() == resolvedRoot,
           resolved.lastPathComponent.hasPrefix("temp_") {
            return .stagingTransaction
        }
        if resolved.deletingLastPathComponent() == resolvedRoot {
            return .legacyDirect
        }
        return .outsideLayout
    }

    func createTransactionDirectories() throws {
        try createSafeReservedDirectory(packagesRoot)
        try createSafeReservedDirectory(stagingRoot)
    }

    func createQuarantineDirectory() throws {
        try createSafeReservedDirectory(quarantineRoot)
    }

    private func createSafeReservedDirectory(_ directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        guard isSafeReservedDirectory(directory) else {
            throw ExtensionError.installationFailed(
                "Extension package storage is not a browser-owned directory"
            )
        }
    }

    private func isSafeReservedDirectory(_ directory: URL) -> Bool {
        let standardizedParent = directory.deletingLastPathComponent()
            .standardizedFileURL
        guard standardizedParent == applicationSupportRoot.standardizedFileURL,
              let values = directoryValues(directory),
              values.isDirectory == true,
              values.isSymbolicLink != true else {
            return false
        }
        return directory.resolvingSymlinksInPath().deletingLastPathComponent()
            .standardizedFileURL
            == applicationSupportRoot.resolvingSymlinksInPath()
                .standardizedFileURL
    }

    private func directoryValues(_ directory: URL) -> URLResourceValues? {
        do {
            return try directory.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
        } catch {
            return nil
        }
    }
}

@available(macOS 15.5, *)
@MainActor
final class ExtensionPackageGenerationRegistry {
    struct Claim: Hashable, Sendable {
        fileprivate let path: String
        fileprivate let nonce: UUID
    }

    private var claimsByPath: [String: Claim] = [:]

    func begin(_ packageRoot: URL) -> Claim? {
        let path = packageRoot.standardizedFileURL.path
        guard claimsByPath[path] == nil else { return nil }
        let claim = Claim(path: path, nonce: UUID())
        claimsByPath[path] = claim
        return claim
    }

    @discardableResult
    func finish(_ claim: Claim) -> Bool {
        guard claimsByPath[claim.path] == claim else { return false }
        claimsByPath.removeValue(forKey: claim.path)
        return true
    }

    func isActive(_ packageRoot: URL) -> Bool {
        claimsByPath[packageRoot.standardizedFileURL.path] != nil
    }
}
