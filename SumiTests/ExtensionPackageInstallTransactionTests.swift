import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionPackageInstallTransactionTests: XCTestCase {
    func testRollbackDeletesCandidateWithoutTouchingSupersededPackage() throws {
        let fixture = try makeFixture()
        addTeardownBlock {
            try FileManager.default.removeItem(at: fixture.root)
        }
        let transaction = ExtensionPackageInstallTransaction(
            extensionsDirectory: fixture.extensions
        )

        try transaction.stage(resourcesAt: fixture.candidate)
        let installed = try transaction.installStagedPackage()
        XCTAssertEqual(try marker(at: installed), "candidate")

        try transaction.rollback()

        XCTAssertFalse(FileManager.default.fileExists(atPath: installed.path))
        XCTAssertEqual(try marker(at: fixture.superseded), "original")
        XCTAssertTrue(try temporaryArtifacts(in: fixture.extensions).isEmpty)
    }

    func testDurableCommitKeepsCandidateWithoutMutatingSupersededPackage()
        throws {
        let fixture = try makeFixture()
        addTeardownBlock {
            try FileManager.default.removeItem(at: fixture.root)
        }
        let transaction = ExtensionPackageInstallTransaction(
            extensionsDirectory: fixture.extensions
        )

        try transaction.stage(resourcesAt: fixture.candidate)
        let installed = try transaction.installStagedPackage()
        transaction.commit()

        XCTAssertEqual(try marker(at: installed), "candidate")
        XCTAssertEqual(try marker(at: fixture.superseded), "original")
        XCTAssertTrue(try temporaryArtifacts(in: fixture.extensions).isEmpty)
    }

    func testPreservedCandidateNeverOverwritesSupersededPackage() throws {
        let fixture = try makeFixture()
        addTeardownBlock {
            try FileManager.default.removeItem(at: fixture.root)
        }
        let transaction = ExtensionPackageInstallTransaction(
            extensionsDirectory: fixture.extensions
        )
        try transaction.stage(resourcesAt: fixture.candidate)
        let installed = try transaction.installStagedPackage()

        transaction.commit()

        XCTAssertEqual(try marker(at: installed), "candidate")
        XCTAssertEqual(try marker(at: fixture.superseded), "original")
    }

    func testFailedCandidateMoveNeverTouchesSupersededPackage() throws {
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
        try transaction.stage(resourcesAt: fixture.candidate)
        try FileManager.default.removeItem(at: transaction.stagedPackageRoot)

        XCTAssertThrowsError(try transaction.installStagedPackage())
        try transaction.rollback()

        XCTAssertEqual(try marker(at: fixture.superseded), "original")
        XCTAssertTrue(try temporaryArtifacts(in: fixture.extensions).isEmpty)
    }

    func testFreshRollbackDeletesUncommittedCandidate() throws {
        let fixture = try makeFixture()
        addTeardownBlock {
            try FileManager.default.removeItem(at: fixture.root)
        }
        let transaction = ExtensionPackageInstallTransaction(
            extensionsDirectory: fixture.extensions
        )
        try transaction.stage(resourcesAt: fixture.candidate)
        let installed = try transaction.installStagedPackage()

        try transaction.rollback()

        XCTAssertFalse(FileManager.default.fileExists(atPath: installed.path))
    }

    func testStagingRejectsSymlinkedRuntimeResources() throws {
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

        XCTAssertThrowsError(
            try transaction.stage(resourcesAt: fixture.candidate)
        )
        try transaction.rollback()

        XCTAssertEqual(
            String(decoding: try Data(contentsOf: outside), as: UTF8.self),
            "outside"
        )
        XCTAssertTrue(try temporaryArtifacts(in: fixture.extensions).isEmpty)
    }

    func testMaterializationRechecksSymlinksInjectedAfterStaging() throws {
        let fixture = try makeFixture()
        addTeardownBlock { try FileManager.default.removeItem(at: fixture.root) }
        let outside = fixture.root.appendingPathComponent("outside.js")
        try Data("outside".utf8).write(to: outside)
        let transaction = ExtensionPackageInstallTransaction(
            extensionsDirectory: fixture.extensions
        )
        try transaction.stage(resourcesAt: fixture.candidate)
        try FileManager.default.createSymbolicLink(
            at: transaction.stagedPackageRoot.appendingPathComponent(
                "injected.js"
            ),
            withDestinationURL: outside
        )

        XCTAssertThrowsError(try transaction.installStagedPackage())
        try transaction.rollback()

        XCTAssertTrue(try temporaryArtifacts(in: fixture.extensions).isEmpty)
        XCTAssertEqual(
            String(decoding: try Data(contentsOf: outside), as: UTF8.self),
            "outside"
        )
    }

    func testFailedInstallCanRollbackWithoutTouchingSupersededPackage() throws {
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
        try transaction.stage(resourcesAt: fixture.candidate)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555],
            ofItemAtPath: packagesRoot(for: fixture).path
        )

        XCTAssertThrowsError(try transaction.installStagedPackage())
        XCTAssertEqual(try marker(at: fixture.superseded), "original")

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: packagesRoot(for: fixture).path
        )
        try transaction.rollback()
        XCTAssertEqual(try marker(at: fixture.superseded), "original")
    }

    func testSuccessfulRollbackIsIdempotent() throws {
        let fixture = try makeFixture()
        addTeardownBlock {
            try FileManager.default.removeItem(at: fixture.root)
        }
        let transaction = ExtensionPackageInstallTransaction(
            extensionsDirectory: fixture.extensions
        )
        try transaction.stage(resourcesAt: fixture.candidate)
        let installed = try transaction.installStagedPackage()

        try transaction.rollback()
        try transaction.rollback()

        XCTAssertFalse(FileManager.default.fileExists(atPath: installed.path))
        XCTAssertEqual(try marker(at: fixture.superseded), "original")
    }

    func testFailedRollbackCanRetryWithoutDeletingSupersededPackage() throws {
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
        try transaction.stage(resourcesAt: fixture.candidate)
        let installed = try transaction.installStagedPackage()
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555],
            ofItemAtPath: packagesRoot(for: fixture).path
        )

        XCTAssertThrowsError(try transaction.rollback())

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: packagesRoot(for: fixture).path
        )
        try transaction.rollback()

        XCTAssertFalse(FileManager.default.fileExists(atPath: installed.path))
        XCTAssertEqual(try marker(at: fixture.superseded), "original")
        XCTAssertTrue(try temporaryArtifacts(in: fixture.extensions).isEmpty)
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
        return (root, extensions, candidate, superseded)
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
