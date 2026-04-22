import Combine
import Foundation
import WebKit

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
            lastMediaActivityAt = Date()
        }

        guard oldState != newState else { return }
        SumiNativeNowPlayingController.shared.scheduleRefresh(delayNanoseconds: 0)
    }
}
