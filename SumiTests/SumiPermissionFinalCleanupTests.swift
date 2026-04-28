import XCTest

final class SumiPermissionFinalCleanupTests: XCTestCase {
    func testObsoleteFallbackTerminologyIsRemovedFromProductionSourcesAndDocs() throws {
        let sources = try files(under: ["Sumi"], extensions: ["swift", "h"])
            .map(\.contents)
            .joined(separator: "\n")
        let docs = try files(under: ["docs/permissions"], extensions: ["md"])
            .map(\.contents)
            .joined(separator: "\n")
        let combined = sources + "\n" + docs

        for forbidden in [
            "denyUntilPromptUIExists",
            "blockUntilPromptUIExists",
            "prompt-ui-unavailable",
            "blockedByPromptUIUnavailable",
            "promptNeededNoUI",
            "blockedPendingUI",
            "prompt-needed-without-UI",
        ] {
            XCTAssertFalse(combined.contains(forbidden), "Found obsolete permission fallback term: \(forbidden)")
        }

        XCTAssertTrue(sources.contains("promptPresenterUnavailableDeny"))
        XCTAssertTrue(sources.contains("promptPresenterUnavailableBlock"))
        XCTAssertTrue(sources.contains("backgroundPromptUnavailableBlock"))
    }

    func testSystemAuthorizationRequestsAreOwnedBySystemPermissionService() throws {
        try assert(
            "UNUserNotificationCenter.current().requestAuthorization",
            appearsOnlyIn: ["Sumi/Permissions/SumiSystemPermissionService.swift"]
        )
        try assert(
            "AVCaptureDevice.requestAccess",
            appearsOnlyIn: ["Sumi/Permissions/SumiSystemPermissionService.swift"]
        )
        try assert(
            "CGRequestScreenCaptureAccess",
            appearsOnlyIn: ["Sumi/Permissions/SumiSystemPermissionService.swift"]
        )
        try assert(
            "requestWhenInUseAuthorization()",
            appearsOnlyIn: ["Sumi/Permissions/SumiSystemPermissionService.swift"]
        )
    }

    func testNormalTabExternalAndFilePickerBoundariesAreIsolated() throws {
        let tabDelegate = try sourceFile("Sumi/Models/Tab/Tab+UIDelegate.swift")
        let externalResponder = try sourceFile("Sumi/Models/Tab/Navigation/SumiExternalSchemeNavigationResponder.swift")
        let externalBridge = try sourceFile("Sumi/Permissions/SumiExternalSchemePermissionBridge.swift")
        let externalResolver = try sourceFile("Sumi/Permissions/SumiExternalAppResolver.swift")

        XCTAssertTrue(tabDelegate.contains("filePickerPermissionBridge.handleOpenPanel("))
        XCTAssertFalse(tabDelegate.contains("NSOpenPanel"))
        XCTAssertFalse(externalResponder.contains("NSWorkspace.shared.open"))
        XCTAssertFalse(externalBridge.contains("NSWorkspace.shared.open"))
        XCTAssertTrue(externalResolver.contains("workspace.open(url)"))

        let openPanelFiles = try filesContaining("NSOpenPanel", under: ["Sumi"], extensions: ["swift"])
        XCTAssertEqual(openPanelFiles, [
            "Sumi/Bookmarks/BrowserManager+Bookmarks.swift",
            "Sumi/Components/MiniWindow/MiniWindowWebView.swift",
            "Sumi/Managers/ExtensionManager/ExtensionManager+UI.swift",
            "Sumi/Managers/PeekManager/PeekWebView.swift",
            "Sumi/Managers/SumiScripts/UI/SumiScriptsManagerView.swift",
            "Sumi/Permissions/SumiFilePickerPanelPresenter.swift",
        ])
    }

    func testPrivateWebKitPermissionAPIsStayInApprovedFiles() throws {
        try assert(
            "WKGeolocationManager",
            appearsOnlyIn: ["Sumi/Geolocation/SumiGeolocationProvider.swift"]
        )
        try assert(
            "SumiWKGeolocationProvider",
            appearsOnlyIn: [
                "Sumi/Geolocation/SumiGeolocationProvider.swift",
                "Sumi/Supporting Files/SumiWebKitGeolocationProviderABI.h",
            ]
        )
        try assert(
            "requestStorageAccessPanelForDomain",
            appearsOnlyIn: ["Sumi/Models/Tab/Tab+UIDelegate.swift"]
        )
        try assert(
            "requestDisplayCapturePermissionForOrigin",
            appearsOnlyIn: ["Sumi/Models/Tab/Tab+UIDelegate.swift"]
        )
        try assert(
            "SumiWebKitDisplayCapturePermissionDecision",
            appearsOnlyIn: [
                "Sumi/Models/Tab/Tab+UIDelegate.swift",
                "Sumi/Permissions/SumiWebKitDisplayCaptureRequest.swift",
                "Sumi/Permissions/SumiWebKitMediaCaptureDecisionMapper.swift",
                "Sumi/Permissions/SumiWebKitPermissionBridge.swift",
            ]
        )
    }

