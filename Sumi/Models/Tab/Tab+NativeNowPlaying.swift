import Foundation
import WebKit

extension Tab {
    func sampleSumiNativeNowPlayingInfo(
        using browserManager: BrowserManager,
        in windowState: BrowserWindowState
    ) async -> SumiNativeNowPlayingInfo? {
        guard let webView = resolvedNowPlayingWebView(
            using: browserManager,
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
        using browserManager: BrowserManager,
        in windowState: BrowserWindowState,
        focusIfNeeded: Bool
    ) async -> Bool {
        await performSumiNativeNowPlayingCommand(
            using: browserManager,
            in: windowState,
            focusIfNeeded: focusIfNeeded
        ) { webView in
            await webView.sumiPlayPredominantOrNowPlayingMediaSession()
        }
    }

    func pauseSumiNativeNowPlayingSession(
        using browserManager: BrowserManager,
        in windowState: BrowserWindowState,
        focusIfNeeded: Bool
    ) async -> Bool {
        await performSumiNativeNowPlayingCommand(
            using: browserManager,
            in: windowState,
            focusIfNeeded: focusIfNeeded
        ) { webView in
            await webView.sumiPauseNowPlayingMediaSession()
        }
    }

    private func resolvedNowPlayingWebView(
        using browserManager: BrowserManager,
        in windowState: BrowserWindowState
    ) -> SumiNowPlayingWebViewAdapter? {
        authoritativeMediaWebView(
            using: browserManager,
            in: windowState
        )
    }

    private func performSumiNativeNowPlayingCommand(
        using browserManager: BrowserManager,
        in windowState: BrowserWindowState,
        focusIfNeeded: Bool,
        perform: @escaping @MainActor (SumiNowPlayingWebViewAdapter) async -> Bool
    ) async -> Bool {
        if let webView = resolvedNowPlayingWebView(using: browserManager, in: windowState) {
            return await perform(webView)
        }

        guard focusIfNeeded else { return false }

        browserManager.selectTab(self, in: windowState)
        try? await Task.sleep(nanoseconds: 180_000_000)

        guard let focusedWebView = resolvedNowPlayingWebView(
            using: browserManager,
            in: windowState
        ) else {
            return false
        }

        return await perform(focusedWebView)
    }

}
