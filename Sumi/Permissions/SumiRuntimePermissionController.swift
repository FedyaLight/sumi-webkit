import Foundation
import WebKit

@MainActor
protocol SumiRuntimePermissionControlling: AnyObject {
    func currentRuntimeState(for webView: WKWebView) -> SumiRuntimePermissionState
    func cameraState(for webView: WKWebView) -> SumiMediaCaptureRuntimeState
    func microphoneState(for webView: WKWebView) -> SumiMediaCaptureRuntimeState
    func setCameraMuted(_ muted: Bool, for webView: WKWebView) async -> SumiRuntimePermissionOperationResult
    func setMicrophoneMuted(_ muted: Bool, for webView: WKWebView) async -> SumiRuntimePermissionOperationResult
    func stopCamera(for webView: WKWebView) async -> SumiRuntimePermissionOperationResult
    func stopMicrophone(for webView: WKWebView) async -> SumiRuntimePermissionOperationResult
    func stopAllMediaCapture(for webView: WKWebView) async -> SumiRuntimePermissionOperationResult
    func applyRuntimeDecision(
        _ decision: SumiPermissionCoordinatorDecision,
        to webView: WKWebView
    ) async -> SumiRuntimePermissionBatchResult
    func revokeRuntimePermissions(
        _ permissionTypes: [SumiPermissionType],
        for webView: WKWebView
    ) async -> SumiRuntimePermissionBatchResult
    func pauseRuntimePermissions(
        _ permissionTypes: [SumiPermissionType],
        for webView: WKWebView
    ) async -> SumiRuntimePermissionBatchResult
    func resumeRuntimePermissions(
        _ permissionTypes: [SumiPermissionType],
        for webView: WKWebView
    ) async -> SumiRuntimePermissionBatchResult
    func evaluateAutoplayPolicyChange(
        _ requestedState: SumiRuntimeAutoplayState,
        for webView: WKWebView
    ) -> SumiRuntimePermissionOperationResult
    func observeRuntimeState(
        for webView: WKWebView,
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
        SumiRuntimePermissionState(
            camera: cameraState(for: webView),
            microphone: microphoneState(for: webView),
            geolocation: geolocationState(),
            autoplay: autoplayState(for: webView)
        )
    }

    func cameraState(for webView: WKWebView) -> SumiMediaCaptureRuntimeState {
        Self.mediaCaptureState(from: webView.cameraCaptureState)
    }

    func microphoneState(for webView: WKWebView) -> SumiMediaCaptureRuntimeState {
        Self.mediaCaptureState(from: webView.microphoneCaptureState)
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

    func stopAllMediaCapture(for webView: WKWebView) async -> SumiRuntimePermissionOperationResult {
        let cameraResult = await stopCamera(for: webView)
        let microphoneResult = await stopMicrophone(for: webView)
        return aggregateMediaResults([cameraResult, microphoneResult])
    }

    func applyRuntimeDecision(
        _ decision: SumiPermissionCoordinatorDecision,
        to webView: WKWebView
    ) async -> SumiRuntimePermissionBatchResult {
        switch decision.outcome {
        case .granted:
            return await resumeRuntimePermissions(decision.permissionTypes, for: webView)
        case .denied, .systemBlocked, .cancelled, .dismissed, .expired:
            return await revokeRuntimePermissions(decision.permissionTypes, for: webView)
        case .unsupported:
            var results: [SumiPermissionType: SumiRuntimePermissionOperationResult] = [:]
            for permissionType in concretePermissionTypes(from: decision.permissionTypes) {
                results[permissionType] = unsupportedOrNoOpResult(for: permissionType)
            }
            return SumiRuntimePermissionBatchResult(results)
        case .promptRequired, .requiresUserActivation, .ignored:
            var results: [SumiPermissionType: SumiRuntimePermissionOperationResult] = [:]
            for permissionType in concretePermissionTypes(from: decision.permissionTypes) {
                results[permissionType] = .noOp
            }
            return SumiRuntimePermissionBatchResult(results)
        }
    }

    func revokeRuntimePermissions(
        _ permissionTypes: [SumiPermissionType],
        for webView: WKWebView
    ) async -> SumiRuntimePermissionBatchResult {
        await applyBatch(permissionTypes, webView: webView) { permissionType in
            switch permissionType {
            case .camera:
                return await stopCamera(for: webView)
            case .microphone:
                return await stopMicrophone(for: webView)
            case .geolocation:
                return applyGeolocationRuntimeOperation { provider in
                    provider.revoke()
                }
            case .autoplay:
                return evaluateAutoplayPolicyChange(.blockAll, for: webView)
            case .notifications, .popups, .externalScheme, .filePicker:
                return .noOp
            case .storageAccess:
                return .unsupported(reason: "storage-access-runtime-state-unsupported")
            case .cameraAndMicrophone:
                return .unsupported(reason: "grouped-permission-should-have-expanded")
            }
        }
    }

    func pauseRuntimePermissions(
        _ permissionTypes: [SumiPermissionType],
        for webView: WKWebView
    ) async -> SumiRuntimePermissionBatchResult {
        await applyBatch(permissionTypes, webView: webView) { permissionType in
            switch permissionType {
            case .camera:
                return await setCameraMuted(true, for: webView)
            case .microphone:
                return await setMicrophoneMuted(true, for: webView)
            case .geolocation:
                return applyGeolocationRuntimeOperation { provider in
                    provider.pause()
                }
            case .autoplay:
                return evaluateAutoplayPolicyChange(.muteAudio, for: webView)
            case .notifications, .popups, .externalScheme, .filePicker:
                return .noOp
            case .storageAccess:
                return .unsupported(reason: "storage-access-runtime-state-unsupported")
            case .cameraAndMicrophone:
                return .unsupported(reason: "grouped-permission-should-have-expanded")
            }
        }
    }

    func resumeRuntimePermissions(
        _ permissionTypes: [SumiPermissionType],
        for webView: WKWebView
    ) async -> SumiRuntimePermissionBatchResult {
        await applyBatch(permissionTypes, webView: webView) { permissionType in
            switch permissionType {
            case .camera:
                return await setCameraMuted(false, for: webView)
            case .microphone:
                return await setMicrophoneMuted(false, for: webView)
            case .geolocation:
                return applyGeolocationRuntimeOperation { provider in
                    provider.resume()
                }
            case .autoplay:
                return evaluateAutoplayPolicyChange(.allowAll, for: webView)
            case .notifications, .popups, .externalScheme, .filePicker:
                return .noOp
            case .storageAccess:
                return .unsupported(reason: "storage-access-runtime-state-unsupported")
            case .cameraAndMicrophone:
                return .unsupported(reason: "grouped-permission-should-have-expanded")
            }
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
                reason: "wkwebview-autoplay-policy-is-configuration-only",
                currentAutoplayState: currentState,
                requestedAutoplayState: requestedState
            )
        )
    }

