import XCTest

@testable import Sumi

final class SafariExtensionScannerTests: XCTestCase {
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

    func testDiscoversSafariWebExtensionInsideAppBundle() throws {
        let appURL = try SafariExtensionScannerTestSupport.makeContainingAppBundle(
            in: scratchDirectory,
            appName: "Bitwarden",
            appBundleIdentifier: "com.8bit.bitwarden.desktop",
            extensions: [
                .init(
                    name: "Bitwarden Extension",
                    bundleIdentifier: "com.8bit.bitwarden.desktop.safari",
                    displayName: "Bitwarden",
                    version: "2026.1.0"
                ),
            ]
        )

        let scanner = SafariExtensionScanner()
        var issues: [SafariExtensionScannerIssue] = []
        let candidates = scanner.inspectContainingAppBundle(at: appURL, issues: &issues)

        XCTAssertTrue(issues.isEmpty)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].extensionBundleIdentifier, "com.8bit.bitwarden.desktop.safari")
        XCTAssertEqual(candidates[0].displayName, "Bitwarden")
        XCTAssertEqual(candidates[0].version, "2026.1.0")
        XCTAssertEqual(candidates[0].containingAppBundleIdentifier, "com.8bit.bitwarden.desktop")
        XCTAssertNotNil(candidates[0].manifestURL)
    }

    func testDiscoversSafariContentBlockerInsideAppBundle() throws {
        let appURL = try SafariExtensionScannerTestSupport.makeContainingAppBundle(
            in: scratchDirectory,
            appName: "Content Shield",
            appBundleIdentifier: "com.example.contentshield",
            extensions: [
                .init(
                    name: "General Blocker",
                    bundleIdentifier: "com.example.contentshield.general",
                    displayName: "General",
                    extensionPointIdentifier: SafariExtensionScanner.safariContentBlockerExtensionPointIdentifier,
                    includeManifest: false,
                    includeExtensionAttributes: false
                ),
            ]
        )

        let scanner = SafariExtensionScanner()
        var issues: [SafariExtensionScannerIssue] = []
        let candidates = scanner.inspectContainingAppBundle(at: appURL, issues: &issues)

        XCTAssertTrue(issues.isEmpty)
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].extensionBundleIdentifier, "com.example.contentshield.general")
        XCTAssertEqual(candidates[0].bundleKind, .contentBlocker)
        XCTAssertEqual(candidates[0].runtimeStatus, .contentBlockerImportable)
        XCTAssertNil(candidates[0].manifestURL)
    }

    func testDiscoversLegacySafariAppExtensionAsUnsupportedCandidate() throws {
        let appexURL = try SafariExtensionScannerTestSupport.makeStandaloneAppex(
            in: scratchDirectory,
            specification: .init(
                name: "PopupExtension",
                bundleIdentifier: "com.example.legacy.popup",
                displayName: "Popup Extension",
                extensionPointIdentifier: SafariExtensionScanner.legacySafariExtensionPointIdentifier,
                includeManifest: false,
                includeExtensionAttributes: false
            )
        )

        let scanner = SafariExtensionScanner()
        var issues: [SafariExtensionScannerIssue] = []
        let candidate = scanner.inspectAppexBundle(at: appexURL, issues: &issues)

        XCTAssertTrue(issues.isEmpty)
        XCTAssertEqual(candidate?.bundleKind, .legacySafariAppExtension)
        XCTAssertEqual(candidate?.runtimeStatus, .unsupportedLegacySafariAppExtension)
        XCTAssertNil(candidate?.manifestURL)
    }

    func testDiscoversMultipleSafariAppexKindsInsideSameAppBundle() throws {
        let appsDirectory = scratchDirectory.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: appsDirectory, withIntermediateDirectories: true)

        _ = try SafariExtensionScannerTestSupport.makeContainingAppBundle(
            in: appsDirectory,
            appName: "Mixed",
            appBundleIdentifier: "com.example.mixed",
            extensions: [
                .init(
                    name: "Mixed Web",
                    bundleIdentifier: "com.example.mixed.web",
                    displayName: "Mixed Web"
                ),
                .init(
                    name: "Mixed Blocker",
                    bundleIdentifier: "com.example.mixed.blocker",
                    displayName: "Mixed Blocker",
                    extensionPointIdentifier: SafariExtensionScanner.safariContentBlockerExtensionPointIdentifier,
                    includeManifest: false,
                    includeExtensionAttributes: false
                ),
                .init(
                    name: "Mixed Legacy",
                    bundleIdentifier: "com.example.mixed.legacy",
                    displayName: "Mixed Legacy",
                    extensionPointIdentifier: SafariExtensionScanner.legacySafariExtensionPointIdentifier,
                    includeManifest: false,
                    includeExtensionAttributes: false
                ),
            ]
        )

        let scanner = SafariExtensionScanner()
        var issues: [SafariExtensionScannerIssue] = []
        let candidates = scanner.scanInstalledExtensions(
            applicationSearchRoots: [appsDirectory],
            issues: &issues
        )

        XCTAssertTrue(issues.isEmpty)
        XCTAssertEqual(Set(candidates.map(\.bundleKind)), [.webExtension, .contentBlocker, .legacySafariAppExtension])
        XCTAssertEqual(candidates.count, 3)
    }

    func testRejectsNonSafariAppex() throws {
        let appexURL = try SafariExtensionScannerTestSupport.makeStandaloneAppex(
            in: scratchDirectory,
            specification: .init(
                name: "ShareExtension",
                bundleIdentifier: "com.example.share",
                displayName: "Share",
                extensionPointIdentifier: "com.apple.share-services"
            )
        )

        let scanner = SafariExtensionScanner()
        var issues: [SafariExtensionScannerIssue] = []
        let candidate = scanner.inspectAppexBundle(at: appexURL, issues: &issues)

        XCTAssertNil(candidate)
        XCTAssertEqual(issues.count, 1)
        if case let .invalidExtensionPoint(url, found) = issues[0] {
            XCTAssertEqual(url, appexURL)
            XCTAssertEqual(found, "com.apple.share-services")
        } else {
            XCTFail("Expected invalidExtensionPoint issue")
        }
    }

    func testMissingManifestIsReportedButCandidateStillReturned() throws {
        let appexURL = try SafariExtensionScannerTestSupport.makeStandaloneAppex(
            in: scratchDirectory,
            specification: .init(
                name: "Broken",
                bundleIdentifier: "com.example.broken",
                displayName: "Broken",
                includeManifest: false
            )
        )

        let scanner = SafariExtensionScanner()
        var issues: [SafariExtensionScannerIssue] = []
        let candidate = scanner.inspectAppexBundle(at: appexURL, issues: &issues)

        XCTAssertNotNil(candidate)
        XCTAssertNil(candidate?.manifestURL)
        XCTAssertTrue(issues.contains { issue in
            if case let .missingManifest(url) = issue {
                return url == appexURL
            }
            return false
        })
    }

    func testCorruptInfoPlistIsRejected() throws {
        let appexURL = try SafariExtensionScannerTestSupport.makeStandaloneAppex(
            in: scratchDirectory,
            specification: .init(
                name: "Corrupt",
                bundleIdentifier: "com.example.corrupt",
                displayName: "Corrupt",
                corruptPlist: true
            )
        )

        let scanner = SafariExtensionScanner()
        var issues: [SafariExtensionScannerIssue] = []
        let candidate = scanner.inspectAppexBundle(at: appexURL, issues: &issues)

        XCTAssertNil(candidate)
        XCTAssertEqual(issues.count, 1)
        if case let .invalidExtensionPoint(url, found) = issues[0] {
            XCTAssertEqual(url, appexURL)
            XCTAssertNil(found)
        } else {
            XCTFail("Expected invalidExtensionPoint for corrupt plist")
        }
    }

    func testScanReportsDuplicateExtensionIdentifiers() throws {
        let appsDirectory = scratchDirectory.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: appsDirectory, withIntermediateDirectories: true)

        _ = try SafariExtensionScannerTestSupport.makeContainingAppBundle(
            in: appsDirectory,
            appName: "RaindropA",
            extensions: [
                .init(
                    name: "Raindrop",
                    bundleIdentifier: "io.raindrop.raindropio.safari",
                    displayName: "Raindrop"
                ),
            ]
        )
        _ = try SafariExtensionScannerTestSupport.makeContainingAppBundle(
            in: appsDirectory,
            appName: "RaindropB",
            extensions: [
                .init(
                    name: "Raindrop",
                    bundleIdentifier: "io.raindrop.raindropio.safari",
                    displayName: "Raindrop Duplicate"
                ),
            ]
        )

        let scanner = SafariExtensionScanner()
        var issues: [SafariExtensionScannerIssue] = []
        let candidates = scanner.scanInstalledExtensions(
            applicationSearchRoots: [appsDirectory],
            issues: &issues
        )

        XCTAssertEqual(candidates.count, 2)
        XCTAssertTrue(
            issues.contains {
                if case .duplicateExtensionIdentifier("io.raindrop.raindropio.safari") = $0 {
                    return true
                }
                return false
            }
        )
    }

    func testAppWithoutPluginsProducesNoCandidates() throws {
        let appURL = scratchDirectory.appendingPathComponent("Empty.app", isDirectory: true)
        try FileManager.default.createDirectory(
            at: appURL.appendingPathComponent("Contents", isDirectory: true),
            withIntermediateDirectories: true
        )

        let scanner = SafariExtensionScanner()
        var issues: [SafariExtensionScannerIssue] = []
        let candidates = scanner.inspectContainingAppBundle(at: appURL, issues: &issues)

        XCTAssertTrue(candidates.isEmpty)
        XCTAssertTrue(issues.isEmpty)
    }
}
