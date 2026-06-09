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

    func testRefreshAndImportableCandidatesExcludeImported() {
        let candidate = DiscoveredSafariExtensionCandidate(
            extensionBundleIdentifier: "com.example.safari",
            displayName: "Example",
            version: "1.0",
            extensionPointIdentifier: SafariExtensionScanner.safariWebExtensionPointIdentifier,
            containingAppName: "Example App",
            containingAppBundleIdentifier: "com.example.app",
            containingAppURL: URL(fileURLWithPath: "/Applications/Example.app"),
            appexURL: URL(fileURLWithPath: "/Applications/Example.app/Contents/PlugIns/Example.appex"),
            manifestURL: nil,
            isReadable: true
        )

        store.refreshDiscoveredCandidates([candidate])
        XCTAssertEqual(store.importableCandidates().count, 1)

        store.markImported(candidate: candidate, installedExtensionId: "installed-1")
        XCTAssertTrue(store.isImported(extensionBundleIdentifier: candidate.extensionBundleIdentifier))
        XCTAssertEqual(
            store.importedExtensionId(forExtensionBundleIdentifier: candidate.extensionBundleIdentifier),
            "installed-1"
        )
        XCTAssertTrue(store.importableCandidates().isEmpty)
    }

    func testImportableCandidatesExcludeInstalledBundlePaths() {
        let candidate = DiscoveredSafariExtensionCandidate(
            extensionBundleIdentifier: "com.example.other",
            displayName: "Other",
            version: nil,
            extensionPointIdentifier: SafariExtensionScanner.safariWebExtensionPointIdentifier,
            containingAppName: "Other App",
            containingAppBundleIdentifier: nil,
            containingAppURL: URL(fileURLWithPath: "/Applications/Other.app"),
            appexURL: URL(fileURLWithPath: "/tmp/Other.appex"),
            manifestURL: nil,
            isReadable: true
        )

        store.refreshDiscoveredCandidates([candidate])
        let filtered = store.importableCandidates(
            excludingInstalledBundlePaths: [candidate.appexURL.path]
        )
        XCTAssertTrue(filtered.isEmpty)
    }
}
