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

        XCTAssertEqual(summary.activityText, "Microphone muted, 2 blocked attempts")
    }

    func testURLBarInlineCycleResolverUsesPermissionSpecificTransitions() {
        XCTAssertEqual(
            URLBarPermissionInlineCycleResolver.nextOption(
                for: row(kind: .autoplay, currentOption: .default, availableOptions: [.default, .allowAll, .blockAudible, .blockAll])
            ),
            .blockAll
        )
        XCTAssertEqual(
            URLBarPermissionInlineCycleResolver.nextOption(
                for: row(kind: .autoplay, currentOption: .blockAll, availableOptions: [.default, .allowAll, .blockAudible, .blockAll])
            ),
            .allowAll
        )
        XCTAssertEqual(
            URLBarPermissionInlineCycleResolver.nextOption(
                for: row(kind: .popups, currentOption: .block, availableOptions: [.default, .allow, .block])
            ),
            .allow
        )
        XCTAssertEqual(
            URLBarPermissionInlineCycleResolver.nextOption(
                for: row(kind: .sitePermission(.camera), currentOption: .allow, availableOptions: [.ask, .allow, .block])
            ),
            .block
        )
    }

    func testURLBarInlineCycleResolverFallsBackToFirstAvailableOption() {
        XCTAssertEqual(
            URLBarPermissionInlineCycleResolver.nextOption(
                for: row(kind: .sitePermission(.camera), currentOption: .ask, availableOptions: [.allow])
            ),
            .allow
        )
    }

    func testURLBarInlineCycleResolverSkipsNonCyclingRows() {
        XCTAssertNil(
            URLBarPermissionInlineCycleResolver.nextOption(
                for: row(kind: .externalApps, currentOption: nil, availableOptions: [.allow, .block])
            )
        )
        XCTAssertNil(
            URLBarPermissionInlineCycleResolver.nextOption(
                for: row(kind: .filePicker, currentOption: nil, availableOptions: [.allow, .block])
            )
        )
    }

    private func row(
        kind: SumiCurrentSitePermissionRow.Kind,
        currentOption: SumiCurrentSitePermissionOption?,
        availableOptions: [SumiCurrentSitePermissionOption]
    ) -> SumiCurrentSitePermissionRow {
        SumiCurrentSitePermissionRow(
            id: "test",
            kind: kind,
            title: "Test",
            fallbackSystemName: "questionmark",
            currentOption: currentOption,
            availableOptions: availableOptions,
            isEditable: true
        )
    }
}
