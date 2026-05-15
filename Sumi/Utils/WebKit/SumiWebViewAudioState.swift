import Combine
import Foundation
import ObjectiveC
import WebKit

enum SumiWebViewAudioState: Equatable {
    case muted(isPlayingAudio: Bool)
    case unmuted(isPlayingAudio: Bool)

    init(mediaMutedStateRaw: UInt, isPlayingAudio: Bool) {
        if mediaMutedStateRaw & Self.audioMutedMask != 0 {
            self = .muted(isPlayingAudio: isPlayingAudio)
        } else {
            self = .unmuted(isPlayingAudio: isPlayingAudio)
        }
    }

    var isMuted: Bool {
        switch self {
        case .muted:
            return true
        case .unmuted:
            return false
        }
    }

    var isPlayingAudio: Bool {
        switch self {
        case .muted(let isPlayingAudio), .unmuted(let isPlayingAudio):
            return isPlayingAudio
        }
    }

    var showsTabAudioButton: Bool {
        isPlayingAudio
    }

    func withMuted(_ muted: Bool) -> SumiWebViewAudioState {
        muted
            ? .muted(isPlayingAudio: isPlayingAudio)
            : .unmuted(isPlayingAudio: isPlayingAudio)
    }

    func withPlayingAudio(_ isPlayingAudio: Bool) -> SumiWebViewAudioState {
        isMuted
            ? .muted(isPlayingAudio: isPlayingAudio)
            : .unmuted(isPlayingAudio: isPlayingAudio)
    }

    static let audioMutedMask: UInt = 1 << 0
}

extension WKWebView {
    private enum SumiAudioSelector {
        static let mediaMutedState = NSSelectorFromString("_mediaMutedState")
        static let isPlayingAudio = "_isPlayingAudio"
        static let hasActiveNowPlayingSession = "_hasActiveNowPlayingSession"
        static let setPageMuted = NSSelectorFromString("_setPageMuted:")
    }

    @objc dynamic var sumiAudioMediaMutedStateRaw: UInt {
        guard responds(to: SumiAudioSelector.mediaMutedState),
              let method = class_getInstanceMethod(object_getClass(self), SumiAudioSelector.mediaMutedState)
        else {
            return 0
        }

        let implementation = method_getImplementation(method)
        typealias Getter = @convention(c) (WKWebView, Selector) -> UInt
        let getter = unsafeBitCast(implementation, to: Getter.self)
        return getter(self, SumiAudioSelector.mediaMutedState)
    }

    @objc(keyPathsForValuesAffectingSumiAudioMediaMutedStateRaw)
    static func keyPathsForValuesAffectingSumiAudioMediaMutedStateRaw() -> Set<String> {
        [NSStringFromSelector(SumiAudioSelector.mediaMutedState)]
    }

    @objc dynamic var sumiAudioIsPlayingAudio: Bool {
        guard responds(to: NSSelectorFromString(SumiAudioSelector.isPlayingAudio)) else {
            return false
        }
        return value(forKey: SumiAudioSelector.isPlayingAudio) as? Bool ?? false
    }

    @objc(keyPathsForValuesAffectingSumiAudioIsPlayingAudio)
    static func keyPathsForValuesAffectingSumiAudioIsPlayingAudio() -> Set<String> {
        [
            NSStringFromSelector(SumiAudioSelector.mediaMutedState),
            SumiAudioSelector.isPlayingAudio
        ]
    }

    @objc dynamic var sumiHasActiveNowPlayingSession: Bool {
        guard responds(to: NSSelectorFromString(SumiAudioSelector.hasActiveNowPlayingSession)) else {
            return false
        }
        return value(forKey: SumiAudioSelector.hasActiveNowPlayingSession) as? Bool ?? false
    }

    @objc(keyPathsForValuesAffectingSumiHasActiveNowPlayingSession)
    static func keyPathsForValuesAffectingSumiHasActiveNowPlayingSession() -> Set<String> {
        [SumiAudioSelector.hasActiveNowPlayingSession]
    }

    var sumiAudioState: SumiWebViewAudioState {
        get {
            SumiWebViewAudioState(
                mediaMutedStateRaw: sumiAudioMediaMutedStateRaw,
                isPlayingAudio: sumiAudioIsPlayingAudio
            )
        }
        set {
            _ = sumiSetAudioMuted(newValue.isMuted)
        }
    }

    @discardableResult
    func sumiSetAudioMuted(_ muted: Bool) -> Bool {
        guard responds(to: SumiAudioSelector.setPageMuted),
              let method = class_getInstanceMethod(object_getClass(self), SumiAudioSelector.setPageMuted)
        else {
            return false
        }

        var mediaMutedStateRaw = sumiAudioMediaMutedStateRaw
        if muted {
            mediaMutedStateRaw |= SumiWebViewAudioState.audioMutedMask
        } else {
            mediaMutedStateRaw &= ~SumiWebViewAudioState.audioMutedMask
        }

        let implementation = method_getImplementation(method)
        typealias Setter = @convention(c) (WKWebView, Selector, UInt) -> Void
        let setter = unsafeBitCast(implementation, to: Setter.self)
        setter(self, SumiAudioSelector.setPageMuted, mediaMutedStateRaw)
        return true
    }

    var sumiAudioStatePublisher: AnyPublisher<SumiWebViewAudioState, Never> {
        publisher(for: \.sumiAudioMediaMutedStateRaw, options: [.initial, .new])
            .combineLatest(publisher(for: \.sumiAudioIsPlayingAudio, options: [.initial, .new]))
            .map { mediaMutedStateRaw, isPlayingAudio in
                SumiWebViewAudioState(
                    mediaMutedStateRaw: mediaMutedStateRaw,
                    isPlayingAudio: isPlayingAudio
                )
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
}
