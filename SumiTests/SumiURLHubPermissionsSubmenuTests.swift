import XCTest

@testable import Sumi

final class SumiURLHubPermissionsSubmenuTests: XCTestCase {
    func testURLHubDefinesPermissionsRowBelowCookiesAndUsesSubmenuMode() throws {
        let source = try sourceFile("Sumi/Components/Sidebar/URLBarView.swift")

        XCTAssertTrue(source.contains("case permissions"))
        XCTAssertTrue(source.contains("SumiCurrentSitePermissionsView("))
        XCTAssertTrue(source.contains("title: SumiCurrentSitePermissionsStrings.rowTitle"))
        XCTAssertTrue(source.contains("kind: .permissions"))

        let cookiesRange = try XCTUnwrap(source.range(of: "id: \"cookies\""))
        let permissionsRange = try XCTUnwrap(source.range(of: "rows.append(permissionsRow)"))
        XCTAssertLessThan(cookiesRange.lowerBound, permissionsRange.lowerBound)
    }

    func testURLHubPermissionsRowKeepsCookiesAndTrackingRows() throws {
        let source = try sourceFile("Sumi/Components/Sidebar/URLBarView.swift")

        XCTAssertTrue(source.contains("kind: .cookies"))
        XCTAssertTrue(source.contains("kind: .tracking("))
        XCTAssertTrue(source.contains("setMode(.siteDataDetails, direction: .forward)"))
        XCTAssertTrue(source.contains("setMode(.permissions, direction: .forward)"))
    }

    func testTopLevelAutoplayControlWasMovedOutOfSiteControlsRows() throws {
        let source = try sourceFile("Sumi/Components/Sidebar/URLBarView.swift")

        XCTAssertFalse(source.contains("kind: .autoplay("))
        XCTAssertFalse(source.contains("id: \"autoplay\",\n                        chromeIconName"))
    }

    func testPermissionsSubmenuDoesNotUseForbiddenAPIs() throws {
        let view = try sourceFile("Sumi/Permissions/UI/SumiCurrentSitePermissionsView.swift")
        let viewModel = try sourceFile("Sumi/Permissions/UI/SumiCurrentSitePermissionsViewModel.swift")

        XCTAssertFalse(view.contains("SwiftData"))
        XCTAssertFalse(view.contains("requestAuthorization"))
        XCTAssertFalse(viewModel.contains("requestAuthorization"))
        XCTAssertFalse(view.contains("WKPermissionDecision"))
        XCTAssertFalse(viewModel.contains("WKPermissionDecision"))
        XCTAssertFalse(viewModel.contains("UserDefaults"))
    }

    func testDocumentationRecordsNoDDGImplementationCopy() throws {
        let licenseNotes = try sourceFile("docs/permissions/LICENSE_NOTES.md")

        XCTAssertTrue(licenseNotes.contains("DDG Permission Center"))
        XCTAssertTrue(licenseNotes.localizedCaseInsensitiveContains("no implementation source was copied"))
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        let testsURL = URL(fileURLWithPath: #filePath)
        let repoRoot = testsURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repoRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
