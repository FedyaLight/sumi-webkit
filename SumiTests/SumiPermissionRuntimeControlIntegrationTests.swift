import XCTest

final class SumiPermissionRuntimeControlIntegrationTests: XCTestCase {
    func testRuntimeControlsDoNotWritePersistentPermissionDecisionsOrRequestSystemAuthorization() throws {
        let sources = try [
            sourceFile("Sumi/Permissions/UI/SumiPermissionRuntimeControlResult.swift"),
            sourceFile("Sumi/Permissions/UI/SumiPermissionRuntimeControl.swift"),
            sourceFile("Sumi/Permissions/UI/SumiPermissionRuntimeControlsViewModel.swift"),
            sourceFile("Sumi/Permissions/UI/SumiPermissionRuntimeControlsView.swift"),
        ].joined(separator: "\n")

        XCTAssertFalse(sources.contains("SwiftData"))
        XCTAssertFalse(sources.contains("setSiteDecision"))
        XCTAssertFalse(sources.contains("resetSiteDecision"))
        XCTAssertFalse(sources.contains("requestAuthorization"))
        XCTAssertFalse(sources.contains("approveOnce"))
        XCTAssertFalse(sources.contains("denyOnce"))
        XCTAssertFalse(sources.contains("WKPermissionDecision"))
        XCTAssertFalse(sources.contains("decisionHandler"))
        XCTAssertFalse(sources.contains("SitePermissionOverridesStore"))
        XCTAssertFalse(sources.contains("UserDefaults"))
    }

    func testRuntimeControlsDoNotExposeFakeScreenCaptureStop() throws {
        let viewModel = try sourceFile("Sumi/Permissions/UI/SumiPermissionRuntimeControlsViewModel.swift")
        let view = try sourceFile("Sumi/Permissions/UI/SumiPermissionRuntimeControlsView.swift")

        XCTAssertFalse(viewModel.contains("stopScreenCapture"))
        XCTAssertFalse(view.contains("stopScreenCapture"))
        XCTAssertTrue(viewModel.contains("screenSharingControlledByWebKit"))
    }

    func testURLBarIndicatorRoutesRuntimeStatesToPermissionsSubmenuWithoutOverlappingPrompt() throws {
        let source = try [
            sourceFile("Sumi/Components/Sidebar/URLBarView.swift"),
            sourceFile("Sumi/Components/Sidebar/URLBarTrailingActions.swift"),
            sourceFile("Sumi/Components/Sidebar/URLBarPermissionViews.swift"),
        ].joined(separator: "\n")

        XCTAssertTrue(source.contains("permissionPromptPresenter.presentFromIndicatorClick()"))
        XCTAssertTrue(source.contains("prefersRuntimeControlsSurface"))
        XCTAssertTrue(source.contains("hubInitialMode = .permissions"))
        XCTAssertTrue(source.contains("initialMode: hubInitialMode"))
        XCTAssertTrue(source.contains("modeRequestNonce: hubModeRequestNonce"))
        XCTAssertTrue(source.contains(".onChange(of: permissionPromptPresenter.isPresented)"))
        XCTAssertTrue(source.contains("isHubPresented = false"))
    }

    func testRuntimeControlsAreInCurrentSitePermissionsSurfaceOnly() throws {
        let currentSiteView = try sourceFile("Sumi/Permissions/UI/SumiCurrentSitePermissionsView.swift")
        let siteSettingsView = try sourceFile("Sumi/Permissions/UI/SumiSiteSettingsView.swift")
        let siteDetailView = try sourceFile("Sumi/Permissions/UI/SumiSiteSettingsSiteDetailView.swift")

        XCTAssertTrue(currentSiteView.contains("SumiPermissionRuntimeControlsView"))
        XCTAssertTrue(currentSiteView.contains("queryPermissionState"))
        XCTAssertFalse(siteSettingsView.contains("SumiPermissionRuntimeControlsView"))
        XCTAssertFalse(siteDetailView.contains("SumiPermissionRuntimeControlsView"))
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repoRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
