import WebKit

@testable import Sumi

@MainActor
final class FakeSumiRuntimePermissionController: SumiRuntimePermissionControlling {
    var cameraRuntimeState: SumiMediaCaptureRuntimeState {
        didSet { emitStateChange() }
    }
    var microphoneRuntimeState: SumiMediaCaptureRuntimeState {
        didSet { emitStateChange() }
    }
    var geolocationRuntimeState: SumiGeolocationRuntimeState {
        didSet { emitStateChange() }
    }
    var autoplayRuntimeState: SumiRuntimeAutoplayState {
        didSet { emitStateChange() }
    }

    var unsupportedOperations: Set<SumiRuntimePermissionOperation> = []
    var failedOperations: [SumiRuntimePermissionOperation: String] = [:]
    var deniedOperations: [SumiRuntimePermissionOperation: String] = [:]
    var autoplayChangesRequireReload = true

    private var observers: [UUID: @MainActor (SumiRuntimePermissionState) -> Void] = [:]

    init(
        cameraRuntimeState: SumiMediaCaptureRuntimeState = .none,
        microphoneRuntimeState: SumiMediaCaptureRuntimeState = .none,
        geolocationRuntimeState: SumiGeolocationRuntimeState = .unsupportedProvider,
        autoplayRuntimeState: SumiRuntimeAutoplayState = .allowAll
    ) {
        self.cameraRuntimeState = cameraRuntimeState
        self.microphoneRuntimeState = microphoneRuntimeState
        self.geolocationRuntimeState = geolocationRuntimeState
        self.autoplayRuntimeState = autoplayRuntimeState
    }

    static func bothActive() -> FakeSumiRuntimePermissionController {
        FakeSumiRuntimePermissionController(
            cameraRuntimeState: .active,
            microphoneRuntimeState: .active
        )
    }

    func currentRuntimeState(for webView: WKWebView) -> SumiRuntimePermissionState {
        SumiRuntimePermissionState(
            camera: cameraRuntimeState,
            microphone: microphoneRuntimeState,
            geolocation: geolocationRuntimeState,
            autoplay: autoplayRuntimeState
        )
    }

    func cameraState(for webView: WKWebView) -> SumiMediaCaptureRuntimeState {
        cameraRuntimeState
    }

    func microphoneState(for webView: WKWebView) -> SumiMediaCaptureRuntimeState {
        microphoneRuntimeState
    }

    func setCameraMuted(
        _ muted: Bool,
        for webView: WKWebView
    ) async -> SumiRuntimePermissionOperationResult {
        let operation = SumiRuntimePermissionOperation.setCameraMuted(muted)
        if let override = configuredResult(for: operation) {
            return override
        }
        return applyMediaMutation(
            currentState: &cameraRuntimeState,
            requestedState: muted ? .muted : .active
        )
    }

    func setMicrophoneMuted(
        _ muted: Bool,
        for webView: WKWebView
    ) async -> SumiRuntimePermissionOperationResult {
        let operation = SumiRuntimePermissionOperation.setMicrophoneMuted(muted)
        if let override = configuredResult(for: operation) {
            return override
        }
        return applyMediaMutation(
            currentState: &microphoneRuntimeState,
            requestedState: muted ? .muted : .active
        )
    }

    func stopCamera(for webView: WKWebView) async -> SumiRuntimePermissionOperationResult {
        let operation = SumiRuntimePermissionOperation.stopCamera
        if let override = configuredResult(for: operation) {
            return override
        }
        return applyMediaMutation(currentState: &cameraRuntimeState, requestedState: .none)
    }

    func stopMicrophone(for webView: WKWebView) async -> SumiRuntimePermissionOperationResult {
        let operation = SumiRuntimePermissionOperation.stopMicrophone
        if let override = configuredResult(for: operation) {
            return override
        }
        return applyMediaMutation(currentState: &microphoneRuntimeState, requestedState: .none)
    }

