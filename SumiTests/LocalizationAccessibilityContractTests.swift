import AppKit
import XCTest

@testable import Sumi

@MainActor
final class LocalizationAccessibilityContractTests: XCTestCase {
    func testNonViewProductDescriptorsRetainLocalizationMetadata() {
        XCTAssertEqual(String(localized: SidebarPosition.left.displayName), "Left")
        XCTAssertEqual(String(localized: SumiDownloadFallbackAction.ask.title), "Ask whether to open or save files")
        XCTAssertEqual(String(localized: SumiContentHandlerKind.useSystemDefault.title), "Use system default app")
        XCTAssertEqual(String(localized: SumiImportCategory.regularTabs.title), "Regular Tabs")
        XCTAssertEqual(String(localized: SumiImportApplyMode.replace.title), "Replace")
        XCTAssertEqual(String(localized: SumiBrowsingDataTimeRange.last24Hours.title), "Last 24 hours")
        XCTAssertEqual(String(localized: SumiBrowsingDataRetentionPeriod.thirtyDays.title), "30 days")
        XCTAssertEqual(String(localized: SumiBrowsingDataCategory.siteData.title), "Cookies and other site data")
        XCTAssertEqual(String(localized: URLBarHubScreenshotCaptureTarget.selectedArea.title), "Selected Area")
        XCTAssertEqual(String(localized: URLBarHubScreenshotDestination.askEveryTime.title), "Ask Every Time")
        XCTAssertEqual(String(localized: URLBarHubScreenshotQuality.fourX.menuTitle), "4x - High Detail")
    }

    func testFindChromePublishesLabelsHelpIdentifiersAndKeyboardHints() throws {
        let viewController = FindInPageViewController.create()
        _ = viewController.view

        XCTAssertEqual(viewController.textField.accessibilityIdentifier(), "FindInPageController.textField")
        XCTAssertEqual(viewController.textField.accessibilityLabel(), "Find in page")
        XCTAssertEqual(viewController.placeholderLabel.stringValue, "Find in page")
        XCTAssertFalse(viewController.placeholderLabel.isHidden)
        XCTAssertEqual(viewController.statusField.accessibilityIdentifier(), "FindInPageController.statusField")
        XCTAssertEqual(viewController.statusField.accessibilityLabel(), "Find match position")

        try assertButton(
            viewController.previousButton,
            title: "Previous match",
            help: "Previous match (Shift-Return)",
            identifier: "FindInPageController.previousButton"
        )
        try assertButton(
            viewController.nextButton,
            title: "Next match",
            help: "Next match (Return)",
            identifier: "FindInPageController.nextButton"
        )
        try assertButton(
            viewController.closeButton,
            title: "Close find bar",
            help: "Close find bar (Escape)",
            identifier: "FindInPageController.closeButton"
        )
    }

    func testFindChromeDisplaysCompactMatchProgress() {
        let viewController = FindInPageViewController.create()
        let model = FindInPageModel()
        model.find("test")
        model.update(progress: .init(currentSelection: 8, matchesFound: 10))
        _ = viewController.view
        viewController.model = model

        XCTAssertEqual(viewController.statusField.stringValue, "8/10")
    }

    func testFindChromeFitsMaximumMatchProgress() {
        let viewController = FindInPageViewController.create()
        let model = FindInPageModel()
        model.find("test")
        model.update(progress: .init(currentSelection: 1000, matchesFound: 1000))
        _ = viewController.view
        viewController.model = model
        viewController.view.layoutSubtreeIfNeeded()

        XCTAssertEqual(viewController.statusField.stringValue, "1000/1000")
        XCTAssertGreaterThanOrEqual(
            viewController.statusField.bounds.width,
            viewController.statusField.intrinsicContentSize.width
        )
    }

    func testFindChromeTextFieldHasNoSeparateVisualSurface() {
        let viewController = FindInPageViewController.create()
        _ = viewController.view
        viewController.view.layoutSubtreeIfNeeded()

        XCTAssertFalse(viewController.textField.isBordered)
        XCTAssertFalse(viewController.textField.isBezeled)
        XCTAssertFalse(viewController.textField.drawsBackground)
        XCTAssertNil(viewController.textField.placeholderString)
        XCTAssertNil(viewController.textField.placeholderAttributedString)
    }

    func testFindChromePlaceholderTracksWhetherQueryIsEmpty() {
        let viewController = FindInPageViewController.create()
        let model = FindInPageModel()
        _ = viewController.view
        viewController.model = model

        XCTAssertFalse(viewController.placeholderLabel.isHidden)

        model.find("test")
        XCTAssertTrue(viewController.placeholderLabel.isHidden)

        model.find("")
        XCTAssertFalse(viewController.placeholderLabel.isHidden)
    }

    func testFindChromePlaceholderUsesSecondaryTextWithoutIncreasingItsOpacity() {
        let viewController = FindInPageViewController.create()
        _ = viewController.view
        let secondaryText = NSColor.black.withAlphaComponent(0.56)

        viewController.applyChromeColors(FindInPageChromePaint(
            shellBackground: .white,
            shellBorder: .clear,
            primaryText: .black,
            secondaryText: secondaryText
        ))

        XCTAssertEqual(
            viewController.placeholderLabel.textColor?.alphaComponent ?? 1,
            secondaryText.alphaComponent,
            accuracy: 0.001
        )
    }

    func testGlanceActionDescriptorsAreSemanticAndStable() {
        XCTAssertEqual(String(localized: GlanceOverlayActionChrome.Action.close.title), "Close Glance")
        XCTAssertEqual(GlanceOverlayActionChrome.Action.close.accessibilityIdentifier, "glance-action-close")
        XCTAssertEqual(String(localized: GlanceOverlayActionChrome.Action.open.title), "Open in Tab")
        XCTAssertEqual(GlanceOverlayActionChrome.Action.open.accessibilityIdentifier, "glance-action-open-in-tab")
        XCTAssertEqual(String(localized: GlanceOverlayActionChrome.Action.split.title), "Open in Split View")
        XCTAssertEqual(GlanceOverlayActionChrome.Action.split.accessibilityIdentifier, "glance-action-open-in-split")
    }

    private func assertButton(
        _ button: NSButton?,
        title: String,
        help: String,
        identifier: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let button = try XCTUnwrap(button, file: file, line: line)
        XCTAssertEqual(button.accessibilityTitle(), title, file: file, line: line)
        XCTAssertEqual(button.toolTip, help, file: file, line: line)
        XCTAssertEqual(button.accessibilityIdentifier(), identifier, file: file, line: line)
    }
}
