import Combine
import Foundation
import WebKit
import SumiWebRuntime

@MainActor
extension Tab {
    func bindAudioState(to webView: WKWebView) {
        let key = ObjectIdentifier(webView)
        guard mediaRuntime.audioStateCancellables[key] == nil else {
            applyAudioState(webView.sumiAudioState)
            return
        }

        mediaRuntime.audioStateCancellables[key] = webView.sumiAudioStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                Task { @MainActor in
                    self?.applyAudioState(state)
                }
            }

        applyAudioState(webView.sumiAudioState)
    }

    func unbindAudioState(from webView: WKWebView) {
        let key = ObjectIdentifier(webView)
        mediaRuntime.audioStateCancellables.removeValue(forKey: key)?.cancel()
    }

    func applyAudioState(_ newState: SumiWebViewAudioState) {
        let oldState = audioState
        audioState = newState

        if newState.isPlayingAudio {
            mediaRuntime.lastMediaActivityAt = Date()
        }

        guard oldState != newState else { return }

        if oldState.isPlayingAudio != newState.isPlayingAudio {
            mediaRuntime.callbacks.scheduleNowPlayingRefresh(0)
        }
    }

    func toggleMute() {
        setMuted(!audioState.isMuted)
    }

    func setMuted(_ muted: Bool) {
        if let webView = resolvedCurrentWebView() {
            _ = webView.sumiSetAudioMuted(muted)
        } else {
            RuntimeDiagnostics.emit("🔇 [Tab] Mute state queued at \(muted); base webView not loaded yet")
        }

        navigationRuntime.webViewRouting.setMuteState(muted, id)

        applyAudioState(audioState.withMuted(muted))
    }

    func resetPlaybackActivity() {
        applyAudioState(audioState.withPlayingAudio(false))
        mediaRuntime.lastMediaActivityAt = .distantPast
    }
}
