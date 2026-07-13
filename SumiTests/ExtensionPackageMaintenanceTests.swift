import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionPackageMaintenanceTests: XCTestCase {
    func testStartupQuarantinesOnlyUnreferencedInactiveGenerations() throws {
        let fixture = try makeFixture()
        addTeardownBlock { try FileManager.default.removeItem(at: fixture.root) }
        let referenced = try makeGeneration(in: fixture.layout)
        let orphan = try makeGeneration(in: fixture.layout)
        let active = try makeGeneration(in: fixture.layout)
        let activeClaim = try XCTUnwrap(fixture.registry.begin(active))

        let quarantined = fixture.maintenance.quarantineOrphans(
            referencedPackagePaths: [referenced.path]
        )

        XCTAssertEqual(quarantined.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: referenced.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: active.path))
        XCTAssertTrue(fixture.registry.finish(activeClaim))
    }

    func testEmptyCatalogStillQuarantinesManagedOrphansAndStaging() throws {
        let fixture = try makeFixture()
        addTeardownBlock { try FileManager.default.removeItem(at: fixture.root) }
        let orphan = try makeGeneration(in: fixture.layout)
        let staging = fixture.layout.makeStagingRoot()
        try FileManager.default.createDirectory(
            at: staging,
            withIntermediateDirectories: true
        )

        let quarantined = fixture.maintenance.quarantineOrphans(
            referencedPackagePaths: []
        )

        XCTAssertEqual(quarantined.count, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
    }

    func testPackageOutsideBrowserStorageIsNeverQuarantined() throws {
        let fixture = try makeFixture()
        addTeardownBlock { try FileManager.default.removeItem(at: fixture.root) }
        let outside = fixture.root.appendingPathComponent(
            "Outside",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: outside,
            withIntermediateDirectories: true
        )

        XCTAssertThrowsError(
            try fixture.maintenance.quarantinePackage(outside)
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testExistingQuarantineIsReturnedForRetryDeletion() throws {
        let fixture = try makeFixture()
        addTeardownBlock { try FileManager.default.removeItem(at: fixture.root) }
        try fixture.layout.createQuarantineDirectory()
        let abandoned = fixture.layout.quarantineRoot.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: abandoned,
            withIntermediateDirectories: true
        )

        let pendingDeletion = fixture.maintenance.quarantineOrphans(
            referencedPackagePaths: []
        )

        XCTAssertEqual(
            pendingDeletion.map {
                $0.resolvingSymlinksInPath().standardizedFileURL
            },
            [abandoned.resolvingSymlinksInPath().standardizedFileURL]
        )
    }

    func testNonUUIDLegacyPackageIsQuarantinedWhenUnreferenced() throws {
        let fixture = try makeFixture()
        addTeardownBlock { try FileManager.default.removeItem(at: fixture.root) }
        let legacy = fixture.layout.extensionsRoot.appendingPathComponent(
            "addon@example.com",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: legacy,
            withIntermediateDirectories: true
        )

        let quarantined = fixture.maintenance.quarantineOrphans(
            referencedPackagePaths: []
        )

        XCTAssertEqual(quarantined.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
    }

    func testLegacyPackageClassificationDoesNotRequireGenerationDirectories()
        throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let extensions = root.appendingPathComponent(
            "Extensions",
            isDirectory: true
        )
        let legacy = extensions.appendingPathComponent(
            "legacy@example.com",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: legacy,
            withIntermediateDirectories: true
        )
        let layout = ExtensionPackageLayout(extensionsRoot: extensions)

        XCTAssertEqual(layout.packageRootKind(legacy), .legacyDirect)
    }

    func testSymlinkEscapeIsNeverQuarantined() throws {
        let fixture = try makeFixture()
        addTeardownBlock { try FileManager.default.removeItem(at: fixture.root) }
        let outside = fixture.root.appendingPathComponent(
            "Outside",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: outside,
            withIntermediateDirectories: true
        )
        let escaped = fixture.layout.packagesRoot.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createSymbolicLink(
            at: escaped,
            withDestinationURL: outside
        )

        XCTAssertThrowsError(
            try fixture.maintenance.quarantinePackage(escaped)
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testManagedSymlinkToAnotherGenerationIsRejected() throws {
        let fixture = try makeFixture()
        addTeardownBlock { try FileManager.default.removeItem(at: fixture.root) }
        let target = try makeGeneration(in: fixture.layout)
        let alias = fixture.layout.makeGenerationRoot()
        try FileManager.default.createSymbolicLink(
            at: alias,
            withDestinationURL: target
        )

        XCTAssertEqual(
            fixture.layout.packageRootKind(alias),
            .outsideLayout
        )
        XCTAssertThrowsError(
            try fixture.maintenance.quarantinePackage(alias)
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
    }

    func testReservedGenerationRootSymlinkIsRejected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let extensions = root.appendingPathComponent(
            "Extensions",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: extensions,
            withIntermediateDirectories: true
        )
        let outside = root.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(
            at: outside,
            withIntermediateDirectories: true
        )
        let layout = ExtensionPackageLayout(extensionsRoot: extensions)
        try FileManager.default.createSymbolicLink(
            at: layout.packagesRoot,
            withDestinationURL: outside
        )

        XCTAssertThrowsError(try layout.createTransactionDirectories())
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    private func makeFixture() throws -> (
        root: URL,
        layout: ExtensionPackageLayout,
        registry: ExtensionPackageGenerationRegistry,
        maintenance: ExtensionPackageMaintenance
    ) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        let extensions = root.appendingPathComponent(
            "Extensions",
            isDirectory: true
        )
        let layout = ExtensionPackageLayout(extensionsRoot: extensions)
        try layout.createTransactionDirectories()
        let registry = ExtensionPackageGenerationRegistry()
        return (
            root,
            layout,
            registry,
            ExtensionPackageMaintenance(
                layout: layout,
                activeGenerations: registry
            )
        )
    }

    private func makeGeneration(
        in layout: ExtensionPackageLayout
    ) throws -> URL {
        let generation = layout.makeGenerationRoot()
        try FileManager.default.createDirectory(
            at: generation,
            withIntermediateDirectories: true
        )
        return generation
    }
}
