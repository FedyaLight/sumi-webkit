import XCTest
@testable import Sumi

final class SumiFolderGlyphParityTests: XCTestCase {
    func testFolderIconNormalizationKeepsOnlyZenBundledValues() {
        XCTAssertEqual(SumiZenFolderIconCatalog.normalizedFolderIconValue(nil), "")
        XCTAssertEqual(SumiZenFolderIconCatalog.normalizedFolderIconValue(""), "")
        XCTAssertEqual(
            SumiZenFolderIconCatalog.normalizedFolderIconValue("zen:bookmark"),
            "zen:bookmark"
        )

        XCTAssertEqual(SumiZenFolderIconCatalog.normalizedFolderIconValue("folder"), "")
        XCTAssertEqual(SumiZenFolderIconCatalog.normalizedFolderIconValue("folder.fill"), "")
        XCTAssertEqual(SumiZenFolderIconCatalog.normalizedFolderIconValue("bookmark"), "")
        XCTAssertEqual(SumiZenFolderIconCatalog.normalizedFolderIconValue("star.fill"), "")
        XCTAssertEqual(SumiZenFolderIconCatalog.normalizedFolderIconValue("🔥"), "")
        XCTAssertEqual(SumiZenFolderIconCatalog.normalizedFolderIconValue("zen:missing-icon"), "")
    }

    func testClosedFolderWithoutCustomIconUsesClosedShellState() {
        let state = makeState(iconValue: "", isOpen: false, hasActiveProjection: false)

        XCTAssertEqual(state.shellState, .closed)
        XCTAssertFalse(state.isActive)
        XCTAssertFalse(state.showsCustomIcon)
        XCTAssertFalse(state.showsDots)
        XCTAssertNil(state.bundledIconName)
    }

    func testOpenFolderWithoutCustomIconUsesOpenShellState() {
        let state = makeState(iconValue: "", isOpen: true, hasActiveProjection: false)

        XCTAssertEqual(state.shellState, .open)
        XCTAssertFalse(state.isActive)
        XCTAssertFalse(state.showsCustomIcon)
        XCTAssertFalse(state.showsDots)
        XCTAssertNil(state.bundledIconName)
    }

    func testClosedFolderWithCustomIconShowsBundledIcon() {
        let state = makeState(iconValue: "zen:bookmark", isOpen: false, hasActiveProjection: false)

        XCTAssertEqual(state.shellState, .closed)
        XCTAssertFalse(state.isActive)
        XCTAssertEqual(state.bundledIconName, "bookmark")
        XCTAssertTrue(state.showsCustomIcon)
        XCTAssertFalse(state.showsDots)
    }

    func testOpenFolderWithCustomIconShowsBundledIcon() {
        let state = makeState(iconValue: "zen:bookmark", isOpen: true, hasActiveProjection: false)

        XCTAssertEqual(state.shellState, .open)
        XCTAssertFalse(state.isActive)
        XCTAssertEqual(state.bundledIconName, "bookmark")
        XCTAssertTrue(state.showsCustomIcon)
        XCTAssertFalse(state.showsDots)
    }

    func testCollapsedActiveFolderShowsDotsInsteadOfCustomIcon() {
        let state = makeState(iconValue: "zen:bookmark", isOpen: false, hasActiveProjection: true)

        XCTAssertEqual(state.shellState, .closed)
        XCTAssertTrue(state.isActive)
        XCTAssertEqual(state.bundledIconName, "bookmark")
        XCTAssertFalse(state.showsCustomIcon)
        XCTAssertTrue(state.showsDots)
    }

    func testOpenActiveFolderKeepsCustomIconVisible() {
        let state = makeState(iconValue: "zen:bookmark", isOpen: true, hasActiveProjection: true)

        XCTAssertEqual(state.shellState, .open)
        XCTAssertFalse(state.isActive)
        XCTAssertEqual(state.bundledIconName, "bookmark")
        XCTAssertTrue(state.showsCustomIcon)
        XCTAssertFalse(state.showsDots)
    }

    func testOpenStateOnlyChangesShellStateForCustomIcon() {
        let closed = makeState(iconValue: "zen:bookmark", isOpen: false, hasActiveProjection: false)
        let open = makeState(iconValue: "zen:bookmark", isOpen: true, hasActiveProjection: false)

        XCTAssertEqual(closed.bundledIconName, open.bundledIconName)
        XCTAssertEqual(closed.showsCustomIcon, open.showsCustomIcon)
        XCTAssertEqual(closed.showsDots, open.showsDots)
        XCTAssertNotEqual(closed.shellState, open.shellState)
    }

    private func makeState(
        iconValue: String,
        isOpen: Bool,
        hasActiveProjection: Bool
    ) -> SumiFolderGlyphPresentationState {
        SumiFolderGlyphPresentationState(
            iconValue: iconValue,
            isOpen: isOpen,
            hasActiveProjection: hasActiveProjection
        )
    }
}
