import WebKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
final class SafariExtensionInstallSourceTests: XCTestCase {
    private var scratchDirectory: URL!

    override func setUpWithError() throws {
        scratchDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: scratchDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let scratchDirectory {
            try? FileManager.default.removeItem(at: scratchDirectory)
        }
        scratchDirectory = nil
    }

    func testResolveInstallSourceAcceptsStandaloneAppex() throws {
        let appexURL = try SafariExtensionScannerTestSupport.makeStandaloneAppex(
            in: scratchDirectory,
            specification: .init(
                name: "BitwardenSafari",
                bundleIdentifier: "com.8bit.bitwarden.safari",
                displayName: "Bitwarden"
            )
        )

        let resolved = try ExtensionManager.resolveInstallSource(at: appexURL)

        XCTAssertEqual(resolved.sourceKind, .safariAppExtension)
        XCTAssertEqual(resolved.appexBundleURL, appexURL)
        XCTAssertEqual(resolved.sourceBundlePath, appexURL)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: resolved.resourcesURL.appendingPathComponent("manifest.json").path
            )
        )
    }

    func testResolveInstallSourceAcceptsContainingAppWithSingleExtension() throws {
        let appURL = try SafariExtensionScannerTestSupport.makeContainingAppBundle(
            in: scratchDirectory,
            appName: "ProtonPass",
            extensions: [
                .init(
                    name: "ProtonPassSafari",
                    bundleIdentifier: "ch.protonmail.pass.safari",
                    displayName: "Proton Pass"
                ),
            ]
        )

        let resolved = try ExtensionManager.resolveInstallSource(at: appURL)

        XCTAssertEqual(resolved.sourceKind, .safariAppExtension)
        XCTAssertEqual(resolved.appexBundleURL?.lastPathComponent, "ProtonPassSafari.appex")
        XCTAssertTrue(resolved.sourceBundlePath.path.hasSuffix(".appex"))
    }

    func testResolveInstallSourceRejectsContainingAppWithMultipleExtensions() throws {
        let appURL = try SafariExtensionScannerTestSupport.makeContainingAppBundle(
            in: scratchDirectory,
            appName: "MultiExtensionApp",
            extensions: [
                .init(
                    name: "ExtensionA",
                    bundleIdentifier: "com.example.a",
                    displayName: "Extension A"
                ),
                .init(
                    name: "ExtensionB",
                    bundleIdentifier: "com.example.b",
                    displayName: "Extension B"
                ),
            ]
        )

        XCTAssertThrowsError(try ExtensionManager.resolveInstallSource(at: appURL)) { error in
            let message = (error as? ExtensionError)?.errorDescription ?? ""
            XCTAssertTrue(message.contains("multiple Safari Web Extensions"))
        }
    }

    func testResolveInstallSourceRejectsNonSafariAppex() throws {
        let appexURL = try SafariExtensionScannerTestSupport.makeStandaloneAppex(
            in: scratchDirectory,
            specification: .init(
                name: "ShareExtension",
                bundleIdentifier: "com.example.share",
                displayName: "Share",
                extensionPointIdentifier: "com.apple.share-services"
            )
        )

        XCTAssertThrowsError(try ExtensionManager.resolveInstallSource(at: appexURL)) { error in
            let message = (error as? ExtensionError)?.errorDescription ?? ""
            XCTAssertTrue(message.contains("not a Safari Web Extension"))
        }
    }

    func testResolveInstallSourceStillAcceptsUnpackedDirectory() throws {
        let directoryURL = scratchDirectory.appendingPathComponent("unpacked", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Directory Extension",
            "version": "1.0",
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        try data.write(
            to: directoryURL.appendingPathComponent("manifest.json"),
            options: [.atomic]
        )

        let resolved = try ExtensionManager.resolveInstallSource(at: directoryURL)

        XCTAssertEqual(resolved.sourceKind, .directory)
        XCTAssertNil(resolved.appexBundleURL)
        XCTAssertEqual(resolved.resourcesURL, directoryURL)
    }

    func testInstalledAppexBundleURLRequiresSafariSourceKind() {
        XCTAssertNil(
            SafariAppExtensionResources.installedAppexBundleURL(
                sourceKind: .directory,
                sourceBundlePath: "/tmp/example.appex"
            )
        )
    }

    func testInstalledAppexBundleURLResolvesReadableAppex() throws {
        let appexURL = try SafariExtensionScannerTestSupport.makeStandaloneAppex(
            in: scratchDirectory,
            specification: .init(
                name: "BitwardenSafari",
                bundleIdentifier: "com.bitwarden.desktop.safari",
                displayName: "Bitwarden"
            )
        )

        let resolved = SafariAppExtensionResources.installedAppexBundleURL(
            sourceKind: .safariAppExtension,
            sourceBundlePath: appexURL.path
        )

        XCTAssertEqual(resolved, appexURL.standardizedFileURL)
    }

    @available(macOS 15.5, *)
    func testSafariAppExtensionRuntimeFactoryDoesNotExposeCopiedResourceFallback() throws {
        let source = try String(
            contentsOf: projectURL(
                "Sumi/Managers/ExtensionManager/SafariExtension/SafariAppExtensionResources.swift"
            )
        )

        XCTAssertFalse(source.contains("copyResources"))
        XCTAssertFalse(source.contains("falling back to copied package"))
    }

    @available(macOS 15.5, *)
    func testMakeWebExtensionFailsClosedWhenSafariAppexMissing() async throws {
        let packageRoot = scratchDirectory.appendingPathComponent("package", isDirectory: true)
        try FileManager.default.createDirectory(at: packageRoot, withIntermediateDirectories: true)
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": "Fallback Extension",
            "version": "1.0",
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        try data.write(to: packageRoot.appendingPathComponent("manifest.json"), options: [.atomic])

        do {
            _ = try await SafariAppExtensionResources.makeWebExtension(
                sourceKind: .safariAppExtension,
                sourceBundlePath: "/tmp/missing.appex",
                packageRoot: packageRoot
            )
            XCTFail("Safari .appex runtime must not fall back to a copied package")
        } catch let error as ExtensionError {
            XCTAssertTrue(error.localizedDescription.contains("unavailable"))
        }
    }

    @available(macOS 15.5, *)
    func testRealInstalledAppexBundleLoadsViaWebKitWhenPresent() async throws {
        let roots = SafariExtensionScanner.defaultApplicationSearchRoots()
        let scanner = SafariExtensionScanner()
        var issues: [SafariExtensionScannerIssue] = []
        let discovered = scanner.scanInstalledExtensions(
            applicationSearchRoots: roots,
            issues: &issues
        )

        for target in SafariExtensionCompatibilityTargets.all {
            guard let candidate = discovered.first(where: {
                $0.extensionBundleIdentifier == target.expectedAppexBundleIdentifier
            }) else {
                continue
            }

            guard let bundle = Bundle(url: candidate.appexURL) else {
                XCTFail("Could not open installed appex bundle for \(target.key)")
                continue
            }

            let webExtension = try await WKWebExtension(appExtensionBundle: bundle)
            let displayName = await MainActor.run { webExtension.displayName }
            XCTAssertFalse(displayName?.isEmpty ?? true)

            let resourcesRoot = try SafariAppExtensionResources.resourcesRoot(
                in: candidate.appexURL
            )
            let loadResult = try await SafariAppExtensionResources.makeWebExtension(
                sourceKind: .safariAppExtension,
                sourceBundlePath: candidate.appexURL.path,
                packageRoot: resourcesRoot
            )
            XCTAssertEqual(loadResult.loadSource, .originalAppexBundle)
        }
    }

    func testResolvedSafariSourceUsesOriginalBundleResourcesRoot() throws {
        let appexURL = try SafariExtensionScannerTestSupport.makeStandaloneAppex(
            in: scratchDirectory,
            specification: .init(
                name: "RaindropSafari",
                bundleIdentifier: "io.raindrop.safari",
                displayName: "Raindrop"
            )
        )
        let resolved = try ExtensionManager.resolveInstallSource(at: appexURL)

        XCTAssertEqual(resolved.sourceKind, .safariAppExtension)
        XCTAssertEqual(resolved.sourceBundlePath, appexURL)
        XCTAssertTrue(resolved.resourcesURL.path.contains(".appex/Contents"))
    }

    private func projectURL(_ path: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(path)
    }
}
