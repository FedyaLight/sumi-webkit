import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SumiRuntimePermissionControllerTests: XCTestCase {
    func testMediaCaptureStateMapsFromPublicWebKitStates() {
        XCTAssertEqual(SumiRuntimePermissionController.mediaCaptureState(from: .none), .none)
        XCTAssertEqual(SumiRuntimePermissionController.mediaCaptureState(from: .active), .active)
        XCTAssertEqual(SumiRuntimePermissionController.mediaCaptureState(from: .muted), .muted)

        let explicitState = SumiRuntimePermissionState(
            camera: .unavailable,
            microphone: .unsupported
        )
        XCTAssertEqual(explicitState.camera, .unavailable)
        XCTAssertEqual(explicitState.microphone, .unsupported)
        XCTAssertEqual(explicitState.screenCapture, .unsupported)
    }

    func testCombinedCameraAndMicrophoneStateReflectsConcreteStates() {
        let state = SumiRuntimePermissionState(camera: .active, microphone: .muted)

        XCTAssertEqual(state.cameraAndMicrophone.camera, .active)
        XCTAssertEqual(state.cameraAndMicrophone.microphone, .muted)
        XCTAssertTrue(state.cameraAndMicrophone.hasAnyActiveStream)
        XCTAssertEqual(
            state.state(for: .cameraAndMicrophone),
            .cameraAndMicrophone(SumiCameraAndMicrophoneRuntimeState(camera: .active, microphone: .muted))
        )
    }

    func testGeolocationAndNonDevicePermissionsExposeExplicitRuntimeState() {
        let state = SumiRuntimePermissionState(camera: .none, microphone: .none)

        XCTAssertEqual(state.geolocation, .unsupportedProvider)
        XCTAssertEqual(state.notifications, .noActiveRuntimeState)
        XCTAssertEqual(state.popups, .noActiveRuntimeState)
        XCTAssertEqual(state.externalScheme, .noActiveRuntimeState)
        XCTAssertEqual(state.filePicker, .noActiveRuntimeState)
        XCTAssertEqual(state.storageAccess, .unsupported)
        XCTAssertEqual(state.screenCapture, .unsupported)
        XCTAssertEqual(state.state(for: .notifications), .nonDevice(.noActiveRuntimeState))
        XCTAssertEqual(state.state(for: .screenCapture), .media(.unsupported))
        XCTAssertEqual(state.state(for: .storageAccess), .nonDevice(.unsupported))
    }

    func testProviderBackedGeolocationRuntimeStateMapsFromProviderState() {
        let provider = FakeSumiGeolocationProvider(currentState: .active)
        let controller = SumiRuntimePermissionController(geolocationProvider: provider)
        let webView = makeWebView()

        XCTAssertEqual(controller.currentRuntimeState(for: webView).geolocation, .active)

        provider.currentState = .paused
        XCTAssertEqual(controller.currentRuntimeState(for: webView).geolocation, .paused)

        provider.currentState = .revoked
        XCTAssertEqual(controller.currentRuntimeState(for: webView).geolocation, .revoked)

        provider.currentState = .unavailable
        XCTAssertEqual(controller.currentRuntimeState(for: webView).geolocation, .unavailable)
    }

    func testProviderBackedGeolocationRuntimeStateCanBeScopedToCurrentPage() {
        let provider = FakeSumiGeolocationProvider(currentState: .active)
        provider.registerAllowedRequest(pageId: "tab-a:1", tabId: "tab-a")
        let controller = SumiRuntimePermissionController(geolocationProvider: provider)
        let webView = makeWebView()

        XCTAssertEqual(
            controller.currentRuntimeState(for: webView, pageId: "tab-a:1").geolocation,
            .active
        )
        XCTAssertEqual(
            controller.currentRuntimeState(for: webView, pageId: "tab-a:2").geolocation,
            .none
        )
    }

    func testProviderBackedGeolocationPauseResumeRevokeOperations() async {
        let provider = FakeSumiGeolocationProvider(currentState: .active)
        let controller = SumiRuntimePermissionController(geolocationProvider: provider)
        let webView = makeWebView()

        let pause = await controller.pauseRuntimePermissions([.geolocation], for: webView)
        let resume = await controller.resumeRuntimePermissions([.geolocation], for: webView)
        let revoke = await controller.revokeRuntimePermissions([.geolocation], for: webView)

        XCTAssertEqual(pause[.geolocation], .applied)
        XCTAssertEqual(resume[.geolocation], .applied)
        XCTAssertEqual(revoke[.geolocation], .applied)
        XCTAssertEqual(provider.pauseCallCount, 1)
        XCTAssertEqual(provider.resumeCallCount, 1)
        XCTAssertEqual(provider.revokeCallCount, 1)
        XCTAssertEqual(provider.currentState, .revoked)
    }

    func testPageScopedGeolocationStopClearsVisitWithoutGlobalRevoke() async {
        let provider = FakeSumiGeolocationProvider(currentState: .active)
        provider.registerAllowedRequest(pageId: "tab-a:1", tabId: "tab-a")
        provider.registerAllowedRequest(pageId: "tab-b:1", tabId: "tab-b")
        let controller = SumiRuntimePermissionController(geolocationProvider: provider)
        let webView = makeWebView()

        let stop = await controller.stopGeolocation(pageId: "tab-a:1", for: webView)

        XCTAssertEqual(stop, .applied)
        XCTAssertEqual(provider.stopCallCount, 1)
        XCTAssertEqual(provider.revokeCallCount, 0)
        XCTAssertFalse(provider.containsAllowedRequest(pageId: "tab-a:1"))
        XCTAssertTrue(provider.containsAllowedRequest(pageId: "tab-b:1"))
        XCTAssertEqual(provider.currentState, .active)
    }

    func testPageScopedGeolocationPauseFailsWhenPageIsNotActive() async {
        let provider = FakeSumiGeolocationProvider(currentState: .active)
        provider.registerAllowedRequest(pageId: "tab-a:1", tabId: "tab-a")
        let controller = SumiRuntimePermissionController(geolocationProvider: provider)
        let webView = makeWebView()

        let pause = await controller.pauseGeolocation(pageId: "tab-a:2", for: webView)

        XCTAssertEqual(pause, .deniedByRuntime(reason: "geolocation-runtime-page-not-active"))
        XCTAssertEqual(provider.pauseCallCount, 0)
        XCTAssertEqual(provider.currentState, .active)
    }

    func testMissingGeolocationProviderReturnsUnsupportedProvider() async {
        let controller = SumiRuntimePermissionController()
        let webView = makeWebView()

        let pause = await controller.pauseRuntimePermissions([.geolocation], for: webView)
        let resume = await controller.resumeRuntimePermissions([.geolocation], for: webView)
        let revoke = await controller.revokeRuntimePermissions([.geolocation], for: webView)

        XCTAssertEqual(controller.currentRuntimeState(for: webView).geolocation, .unsupportedProvider)
        XCTAssertEqual(
            pause[.geolocation],
            .unsupported(reason: "geolocation-runtime-provider-unsupported")
        )
        XCTAssertEqual(
            resume[.geolocation],
            .unsupported(reason: "geolocation-runtime-provider-unsupported")
        )
        XCTAssertEqual(
            revoke[.geolocation],
            .unsupported(reason: "geolocation-runtime-provider-unsupported")
        )
    }

    func testUnavailableGeolocationProviderReturnsUnsupportedOperationResult() async {
        let provider = FakeSumiGeolocationProvider(currentState: .unavailable)
        let controller = SumiRuntimePermissionController(geolocationProvider: provider)
        let webView = makeWebView()

        let pause = await controller.pauseRuntimePermissions([.geolocation], for: webView)

        XCTAssertEqual(controller.currentRuntimeState(for: webView).geolocation, .unavailable)
        XCTAssertEqual(
            pause[.geolocation],
            .unsupported(reason: "geolocation-runtime-provider-unavailable")
        )
    }

    func testFakeMuteCameraChangesActiveToMuted() async {
        let fake = FakeSumiRuntimePermissionController(cameraRuntimeState: .active)
        let webView = makeWebView()

        let result = await fake.setCameraMuted(true, for: webView)

        XCTAssertEqual(result, .applied)
        XCTAssertEqual(fake.cameraRuntimeState, .muted)
    }

    func testFakeMuteCameraWhenAlreadyMutedIsIdempotent() async {
        let fake = FakeSumiRuntimePermissionController(cameraRuntimeState: .muted)
        let webView = makeWebView()

        let result = await fake.setCameraMuted(true, for: webView)

        XCTAssertEqual(result, .noOp)
        XCTAssertEqual(fake.cameraRuntimeState, .muted)
    }

    func testFakeResumeCameraChangesMutedToActive() async {
        let fake = FakeSumiRuntimePermissionController(cameraRuntimeState: .muted)
        let webView = makeWebView()

        let result = await fake.setCameraMuted(false, for: webView)

        XCTAssertEqual(result, .applied)
        XCTAssertEqual(fake.cameraRuntimeState, .active)
    }

    func testFakeStopCameraChangesActiveOrMutedToNoneAndNoneIsIdempotent() async {
        let fake = FakeSumiRuntimePermissionController(cameraRuntimeState: .active)
        let webView = makeWebView()

        let activeStop = await fake.stopCamera(for: webView)
        let noneStop = await fake.stopCamera(for: webView)
        fake.cameraRuntimeState = .muted
        let mutedStop = await fake.stopCamera(for: webView)

        XCTAssertEqual(activeStop, .applied)
        XCTAssertEqual(noneStop, .noOp)
        XCTAssertEqual(mutedStop, .applied)
        XCTAssertEqual(fake.cameraRuntimeState, .none)
    }

    func testFakeMicrophoneMuteResumeAndStopMirrorCameraBehavior() async {
        let fake = FakeSumiRuntimePermissionController(microphoneRuntimeState: .active)
        let webView = makeWebView()

        let mute = await fake.setMicrophoneMuted(true, for: webView)
        let duplicateMute = await fake.setMicrophoneMuted(true, for: webView)
        let resume = await fake.setMicrophoneMuted(false, for: webView)
        let stop = await fake.stopMicrophone(for: webView)
        let duplicateStop = await fake.stopMicrophone(for: webView)

        XCTAssertEqual(mute, .applied)
        XCTAssertEqual(duplicateMute, .noOp)
        XCTAssertEqual(resume, .applied)
        XCTAssertEqual(stop, .applied)
        XCTAssertEqual(duplicateStop, .noOp)
        XCTAssertEqual(fake.microphoneRuntimeState, .none)
    }

    func testFakeStopAllMediaCaptureClearsCameraAndMicrophone() async {
        let fake = FakeSumiRuntimePermissionController.bothActive()
        let webView = makeWebView()

        let result = await fake.stopAllMediaCapture(for: webView)

        XCTAssertEqual(result, .applied)
        XCTAssertEqual(fake.cameraRuntimeState, .none)
        XCTAssertEqual(fake.microphoneRuntimeState, .none)
    }

    func testFakeUnsupportedOperationReturnsUnsupportedWithoutMutation() async {
        let fake = FakeSumiRuntimePermissionController(cameraRuntimeState: .active)
        fake.unsupportedOperations.insert(.setCameraMuted(true))
        let webView = makeWebView()

        let result = await fake.setCameraMuted(true, for: webView)

        XCTAssertEqual(result, .unsupported(reason: "fake-operation-unsupported"))
        XCTAssertEqual(fake.cameraRuntimeState, .active)
    }

    func testFakeFailedOperationReturnsFailedWithoutCorruptingState() async {
        let fake = FakeSumiRuntimePermissionController(cameraRuntimeState: .active)
        fake.failedOperations[.stopCamera] = "device-error"
        let webView = makeWebView()

        let result = await fake.stopCamera(for: webView)

        XCTAssertEqual(result, .failed(reason: "device-error"))
        XCTAssertEqual(fake.cameraRuntimeState, .active)
    }

    func testFakeRevokeMultiplePermissionsReportsPerPermissionResults() async {
        let fake = FakeSumiRuntimePermissionController.bothActive()
        let webView = makeWebView()

        let result = await fake.revokeRuntimePermissions([.camera, .microphone], for: webView)

        XCTAssertEqual(result[.camera], .applied)
        XCTAssertEqual(result[.microphone], .applied)
        XCTAssertEqual(fake.cameraRuntimeState, .none)
        XCTAssertEqual(fake.microphoneRuntimeState, .none)
    }

    func testFakeCameraAndMicrophoneExpandsForRuntimeOperations() async {
        let fake = FakeSumiRuntimePermissionController.bothActive()
        let webView = makeWebView()

        let result = await fake.revokeRuntimePermissions([.cameraAndMicrophone], for: webView)

        XCTAssertEqual(result[.camera], .applied)
        XCTAssertEqual(result[.microphone], .applied)
        XCTAssertNil(result[.cameraAndMicrophone])
        XCTAssertEqual(fake.cameraRuntimeState, .none)
        XCTAssertEqual(fake.microphoneRuntimeState, .none)
    }

    func testFakeNonDevicePermissionOperationsDoNotCrash() async {
        let fake = FakeSumiRuntimePermissionController()
        let webView = makeWebView()

        let result = await fake.revokeRuntimePermissions(
            [.notifications, .popups, .externalScheme("MailTo"), .filePicker, .storageAccess],
            for: webView
        )

        XCTAssertEqual(result[.notifications], .noOp)
        XCTAssertEqual(result[.popups], .noOp)
        XCTAssertEqual(result[.externalScheme("mailto")], .noOp)
        XCTAssertEqual(result[.filePicker], .noOp)
        XCTAssertEqual(
            result[.storageAccess],
            .unsupported(reason: "storage-access-runtime-state-unsupported")
        )
    }

    func testFakeScreenCaptureRuntimeStateAndStopAreExplicit() async {
        let fake = FakeSumiRuntimePermissionController(screenCaptureRuntimeState: .active)
        let webView = makeWebView()

        XCTAssertEqual(fake.currentRuntimeState(for: webView).screenCapture, .active)
        XCTAssertEqual(fake.screenCaptureState(for: webView), .active)

        let stop = await fake.stopScreenCapture(for: webView)
        let duplicateStop = await fake.stopScreenCapture(for: webView)

        XCTAssertEqual(stop, .applied)
        XCTAssertEqual(duplicateStop, .noOp)
        XCTAssertEqual(fake.screenCaptureRuntimeState, .none)
    }

    func testFakeScreenCapturePauseResumeAreUnsupportedWithoutObservableWebKitState() async {
        let fake = FakeSumiRuntimePermissionController(screenCaptureRuntimeState: .active)
        let webView = makeWebView()

        let pause = await fake.pauseRuntimePermissions([.screenCapture], for: webView)
        let resume = await fake.resumeRuntimePermissions([.screenCapture], for: webView)

        XCTAssertEqual(
            pause[.screenCapture],
            .unsupported(reason: "screen-capture-runtime-state-unsupported")
        )
        XCTAssertEqual(
            resume[.screenCapture],
            .unsupported(reason: "screen-capture-runtime-state-unsupported")
        )
        XCTAssertEqual(fake.screenCaptureRuntimeState, .active)
    }

    func testApplyDeniedRuntimeDecisionRevokesConcreteMediaTypes() async {
        let fake = FakeSumiRuntimePermissionController.bothActive()
        let webView = makeWebView()
        let decision = SumiPermissionCoordinatorDecision(
            outcome: .denied,
            state: .deny,
            persistence: nil,
            source: .user,
            reason: "blocked",
            permissionTypes: [.cameraAndMicrophone]
        )

        let result = await fake.applyRuntimeDecision(decision, to: webView)

        XCTAssertEqual(result[.camera], .applied)
        XCTAssertEqual(result[.microphone], .applied)
        XCTAssertEqual(fake.cameraRuntimeState, .none)
        XCTAssertEqual(fake.microphoneRuntimeState, .none)
    }

    func testWKWebViewBackedControllerMapsNoActiveMediaStateToNone() {
        let controller = SumiRuntimePermissionController()
        let webView = makeWebView()

        let state = controller.currentRuntimeState(for: webView)

        XCTAssertEqual(state.camera, .none)
        XCTAssertEqual(state.microphone, .none)
        XCTAssertEqual(state.screenCapture, .unsupported)
        XCTAssertEqual(controller.cameraState(for: webView), .none)
        XCTAssertEqual(controller.microphoneState(for: webView), .none)
        XCTAssertEqual(controller.screenCaptureState(for: webView), .unsupported)
    }

    func testWKWebViewBackedNoActiveMediaOperationsAreNoOpAndDoNotCrash() async {
        let controller = SumiRuntimePermissionController()
        let webView = makeWebView()

        let muteCamera = await controller.setCameraMuted(true, for: webView)
        let resumeMicrophone = await controller.setMicrophoneMuted(false, for: webView)
        let stopCamera = await controller.stopCamera(for: webView)
        let stopScreenCapture = await controller.stopScreenCapture(for: webView)
        let stopAll = await controller.stopAllMediaCapture(for: webView)

        XCTAssertEqual(muteCamera, .noOp)
        XCTAssertEqual(resumeMicrophone, .noOp)
        XCTAssertEqual(stopCamera, .noOp)
        XCTAssertEqual(
            stopScreenCapture,
            .unsupported(reason: "screen-capture-runtime-state-unsupported")
        )
        XCTAssertEqual(stopAll, .noOp)
    }

    func testWKWebViewBackedObservationEmitsInitialSnapshotAndCanDetach() {
        let controller = SumiRuntimePermissionController()
        let webView = makeWebView()
        var observedStates: [SumiRuntimePermissionState] = []

        let observation = controller.observeRuntimeState(for: webView) { state in
            observedStates.append(state)
        }
        observation.cancel()

        XCTAssertEqual(observedStates.count, 1)
        XCTAssertEqual(observedStates.first?.camera, Optional(SumiMediaCaptureRuntimeState.none))
        XCTAssertEqual(observedStates.first?.microphone, Optional(SumiMediaCaptureRuntimeState.none))
        XCTAssertEqual(observedStates.first?.screenCapture, Optional(SumiMediaCaptureRuntimeState.unsupported))
    }

    func testAutoplayPolicyChangeRequiresReloadForCurrentArchitecture() {
        let controller = SumiRuntimePermissionController()
        let webView = makeWebView(autoplay: [])

        let result = controller.evaluateAutoplayPolicyChange(.blockAll, for: webView)

        guard case .requiresReload(let requirement) = result else {
            return XCTFail("Expected autoplay change to require reload")
        }
        XCTAssertEqual(requirement.kind, .rebuild)
        XCTAssertEqual(requirement.permissionType, .autoplay)
        XCTAssertEqual(requirement.currentAutoplayState, .allowAll)
        XCTAssertEqual(requirement.requestedAutoplayState, .blockAll)
    }

    func testAutoplayPolicyNoChangeIsNoOp() {
        let controller = SumiRuntimePermissionController()
        let webView = makeWebView(autoplay: [])

        let result = controller.evaluateAutoplayPolicyChange(.allowAll, for: webView)

        XCTAssertEqual(result, .noOp)
    }

    func testRuntimeControllerDoesNotTouchExistingAutoplayStoreOrBrowserConfig() throws {
        let source = try sourceFile("Sumi/Permissions/SumiRuntimePermissionController.swift")

        XCTAssertFalse(source.contains("SitePermissionOverridesStore"))
        XCTAssertFalse(source.contains("BrowserConfiguration"))
        XCTAssertFalse(source.contains("BrowserConfig"))
    }

    func testFakeObserverReceivesStateChangesAndDetachStopsUpdates() {
        let fake = FakeSumiRuntimePermissionController()
        let webView = makeWebView()
        var observedStates: [SumiRuntimePermissionState] = []

        let observation = fake.observeRuntimeState(for: webView) { state in
            observedStates.append(state)
        }
        fake.cameraRuntimeState = .active
        observation.cancel()
        fake.cameraRuntimeState = .muted

        XCTAssertEqual(observedStates.map(\.camera), [.none, .active])
        XCTAssertEqual(observedStates.map(\.screenCapture), [.unsupported, .unsupported])
    }

    func testFakeObservationCancelReleasesHandlerCaptures() {
        final class LifetimeProbe {}

        let fake = FakeSumiRuntimePermissionController()
        let webView = makeWebView()
        var observation: SumiRuntimePermissionObservation?
        weak var weakProbe: LifetimeProbe?

        do {
            let probe = LifetimeProbe()
            weakProbe = probe
            observation = fake.observeRuntimeState(for: webView) { _ in
                _ = probe
            }
        }

        XCTAssertNotNil(weakProbe)
        observation?.cancel()
        observation = nil
        XCTAssertNil(weakProbe)
    }

    private func makeWebView(
        autoplay: WKAudiovisualMediaTypes = []
    ) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.mediaTypesRequiringUserActionForPlayback = autoplay
        return WKWebView(frame: .zero, configuration: configuration)
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repoRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
