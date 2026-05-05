import WebKit

@testable import Sumi

enum SumiRuntimePermissionOperation: Hashable {
    case setCameraMuted(Bool)
    case setMicrophoneMuted(Bool)
    case stopCamera
    case stopMicrophone
    case stopScreenCapture
    case stopAllMediaCapture
    case revoke(SumiPermissionType)
    case pause(SumiPermissionType)
    case resume(SumiPermissionType)
    case autoplay(SumiRuntimeAutoplayState)
}

struct SumiRuntimePermissionBatchResult: Equatable {
    private let results: [SumiPermissionType: SumiRuntimePermissionOperationResult]

    init(_ results: [SumiPermissionType: SumiRuntimePermissionOperationResult]) {
        self.results = results
    }

    subscript(_ permissionType: SumiPermissionType) -> SumiRuntimePermissionOperationResult? {
        results[permissionType]
    }
}

@MainActor
final class FakeSumiRuntimePermissionController: SumiRuntimePermissionControlling {
    var cameraRuntimeState: SumiMediaCaptureRuntimeState {
        didSet { emitStateChange() }
    }
    var microphoneRuntimeState: SumiMediaCaptureRuntimeState {
        didSet { emitStateChange() }
    }
    var screenCaptureRuntimeState: SumiMediaCaptureRuntimeState {
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
    private(set) var currentRuntimeStateCallCount = 0
    private(set) var revokeRuntimePermissionsCallCount = 0
    private(set) var pauseRuntimePermissionsCallCount = 0
    private(set) var resumeRuntimePermissionsCallCount = 0

    private var observers: [UUID: @MainActor (SumiRuntimePermissionState) -> Void] = [:]

    init(
        cameraRuntimeState: SumiMediaCaptureRuntimeState = .none,
        microphoneRuntimeState: SumiMediaCaptureRuntimeState = .none,
        screenCaptureRuntimeState: SumiMediaCaptureRuntimeState = .unsupported,
        geolocationRuntimeState: SumiGeolocationRuntimeState = .unsupportedProvider,
        autoplayRuntimeState: SumiRuntimeAutoplayState = .allowAll
    ) {
        self.cameraRuntimeState = cameraRuntimeState
        self.microphoneRuntimeState = microphoneRuntimeState
        self.screenCaptureRuntimeState = screenCaptureRuntimeState
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
        currentRuntimeState(for: webView, pageId: nil)
    }

    func currentRuntimeState(for webView: WKWebView, pageId: String?) -> SumiRuntimePermissionState {
        currentRuntimeStateCallCount += 1
        return SumiRuntimePermissionState(
            camera: cameraRuntimeState,
            microphone: microphoneRuntimeState,
            screenCapture: screenCaptureRuntimeState,
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

    func screenCaptureState(for webView: WKWebView) -> SumiMediaCaptureRuntimeState {
        screenCaptureRuntimeState
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

    func stopScreenCapture(for webView: WKWebView) async -> SumiRuntimePermissionOperationResult {
        let operation = SumiRuntimePermissionOperation.stopScreenCapture
        if let override = configuredResult(for: operation) {
            return override
        }
        return applyMediaMutation(currentState: &screenCaptureRuntimeState, requestedState: .none)
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

    func pauseGeolocation(
        pageId: String?,
        for webView: WKWebView
    ) async -> SumiRuntimePermissionOperationResult {
        await geolocationOperation(.pause(.geolocation), pageId: pageId) {
            geolocationRuntimeState = .paused
        }
    }

    func resumeGeolocation(
        pageId: String?,
        for webView: WKWebView
    ) async -> SumiRuntimePermissionOperationResult {
        await geolocationOperation(.resume(.geolocation), pageId: pageId) {
            geolocationRuntimeState = .active
        }
    }

    func stopGeolocation(
        pageId: String?,
        for webView: WKWebView
    ) async -> SumiRuntimePermissionOperationResult {
        await geolocationOperation(.revoke(.geolocation), pageId: pageId) {
            geolocationRuntimeState = .none
        }
    }

    func applyRuntimeDecision(
        _ decision: SumiPermissionCoordinatorDecision,
        to webView: WKWebView
    ) async -> SumiRuntimePermissionBatchResult {
        switch decision.outcome {
        case .granted:
            return await resumeRuntimePermissions(decision.permissionTypes, for: webView)
        case .denied, .systemBlocked, .cancelled, .dismissed, .suppressed, .expired:
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
        revokeRuntimePermissionsCallCount += 1
        return await applyBatch(permissionTypes, webView: webView) { permissionType in
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
            case .screenCapture:
                return await stopScreenCapture(for: webView)
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
        pauseRuntimePermissionsCallCount += 1
        return await applyBatch(permissionTypes, webView: webView) { permissionType in
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
            case .screenCapture:
                return .unsupported(reason: "screen-capture-runtime-state-unsupported")
            case .autoplay:
                return evaluateAutoplayPolicyChange(.blockAudible, for: webView)
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
        resumeRuntimePermissionsCallCount += 1
        return await applyBatch(permissionTypes, webView: webView) { permissionType in
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
            case .screenCapture:
                return .unsupported(reason: "screen-capture-runtime-state-unsupported")
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
        guard requestedState == .allowAll || requestedState == .blockAudible || requestedState == .blockAll else {
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
        observeRuntimeState(for: webView, pageId: nil, handler: handler)
    }

    func observeRuntimeState(
        for webView: WKWebView,
        pageId: String?,
        handler: @escaping @MainActor (SumiRuntimePermissionState) -> Void
    ) -> SumiRuntimePermissionObservation {
        let id = UUID()
        observers[id] = handler
        handler(currentRuntimeState(for: webView, pageId: pageId))

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

    private func geolocationOperation(
        _ operation: SumiRuntimePermissionOperation,
        pageId: String?,
        mutation: () -> Void
    ) async -> SumiRuntimePermissionOperationResult {
        if let override = configuredResult(for: operation) {
            return override
        }
        guard geolocationRuntimeState != .unsupportedProvider else {
            return .unsupported(reason: "geolocation-runtime-provider-unsupported")
        }
        guard geolocationRuntimeState != .unavailable else {
            return .unsupported(reason: "geolocation-runtime-provider-unavailable")
        }
        let oldState = geolocationRuntimeState
        mutation()
        return oldState == geolocationRuntimeState ? .noOp : .applied
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
            screenCapture: screenCaptureRuntimeState,
            geolocation: geolocationRuntimeState,
            autoplay: autoplayRuntimeState
        )
        for observer in observers.values {
            observer(state)
        }
    }
}

@MainActor
extension SumiRuntimePermissionControlling {
    func observeRuntimeState(
        for webView: WKWebView,
        handler: @escaping @MainActor (SumiRuntimePermissionState) -> Void
    ) -> SumiRuntimePermissionObservation {
        observeRuntimeState(for: webView, pageId: nil, handler: handler)
    }
}

@MainActor
extension SumiRuntimePermissionController {
    func cameraState(for webView: WKWebView) -> SumiMediaCaptureRuntimeState {
        currentRuntimeState(for: webView).camera
    }

    func microphoneState(for webView: WKWebView) -> SumiMediaCaptureRuntimeState {
        currentRuntimeState(for: webView).microphone
    }

    func screenCaptureState(for webView: WKWebView) -> SumiMediaCaptureRuntimeState {
        currentRuntimeState(for: webView).screenCapture
    }

    func screenCaptureState() -> SumiMediaCaptureRuntimeState {
        .unsupported
    }

    func stopScreenCapture(for webView: WKWebView) async -> SumiRuntimePermissionOperationResult {
        .unsupported(reason: "screen-capture-runtime-state-unsupported")
    }

    func stopAllMediaCapture(for webView: WKWebView) async -> SumiRuntimePermissionOperationResult {
        let cameraResult = await stopCamera(for: webView)
        let microphoneResult = await stopMicrophone(for: webView)
        return aggregateRuntimePermissionResults([cameraResult, microphoneResult])
    }

    func revokeRuntimePermissions(
        _ permissionTypes: [SumiPermissionType],
        for webView: WKWebView
    ) async -> SumiRuntimePermissionBatchResult {
        await applyBatch(permissionTypes) { permissionType in
            switch permissionType {
            case .camera:
                return await stopCamera(for: webView)
            case .microphone:
                return await stopMicrophone(for: webView)
            case .geolocation:
                return await stopGeolocation(pageId: nil, for: webView)
            case .screenCapture:
                return await stopScreenCapture(for: webView)
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
        await applyBatch(permissionTypes) { permissionType in
            switch permissionType {
            case .camera:
                return await setCameraMuted(true, for: webView)
            case .microphone:
                return await setMicrophoneMuted(true, for: webView)
            case .geolocation:
                return await pauseGeolocation(pageId: nil, for: webView)
            case .screenCapture:
                return .unsupported(reason: "screen-capture-runtime-state-unsupported")
            case .autoplay:
                return evaluateAutoplayPolicyChange(.blockAudible, for: webView)
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
        await applyBatch(permissionTypes) { permissionType in
            switch permissionType {
            case .camera:
                return await setCameraMuted(false, for: webView)
            case .microphone:
                return await setMicrophoneMuted(false, for: webView)
            case .geolocation:
                return await resumeGeolocation(pageId: nil, for: webView)
            case .screenCapture:
                return .unsupported(reason: "screen-capture-runtime-state-unsupported")
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

    private func applyBatch(
        _ permissionTypes: [SumiPermissionType],
        operation: (SumiPermissionType) async -> SumiRuntimePermissionOperationResult
    ) async -> SumiRuntimePermissionBatchResult {
        var results: [SumiPermissionType: SumiRuntimePermissionOperationResult] = [:]
        for permissionType in expandedPermissionTypes(from: permissionTypes) {
            results[permissionType] = await operation(permissionType)
        }
        return SumiRuntimePermissionBatchResult(results)
    }

    private func expandedPermissionTypes(from permissionTypes: [SumiPermissionType]) -> [SumiPermissionType] {
        permissionTypes.flatMap { permissionType in
            switch permissionType {
            case .cameraAndMicrophone:
                return [SumiPermissionType.camera, .microphone]
            default:
                return [permissionType]
            }
        }
    }

    private func aggregateRuntimePermissionResults(
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
}
