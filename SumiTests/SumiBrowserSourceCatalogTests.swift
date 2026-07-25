import XCTest

@testable import Sumi

final class SumiBrowserSourceCatalogTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiBrowserSourceCatalogTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    func testDetectsChromiumProfilesWithTheirDisplayNames() throws {
        let userData = try makeDirectory("Library/Application Support/Google/Chrome")
        try write(
            [
                "profile": [
                    "info_cache": [
                        "Default": ["name": "Personal"],
                        "Profile 1": ["name": "Work"],
                    ]
                ]
            ],
            to: userData.appendingPathComponent("Local State")
        )
        for directory in ["Default", "Profile 1"] {
            let profile = try makeDirectory("Library/Application Support/Google/Chrome/\(directory)")
            try Data("{}".utf8).write(to: profile.appendingPathComponent("Bookmarks"))
        }
        // Support directories are not profiles.
        _ = try makeDirectory("Library/Application Support/Google/Chrome/ShaderCache")

        let chrome = try XCTUnwrap(detect().first { $0.id == "chrome" })

        XCTAssertEqual(chrome.profiles.map(\.displayName), ["Personal", "Work"])
        XCTAssertEqual(chrome.profiles.map(\.sourceDirectoryKey), ["Default", "Profile 1"])
        XCTAssertNil(chrome.accessIssue)
    }

    /// Under TCC the Safari directory exists but cannot be listed. Reporting
    /// "not installed" would tell the user the wrong thing and offer no remedy.
    func testSafariUnreadableDirectoryReportsFullDiskAccess() throws {
        let safari = try makeDirectory("Library/Safari")
        // 0o000 makes the listing fail with the same EPERM shape TCC produces.
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: safari.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: safari.path) }

        let detected = try XCTUnwrap(detect().first { $0.id == "safari" })

        XCTAssertEqual(detected.accessIssue, .fullDiskAccessRequired)
        XCTAssertFalse(detected.isImportable)
    }

    func testRunningBrowserIsStillImportableButFlagged() throws {
        let userData = try makeDirectory("Library/Application Support/BraveSoftware/Brave-Browser/Default")
        try Data("{}".utf8).write(to: userData.appendingPathComponent("Bookmarks"))

        let brave = try XCTUnwrap(
            detect(applications: RunningApplications(running: ["com.brave.Browser"]))
                .first { $0.id == "brave" }
        )

        XCTAssertEqual(brave.accessIssue, .sourceBrowserRunning("Brave"))
        XCTAssertTrue(brave.isImportable, "a running browser can still be imported from its snapshot")
    }

    func testBrowserWithNeitherApplicationNorDataIsNotListed() {
        XCTAssertTrue(detect().isEmpty)
    }

    /// A leftover support folder from an uninstalled browser must not be
    /// offered as a broken source the user is invited to fix.
    func testUninstalledBrowserWithEmptyLeftoverFolderIsNotListed() throws {
        _ = try makeDirectory("Library/Application Support/Chromium")

        XCTAssertTrue(detect().isEmpty)
    }

    func testInstalledBrowserWithoutProfilesReportsNoProfiles() throws {
        let detected = try XCTUnwrap(
            detect(applications: RunningApplications(installed: ["com.google.Chrome"]))
                .first { $0.id == "chrome" }
        )

        XCTAssertEqual(detected.accessIssue, .noProfilesFound)
        XCTAssertFalse(detected.isImportable)
    }

    func testEverySourceKindIsDistinctPerFamily() {
        // The identity resolver namespaces imported ids by source kind, so two
        // families sharing a kind would collide.
        let kinds = Dictionary(
            grouping: SumiBrowserSourceCatalog.vendors,
            by: \.family
        ).mapValues { Set($0.map(\.sourceKind)) }

        for (family, sourceKinds) in kinds {
            XCTAssertEqual(sourceKinds.count, 1, "\(family) maps to more than one source kind")
        }
        XCTAssertEqual(Set(kinds.values.flatMap { $0 }).count, kinds.count)
    }

    // MARK: - Helpers

    private func detect(
        applications: any SumiInstalledApplicationLocating = RunningApplications()
    ) -> [SumiDetectedBrowser] {
        SumiBrowserSourceCatalog.detect(homeDirectory: home, applications: applications)
    }

    private func makeDirectory(_ relativePath: String) throws -> URL {
        let url = home.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ object: [String: Any], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: object).write(to: url)
    }

    private struct RunningApplications: SumiInstalledApplicationLocating {
        var installed: Set<String> = []
        var running: Set<String> = []

        func isInstalled(bundleIdentifier: String) -> Bool {
            installed.contains(bundleIdentifier) || running.contains(bundleIdentifier)
        }

        func isRunning(bundleIdentifier: String) -> Bool {
            running.contains(bundleIdentifier)
        }
    }
}
