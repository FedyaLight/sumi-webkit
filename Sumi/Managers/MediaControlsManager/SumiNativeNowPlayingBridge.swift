import Foundation
import WebKit

@MainActor
protocol SumiNowPlayingWebViewAdapter: AnyObject {
    func sumiRequestNowPlayingInfo() async -> SumiNativeNowPlayingInfo
    func sumiPlayPredominantOrNowPlayingMediaSession() async -> Bool
    func sumiPauseNowPlayingMediaSession() async -> Bool
    func sumiTogglePictureInPicture() -> Bool
}

enum SumiNowPlayingInfoMapper {
    static func makeInfo(
        titleAndArtist: (title: String?, artist: String?),
        playbackState: SumiBackgroundMediaPlaybackState,
        canPictureInPicture: Bool = false
    ) -> SumiNativeNowPlayingInfo {
        let artist = normalize(titleAndArtist.artist)
        let title =
            normalize(titleAndArtist.title)
            ?? ""

        return SumiNativeNowPlayingInfo(
            title: title,
            artist: artist,
            playbackState: playbackState,
            canPictureInPicture: canPictureInPicture
        )
    }

    private static func normalize(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

@MainActor
extension WKWebView: SumiNowPlayingWebViewAdapter {
    func sumiRequestNowPlayingInfo() async -> SumiNativeNowPlayingInfo {
        let titleAndArtist = await _nowPlayingMediaTitleAndArtist()
        _updateMediaPlaybackControlsManager()

        return SumiNowPlayingInfoMapper.makeInfo(
            titleAndArtist: titleAndArtist,
            playbackState: await sumiRequestBackgroundMediaPlaybackState(),
            canPictureInPicture: _canTogglePictureInPicture
        )
    }

    private func sumiRequestBackgroundMediaPlaybackState() async -> SumiBackgroundMediaPlaybackState {
        let playbackState = await withCheckedContinuation { continuation in
            requestMediaPlaybackState(completionHandler: { state in
                continuation.resume(returning: state)
            })
        }

        switch playbackState {
        case .playing:
            return .playing
        case .paused, .suspended, .none:
            return .paused
        @unknown default:
            return .paused
        }
    }

    func sumiPlayPredominantOrNowPlayingMediaSession() async -> Bool {
        await withCheckedContinuation { continuation in
            _playPredominantOrNowPlayingMediaSession { success in
                continuation.resume(returning: success)
            }
        }
    }

    func sumiPauseNowPlayingMediaSession() async -> Bool {
        await withCheckedContinuation { continuation in
            _pauseNowPlayingMediaSession { success in
                continuation.resume(returning: success)
            }
        }
    }

    func sumiTogglePictureInPicture() -> Bool {
        _updateMediaPlaybackControlsManager()
        guard _canTogglePictureInPicture else { return false }
        _togglePictureInPicture()
        return true
    }
}
