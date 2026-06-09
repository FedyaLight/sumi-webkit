import XCTest

@testable import Sumi

@MainActor
final class SafariExtensionImportAutoEnableTests: XCTestCase {
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testImportSafariAppExtensionSourceEnablesAfterImport() throws {
        let source = try String(
            contentsOf: repoRoot.appendingPathComponent(
                "Sumi/Managers/ExtensionManager/SumiExtensionsModule.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("enableExtension(installed.id)"))
        XCTAssertTrue(source.contains("enableOnInstall: false"))
        XCTAssertTrue(source.contains("importSucceededEnableFailed"))
    }

    func testImportCandidatesSectionDoesNotAutoEnableDiscoveredCandidates() throws {
        let source = try String(
            contentsOf: repoRoot.appendingPathComponent(
                "Sumi/Components/Settings/SafariExtensionImportCandidatesSection.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("importCandidate"))
        XCTAssertFalse(source.contains("enableExtension"))
    }

    func testImportSucceededEnableFailedErrorDescription() {
        let error = ExtensionError.importSucceededEnableFailed(
            "Raindrop was imported but could not be enabled: runtime unavailable"
        )
        XCTAssertEqual(
            error.errorDescription,
            "Raindrop was imported but could not be enabled: runtime unavailable"
        )
    }
}
