import UniformTypeIdentifiers
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SumiFilePickerPanelPresenterTests: XCTestCase {
    func testOpenPanelConfigurationAppliesSupportedWebKitParameters() {
        let presenter = SumiFilePickerPanelPresenter()
        let request = SumiFilePickerPanelPresentationRequest(
            allowsMultipleSelection: true,
            allowsDirectories: true,
            allowedContentTypeIdentifiers: [UTType.png.identifier],
            allowedFileExtensions: ["txt"]
        )

        let panel = presenter.makeOpenPanel(for: request)

        XCTAssertTrue(panel.allowsMultipleSelection)
        XCTAssertTrue(panel.canChooseDirectories)
        XCTAssertTrue(panel.canChooseFiles)
        XCTAssertTrue(panel.resolvesAliases)
        XCTAssertEqual(panel.title, "Choose File")
        XCTAssertEqual(panel.prompt, "Choose")
        XCTAssertTrue(panel.allowedContentTypes.contains(.png))
        XCTAssertTrue(panel.allowedContentTypes.contains { $0.preferredFilenameExtension == "txt" })
    }

    func testOpenPanelConfigurationCanDisableMultipleAndDirectorySelection() {
        let presenter = SumiFilePickerPanelPresenter()
        let request = SumiFilePickerPanelPresentationRequest(
            allowsMultipleSelection: false,
            allowsDirectories: false
        )

        let panel = presenter.makeOpenPanel(for: request)

        XCTAssertFalse(panel.allowsMultipleSelection)
        XCTAssertFalse(panel.canChooseDirectories)
        XCTAssertTrue(panel.canChooseFiles)
        XCTAssertTrue(panel.allowedContentTypes.isEmpty)
    }
}