    func testPermissionUIDoesNotOwnStorageWebKitOrSystemAuthorizationSideEffects() throws {
        let uiSources = try files(under: ["Sumi/Permissions/UI"], extensions: ["swift"])
        let settingsSources = try files(under: ["Sumi/Components/Settings"], extensions: ["swift"])
        let runtimeSources = try [
            "Sumi/Permissions/UI/SumiPermissionRuntimeControlsView.swift",
            "Sumi/Permissions/UI/SumiPermissionRuntimeControlsViewModel.swift",
        ].map(sourceFile).joined(separator: "\n")
        let siteSettingsSources = uiSources
            .filter { $0.relativePath.contains("SumiSiteSettings") }
            .map(\.contents)
            .joined(separator: "\n")

        XCTAssertFalse(siteSettingsSources.contains("import SwiftData"))
        XCTAssertFalse(siteSettingsSources.contains("ModelContext("))
        XCTAssertFalse(settingsSources.map(\.contents).joined(separator: "\n").contains("requestAuthorization("))
        XCTAssertFalse(runtimeSources.contains("setSiteDecision("))
        XCTAssertFalse(runtimeSources.contains("resetSiteDecision"))
        XCTAssertFalse(runtimeSources.contains("SumiPermissionStore"))
        XCTAssertFalse(siteSettingsSources.contains("removeWebsiteData"))
    }

    func testDocsLicenseAndManualPagesDescribeFinalCleanupState() throws {
        let readme = try sourceFile("docs/permissions/README.md")
        let architecture = try sourceFile("docs/permissions/ARCHITECTURE.md")
        let testPlan = try sourceFile("docs/permissions/TEST_PLAN.md")
        let license = try sourceFile("docs/permissions/LICENSE_NOTES.md")

        XCTAssertTrue(readme.contains("ARCHITECTURE.md"))
        XCTAssertTrue(readme.contains("TEST_PLAN.md"))
        XCTAssertTrue(readme.contains("LICENSE_NOTES.md"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent("docs/permissions/IMPLEMENTATION_HANDOFF.md").path))
        XCTAssertTrue(architecture.contains("Implemented Normal-Tab Permission Scope"))
        XCTAssertTrue(architecture.contains("Deferred Work"))
        XCTAssertTrue(architecture.contains("Private WebKit API Boundaries And Known Limitations"))
        XCTAssertFalse(architecture.contains("Target Architecture"))
        XCTAssertTrue(testPlan.contains("SumiPermissionFinalCleanupTests"))
        XCTAssertTrue(testPlan.contains("Source-Level Regression Guards"))

        for area in [
            "Geolocation",
            "Notifications",
            "Popups",
            "External schemes",
            "Autoplay",
            "File picker",
            "Storage access",
            "Screen sharing/display capture",
            "URL-bar indicator",
            "Prompt UI",
            "URL hub submenu",
            "Privacy Site Settings",
            "Runtime controls",
            "One-time lifecycle",
            "Anti-abuse/cleanup",
            "Manual pages",
            "Automated tests",
        ] {
            XCTAssertTrue(license.contains("| \(area) |"), "Missing LICENSE_NOTES matrix entry for \(area)")
        }
        XCTAssertTrue(license.contains("Sumi/Supporting Files/SumiWebKitGeolocationProviderABI.h"))
        XCTAssertTrue(license.contains("Apache License, Version 2.0"))

        for manualPage in try files(under: ["ManualTests/permissions"], extensions: ["html"]) {
            XCTAssertFalse(manualPage.contents.contains("/Users/"), "\(manualPage.relativePath) leaks a local path")
            XCTAssertFalse(manualPage.contents.contains("file:///"), "\(manualPage.relativePath) leaks a local file URL")
        }
    }

    private func assert(
        _ needle: String,
        appearsOnlyIn allowed: Set<String>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let actual = try filesContaining(needle, under: ["Sumi"], extensions: ["swift", "h"])
        XCTAssertEqual(actual, allowed, "\(needle) appears in unexpected files", file: file, line: line)
    }

    private func filesContaining(
        _ needle: String,
        under roots: [String],
        extensions: Set<String>
    ) throws -> Set<String> {
        Set(try files(under: roots, extensions: extensions)
            .filter { $0.contents.contains(needle) }
            .map(\.relativePath))
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        try String(contentsOf: repoRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func files(under roots: [String], extensions: Set<String>) throws -> [SourceFile] {
        let fileManager = FileManager.default
        var result: [SourceFile] = []
        for root in roots {
            let rootURL = repoRoot.appendingPathComponent(root)
            guard let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let fileURL as URL in enumerator {
                guard extensions.contains(fileURL.pathExtension) else { continue }
                let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                guard values.isRegularFile == true else { continue }
                result.append(SourceFile(
                    relativePath: relativePath(for: fileURL),
                    contents: try String(contentsOf: fileURL, encoding: .utf8)
                ))
            }
        }
        return result
    }

    private func relativePath(for url: URL) -> String {
        let rootPath = repoRoot.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return path }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private struct SourceFile {
    let relativePath: String
    let contents: String
}
