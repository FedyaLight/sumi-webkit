import XCTest

@testable import Sumi

final class SumiPermissionIconCatalogTests: XCTestCase {
    func testEveryPermissionTypeHasNonEmptyIconMapping() {
        let permissionTypes: [SumiPermissionType] = [
            .camera,
            .microphone,
            .cameraAndMicrophone,
            .geolocation,
            .notifications,
            .screenCapture,
            .popups,
            .externalScheme("zoommtg"),
            .autoplay,
            .storageAccess,
            .filePicker,
        ]

        for permissionType in permissionTypes {
            let icon = SumiPermissionIconCatalog.icon(for: permissionType)
            XCTAssertFalse(icon.id.isEmpty, permissionType.identity)
            XCTAssertFalse(icon.fallbackSystemName.isEmpty, permissionType.identity)
        }
    }

    func testActiveSensitivePermissionIconsUseDistinctMappings() {
        XCTAssertNotEqual(
            SumiPermissionIconCatalog.icon(for: .camera, visualStyle: .neutral),
            SumiPermissionIconCatalog.icon(for: .camera, visualStyle: .active)
        )
        XCTAssertNotEqual(
            SumiPermissionIconCatalog.icon(for: .microphone, visualStyle: .neutral),
            SumiPermissionIconCatalog.icon(for: .microphone, visualStyle: .active)
        )
        XCTAssertNotEqual(
            SumiPermissionIconCatalog.icon(for: .geolocation, visualStyle: .neutral),
            SumiPermissionIconCatalog.icon(for: .geolocation, visualStyle: .active)
        )
        XCTAssertNotEqual(
            SumiPermissionIconCatalog.icon(for: .screenCapture, visualStyle: .neutral),
            SumiPermissionIconCatalog.icon(for: .screenCapture, visualStyle: .active)
        )
    }

    func testMissingAssetFallbackUsesGenericPermissionsIcon() {
        let icon = SumiPermissionIconCatalog.icon(for: nil)

        XCTAssertEqual(icon.id, "permissions")
        XCTAssertEqual(icon.chromeIconName, "permissions")
        XCTAssertFalse(icon.fallbackSystemName.isEmpty)
    }

    func testSystemBlockedVisualStyleIsDocumentedByStateAndWarningOverlay() {
        let state = SumiPermissionIndicatorState.visible(
            category: .systemBlocked,
            primaryPermissionType: .screenCapture,
            displayDomain: "meet.example",
            tabId: "tab-a",
            pageId: "tab-a:1",
            priority: .systemBlockedSensitive,
            visualStyle: .systemWarning
        )

        XCTAssertEqual(state.visualStyle, .systemWarning)
        XCTAssertEqual(state.icon.id, "screen-capture")
    }

    func testFilePickerDocumentsSFSymbolFallback() {
        let icon = SumiPermissionIconCatalog.icon(for: .filePicker)

        XCTAssertNil(icon.chromeIconName)
        XCTAssertEqual(icon.fallbackSystemName, "doc.badge.plus")
        XCTAssertNotNil(SumiPermissionIconCatalog.documentedFallbackReason(for: .filePicker))
    }

    func testScreenCaptureHasDisplayFallback() {
        let icon = SumiPermissionIconCatalog.icon(for: .screenCapture)

        XCTAssertEqual(icon.fallbackSystemName, "display")
    }
}
