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

        let configuration = presenter.openPanelConfiguration(for: request)

        XCTAssertTrue(configuration.allowsMultipleSelection)
        XCTAssertTrue(configuration.canChooseDirectories)
        XCTAssertTrue(configuration.canChooseFiles)
        XCTAssertTrue(configuration.resolvesAliases)
        XCTAssertEqual(configuration.title, "Choose File")
        XCTAssertEqual(configuration.prompt, "Choose")
        XCTAssertTrue(configuration.allowedContentTypes.contains(.png))
        XCTAssertTrue(configuration.allowedContentTypes.contains { $0.preferredFilenameExtension == "txt" })
    }

    func testOpenPanelConfigurationCanDisableMultipleAndDirectorySelection() {
        let presenter = SumiFilePickerPanelPresenter()
        let request = SumiFilePickerPanelPresentationRequest(
            allowsMultipleSelection: false,
            allowsDirectories: false
        )

        let configuration = presenter.openPanelConfiguration(for: request)

        XCTAssertFalse(configuration.allowsMultipleSelection)
        XCTAssertFalse(configuration.canChooseDirectories)
        XCTAssertTrue(configuration.canChooseFiles)
        XCTAssertTrue(configuration.allowedContentTypes.isEmpty)
    }
}
