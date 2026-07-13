import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class ExtensionInstallationPackageIntegrityTests: XCTestCase {
    func testCopiedManifestDriftBeforeMaterializationIsRejectedAndReversible()
        throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let extensions = root.appendingPathComponent(
            "Extensions",
            isDirectory: true
        )
        try writeManifest(name: "Original", at: source)
        let resolved = try ExtensionInstallSourceResolver.resolve(at: source)
        let package = try ExtensionInstallationPackage.prepare(
            source: resolved,
            extensionsDirectory: extensions,
            activeGenerations: ExtensionPackageGenerationRegistry()
        )
        let layout = ExtensionPackageLayout(extensionsRoot: extensions)
        let staged = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(
                at: layout.stagingRoot,
                includingPropertiesForKeys: nil
            ).first
        )
        try writeManifest(name: "Changed", at: staged)

        XCTAssertThrowsError(
            try package.materialize(extensionID: "integrity.example")
        )
        try package.rollback()

        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(
                at: layout.stagingRoot,
                includingPropertiesForKeys: nil
            ).isEmpty
        )
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(
                at: layout.packagesRoot,
                includingPropertiesForKeys: nil
            ).isEmpty
        )
    }

    private func writeManifest(name: String, at root: URL) throws {
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": name,
            "version": "1.0",
        ]
        try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.sortedKeys]
        ).write(to: root.appendingPathComponent("manifest.json"))
    }
}
