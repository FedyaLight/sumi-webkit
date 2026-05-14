import XCTest
@testable import Sumi

final class SidebarContextMenuLifecycleTests: XCTestCase {
    func testPopupReturnFinalizesClosedVisibleMenu() {
        XCTAssertEqual(
            SidebarContextMenuPopupReturnPolicy.finalizationReason(
                didBecomeVisible: true,
                didClose: true
            ),
            "popup-return-after-close"
        )
    }

    func testPopupReturnFinalizesMenuThatNeverOpened() {
        XCTAssertEqual(
            SidebarContextMenuPopupReturnPolicy.finalizationReason(
                didBecomeVisible: false,
                didClose: false
            ),
            "popup-return-before-open"
        )
    }

    func testPopupReturnDoesNotFinalizeVisibleMenuWithoutCloseSignal() {
        XCTAssertNil(
            SidebarContextMenuPopupReturnPolicy.finalizationReason(
                didBecomeVisible: true,
                didClose: false
            )
        )
    }

    func testContextMenuControllerKeepsRootMenuAliveUntilFinalization() throws {
        let source = try Self.source(named: "Sumi/Components/Sidebar/SidebarContextMenuController.swift")

        XCTAssertTrue(source.contains("private var activeRootMenu: NSMenu?"))
        XCTAssertFalse(source.contains("private weak var activeRootMenu: NSMenu?"))
    }

    private static func source(named path: String) throws -> String {
        let url = repoRoot.appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
