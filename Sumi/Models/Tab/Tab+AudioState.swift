import Combine
import Foundation
import WebKit

@MainActor
extension Tab {
    func authoritativeMediaWebView(
        using browserManager: BrowserManager,
        in windowState: BrowserWindowState
    ) -> WKWebView? {
        browserManager.getWebView(for: id, in: windowState.id)
            ?? assignedWebView
            ?? existingWebView
    }

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
            lastMediaActivityAt = Date()
        }

        guard oldState != newState else { return }

        if oldState.isPlayingAudio != newState.isPlayingAudio {
            browserManager?.nativeNowPlayingController.scheduleRefresh(delayNanoseconds: 0)
            browserManager?.backgroundMediaOptimizationService.scheduleReconcile(
                reason: "tab-audio-state-changed"
            )
        }
    }

    func toggleMute() {
        setMuted(!audioState.isMuted)
    }

    func setMuted(_ muted: Bool) {
        if let webView = currentWebView {
            _ = webView.sumiSetAudioMuted(muted)
        } else {
            RuntimeDiagnostics.emit("🔇 [Tab] Mute state queued at \(muted); base webView not loaded yet")
        }

        browserManager?.setMuteState(muted, for: id)

        applyAudioState(audioState.withMuted(muted))
    }

    func resetPlaybackActivity() {
        applyAudioState(audioState.withPlayingAudio(false))
        lastMediaActivityAt = .distantPast
    }
}