    func observeRuntimeState(
        for webView: WKWebView,
        handler: @escaping @MainActor (SumiRuntimePermissionState) -> Void
    ) -> SumiRuntimePermissionObservation {
        handler(currentRuntimeState(for: webView))

        let cameraObservation = webView.observe(\.cameraCaptureState, options: [.new]) { [weak self, weak webView] _, _ in
            Task { @MainActor [weak self, weak webView] in
                guard let self, let webView else { return }
                handler(self.currentRuntimeState(for: webView))
            }
        }
        let microphoneObservation = webView.observe(\.microphoneCaptureState, options: [.new]) { [weak self, weak webView] _, _ in
            Task { @MainActor [weak self, weak webView] in
                guard let self, let webView else { return }
                handler(self.currentRuntimeState(for: webView))
            }
        }
        let geolocationObservation = geolocationProvider?.observeState { [weak self, weak webView] _ in
            guard let self, let webView else { return }
            handler(self.currentRuntimeState(for: webView))
        }

        return SumiRuntimePermissionObservation {
            cameraObservation.invalidate()
            microphoneObservation.invalidate()
            geolocationObservation?.cancel()
        }
    }

    private func geolocationState() -> SumiGeolocationRuntimeState {
        guard let geolocationProvider else {
            return .unsupportedProvider
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
        _ operation: (any SumiGeolocationProviding) -> SumiGeolocationProviderState
    ) -> SumiRuntimePermissionOperationResult {
        guard let geolocationProvider else {
            return .unsupported(reason: "geolocation-runtime-provider-unsupported")
        }
        guard geolocationProvider.currentState != .unavailable else {
            return .unsupported(reason: "geolocation-runtime-provider-unavailable")
        }

        let previousState = geolocationProvider.currentState
        let nextState = operation(geolocationProvider)
        if nextState == previousState {
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

    private func aggregateMediaResults(
        _ results: [SumiRuntimePermissionOperationResult]
    ) -> SumiRuntimePermissionOperationResult {
        if let failed = results.first(where: {
            if case .failed = $0 { return true }
            return false
        }) {
            return failed
        }
        if let denied = results.first(where: {
            if case .deniedByRuntime = $0 { return true }
            return false
        }) {
            return denied
        }
        if let unsupported = results.first(where: {
            if case .unsupported = $0 { return true }
            return false
        }) {
            return unsupported
        }
        return results.contains(.applied) ? .applied : .noOp
    }

    private func applyBatch(
        _ permissionTypes: [SumiPermissionType],
        webView: WKWebView,
        operation: (SumiPermissionType) async -> SumiRuntimePermissionOperationResult
    ) async -> SumiRuntimePermissionBatchResult {
        var results: [SumiPermissionType: SumiRuntimePermissionOperationResult] = [:]
        for permissionType in concretePermissionTypes(from: permissionTypes) {
            results[permissionType] = await operation(permissionType)
        }
        return SumiRuntimePermissionBatchResult(results)
    }

    private func concretePermissionTypes(
        from permissionTypes: [SumiPermissionType]
    ) -> [SumiPermissionType] {
        permissionTypes.flatMap { permissionType in
            switch permissionType {
            case .cameraAndMicrophone:
                return [SumiPermissionType.camera, .microphone]
            default:
                return [permissionType]
            }
        }
    }

    private func unsupportedOrNoOpResult(
        for permissionType: SumiPermissionType
    ) -> SumiRuntimePermissionOperationResult {
        switch permissionType {
        case .camera, .microphone, .geolocation, .storageAccess:
            return .unsupported(reason: "runtime-operation-unsupported")
        case .cameraAndMicrophone:
            return .unsupported(reason: "grouped-permission-should-have-expanded")
        case .notifications, .popups, .externalScheme, .autoplay, .filePicker:
            return .noOp
        }
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
            return .muteAudio
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

    deinit {
        cancellation?()
    }
}

private extension SumiRuntimeAutoplayState {
    var isConcreteAutoplayPolicy: Bool {
        switch self {
        case .allowAll, .muteAudio, .blockAll:
            return true
        case .reloadRequired, .unsupported:
            return false
        }
    }
}
