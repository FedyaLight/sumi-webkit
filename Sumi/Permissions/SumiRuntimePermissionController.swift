import Foundation
import WebKit

@MainActor
protocol SumiRuntimePermissionControlling: AnyObject {
    func currentRuntimeState(for webView: WKWebView) -> SumiRuntimePermissionState
    func currentRuntimeState(for webView: WKWebView, pageId: String?) -> SumiRuntimePermissionState
    func setCameraMuted(_ muted: Bool, for webView: WKWebView) async -> SumiRuntimePermissionOperationResult
    func setMicrophoneMuted(_ muted: Bool, for webView: WKWebView) async -> SumiRuntimePermissionOperationResult
    func stopCamera(for webView: WKWebView) async -> SumiRuntimePermissionOperationResult
    func stopMicrophone(for webView: WKWebView) async -> SumiRuntimePermissionOperationResult
    func pauseGeolocation(pageId: String?, for webView: WKWebView) async -> SumiRuntimePermissionOperationResult
    func resumeGeolocation(pageId: String?, for webView: WKWebView) async -> SumiRuntimePermissionOperationResult
    func stopGeolocation(pageId: String?, for webView: WKWebView) async -> SumiRuntimePermissionOperationResult
    func evaluateAutoplayPolicyChange(
        _ requestedState: SumiRuntimeAutoplayState,
        for webView: WKWebView
    ) -> SumiRuntimePermissionOperationResult
    func observeRuntimeState(
        for webView: WKWebView,
        pageId: String?,
        handler: @escaping @MainActor (SumiRuntimePermissionState) -> Void
    ) -> SumiRuntimePermissionObservation
}

@MainActor
final class SumiRuntimePermissionController: SumiRuntimePermissionControlling {
    private let geolocationProvider: (any SumiGeolocationProviding)?

    init(geolocationProvider: (any SumiGeolocationProviding)? = nil) {
        self.geolocationProvider = geolocationProvider
    }

    func currentRuntimeState(for webView: WKWebView) -> SumiRuntimePermissionState {
        currentRuntimeState(for: webView, pageId: nil)
    }

    func currentRuntimeState(for webView: WKWebView, pageId: String?) -> SumiRuntimePermissionState {
        SumiRuntimePermissionState(
            camera: cameraState(for: webView),
            microphone: microphoneState(for: webView),
            screenCapture: screenCaptureState(),
            geolocation: geolocationState(pageId: pageId),
            autoplay: autoplayState(for: webView)
        )
    }

    private func cameraState(for webView: WKWebView) -> SumiMediaCaptureRuntimeState {
        Self.mediaCaptureState(from: webView.cameraCaptureState)
    }

    private func microphoneState(for webView: WKWebView) -> SumiMediaCaptureRuntimeState {
        Self.mediaCaptureState(from: webView.microphoneCaptureState)
    }

    private func screenCaptureState() -> SumiMediaCaptureRuntimeState {
        .unsupported
    }

    func setCameraMuted(
        _ muted: Bool,
        for webView: WKWebView
    ) async -> SumiRuntimePermissionOperationResult {
        await setMediaCaptureState(
            currentState: webView.cameraCaptureState,
            requestedState: muted ? .muted : .active,
            setter: { requestedState in
                await webView.setCameraCaptureState(requestedState)
            }
        )
    }

    func setMicrophoneMuted(
        _ muted: Bool,
        for webView: WKWebView
    ) async -> SumiRuntimePermissionOperationResult {
        await setMediaCaptureState(
            currentState: webView.microphoneCaptureState,
            requestedState: muted ? .muted : .active,
            setter: { requestedState in
                await webView.setMicrophoneCaptureState(requestedState)
            }
        )
    }

    func stopCamera(for webView: WKWebView) async -> SumiRuntimePermissionOperationResult {
        await setMediaCaptureState(
            currentState: webView.cameraCaptureState,
            requestedState: .none,
            setter: { requestedState in
                await webView.setCameraCaptureState(requestedState)
            }
        )
    }

    func stopMicrophone(for webView: WKWebView) async -> SumiRuntimePermissionOperationResult {
        await setMediaCaptureState(
            currentState: webView.microphoneCaptureState,
            requestedState: .none,
            setter: { requestedState in
                await webView.setMicrophoneCaptureState(requestedState)
            }
        )
    }

    func pauseGeolocation(
        pageId: String?,
        for webView: WKWebView
    ) async -> SumiRuntimePermissionOperationResult {
        applyGeolocationRuntimeOperation(pageId: pageId) { provider in
            provider.pause()
        }
    }

    func resumeGeolocation(
        pageId: String?,
        for webView: WKWebView
    ) async -> SumiRuntimePermissionOperationResult {
        applyGeolocationRuntimeOperation(pageId: pageId) { provider in
            provider.resume()
        }
    }

    func stopGeolocation(
        pageId: String?,
        for webView: WKWebView
    ) async -> SumiRuntimePermissionOperationResult {
        applyGeolocationRuntimeOperation(pageId: pageId, requiresActivePage: false) { provider in
            provider.stop(pageId: pageId)
        }
    }

