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

    func testURLBarIndicatorRoutesRuntimeStatesToPopoverWithoutOverlappingPrompt() throws {
        let source = try [
            sourceFile("Sumi/Components/Sidebar/URLBarView.swift"),
            sourceFile("Sumi/Components/Sidebar/URLBarTrailingActions.swift"),
            sourceFile("Sumi/Components/Sidebar/URLBarPermissionViews.swift"),
        ].joined(separator: "\n")

        XCTAssertTrue(source.contains("permissionPromptPresenter.presentFromIndicatorClick()"))
        XCTAssertFalse(source.contains("initialMode: .permissions"))
        XCTAssertFalse(source.contains("browserManager.presentURLBarHubPopover(in: windowState, initialMode: .controls)"))
        XCTAssertTrue(source.contains("URLBarHubPopoverAnchorView("))
        XCTAssertTrue(source.contains(".onChange(of: permissionPromptPresenter.isPresented)"))
        XCTAssertTrue(source.contains("browserManager.closeURLBarHubPopover(in: windowState)"))
        XCTAssertTrue(source.contains("SumiPermissionIndicatorActionPopover"))
        XCTAssertTrue(source.contains("permissionRuntimeControlsModel.load"))
        XCTAssertFalse(source.contains("SumiPermissionIndicatorDeviceMenuRow"))
        XCTAssertFalse(source.contains("AVCaptureDevice.DiscoverySession"))
    }

    func testRuntimeControlsAreLimitedToCurrentSiteAndIndicatorSurfaces() throws {
        let currentSiteView = try sourceFile("Sumi/Permissions/UI/SumiCurrentSitePermissionsView.swift")
        let indicatorView = try sourceFile("Sumi/Components/Sidebar/URLBarPermissionViews.swift")
        let siteSettingsView = try sourceFile("Sumi/Permissions/UI/SumiSiteSettingsView.swift")
        let siteDetailView = try sourceFile("Sumi/Permissions/UI/SumiSiteSettingsSiteDetailView.swift")

        XCTAssertTrue(currentSiteView.contains("SumiPermissionRuntimeControlsView"))
        XCTAssertTrue(currentSiteView.contains("queryPermissionState"))
        XCTAssertTrue(indicatorView.contains("SumiPermissionRuntimeControlsView"))
        XCTAssertTrue(indicatorView.contains("queryPermissionState"))
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
