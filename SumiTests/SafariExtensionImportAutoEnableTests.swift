import XCTest

@testable import Sumi

@MainActor
final class SafariExtensionImportAutoEnableTests: XCTestCase {
    func testImportSucceededEnableFailedErrorDescription() {
        let error = ExtensionError.importSucceededEnableFailed(
            "Raindrop was imported but could not be enabled: runtime unavailable"
        )
        XCTAssertEqual(
            error.errorDescription,
            "Raindrop was imported but could not be enabled: runtime unavailable"
        )
    }
}
