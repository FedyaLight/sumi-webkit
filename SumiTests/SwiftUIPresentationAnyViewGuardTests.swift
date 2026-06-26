import XCTest

@testable import Sumi

final class SwiftUIPresentationAnyViewGuardTests: XCTestCase {
    func testURLBarHubPresenterKeepsPopoverRootConcrete() throws {
        let source = try sourceFile("Sumi/Components/Sidebar/URLBarHubPopoverPresenter.swift")

        XCTAssertTrue(source.contains("NSHostingController<URLBarHubPopoverRootView>"))
        XCTAssertTrue(source.contains("private struct URLBarHubPopoverRootView: View"))
        assertNoBroadAnyViewErasure(in: source)
    }

    func testEmojiPickerKeepsPopoverRootConcrete() throws {
        let source = try sourceFile("Sumi/Components/EmojiPicker/EmojiPicker.swift")

        XCTAssertTrue(source.contains("NSHostingController<EmojiPickerPanelHost>"))
        XCTAssertTrue(source.contains("private struct EmojiPickerPanelHost: View"))
        assertNoBroadAnyViewErasure(in: source)
    }

    func testFolderGlyphPickerKeepsPopoverRootConcrete() throws {
        let source = try sourceFile("Sumi/Components/Sidebar/SpaceSection/FolderGlyphPicker.swift")

        XCTAssertTrue(source.contains("NSHostingController<FolderGlyphPickerPanelHost>"))
        XCTAssertTrue(source.contains("private struct FolderGlyphPickerPanelHost: View"))
        assertNoBroadAnyViewErasure(in: source)
    }

    private func assertNoBroadAnyViewErasure(
        in source: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(source.contains("NSHostingController<AnyView>"), file: file, line: line)
        XCTAssertFalse(source.contains("-> AnyView"), file: file, line: line)
        XCTAssertFalse(source.contains("AnyView("), file: file, line: line)
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