    func evaluateAutoplayPolicyChange(
        _ requestedState: SumiRuntimeAutoplayState,
        for webView: WKWebView
    ) -> SumiRuntimePermissionOperationResult {
        guard requestedState.isConcreteAutoplayPolicy else {
            return .unsupported(reason: "autoplay-policy-state-not-applicable")
        }

        let currentState = autoplayState(for: webView)
        guard currentState != requestedState else {
            return .noOp
        }

        return .requiresReload(
            SumiRuntimePermissionReloadRequirement(
                kind: .rebuild,
                permissionType: .autoplay,
                reason: "wkwebpagepreferences-autoplay-policy-requires-navigation-reload",
                currentAutoplayState: currentState,
                requestedAutoplayState: requestedState
            )
        )
    }

    func observeRuntimeState(
        for webView: WKWebView,
        pageId: String?,
        handler: @escaping @MainActor (SumiRuntimePermissionState) -> Void
    ) -> SumiRuntimePermissionObservation {
        handler(currentRuntimeState(for: webView, pageId: pageId))

        let cameraObservation = webView.observe(\.cameraCaptureState, options: [.new]) { [weak self, weak webView] _, _ in
            Task { @MainActor [weak self, weak webView] in
                guard let self, let webView else { return }
                handler(self.currentRuntimeState(for: webView, pageId: pageId))
            }
        }
        let microphoneObservation = webView.observe(\.microphoneCaptureState, options: [.new]) { [weak self, weak webView] _, _ in
            Task { @MainActor [weak self, weak webView] in
                guard let self, let webView else { return }
                handler(self.currentRuntimeState(for: webView, pageId: pageId))
            }
        }
        let geolocationObservation = geolocationProvider?.observeState { [weak self, weak webView] _ in
            guard let self, let webView else { return }
            handler(self.currentRuntimeState(for: webView, pageId: pageId))
        }

        return SumiRuntimePermissionObservation {
            cameraObservation.invalidate()
            microphoneObservation.invalidate()
            geolocationObservation?.cancel()
        }
    }

    private func geolocationState(pageId: String?) -> SumiGeolocationRuntimeState {
        guard let geolocationProvider else {
            return .unsupportedProvider
        }
        if let pageId,
           !pageId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !geolocationProvider.containsAllowedRequest(pageId: pageId)
        {
            return .none
        }
        switch geolocationProvider.currentState {
        case .inactive:
            return .none
        case .active:
            return .active
        case .paused:
            return .paused
        case .revoked:
            return .revoked
        case .unavailable, .failed:
            return .unavailable
        }
    }

    private func applyGeolocationRuntimeOperation(
        pageId: String? = nil,
        requiresActivePage: Bool = true,
        _ operation: (any SumiGeolocationProviding) -> SumiGeolocationProviderState
    ) -> SumiRuntimePermissionOperationResult {
        guard let geolocationProvider else {
            return .unsupported(reason: "geolocation-runtime-provider-unsupported")
        }
        guard geolocationProvider.currentState != .unavailable else {
            return .unsupported(reason: "geolocation-runtime-provider-unavailable")
        }
        let pageWasAllowed = pageId.map {
            geolocationProvider.containsAllowedRequest(pageId: $0)
        } ?? false
        if requiresActivePage,
           let pageId,
           !pageId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !pageWasAllowed
        {
            return .deniedByRuntime(reason: "geolocation-runtime-page-not-active")
        }

        let previousState = geolocationProvider.currentState
        let nextState = operation(geolocationProvider)
        if nextState == previousState {
            if let pageId,
               pageWasAllowed,
               !geolocationProvider.containsAllowedRequest(pageId: pageId)
            {
                return .applied
            }
            return .noOp
        }
        switch nextState {
        case .failed(let reason):
            return .failed(reason: reason)
        case .unavailable:
            return .unsupported(reason: "geolocation-runtime-provider-unavailable")
        case .inactive, .active, .paused, .revoked:
            return .applied
        }
    }

    private func setMediaCaptureState(
        currentState: WKMediaCaptureState,
        requestedState: WKMediaCaptureState,
        setter: (WKMediaCaptureState) async -> Void
    ) async -> SumiRuntimePermissionOperationResult {
        guard currentState != requestedState else {
            return .noOp
        }
        guard currentState != .none || requestedState == .none else {
            return .noOp
        }

        await setter(requestedState)
        return .applied
    }

    private func autoplayState(for webView: WKWebView) -> SumiRuntimeAutoplayState {
        Self.autoplayState(from: webView.configuration.mediaTypesRequiringUserActionForPlayback)
    }

    static func mediaCaptureState(
        from webKitState: WKMediaCaptureState
    ) -> SumiMediaCaptureRuntimeState {
        switch webKitState {
        case .none:
            return .none
        case .active:
            return .active
        case .muted:
            return .muted
        @unknown default:
            return .unsupported
        }
    }

    static func autoplayState(
        from mediaTypes: WKAudiovisualMediaTypes
    ) -> SumiRuntimeAutoplayState {
        if mediaTypes.isEmpty {
            return .allowAll
        }
        if mediaTypes == .audio {
            return .blockAudible
        }
        if mediaTypes == .all || mediaTypes.contains(.audio) || mediaTypes.contains(.video) {
            return .blockAll
        }
        return .unsupported
    }
}

@MainActor
final class SumiRuntimePermissionObservation {
    private var cancellation: (() -> Void)?

    init(_ cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
    }

    func cancel() {
        cancellation?()
        cancellation = nil
    }

    isolated deinit {
        cancellation?()
    }
}

private extension SumiRuntimeAutoplayState {
    var isConcreteAutoplayPolicy: Bool {
        switch self {
        case .allowAll, .blockAudible, .blockAll:
            return true
        case .reloadRequired, .unsupported:
            return false
        }
    }
}
