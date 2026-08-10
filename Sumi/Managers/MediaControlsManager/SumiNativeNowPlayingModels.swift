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

struct SumiMediaResidenceKey: Hashable, Comparable {
    let tabId: UUID
    let windowId: UUID

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.windowId != rhs.windowId {
            return lhs.windowId < rhs.windowId
        }
        return lhs.tabId < rhs.tabId
    }
}

struct SumiBackgroundMediaCardID: Hashable {
    let tabId: UUID
    let windowId: UUID
    let residenceGeneration: UInt64
    let webViewIdentity: ObjectIdentifier

    var residenceKey: SumiMediaResidenceKey {
        SumiMediaResidenceKey(tabId: tabId, windowId: windowId)
    }
}

struct SumiBackgroundMediaCardState: Identifiable, Equatable {
    let id: SumiBackgroundMediaCardID
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
}

@MainActor
enum SumiBackgroundMediaCardProjection {
    static let maximumVisibleCount = 3

    static func visibleStates(
        _ states: [SumiBackgroundMediaCardState],
        in windowState: BrowserWindowState
    ) -> [SumiBackgroundMediaCardState] {
        guard !windowState.isIncognito else { return [] }
        return Array(
            states.lazy
                .filter { state in
                    !(state.windowId == windowState.id
                        && state.tabId == windowState.currentTabId)
                }
                .prefix(maximumVisibleCount)
        )
    }
}
