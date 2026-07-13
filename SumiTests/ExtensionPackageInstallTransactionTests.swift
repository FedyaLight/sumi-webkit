import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionPackageInstallTransactionTests: XCTestCase {
    func testRollbackDeletesCandidateWithoutTouchingSupersededPackage() async throws {
        let fixture = try makeFixture()
        addTeardownBlock {
            try FileManager.default.removeItem(at: fixture.root)
        }
        let transaction = ExtensionPackageInstallTransaction(
            extensionsDirectory: fixture.extensions
        )

        let staged = try await transaction.stage(resourcesAt: fixture.candidate)
        let installed = try await transaction.materialize(
            expectedManifestFingerprint: staged.fingerprint
        ).root
        XCTAssertEqual(try marker(at: installed), "candidate")

        try await transaction.rollback()

        XCTAssertFalse(FileManager.default.fileExists(atPath: installed.path))
        XCTAssertEqual(try marker(at: fixture.superseded), "original")
        XCTAssertTrue(try temporaryArtifacts(in: fixture.extensions).isEmpty)
    }

    func testDurableCommitKeepsCandidateWithoutMutatingSupersededPackage()
        async throws {
        let fixture = try makeFixture()
        addTeardownBlock {
            try FileManager.default.removeItem(at: fixture.root)
        }
        let transaction = ExtensionPackageInstallTransaction(
            extensionsDirectory: fixture.extensions
        )

        let staged = try await transaction.stage(resourcesAt: fixture.candidate)
        let installed = try await transaction.materialize(
            expectedManifestFingerprint: staged.fingerprint
        ).root
        await transaction.commit()

        XCTAssertEqual(try marker(at: installed), "candidate")
        XCTAssertEqual(try marker(at: fixture.superseded), "original")
        XCTAssertTrue(try temporaryArtifacts(in: fixture.extensions).isEmpty)
    }

    func testPreservedCandidateNeverOverwritesSupersededPackage() async throws {
        let fixture = try makeFixture()
        addTeardownBlock {
            try FileManager.default.removeItem(at: fixture.root)
        }
        let transaction = ExtensionPackageInstallTransaction(
            extensionsDirectory: fixture.extensions
        )
        let staged = try await transaction.stage(resourcesAt: fixture.candidate)
        let installed = try await transaction.materialize(
            expectedManifestFingerprint: staged.fingerprint
        ).root

        await transaction.commit()

        XCTAssertEqual(try marker(at: installed), "candidate")
        XCTAssertEqual(try marker(at: fixture.superseded), "original")
    }

    func testFailedCandidateMoveNeverTouchesSupersededPackage() async throws {
        let fixture = try makeFixture()
        addTeardownBlock {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: self.packagesRoot(for: fixture).path
            )
            try FileManager.default.removeItem(at: fixture.root)
        }
        let transaction = ExtensionPackageInstallTransaction(
            extensionsDirectory: fixture.extensions
        )
        let staged = try await transaction.stage(resourcesAt: fixture.candidate)
        try FileManager.default.removeItem(at: transaction.stagedPackageRoot)

        await assertThrows {
            _ = try await transaction.materialize(
                expectedManifestFingerprint: staged.fingerprint
            )
        }
        try await transaction.rollback()

        XCTAssertEqual(try marker(at: fixture.superseded), "original")
        XCTAssertTrue(try temporaryArtifacts(in: fixture.extensions).isEmpty)
    }

    func testFreshRollbackDeletesUncommittedCandidate() async throws {
        let fixture = try makeFixture()
        addTeardownBlock {
            try FileManager.default.removeItem(at: fixture.root)
        }
        let transaction = ExtensionPackageInstallTransaction(
            extensionsDirectory: fixture.extensions
        )
        let staged = try await transaction.stage(resourcesAt: fixture.candidate)
        let installed = try await transaction.materialize(
            expectedManifestFingerprint: staged.fingerprint
        ).root

        try await transaction.rollback()

        XCTAssertFalse(FileManager.default.fileExists(atPath: installed.path))
    }

    func testStagingRejectsSymlinkedRuntimeResources() async throws {
        let fixture = try makeFixture()
        addTeardownBlock { try FileManager.default.removeItem(at: fixture.root) }
        let outside = fixture.root.appendingPathComponent("outside.js")
        try Data("outside".utf8).write(to: outside)
        let linkedResource = fixture.candidate.appendingPathComponent("worker.js")
        try FileManager.default.createSymbolicLink(
            at: linkedResource,
            withDestinationURL: outside
        )
        let transaction = ExtensionPackageInstallTransaction(
            extensionsDirectory: fixture.extensions
        )

        let error = await capturedError {
            _ = try await transaction.stage(resourcesAt: fixture.candidate)
        }
        XCTAssertTrue(error is ExtensionError)
        XCTAssertTrue(
            error?.localizedDescription.contains(
                "cannot contain symbolic links"
            ) == true
        )
        try await transaction.rollback()

        XCTAssertEqual(
            String(decoding: try Data(contentsOf: outside), as: UTF8.self),
            "outside"
        )
        XCTAssertTrue(try temporaryArtifacts(in: fixture.extensions).isEmpty)
    }

    func testMaterializationRechecksSymlinksInjectedAfterStaging() async throws {
        let fixture = try makeFixture()
        addTeardownBlock { try FileManager.default.removeItem(at: fixture.root) }
        let outside = fixture.root.appendingPathComponent("outside.js")
        try Data("outside".utf8).write(to: outside)
        let transaction = ExtensionPackageInstallTransaction(
            extensionsDirectory: fixture.extensions
        )
        let staged = try await transaction.stage(resourcesAt: fixture.candidate)
        try FileManager.default.createSymbolicLink(
            at: transaction.stagedPackageRoot.appendingPathComponent(
                "injected.js"
            ),
            withDestinationURL: outside
        )

        let error = await capturedError {
            _ = try await transaction.materialize(
                expectedManifestFingerprint: staged.fingerprint
            )
        }
        XCTAssertTrue(error is ExtensionError)
        XCTAssertTrue(
            error?.localizedDescription.contains(
                "cannot contain symbolic links"
            ) == true
        )
        try await transaction.rollback()

        XCTAssertTrue(try temporaryArtifacts(in: fixture.extensions).isEmpty)
        XCTAssertEqual(
            String(decoding: try Data(contentsOf: outside), as: UTF8.self),
            "outside"
        )
    }

    func testFailedInstallCanRollbackWithoutTouchingSupersededPackage() async throws {
        let fixture = try makeFixture()
        addTeardownBlock {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: fixture.extensions.path
            )
            try FileManager.default.removeItem(at: fixture.root)
        }
        let transaction = ExtensionPackageInstallTransaction(
            extensionsDirectory: fixture.extensions
        )
        let staged = try await transaction.stage(resourcesAt: fixture.candidate)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555],
            ofItemAtPath: packagesRoot(for: fixture).path
        )

        await assertThrows {
            _ = try await transaction.materialize(
                expectedManifestFingerprint: staged.fingerprint
            )
        }
        XCTAssertEqual(try marker(at: fixture.superseded), "original")

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: packagesRoot(for: fixture).path
        )
        try await transaction.rollback()
        XCTAssertEqual(try marker(at: fixture.superseded), "original")
    }

    func testSuccessfulRollbackIsIdempotent() async throws {
        let fixture = try makeFixture()
        addTeardownBlock {
            try FileManager.default.removeItem(at: fixture.root)
        }
        let transaction = ExtensionPackageInstallTransaction(
            extensionsDirectory: fixture.extensions
        )
        let staged = try await transaction.stage(resourcesAt: fixture.candidate)
        let installed = try await transaction.materialize(
            expectedManifestFingerprint: staged.fingerprint
        ).root

        try await transaction.rollback()
        try await transaction.rollback()

        XCTAssertFalse(FileManager.default.fileExists(atPath: installed.path))
        XCTAssertEqual(try marker(at: fixture.superseded), "original")
    }

    func testFailedRollbackCanRetryWithoutDeletingSupersededPackage() async throws {
        let fixture = try makeFixture()
        addTeardownBlock {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: self.packagesRoot(for: fixture).path
            )
            try FileManager.default.removeItem(at: fixture.root)
        }
        let transaction = ExtensionPackageInstallTransaction(
            extensionsDirectory: fixture.extensions
        )
        let staged = try await transaction.stage(resourcesAt: fixture.candidate)
        let installed = try await transaction.materialize(
            expectedManifestFingerprint: staged.fingerprint
        ).root
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555],
            ofItemAtPath: packagesRoot(for: fixture).path
        )

        let rollbackError = await capturedError {
            try await transaction.rollback()
        }
        XCTAssertTrue(
            rollbackError
                is ExtensionPackageInstallTransaction.RollbackFailure
        )

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: packagesRoot(for: fixture).path
        )
        try await transaction.rollback()

        XCTAssertFalse(FileManager.default.fileExists(atPath: installed.path))
        XCTAssertEqual(try marker(at: fixture.superseded), "original")
        XCTAssertTrue(try temporaryArtifacts(in: fixture.extensions).isEmpty)
    }

    func testMaterializeBeforeStageFailsWithoutChangingPhase() async throws {
        let fixture = try makeFixture()
        addTeardownBlock { try FileManager.default.removeItem(at: fixture.root) }
        let transaction = ExtensionPackageInstallTransaction(
            extensionsDirectory: fixture.extensions
        )

        let error = await capturedError {
            _ = try await transaction.materialize(
                expectedManifestFingerprint: "unused"
            )
        }

        XCTAssertTrue(error is ExtensionPackageInstallTransaction.InvalidPhase)
        let phase = await transaction.currentPhase()
        XCTAssertEqual(phase, .initialized)
    }

    func testCancellationAfterStagingClaimRollsBackBytesAndReleasesExactClaim()
        async throws {
        let fixture = try makeFixture()
        addTeardownBlock { try FileManager.default.removeItem(at: fixture.root) }
        let registry = ExtensionPackageGenerationRegistry()
        let gate = PackageFileOperationGate(target: .copyStagedPackage)
        defer { gate.release() }
        let fileExecutor = ExtensionPackageFileExecutor(
            label: "ExtensionPackageInstallTransactionTests.stage-cancellation",
            willExecute: gate.willExecute
        )
        let transaction = ExtensionPackageInstallTransaction(
            extensionsDirectory: fixture.extensions,
            activeGenerations: registry,
            fileExecutor: fileExecutor
        )
        let stageTask = Task {
            try await transaction.stage(resourcesAt: fixture.candidate)
        }
        let didBlock = await gate.waitUntilBlocked()
        XCTAssertTrue(didBlock)

        let blockedPhase = await transaction.currentPhase()
        XCTAssertEqual(blockedPhase, .staging)
        XCTAssertTrue(registry.isActive(transaction.stagedPackageRoot))
        stageTask.cancel()
        gate.release()

        let cancellationError = await capturedError {
            _ = try await stageTask.value
        }
        XCTAssertTrue(cancellationError is CancellationError)
        try await transaction.rollback()

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: transaction.stagedPackageRoot.path
            )
        )
        XCTAssertFalse(registry.isActive(transaction.stagedPackageRoot))
        let replacementClaim = try XCTUnwrap(
            registry.begin(transaction.stagedPackageRoot)
        )
        XCTAssertTrue(registry.finish(replacementClaim))
        let phase = await transaction.currentPhase()
        XCTAssertEqual(phase, .rolledBack)
    }

    func testCancellationAfterGenerationClaimRollsBackMovedBytesAndReleasesClaim()
        async throws {
        let fixture = try makeFixture()
        addTeardownBlock { try FileManager.default.removeItem(at: fixture.root) }
        let registry = ExtensionPackageGenerationRegistry()
        let gate = PackageFileOperationGate(target: .materializePackage)
        defer { gate.release() }
        let fileExecutor = ExtensionPackageFileExecutor(
            label: "ExtensionPackageInstallTransactionTests.materialize-cancellation",
            willExecute: gate.willExecute
        )
        let transaction = ExtensionPackageInstallTransaction(
            extensionsDirectory: fixture.extensions,
            activeGenerations: registry,
            fileExecutor: fileExecutor
        )
        let staged = try await transaction.stage(resourcesAt: fixture.candidate)
        let materializeTask = Task {
            try await transaction.materialize(
                expectedManifestFingerprint: staged.fingerprint
            )
        }
        let didBlock = await gate.waitUntilBlocked()
        XCTAssertTrue(didBlock)

        let blockedPhase = await transaction.currentPhase()
        XCTAssertEqual(blockedPhase, .materializing)
        materializeTask.cancel()
        gate.release()

        let cancellationError = await capturedError {
            _ = try await materializeTask.value
        }
        XCTAssertTrue(cancellationError is CancellationError)

        let installed = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(
                at: packagesRoot(for: fixture),
                includingPropertiesForKeys: nil
            ).first
        )
        XCTAssertTrue(registry.isActive(installed))
        try await transaction.rollback()

        XCTAssertFalse(registry.isActive(transaction.stagedPackageRoot))
        XCTAssertFalse(registry.isActive(installed))
        let replacementClaim = try XCTUnwrap(registry.begin(installed))
        XCTAssertTrue(registry.finish(replacementClaim))
        XCTAssertTrue(try temporaryArtifacts(in: fixture.extensions).isEmpty)
        let phase = await transaction.currentPhase()
        XCTAssertEqual(phase, .rolledBack)
    }

    func testTerminalOperationsAreIdempotentAndCommittedRollbackIsRejected()
        async throws {
        let committedFixture = try makeFixture()
        addTeardownBlock {
            try FileManager.default.removeItem(at: committedFixture.root)
        }
        let committed = ExtensionPackageInstallTransaction(
            extensionsDirectory: committedFixture.extensions
        )
        let committedStage = try await committed.stage(
            resourcesAt: committedFixture.candidate
        )
        _ = try await committed.materialize(
            expectedManifestFingerprint: committedStage.fingerprint
        )
        await committed.commit()
        await committed.commit()
        let committedPhase = await committed.currentPhase()
        let committedRollbackError = await capturedError {
            try await committed.rollback()
        }
        XCTAssertEqual(committedPhase, .committed)
        XCTAssertTrue(
            committedRollbackError
                is ExtensionPackageInstallTransaction.InvalidPhase
        )

        let rolledBackFixture = try makeFixture()
        addTeardownBlock {
            try FileManager.default.removeItem(at: rolledBackFixture.root)
        }
        let rolledBack = ExtensionPackageInstallTransaction(
            extensionsDirectory: rolledBackFixture.extensions
        )
        _ = try await rolledBack.stage(resourcesAt: rolledBackFixture.candidate)
        try await rolledBack.rollback()
        try await rolledBack.rollback()
        let rolledBackPhase = await rolledBack.currentPhase()
        XCTAssertEqual(rolledBackPhase, .rolledBack)
    }

    func testExactClaimsBlockMaintenanceUntilTransactionSettles() async throws {
        let fixture = try makeFixture()
        addTeardownBlock { try FileManager.default.removeItem(at: fixture.root) }
        let registry = ExtensionPackageGenerationRegistry()
        let layout = ExtensionPackageLayout(extensionsRoot: fixture.extensions)
        let maintenance = ExtensionPackageMaintenance(
            layout: layout,
            activeGenerations: registry
        )
        let transaction = ExtensionPackageInstallTransaction(
            extensionsDirectory: fixture.extensions,
            activeGenerations: registry
        )
        let staged = try await transaction.stage(resourcesAt: fixture.candidate)

        XCTAssertTrue(registry.isActive(transaction.stagedPackageRoot))
        XCTAssertThrowsError(
            try maintenance.quarantinePackage(transaction.stagedPackageRoot)
        )

        let installed = try await transaction.materialize(
            expectedManifestFingerprint: staged.fingerprint
        ).root
        XCTAssertTrue(registry.isActive(installed))
        XCTAssertThrowsError(try maintenance.quarantinePackage(installed))

        await transaction.commit()
        XCTAssertFalse(registry.isActive(installed))
        let quarantined = try maintenance.quarantinePackage(installed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: quarantined.path))
    }

    func testBlockedFileQueueKeepsMainActorResponsiveAndRejectsReentry()
        async throws {
        let fixture = try makeFixture()
        addTeardownBlock { try FileManager.default.removeItem(at: fixture.root) }
        let gate = PackageFileOperationGate(target: .prepareStaging)
        defer { gate.release() }
        let fileExecutor = ExtensionPackageFileExecutor(
            label: "ExtensionPackageInstallTransactionTests.gated",
            willExecute: gate.willExecute
        )
        let transaction = ExtensionPackageInstallTransaction(
            extensionsDirectory: fixture.extensions,
            fileExecutor: fileExecutor
        )
        let stageTask = Task {
            try await transaction.stage(resourcesAt: fixture.candidate)
        }
        let didBlock = await gate.waitUntilBlocked()
        XCTAssertTrue(didBlock)

        // Reaching this MainActor assertion while the package queue is blocked
        // is the behavioral proof that filesystem work did not pin the UI.
        let blockedPhase = await transaction.currentPhase()
        XCTAssertEqual(blockedPhase, .preparingStaging)
        let reentryError = await capturedError {
            _ = try await transaction.materialize(
                expectedManifestFingerprint: "not-staged"
            )
        }
        XCTAssertTrue(
            reentryError is ExtensionPackageInstallTransaction.InvalidPhase
        )

        stageTask.cancel()
        gate.release()
        let cancellationError = await capturedError {
            _ = try await stageTask.value
        }
        XCTAssertTrue(cancellationError is CancellationError)
        try await transaction.rollback()

        let finalPhase = await transaction.currentPhase()
        XCTAssertEqual(finalPhase, .rolledBack)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: transaction.stagedPackageRoot.path
            )
        )
    }

    private func makeFixture() throws -> (
        root: URL,
        extensions: URL,
        candidate: URL,
        superseded: URL
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let extensions = root.appendingPathComponent(
            "Extensions",
            isDirectory: true
        )
        let candidate = root.appendingPathComponent(
            "Candidate",
            isDirectory: true
        )
        let superseded = extensions.appendingPathComponent(
            "LegacyPackage",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: superseded,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: candidate,
            withIntermediateDirectories: true
        )
        try Data("original".utf8).write(
            to: superseded.appendingPathComponent("marker.txt")
        )
        try Data("candidate".utf8).write(
            to: candidate.appendingPathComponent("marker.txt")
        )
        try JSONSerialization.data(
            withJSONObject: [
                "manifest_version": 3,
                "name": "Candidate",
                "version": "1.0",
            ],
            options: [.sortedKeys]
        ).write(to: candidate.appendingPathComponent("manifest.json"))
        return (root, extensions, candidate, superseded)
    }

    private func assertThrows(
        _ operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("Expected operation to throw", file: file, line: line)
        } catch {
            XCTAssertFalse(
                error is ExtensionPackageInstallTransaction.InvalidPhase,
                "Expected an operational failure, got invalid phase",
                file: file,
                line: line
            )
            XCTAssertFalse(
                error is CancellationError,
                "Expected an operational failure, got cancellation",
                file: file,
                line: line
            )
        }
    }

    private func capturedError(
        _ operation: () async throws -> Void
    ) async -> (any Error)? {
        do {
            try await operation()
            return nil
        } catch {
            return error
        }
    }

    private func marker(at directory: URL) throws -> String {
        String(
            decoding: try Data(
                contentsOf: directory.appendingPathComponent("marker.txt")
            ),
            as: UTF8.self
        )
    }

    private func temporaryArtifacts(in directory: URL) throws -> [URL] {
        let rootArtifacts = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter {
            $0.lastPathComponent.hasPrefix("temp_")
        }
        let staging = ExtensionPackageLayout(
            extensionsRoot: directory
        ).stagingRoot
        let stagedArtifacts = try FileManager.default.contentsOfDirectory(
            at: staging,
            includingPropertiesForKeys: nil
        )
        return rootArtifacts + stagedArtifacts
    }

    private func packagesRoot(
        for fixture: (
            root: URL,
            extensions: URL,
            candidate: URL,
            superseded: URL
        )
    ) -> URL {
        ExtensionPackageLayout(
            extensionsRoot: fixture.extensions
        ).packagesRoot
    }
}

private final class PackageFileOperationGate: @unchecked Sendable {
    let target: ExtensionPackageFileExecutor.Operation
    private let blocked = DispatchSemaphore(value: 0)
    private let releaseSignal = DispatchSemaphore(value: 0)

    init(target: ExtensionPackageFileExecutor.Operation) {
        self.target = target
    }

    lazy var willExecute: @Sendable (
        ExtensionPackageFileExecutor.Operation
    ) -> Void = { [weak self] operation in
        self?.blockIfTarget(operation)
    }

    private func blockIfTarget(
        _ operation: ExtensionPackageFileExecutor.Operation
    ) {
        guard operation == target else { return }
        blocked.signal()
        releaseSignal.wait()
    }

    func waitUntilBlocked() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { [blocked] in
                let result = blocked.wait(timeout: .now() + 2)
                continuation.resume(returning: result == .success)
            }
        }
    }

    func release() {
        releaseSignal.signal()
    }
}
