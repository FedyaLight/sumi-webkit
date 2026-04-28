import XCTest

@testable import Sumi

final class SumiCurrentSitePermissionRowTests: XCTestCase {
    func testOptionTitlesMatchCurrentSitePermissionCopy() {
        XCTAssertEqual(SumiCurrentSitePermissionOption.ask.title, "Ask")
        XCTAssertEqual(SumiCurrentSitePermissionOption.allow.title, "Allow")
        XCTAssertEqual(SumiCurrentSitePermissionOption.block.title, "Block")
        XCTAssertEqual(SumiCurrentSitePermissionOption.default.title, "Default")
        XCTAssertEqual(SumiCurrentSitePermissionOption.allowAll.title, "Allow all autoplay")
        XCTAssertEqual(SumiCurrentSitePermissionOption.blockAudible.title, "Block audible autoplay")
        XCTAssertEqual(SumiCurrentSitePermissionOption.blockAll.title, "Block all autoplay")
    }

    func testRowStatusLinesAreDeterministicAndCompact() {
        let row = SumiCurrentSitePermissionRow(
            id: "camera",
            kind: .sitePermission(.camera),
            title: "Camera",
            subtitle: "Allow",
            iconName: "camera",
            fallbackSystemName: "camera",
            currentOption: .allow,
            availableOptions: [.ask, .allow, .block],
            isEditable: true,
            systemStatus: "Camera access was denied for Sumi in macOS settings.",
            runtimeStatus: "Active",
            reloadRequired: false
        )

        XCTAssertEqual(
            row.statusLines,
            [
                "Allow",
                "Active",
                "Camera access was denied for Sumi in macOS settings.",
            ]
        )
        XCTAssertTrue(row.accessibilityLabel.contains("Camera"))
        XCTAssertTrue(row.accessibilityLabel.contains("Allow"))
    }

    func testSummaryPrefersRuntimeThenBlockedAttemptsThenCustomSettings() {
        let runtime = SumiCurrentSitePermissionRow(
            id: "microphone",
            kind: .sitePermission(.microphone),
            title: "Microphone",
            fallbackSystemName: "mic",
            currentOption: .ask,
            runtimeStatus: "Muted"
        )
        let popup = SumiCurrentSitePermissionRow(
            id: "popups",
            kind: .popups,
            title: "Pop-ups and redirects",
            fallbackSystemName: "rectangle.on.rectangle",
            currentOption: .default,
            recentEventCount: 2
        )

        let summary = SumiCurrentSitePermissionSummary.make(
            rows: [runtime, popup],
            isEphemeralProfile: false
        )

        XCTAssertEqual(summary.subtitle, "Microphone muted, 2 blocked attempts")
    }
}
