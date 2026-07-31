import XCTest

@testable import Sumi

@MainActor
final class CommandPaletteTextFieldTests: XCTestCase {
    func testCommandPaletteInputUsesNativeHorizontalScrolling() {
        let view = CommandPaletteTextFieldView()

        XCTAssertTrue(view.textField.cell?.isScrollable == true)
    }
}
