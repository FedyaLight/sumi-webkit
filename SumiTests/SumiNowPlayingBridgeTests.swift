import XCTest
@testable import Sumi

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