    func stopAllMediaCapture(for webView: WKWebView) async -> SumiRuntimePermissionOperationResult {
        let operation = SumiRuntimePermissionOperation.stopAllMediaCapture
        if let override = configuredResult(for: operation) {
            return override
        }

        let cameraResult = await stopCamera(for: webView)
        let microphoneResult = await stopMicrophone(for: webView)
        return aggregate([cameraResult, microphoneResult])
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
            for permissionType in expandedPermissionTypes(from: decision.permissionTypes) {
                results[permissionType] = .unsupported(reason: "runtime-operation-unsupported")
            }
            return SumiRuntimePermissionBatchResult(results)
        case .promptRequired, .requiresUserActivation, .ignored:
            var results: [SumiPermissionType: SumiRuntimePermissionOperationResult] = [:]
            for permissionType in expandedPermissionTypes(from: decision.permissionTypes) {
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
            let operation = SumiRuntimePermissionOperation.revoke(permissionType)
            if let override = configuredResult(for: operation) {
                return override
            }

            switch permissionType {
            case .camera:
                return await stopCamera(for: webView)
            case .microphone:
                return await stopMicrophone(for: webView)
            case .geolocation:
                geolocationRuntimeState = .revoked
                return .applied
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
            let operation = SumiRuntimePermissionOperation.pause(permissionType)
            if let override = configuredResult(for: operation) {
                return override
            }

            switch permissionType {
            case .camera:
                return await setCameraMuted(true, for: webView)
            case .microphone:
                return await setMicrophoneMuted(true, for: webView)
            case .geolocation:
                geolocationRuntimeState = .paused
                return .applied
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
            let operation = SumiRuntimePermissionOperation.resume(permissionType)
            if let override = configuredResult(for: operation) {
                return override
            }

            switch permissionType {
            case .camera:
                return await setCameraMuted(false, for: webView)
            case .microphone:
                return await setMicrophoneMuted(false, for: webView)
            case .geolocation:
                geolocationRuntimeState = .active
                return .applied
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
        let operation = SumiRuntimePermissionOperation.autoplay(requestedState)
        if let override = configuredResult(for: operation) {
            return override
        }
        guard requestedState == .allowAll || requestedState == .muteAudio || requestedState == .blockAll else {
            return .unsupported(reason: "autoplay-policy-state-not-applicable")
        }
        guard autoplayRuntimeState != requestedState else {
            return .noOp
        }
        guard autoplayChangesRequireReload == false else {
            return .requiresReload(
                SumiRuntimePermissionReloadRequirement(
                    kind: .rebuild,
                    permissionType: .autoplay,
                    reason: "fake-autoplay-policy-requires-reload",
                    currentAutoplayState: autoplayRuntimeState,
                    requestedAutoplayState: requestedState
                )
            )
        }

        autoplayRuntimeState = requestedState
        return .applied
    }

    func observeRuntimeState(
        for webView: WKWebView,
        handler: @escaping @MainActor (SumiRuntimePermissionState) -> Void
    ) -> SumiRuntimePermissionObservation {
        let id = UUID()
        observers[id] = handler
        handler(currentRuntimeState(for: webView))

        return SumiRuntimePermissionObservation { [weak self] in
            self?.observers[id] = nil
        }
    }

    private func configuredResult(
        for operation: SumiRuntimePermissionOperation
    ) -> SumiRuntimePermissionOperationResult? {
        if let reason = failedOperations[operation] {
            return .failed(reason: reason)
        }
        if let reason = deniedOperations[operation] {
            return .deniedByRuntime(reason: reason)
        }
        if unsupportedOperations.contains(operation) {
            return .unsupported(reason: "fake-operation-unsupported")
        }
        return nil
    }

    private func applyMediaMutation(
        currentState: inout SumiMediaCaptureRuntimeState,
        requestedState: SumiMediaCaptureRuntimeState
    ) -> SumiRuntimePermissionOperationResult {
        guard currentState != .unavailable else {
            return .unsupported(reason: "media-capture-unavailable")
        }
        guard currentState != .unsupported else {
            return .unsupported(reason: "media-capture-unsupported")
        }
        guard currentState != requestedState else {
            return .noOp
        }
        guard currentState != .none || requestedState == .none else {
            return .noOp
        }

        currentState = requestedState
        return .applied
    }

    private func applyBatch(
        _ permissionTypes: [SumiPermissionType],
        webView: WKWebView,
        operation: (SumiPermissionType) async -> SumiRuntimePermissionOperationResult
    ) async -> SumiRuntimePermissionBatchResult {
        var results: [SumiPermissionType: SumiRuntimePermissionOperationResult] = [:]
        for permissionType in expandedPermissionTypes(from: permissionTypes) {
            results[permissionType] = await operation(permissionType)
        }
        return SumiRuntimePermissionBatchResult(results)
    }

    private func expandedPermissionTypes(
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

    private func aggregate(
        _ results: [SumiRuntimePermissionOperationResult]
    ) -> SumiRuntimePermissionOperationResult {
        if let failed = results.first(where: {
            if case .failed = $0 { return true }
            return false
        }) {
            return failed
        }
        if let unsupported = results.first(where: {
            if case .unsupported = $0 { return true }
            return false
        }) {
            return unsupported
        }
        return results.contains(.applied) ? .applied : .noOp
    }

    private func emitStateChange() {
        guard observers.isEmpty == false else { return }
        let state = SumiRuntimePermissionState(
            camera: cameraRuntimeState,
            microphone: microphoneRuntimeState,
            geolocation: geolocationRuntimeState,
            autoplay: autoplayRuntimeState
        )
        for observer in observers.values {
            observer(state)
        }
    }
}
