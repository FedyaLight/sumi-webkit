import XCTest
@testable import Sumi

@MainActor
final class SumiWebViewAudioStateTests: XCTestCase {
    func testUnmutedPlayingShowsAudioButton() {
        let state = SumiWebViewAudioState.unmuted(isPlayingAudio: true)

        XCTAssertTrue(state.isPlayingAudio)
        XCTAssertFalse(state.isMuted)
        XCTAssertTrue(state.showsTabAudioButton)
    }

    func testMutedPlayingShowsAudioButton() {
        let state = SumiWebViewAudioState.muted(isPlayingAudio: true)

        XCTAssertTrue(state.isPlayingAudio)
        XCTAssertTrue(state.isMuted)
        XCTAssertTrue(state.showsTabAudioButton)
    }

    func testNonPlayingAudioStatesHideAudioButton() {
        XCTAssertFalse(SumiWebViewAudioState.unmuted(isPlayingAudio: false).showsTabAudioButton)
        XCTAssertFalse(SumiWebViewAudioState.muted(isPlayingAudio: false).showsTabAudioButton)
    }

    func testRawMediaMutedStateMapsOnlyAudioBitToMuted() {
        XCTAssertFalse(
            SumiWebViewAudioState(
                mediaMutedStateRaw: 0,
                isPlayingAudio: true
            ).isMuted
        )

        XCTAssertTrue(
            SumiWebViewAudioState(
                mediaMutedStateRaw: SumiWebViewAudioState.audioMutedMask,
                isPlayingAudio: true
            ).isMuted
        )

        XCTAssertFalse(
            SumiWebViewAudioState(
                mediaMutedStateRaw: 1 << 1,
                isPlayingAudio: true
            ).isMuted
        )
    }

    func testTabAudioStateReflectsAppliedAudioState() {
        let tab = Tab(name: "Audio")

        tab.applyAudioState(.muted(isPlayingAudio: true))

        XCTAssertTrue(tab.audioState.isMuted)
        XCTAssertTrue(tab.audioState.isPlayingAudio)
        XCTAssertTrue(tab.audioState.showsTabAudioButton)

        tab.applyAudioState(.muted(isPlayingAudio: false))

        XCTAssertTrue(tab.audioState.isMuted)
        XCTAssertFalse(tab.audioState.isPlayingAudio)
        XCTAssertFalse(tab.audioState.showsTabAudioButton)
    }

    func testSetMutedUpdatesUnloadedTabAudioState() {
        let tab = Tab(name: "Audio")
        tab.applyAudioState(.unmuted(isPlayingAudio: true))

        tab.setMuted(true)

        XCTAssertTrue(tab.audioState.isMuted)
        XCTAssertTrue(tab.audioState.isPlayingAudio)
        XCTAssertTrue(tab.audioState.showsTabAudioButton)
    }
}
