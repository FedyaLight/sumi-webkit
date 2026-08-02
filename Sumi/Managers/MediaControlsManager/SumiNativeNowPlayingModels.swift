import Foundation

enum SumiBackgroundMediaPlaybackState: String, Equatable {
    case paused
    case playing
}

struct SumiNativeNowPlayingInfo: Equatable {
    let title: String
    let artist: String?
    let playbackState: SumiBackgroundMediaPlaybackState
    let canPictureInPicture: Bool
}

struct SumiBackgroundMediaFaviconSource: Equatable {
    let documentURL: URL
    let partition: SumiFaviconPartition
}

struct SumiBackgroundMediaCardState: Identifiable, Equatable {
    let id: String
    let tabId: UUID
    let windowId: UUID
    let title: String
    let subtitle: String
    let sourceHost: String?
    let tabTitle: String
    var playbackState: SumiBackgroundMediaPlaybackState
    var isMuted: Bool
    let faviconSource: SumiBackgroundMediaFaviconSource?
    let canPlayPause: Bool
    let canMute: Bool
    let canPictureInPicture: Bool

    var isPlaying: Bool {
        playbackState == .playing
    }

    func withMuted(_ muted: Bool) -> SumiBackgroundMediaCardState {
        SumiBackgroundMediaCardState(
            id: id,
            tabId: tabId,
            windowId: windowId,
            title: title,
            subtitle: subtitle,
            sourceHost: sourceHost,
            tabTitle: tabTitle,
            playbackState: playbackState,
            isMuted: muted,
            faviconSource: faviconSource,
            canPlayPause: canPlayPause,
            canMute: canMute,
            canPictureInPicture: canPictureInPicture
        )
    }
}
