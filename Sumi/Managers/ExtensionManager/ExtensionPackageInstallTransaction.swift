import Foundation
import OSLog

/// Runs blocking package filesystem calls on a serial GCD utility queue rather
/// than occupying either MainActor or Swift's cooperative executor. The
/// transaction actor remains the only authority over phases and artifacts.
final class ExtensionPackageFileExecutor: Sendable {
    enum Operation: Equatable, Sendable {
        case prepareStaging
        case copyStagedPackage
        case prepareMaterialization
        case materializePackage
        case inspectMaterializedPackage
        case deleteRollbackArtifacts
    }

    private let queue: DispatchQueue
    private let willExecute: (@Sendable (Operation) -> Void)?

    init(
        label: String = "com.sumi.extensions.package-files",
        willExecute: (@Sendable (Operation) -> Void)? = nil
    ) {
        self.queue = DispatchQueue(label: label, qos: .utility)
        self.willExecute = willExecute
    }

    func perform<T: Sendable>(
        _ operation: Operation,
        body: @escaping @Sendable () -> T
    ) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { [willExecute] in
                willExecute?(operation)
                continuation.resume(returning: body())
            }
        }
    }

    func performThrowing<T: Sendable>(
        _ operation: Operation,
        body: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [willExecute] in
                willExecute?(operation)
                do {
                    continuation.resume(returning: try body())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

/// Owns the reversible filesystem part of installing one directory-backed
/// extension. Persistence and WebKit activation remain outside this actor.
@available(macOS 15.5, *)
actor ExtensionPackageInstallTransaction {
    struct StagedManifest: Sendable {
        let data: Data
        let fingerprint: String
    }

    struct MaterializedPackage: Sendable {
        let root: URL
        let manifestData: Data
        let manifestFingerprint: String
    }

    struct RollbackFailure: LocalizedError, Sendable {
        let failures: [String]

        var errorDescription: String? {
            "Extension package rollback was incomplete: "
                + failures.joined(separator: "; ")
        }
    }

    struct InvalidPhase: LocalizedError, Sendable {
        let operation: String
        let phase: Phase

        var errorDescription: String? {
            "Cannot \(operation) extension package while transaction is \(phase.rawValue)"
        }
    }

    private enum ClaimReleaseIssue: String, Sendable {
        case stagingClaimWasNoLongerExact
        case installedClaimWasNoLongerExact
    }

    enum Phase: String, Sendable {
        case initialized
        case preparingStaging
        case claimingStaging
        case staging
        case staged
        case preparingMaterialization
        case claimingGeneration
        case materializing
        case materialized
        case rollbackRequired
        case committing
        case committed
        case rollingBack
        case rollbackRetryable
        case rolledBack
    }

    nonisolated let stagedPackageRoot: URL

    private static let logger = Logger.sumi(category: "Extensions")
    private let layout: ExtensionPackageLayout
    private let activeGenerations: ExtensionPackageGenerationRegistry
    private let fileExecutor: ExtensionPackageFileExecutor
    private var stagingClaim: ExtensionPackageGenerationRegistry.Claim?
    private var generationClaim: ExtensionPackageGenerationRegistry.Claim?
    private var installedPackageRoot: URL?
    private var phase: Phase = .initialized

    init(
        extensionsDirectory: URL,
        activeGenerations: ExtensionPackageGenerationRegistry = .init(),
        fileExecutor: ExtensionPackageFileExecutor = .init()
    ) {
        let layout = ExtensionPackageLayout(extensionsRoot: extensionsDirectory)
        self.layout = layout
        self.activeGenerations = activeGenerations
        self.fileExecutor = fileExecutor
        self.stagedPackageRoot = layout.makeStagingRoot()
    }

    func currentPhase() -> Phase {
        phase
    }

    func stage(resourcesAt source: URL) async throws -> StagedManifest {
        guard phase == .initialized else {
            throw InvalidPhase(operation: "stage", phase: phase)
        }
        phase = .preparingStaging
        do {
            try await prepareStagingLayout(source: source)
            try Task.checkCancellation()
        } catch {
            phase = .initialized
            throw error
        }

        phase = .claimingStaging
        guard let claim = await activeGenerations.begin(stagedPackageRoot) else {
            phase = .initialized
            throw ExtensionError.installationFailed(
                "The generated extension staging destination is already active"
            )
        }
        stagingClaim = claim
        phase = .staging

        do {
            try Task.checkCancellation()
            let stagedManifest = try await copyAndInspectStagedPackage(
                source: source
            )
            try Task.checkCancellation()
            phase = .staged
            return stagedManifest
        } catch {
            phase = .rollbackRequired
            throw error
        }
    }

    func materialize(
        expectedManifestFingerprint: String
    ) async throws -> MaterializedPackage {
        guard phase == .staged else {
            throw InvalidPhase(operation: "materialize", phase: phase)
        }

        do {
            try Task.checkCancellation()
            let destination = layout.makeGenerationRoot()
            phase = .preparingMaterialization
            try await prepareMaterializationLayout(destination: destination)
            try Task.checkCancellation()

            phase = .claimingGeneration
            guard let claim = await activeGenerations.begin(destination) else {
                phase = .staged
                throw ExtensionError.installationFailed(
                    "The generated extension package destination is already active"
                )
            }
            generationClaim = claim
            phase = .materializing

            try Task.checkCancellation()
            try await scanAndMoveStagedPackage(to: destination)
            // Publish rollback authority before any operation that can fail or
            // observe cancellation after the move.
            installedPackageRoot = destination

            try Task.checkCancellation()
            let manifestData = try await inspectMaterializedPackage(
                at: destination,
                expectedManifestFingerprint: expectedManifestFingerprint
            )
            try Task.checkCancellation()
            phase = .materialized
            return MaterializedPackage(
                root: destination,
                manifestData: manifestData,
                manifestFingerprint: expectedManifestFingerprint
            )
        } catch {
            if generationClaim != nil || installedPackageRoot != nil {
                phase = .rollbackRequired
            } else if phase != .staged {
                phase = .rollbackRequired
            }
            throw error
        }
    }

    func commit() async {
        switch phase {
        case .committed:
            return
        case .materialized:
            break
        default:
            preconditionFailure(
                InvalidPhase(operation: "commit", phase: phase)
                    .localizedDescription
            )
        }

        phase = .committing
        let releaseFailures = await finishClaims()
        if releaseFailures.isEmpty == false {
            let summary = releaseFailures.map(\.rawValue).joined(separator: "; ")
            Self.logger.error(
                "Committed extension package but exact generation claim release failed: \(summary, privacy: .public)"
            )
        }
        phase = .committed
    }

    /// Rollback deliberately ignores task cancellation. Once a forward phase
    /// owns bytes or a generation claim, cleanup must reach a terminal or
    /// explicitly retryable state before returning.
    func rollback() async throws {
        switch phase {
        case .rolledBack:
            return
        case .committed:
            throw InvalidPhase(operation: "rollback", phase: phase)
        case .rollingBack, .committing, .claimingStaging,
            .preparingStaging, .staging, .preparingMaterialization,
            .claimingGeneration, .materializing:
            throw InvalidPhase(operation: "rollback", phase: phase)
        case .initialized:
            phase = .rolledBack
            return
        case .staged, .materialized, .rollbackRequired, .rollbackRetryable:
            break
        }

        phase = .rollingBack
        let deletion = await deleteRollbackArtifacts(
            installedPackageRoot: installedPackageRoot,
            stagedPackageRoot: stagingClaim == nil ? nil : stagedPackageRoot
        )
        if deletion.didRemoveInstalledPackage {
            installedPackageRoot = nil
        }
        var failures = deletion.failures

        guard failures.isEmpty else {
            phase = .rollbackRetryable
            throw RollbackFailure(failures: failures)
        }

        let claimReleaseIssues = await finishClaims()
        failures.append(contentsOf: claimReleaseIssues.map(\.rawValue))
        guard failures.isEmpty else {
            phase = .rollbackRetryable
            throw RollbackFailure(failures: failures)
        }
        phase = .rolledBack
    }

    private func finishClaims() async -> [ClaimReleaseIssue] {
        var failures: [ClaimReleaseIssue] = []
        if let stagingClaim {
            // `phase` is already committing/rollingBack before this MainActor
            // hop, so a reentrant public call cannot enter a forward phase.
            let didFinish = await activeGenerations.finish(stagingClaim)
            self.stagingClaim = nil
            if didFinish == false {
                failures.append(.stagingClaimWasNoLongerExact)
            }
        }
        if let generationClaim {
            let didFinish = await activeGenerations.finish(generationClaim)
            self.generationClaim = nil
            if didFinish == false {
                failures.append(.installedClaimWasNoLongerExact)
            }
        }
        return failures
    }

    private func prepareStagingLayout(source: URL) async throws {
        let layout = self.layout
        try Task.checkCancellation()
        try await fileExecutor.performThrowing(.prepareStaging) {
            guard try source.resourceValues(forKeys: [.isSymbolicLinkKey])
                    .isSymbolicLink != true else {
                throw ExtensionError.installationFailed(
                    "Extension package roots cannot be symbolic links"
                )
            }
            try layout.createTransactionDirectories()
        }
        try Task.checkCancellation()
    }

    private func copyAndInspectStagedPackage(
        source: URL
    ) async throws -> StagedManifest {
        let destination = stagedPackageRoot
        try Task.checkCancellation()
        let result = try await fileExecutor.performThrowing(.copyStagedPackage) {
            try Self.removeArtifactIfPresent(destination)
            try FileManager.default.copyItem(at: source, to: destination)
            try Self.rejectSymbolicLinks(in: destination)
            let manifestData = try Data(
                contentsOf: destination.appendingPathComponent("manifest.json")
            )
            try Self.validateCopiedManifest(
                manifestData,
                packageRoot: destination
            )
            return StagedManifest(
                data: manifestData,
                fingerprint: ExtensionPackageFingerprint.data(manifestData)
            )
        }
        try Task.checkCancellation()
        return result
    }

    private func prepareMaterializationLayout(
        destination: URL
    ) async throws {
        let layout = self.layout
        try Task.checkCancellation()
        try await fileExecutor.performThrowing(.prepareMaterialization) {
            try layout.createTransactionDirectories()
            guard FileManager.default.fileExists(atPath: destination.path) == false
            else {
                throw ExtensionError.installationFailed(
                    "A generated extension package destination already exists"
                )
            }
        }
        try Task.checkCancellation()
    }

    /// Cancellation is intentionally checked before, but not after, the move.
    /// Once `moveItem` succeeds the actor must first publish the destination as
    /// rollback authority.
    private func scanAndMoveStagedPackage(to destination: URL) async throws {
        let stagedPackageRoot = self.stagedPackageRoot
        try Task.checkCancellation()
        try await fileExecutor.performThrowing(.materializePackage) {
            // The last pre-move scan and the same-volume rename share one
            // serial critical section, so this actor introduces no suspension
            // between integrity validation and materialization.
            try Self.rejectSymbolicLinks(in: stagedPackageRoot)
            try FileManager.default.moveItem(
                at: stagedPackageRoot,
                to: destination
            )
        }
    }

    private func inspectMaterializedPackage(
        at destination: URL,
        expectedManifestFingerprint: String
    ) async throws -> Data {
        let layout = self.layout
        try Task.checkCancellation()
        let data = try await fileExecutor.performThrowing(
            .inspectMaterializedPackage
        ) {
            guard layout.packageRootKind(destination) == .managedGeneration else {
                throw ExtensionError.installationFailed(
                    "The generated extension package escaped browser-owned storage"
                )
            }
            try Self.rejectSymbolicLinks(in: destination)
            let manifestURL = destination.appendingPathComponent(
                "manifest.json"
            )
            let manifestValues = try manifestURL.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            guard manifestValues.isRegularFile == true,
                  manifestValues.isSymbolicLink != true else {
                throw ExtensionError.installationFailed(
                    "The materialized extension manifest is not a regular file"
                )
            }
            let manifestData = try Data(contentsOf: manifestURL)
            guard ExtensionPackageFingerprint.data(manifestData)
                    == expectedManifestFingerprint else {
                throw ExtensionError.installationFailed(
                    "The staged extension manifest changed during installation"
                )
            }
            try Self.validateCopiedManifest(
                manifestData,
                packageRoot: destination
            )
            return manifestData
        }
        try Task.checkCancellation()
        return data
    }

    private struct RollbackDeletionResult: Sendable {
        let didRemoveInstalledPackage: Bool
        let failures: [String]
    }

    private func deleteRollbackArtifacts(
        installedPackageRoot: URL?,
        stagedPackageRoot: URL?
    ) async -> RollbackDeletionResult {
        // The GCD operation does not inherit caller cancellation. Cleanup
        // always reaches a complete or retryable phase before returning.
        await fileExecutor.perform(.deleteRollbackArtifacts) {
            var failures: [String] = []
            var didRemoveInstalledPackage = installedPackageRoot == nil
            if let installedPackageRoot {
                do {
                    try Self.removeArtifactIfPresent(installedPackageRoot)
                    didRemoveInstalledPackage = true
                } catch {
                    failures.append(
                        "failed to remove candidate package: "
                            + error.localizedDescription
                    )
                }
            }
            if let stagedPackageRoot {
                do {
                    try Self.removeArtifactIfPresent(stagedPackageRoot)
                } catch {
                    failures.append(
                        "failed to remove staging package: "
                            + error.localizedDescription
                    )
                }
            }
            return RollbackDeletionResult(
                didRemoveInstalledPackage: didRemoveInstalledPackage,
                failures: failures
            )
        }
    }

    private nonisolated static func rejectSymbolicLinks(
        in packageRoot: URL
    ) throws {
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: packageRoot,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else {
            throw ExtensionError.installationFailed(
                "The extension package could not be enumerated safely"
            )
        }
        for case let entry as URL in enumerator {
            if try entry.resourceValues(forKeys: keys).isSymbolicLink == true {
                throw ExtensionError.installationFailed(
                    "Extension packages cannot contain symbolic links"
                )
            }
        }
    }

    private nonisolated static func validateCopiedManifest(
        _ data: Data,
        packageRoot: URL
    ) throws {
        guard let manifest = try JSONSerialization.jsonObject(with: data)
                as? [String: Any] else {
            throw ExtensionError.invalidManifest("Invalid JSON structure")
        }
        try ExtensionManifestValidation.validateContents(
            manifest,
            policy: .unpackedDirectory
        )
        try ExtensionInstallSourceResolver.validateMV3Requirements(
            manifest: manifest,
            baseURL: packageRoot
        )
    }

    private nonisolated static func removeArtifactIfPresent(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
