@testable import Sumi
import XCTest

final class SumiNowPlayingBridgeTests: XCTestCase {
    func testMapperPrefersTitleArtistPayloadWhenAvailable() {
        let info = SumiNowPlayingInfoMapper.makeInfo(
            titleAndArtist: ("  Native Title  ", "  Native Artist "),
            playbackState: .playing
        )

        XCTAssertEqual(info.title, "Native Title")
        XCTAssertEqual(info.artist, "Native Artist")
        XCTAssertEqual(info.playbackState, .playing)
    }

    func testMapperNormalizesEmptyValues() {
        let info = SumiNowPlayingInfoMapper.makeInfo(
            titleAndArtist: ("   ", " "),
            playbackState: .paused
        )

        XCTAssertEqual(info.title, "")
        XCTAssertNil(info.artist)
        XCTAssertEqual(info.playbackState, .paused)
    }

    func testMapperKeepsPlaybackState() {
        let info = SumiNowPlayingInfoMapper.makeInfo(
            titleAndArtist: ("Native Title", nil),
            playbackState: .playing
        )

        XCTAssertEqual(info.playbackState, .playing)
    }
}

@MainActor
final class SumiNativeNowPlayingControllerFeatureGateTests: XCTestCase {
    func testDisablingFeatureSuspendsController() {
        let controller = SumiNativeNowPlayingController(
            candidateProvider: { _ in [] },
            infoProvider: { _, _, _ in nil },
            commandExecutor: { _, _, _, _ in false },
            activationHandler: { _, _, _ in /* no-op */ }
        )

        controller.setFeatureEnabled(true)
        controller.setFeatureEnabled(false)

        XCTAssertFalse(controller.isFeatureEnabled)
        XCTAssertNil(controller.cardState)
    }

    func testScheduleRefreshIsNoOpWhenFeatureDisabled() async {
        let controller = SumiNativeNowPlayingController(
            candidateProvider: { _ in [] },
            infoProvider: { _, _, _ in nil },
            commandExecutor: { _, _, _, _ in false },
            activationHandler: { _, _, _ in /* no-op */ }
        )

        controller.setFeatureEnabled(false)
        controller.scheduleRefresh(delayNanoseconds: 0)

        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNil(controller.cardState)
    }

    func testShouldMountMiniPlayerRequiresVisibleGlobalState() {
        let windowId = UUID()
        let tabId = UUID()
        let windowState = BrowserWindowState(id: windowId)
        windowState.currentTabId = tabId

        let globalState = SumiBackgroundMediaCardState(
            id: "test",
            tabId: tabId,
            windowId: windowId,
            title: "Title",
            subtitle: "",
            sourceHost: nil,
            tabTitle: "Title",
            playbackState: .playing,
            isMuted: false,
            favicon: nil,
            canPlayPause: true,
            canMute: true
        )

        XCTAssertFalse(
            SumiBackgroundMediaCardStore.shouldMountMiniPlayer(
                globalState: globalState,
                in: windowState
            )
        )

        windowState.currentTabId = UUID()

        XCTAssertTrue(
            SumiBackgroundMediaCardStore.shouldMountMiniPlayer(
                globalState: globalState,
                in: windowState
            )
        )
    }
}
