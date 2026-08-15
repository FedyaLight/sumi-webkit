import Foundation
import WebKit

extension Tab {
    func sampleSumiNativeNowPlayingInfo(
        using context: SumiNativeNowPlayingRuntimeContext,
        in windowState: BrowserWindowState
    ) async -> SumiNativeNowPlayingInfo? {
        guard let webView = resolvedNowPlayingWebView(
            using: context,
            in: windowState
        ) else {
            // Metadata is optional and must not mutate playback evidence.
            return nil
        }

        let info = await webView.sumiRequestNowPlayingInfo()
        return info
    }

    func setSumiNativeNowPlayingPlayback(
        _ playbackState: SumiBackgroundMediaPlaybackState,
        using context: SumiNativeNowPlayingRuntimeContext,
        in windowState: BrowserWindowState
    ) async -> Bool {
        await performSumiNativeNowPlayingCommand(
            using: context,
            in: windowState
        ) { webView in
            await webView.sumiSetNowPlayingPlayback(playbackState)
        }
    }

    func setSumiNativeNowPlayingMuted(
        _ muted: Bool,
        using context: SumiNativeNowPlayingRuntimeContext,
        in windowState: BrowserWindowState
    ) -> Bool {
        guard let webView = resolvedNowPlayingWebView(
            using: context,
            in: windowState
        ), webView.sumiSetNowPlayingAudioMuted(muted)
        else { return false }

        applyAudioState(audioState.withMuted(muted))
        return true
    }

    func dismissSumiNativeNowPlayingSession(
        using context: SumiNativeNowPlayingRuntimeContext,
        in windowState: BrowserWindowState
    ) async -> Bool {
        await performSumiNativeNowPlayingCommand(
            using: context,
            in: windowState
        ) { webView in
            await webView.sumiSetNowPlayingPlayback(.paused)
        }
    }

    func toggleSumiNativePictureInPicture(
        using context: SumiNativeNowPlayingRuntimeContext,
        in windowState: BrowserWindowState
    ) async -> Bool {
        await performSumiNativeNowPlayingCommand(
            using: context,
            in: windowState
        ) { webView in
            webView.sumiTogglePictureInPicture()
        }
    }

    private func resolvedNowPlayingWebView(
        using context: SumiNativeNowPlayingRuntimeContext,
        in windowState: BrowserWindowState
    ) -> SumiNowPlayingWebViewAdapter? {
        context.resolvedNowPlayingWebView(self, windowState)
    }

    private func performSumiNativeNowPlayingCommand(
        using context: SumiNativeNowPlayingRuntimeContext,
        in windowState: BrowserWindowState,
        perform: @escaping @MainActor (SumiNowPlayingWebViewAdapter) async -> Bool
    ) async -> Bool {
        guard let webView = resolvedNowPlayingWebView(
            using: context,
            in: windowState
        ) else { return false }
        return await perform(webView)
    }
}
