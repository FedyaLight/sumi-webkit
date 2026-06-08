//
//  ChromeMV3LiveUsablePopupFixtureLocation.swift
//  Sumi
//
//  DEBUG-only resolver for the mv3-sumi-usable-popup manual verification fixture.
//

import Foundation

#if DEBUG

enum ChromeMV3LiveUsablePopupFixtureLocation {
    static let packageDirectoryName = "mv3-sumi-usable-popup"
    static let fixtureEnvironmentVariable = "SUMI_MV3_USABLE_POPUP_FIXTURE_ROOT"

    static let manualVerificationSummary = """
    mv3-sumi-usable-popup is a test fixture, not installed automatically.
    1. Fixture folder: SumiTests/Fixtures/mv3-sumi-usable-popup/ in the Sumi-webkit repo.
    2. In DEBUG Sumi: Settings → Extensions → Local Experimental MV3 → Install Usable Popup Fixture.
       This uses the same local unpacked / generated-bundle / URL-hub / controlled-popup path as other MV3 extensions.
    3. Enable the extension, open any normal tab, then open the URL-hub and click the extension action tile.
    4. Capture console lines prefixed with [live-popup-product-path] and grouped BEGIN/END live-popup-staged-summary blocks.
    Optional: set SUMI_MV3_USABLE_POPUP_FIXTURE_ROOT to an absolute path when the repo fixture is not discoverable.
    """

    static func packageRoot(file: StaticString = #filePath) -> URL? {
        if let environmentRoot = packageRootFromEnvironment() {
            return environmentRoot
        }
        if let repositoryRoot = packageRootFromRepository(file: file) {
            return repositoryRoot
        }
        return packageRootFromWorkingDirectory()
    }

    static func resolvedPathDescription(file: StaticString = #filePath) -> String {
        packageRoot(file: file)?.path ?? "not-found"
    }

    private static func packageRootFromEnvironment() -> URL? {
        guard
            let raw = ProcessInfo.processInfo.environment[fixtureEnvironmentVariable]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            raw.isEmpty == false
        else { return nil }
        let url = URL(fileURLWithPath: raw, isDirectory: true).standardizedFileURL
        return manifestExists(at: url) ? url : nil
    }

    private static func packageRootFromRepository(file: StaticString) -> URL? {
        var url = URL(fileURLWithPath: "\(file)")
        for _ in 0 ..< 10 {
            url.deleteLastPathComponent()
            let candidate = url
                .appendingPathComponent("SumiTests/Fixtures/\(packageDirectoryName)", isDirectory: true)
                .standardizedFileURL
            if manifestExists(at: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func packageRootFromWorkingDirectory() -> URL? {
        var url = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        ).standardizedFileURL
        for _ in 0 ..< 8 {
            let candidate = url
                .appendingPathComponent("SumiTests/Fixtures/\(packageDirectoryName)", isDirectory: true)
                .standardizedFileURL
            if manifestExists(at: candidate) {
                return candidate
            }
            url.deleteLastPathComponent()
        }
        return nil
    }

    private static func manifestExists(at url: URL) -> Bool {
        FileManager.default.fileExists(
            atPath: url.appendingPathComponent("manifest.json").path
        )
    }
}

#endif
