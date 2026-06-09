import XCTest

@testable import Sumi

final class SafariExtensionImportStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: SafariExtensionImportStore!

    override func setUp() {
        suiteName = "SafariExtensionImportStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        store = SafariExtensionImportStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        suiteName = nil
        defaults = nil
        store = nil
    }

    func testRefreshAndImportableCandidatesExcludeInstalledBundlePaths() {
        let candidate = makeCandidate(
            bundleIdentifier: "com.example.safari",
            appexPath: "/Applications/Example.app/Contents/PlugIns/Example.appex"
        )

        store.refreshDiscoveredCandidates([candidate])
        XCTAssertEqual(store.importableCandidates().count, 1)

        store.markImported(candidate: candidate, installedExtensionId: "installed-1")
        XCTAssertTrue(store.isImported(extensionBundleIdentifier: candidate.extensionBundleIdentifier))
        XCTAssertEqual(
            store.importedExtensionId(forExtensionBundleIdentifier: candidate.extensionBundleIdentifier),
            "installed-1"
        )
        XCTAssertEqual(store.importableCandidates().count, 1)

        let filtered = store.importableCandidates(
            excludingInstalledBundlePaths: [candidate.appexURL.path]
        )
        XCTAssertTrue(filtered.isEmpty)
    }

    func testRemoveImportedRecordClearsImportHistory() {
        let candidate = makeCandidate(
            bundleIdentifier: "com.example.safari",
            appexPath: "/Applications/Example.app/Contents/PlugIns/Example.appex"
        )

        store.refreshDiscoveredCandidates([candidate])
        store.markImported(candidate: candidate, installedExtensionId: "installed-1")

        store.removeImportedRecord(forInstalledExtensionId: "installed-1")

        XCTAssertFalse(store.isImported(extensionBundleIdentifier: candidate.extensionBundleIdentifier))
        XCTAssertNil(
            store.importedExtensionId(forExtensionBundleIdentifier: candidate.extensionBundleIdentifier)
        )
    }

    func testRemoveImportedRecordByBundleIdentifier() {
        let candidate = makeCandidate(
            bundleIdentifier: "com.example.other",
            appexPath: "/Applications/Other.app/Contents/PlugIns/Other.appex"
        )

        store.markImported(candidate: candidate, installedExtensionId: "installed-2")
        store.removeImportedRecord(extensionBundleIdentifier: candidate.extensionBundleIdentifier)

        XCTAssertFalse(store.isImported(extensionBundleIdentifier: candidate.extensionBundleIdentifier))
    }

    func testScanImportDeleteRescanLifecycle() throws {
        let scratchDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scratchDirectory) }

        let appsDirectory = scratchDirectory.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: appsDirectory, withIntermediateDirectories: true)

        let appURL = try SafariExtensionScannerTestSupport.makeContainingAppBundle(
            in: appsDirectory,
            appName: "Raindrop",
            extensions: [
                .init(
                    name: "Raindrop",
                    bundleIdentifier: "io.raindrop.raindropio.safari",
                    displayName: "Raindrop"
                ),
            ]
        )

        var issues: [SafariExtensionScannerIssue] = []
        let discovered = SafariExtensionScanner().scanInstalledExtensions(
            applicationSearchRoots: [appsDirectory],
            issues: &issues
        )
        XCTAssertEqual(discovered.count, 1)
        store.refreshDiscoveredCandidates(discovered)
        XCTAssertEqual(store.importableCandidates().count, 1)

        let candidate = discovered[0]
        store.markImported(candidate: candidate, installedExtensionId: "sumi-ext-1")
        XCTAssertEqual(
            store.importableCandidates(
                excludingInstalledBundlePaths: [candidate.appexURL.path]
            ).count,
            0
        )

        store.removeImportedRecord(forInstalledExtensionId: "sumi-ext-1")
        XCTAssertEqual(store.importableCandidates().count, 1)

        var rescanIssues: [SafariExtensionScannerIssue] = []
        let rescanned = SafariExtensionScanner().scanInstalledExtensions(
            applicationSearchRoots: [appsDirectory],
            issues: &rescanIssues
        )
        store.refreshDiscoveredCandidates(rescanned)
        XCTAssertEqual(store.importableCandidates().count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: appURL.path))
    }

    func testDuplicateCandidatesRemainAfterDeleteAndRescan() throws {
        let scratchDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scratchDirectory) }

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

        var issues: [SafariExtensionScannerIssue] = []
        let discovered = SafariExtensionScanner().scanInstalledExtensions(
            applicationSearchRoots: [appsDirectory],
            issues: &issues
        )
        store.refreshDiscoveredCandidates(discovered)

        XCTAssertEqual(discovered.count, 2)
        XCTAssertTrue(
            issues.contains {
                if case .duplicateExtensionIdentifier("io.raindrop.raindropio.safari") = $0 {
                    return true
                }
                return false
            }
        )

        store.markImported(
            candidate: discovered[0],
            installedExtensionId: "sumi-ext-dup"
        )
        store.removeImportedRecord(forInstalledExtensionId: "sumi-ext-dup")

        let rescanned = SafariExtensionScanner().scanInstalledExtensions(
            applicationSearchRoots: [appsDirectory],
            issues: &issues
        )
        store.refreshDiscoveredCandidates(rescanned)
        XCTAssertEqual(store.importableCandidates().count, 2)
    }

    private func makeCandidate(
        bundleIdentifier: String,
        appexPath: String
    ) -> DiscoveredSafariExtensionCandidate {
        DiscoveredSafariExtensionCandidate(
            extensionBundleIdentifier: bundleIdentifier,
            displayName: "Example",
            version: "1.0",
            extensionPointIdentifier: SafariExtensionScanner.safariWebExtensionPointIdentifier,
            containingAppName: "Example App",
            containingAppBundleIdentifier: "com.example.app",
            containingAppURL: URL(fileURLWithPath: "/Applications/Example.app"),
            appexURL: URL(fileURLWithPath: appexPath),
            manifestURL: nil,
            isReadable: true
        )
    }
}
