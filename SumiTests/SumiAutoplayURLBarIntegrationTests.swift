import XCTest

@testable import Sumi

final class SumiAutoplayURLBarIntegrationTests: XCTestCase {
    func testURLBarAutoplayRowUsesCanonicalStoreAdapter() throws {
        let source = try sourceFile("Sumi/Components/Sidebar/URLBarView.swift")

        XCTAssertTrue(source.contains("SumiAutoplayPolicyStoreAdapter.shared"))
        XCTAssertTrue(source.contains(".setPolicy("))
        XCTAssertTrue(source.contains(".resetPolicy("))
        XCTAssertFalse(source.contains("SitePermissionOverridesStore"))
        XCTAssertFalse(source.contains("AutoplayOverrideState"))
    }

    func testBrowserConfigNoLongerDefinesOldAutoplayOverrideStore() throws {
        let source = try sourceFile("Sumi/Models/BrowserConfig/BrowserConfig.swift")

        XCTAssertTrue(source.contains("applyAutoplayPolicy"))
        XCTAssertTrue(source.contains("resolvedAutoplayPolicy"))
        XCTAssertFalse(source.contains("SitePermissionOverridesStore"))
        XCTAssertFalse(source.contains("AutoplayOverrideState"))
        XCTAssertFalse(source.contains("settings.sitePermissionOverrides.autoplay"))
    }

    func testNormalTabRuntimeUsesCanonicalAutoplayPolicyResolution() throws {
        let source = try sourceFile("Sumi/Models/Tab/Tab+WebViewRuntime.swift")

        XCTAssertTrue(source.contains("resolvedAutoplayPolicy"))
        XCTAssertFalse(source.contains("applySitePermissionOverrides"))
        XCTAssertFalse(source.contains("SitePermissionOverridesStore"))
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
