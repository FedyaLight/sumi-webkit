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
            // No resolvable web view for this window (e.g. tab backgrounded and host evicted from
            // the window pool). Do not clear `audioState` here: `discoverOwner` still uses
            // `tab.audioState.isPlayingAudio` after this call, and resetting would suppress the
            // sidebar media card when switching away from the playing tab.
            return nil
        }

        let info = await webView.sumiRequestNowPlayingInfo()
        return info
    }

    func playSumiNativeNowPlayingSession(
        using context: SumiNativeNowPlayingRuntimeContext,
        in windowState: BrowserWindowState
    ) async -> Bool {
        await performSumiNativeNowPlayingCommand(
            using: context,
            in: windowState
        ) { webView in
            await webView.sumiPlayPredominantOrNowPlayingMediaSession()
        }
    }

    func pauseSumiNativeNowPlayingSession(
        using context: SumiNativeNowPlayingRuntimeContext,
        in windowState: BrowserWindowState
    ) async -> Bool {
        await performSumiNativeNowPlayingCommand(
            using: context,
            in: windowState
        ) { webView in
            await webView.sumiPauseNowPlayingMediaSession()
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
