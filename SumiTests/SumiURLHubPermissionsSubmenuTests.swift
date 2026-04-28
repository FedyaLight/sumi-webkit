import Combine
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

    func testURLHubPermissionsSubmenuUsesNonLiveSystemSnapshotModeAndIdentifiers() throws {
        let urlBar = try sourceFile("Sumi/Components/Sidebar/URLBarView.swift")
        let permissionsView = try sourceFile("Sumi/Permissions/UI/SumiCurrentSitePermissionsView.swift")

        XCTAssertTrue(urlBar.contains(".accessibilityIdentifier(\"urlbar-site-controls-button\")"))
        XCTAssertTrue(urlBar.contains(".accessibilityIdentifier(\"urlhub-setting-row-\\(model.id)\")"))
        XCTAssertTrue(permissionsView.contains("systemSnapshotMode: .none"))
        XCTAssertTrue(permissionsView.contains(".accessibilityIdentifier(\"urlhub-permissions-submenu\")"))
        XCTAssertTrue(permissionsView.contains(".accessibilityIdentifier(\"urlhub-permission-row-\\(row.id)\")"))
    }

    func testURLHubPermissionsRowUsesHandIcon() throws {
        let urlBar = try sourceFile("Sumi/Components/Sidebar/URLBarView.swift")
        let iconCatalog = try sourceFile("Sumi/Permissions/UI/SumiPermissionIconCatalog.swift")

        XCTAssertTrue(urlBar.contains("fallbackSystemName: \"hand.raised\""))
        XCTAssertTrue(iconCatalog.contains("fallbackSystemName: \"hand.raised\""))
    }

    func testURLHubFooterDoesNotExposeRedundantSiteSettingsMenu() throws {
        let source = try sourceFile("Sumi/Components/Sidebar/URLBarView.swift")

        XCTAssertFalse(source.contains("Button(\"Site Settings\")"))
        XCTAssertFalse(source.contains("fallbackSystemName: \"ellipsis\""))
        XCTAssertFalse(source.contains("iconName: \"menu\""))
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

    func testPermissionsSubmenuCoalescesStoreDrivenReloads() throws {
        let view = try sourceFile("Sumi/Permissions/UI/SumiCurrentSitePermissionsView.swift")

        XCTAssertTrue(view.contains("@State private var scheduledReloadTask"))
        XCTAssertTrue(view.contains("scheduleReloadAfterStoreChange()"))
        XCTAssertTrue(view.contains("scheduledReloadTask?.cancel()"))
    }

    @MainActor
    func testPermissionEventSnapshotReadsDoNotPublishChanges() {
        let store = SumiPermissionIndicatorEventStore()
        let now = Date()
        store.record(
            SumiPermissionIndicatorEventRecord(
                id: "expired-notification",
                tabId: "tab-a",
                pageId: "tab-a:1",
                displayDomain: "example.com",
                permissionTypes: [.notifications],
                category: .blockedEvent,
                visualStyle: .blocked,
                priority: .blockedNotification,
                createdAt: now.addingTimeInterval(-20),
                expiresAt: now.addingTimeInterval(-10)
            )
        )

        var changeCount = 0
        let cancellable = store.objectWillChange.sink {
            changeCount += 1
        }

        XCTAssertTrue(store.recordsSnapshot(forPageId: "tab-a:1", now: now).isEmpty)
        XCTAssertEqual(changeCount, 0)
        cancellable.cancel()
    }

    func testDocumentationRecordsNoDDGImplementationCopy() throws {
        let licenseNotes = try sourceFile("docs/permissions/LICENSE_NOTES.md")
        let lowercasedNotes = licenseNotes.lowercased()

        XCTAssertTrue(licenseNotes.contains("DDG Permission Center"))
        XCTAssertTrue(
            lowercasedNotes.contains("no implementation source was copied")
                || lowercasedNotes.contains("no duckduckgo swiftui/appkit view source, implementation source")
        )
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
