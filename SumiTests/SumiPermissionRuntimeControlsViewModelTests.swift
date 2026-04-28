import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SumiPermissionRuntimeControlsViewModelTests: XCTestCase {
    func testNoRuntimeStateProducesNoControls() {
        let controls = SumiPermissionRuntimeControlsViewModel.makeControls(
            runtimeState: SumiRuntimePermissionState(
                camera: .none,
                microphone: .none,
                geolocation: .none
            ),
            reloadRequired: false,
            displayDomain: "example.com"
        )

        XCTAssertTrue(controls.isEmpty)
    }

    func testCameraRuntimeStatesProduceMuteUnmuteAndStopActions() {
        let active = SumiPermissionRuntimeControlsViewModel.makeControls(
            runtimeState: SumiRuntimePermissionState(camera: .active, microphone: .none),
            reloadRequired: false,
            displayDomain: "example.com"
        )
        let muted = SumiPermissionRuntimeControlsViewModel.makeControls(
            runtimeState: SumiRuntimePermissionState(camera: .muted, microphone: .none),
            reloadRequired: false,
            displayDomain: "example.com"
        )

        XCTAssertEqual(actions(for: .camera, in: active), [.muteCamera, .stopCamera])
        XCTAssertEqual(actions(for: .camera, in: muted), [.unmuteCamera, .stopCamera])
    }

    func testMicrophoneRuntimeStatesProduceMuteUnmuteAndStopActions() {
        let active = SumiPermissionRuntimeControlsViewModel.makeControls(
            runtimeState: SumiRuntimePermissionState(camera: .none, microphone: .active),
            reloadRequired: false,
            displayDomain: "example.com"
        )
        let muted = SumiPermissionRuntimeControlsViewModel.makeControls(
            runtimeState: SumiRuntimePermissionState(camera: .none, microphone: .muted),
            reloadRequired: false,
            displayDomain: "example.com"
        )

        XCTAssertEqual(actions(for: .microphone, in: active), [.muteMicrophone, .stopMicrophone])
        XCTAssertEqual(actions(for: .microphone, in: muted), [.unmuteMicrophone, .stopMicrophone])
    }

    func testCameraAndMicrophoneActiveProduceSeparateControls() {
        let controls = SumiPermissionRuntimeControlsViewModel.makeControls(
            runtimeState: SumiRuntimePermissionState(camera: .active, microphone: .active),
            reloadRequired: false,
            displayDomain: "example.com"
        )

        XCTAssertEqual(actions(for: .camera, in: controls), [.muteCamera, .stopCamera])
        XCTAssertEqual(actions(for: .microphone, in: controls), [.muteMicrophone, .stopMicrophone])
        XCTAssertFalse(controls.flatMap(\.actions).contains { $0.kind.rawValue == "stopAllMediaCapture" })
    }

    func testGeolocationRuntimeStatesProducePauseResumeAndStopThisVisitActions() {
        let active = SumiPermissionRuntimeControlsViewModel.makeControls(
            runtimeState: SumiRuntimePermissionState(
                camera: .none,
                microphone: .none,
                geolocation: .active
            ),
            reloadRequired: false,
            displayDomain: "example.com"
        )
        let paused = SumiPermissionRuntimeControlsViewModel.makeControls(
            runtimeState: SumiRuntimePermissionState(
                camera: .none,
                microphone: .none,
                geolocation: .paused
            ),
            reloadRequired: false,
            displayDomain: "example.com"
        )

        XCTAssertEqual(actions(for: .geolocation, in: active), [.pauseGeolocation, .stopGeolocationForVisit])
        XCTAssertEqual(actions(for: .geolocation, in: paused), [.resumeGeolocation, .stopGeolocationForVisit])
    }

    func testUnsupportedScreenCaptureProducesNoFakeStopControl() {
        let unsupported = SumiPermissionRuntimeControlsViewModel.makeControls(
            runtimeState: SumiRuntimePermissionState(
                camera: .none,
                microphone: .none,
                screenCapture: .unsupported
            ),
            reloadRequired: false,
            displayDomain: "example.com"
        )
        let active = SumiPermissionRuntimeControlsViewModel.makeControls(
            runtimeState: SumiRuntimePermissionState(
                camera: .none,
                microphone: .none,
                screenCapture: .active
            ),
            reloadRequired: false,
            displayDomain: "example.com"
        )

        XCTAssertNil(unsupported.first { $0.permissionType == .screenCapture })
        let screen = active.first { $0.permissionType == .screenCapture }
        XCTAssertEqual(screen?.actions, [])
        XCTAssertEqual(
            screen?.disabledReason,
            SumiPermissionRuntimeControlsStrings.screenSharingControlledByWebKit
        )
    }

    func testAutoplayReloadRequiredProducesReloadAction() {
        let controls = SumiPermissionRuntimeControlsViewModel.makeControls(
            runtimeState: SumiRuntimePermissionState(camera: .none, microphone: .none),
            reloadRequired: true,
            displayDomain: "example.com"
        )

        XCTAssertEqual(actions(for: .autoplay, in: controls), [.reloadAutoplay])
    }

    func testNonDevicePermissionsDoNotProduceRuntimeControls() {
        let controls = SumiPermissionRuntimeControlsViewModel.makeControls(
            runtimeState: SumiRuntimePermissionState(
                camera: .none,
                microphone: .none,
                geolocation: .none,
                notifications: .noActiveRuntimeState,
                popups: .noActiveRuntimeState,
                externalScheme: .noActiveRuntimeState,
                filePicker: .noActiveRuntimeState,
                storageAccess: .unsupported
            ),
            reloadRequired: false,
            displayDomain: "example.com"
        )

        XCTAssertTrue(controls.isEmpty)
    }

    func testMuteUnmuteAndStopCameraCallRuntimeControllerAndRefreshState() async {
        let runtime = FakeSumiRuntimePermissionController(cameraRuntimeState: .active)
        let model = SumiPermissionRuntimeControlsViewModel()
        let webView = makeWebView()
        model.load(
            pageContext: pageContext(webView: webView),
            runtimeController: runtime,
            reloadRequired: false
        )

        let mute = await model.perform(.muteCamera)
        let unmute = await model.perform(.unmuteCamera)
        let stop = await model.perform(.stopCamera)

        XCTAssertEqual(mute, .applied(message: SumiPermissionRuntimeControlsStrings.cameraMutedResult))
        XCTAssertEqual(unmute, .applied(message: SumiPermissionRuntimeControlsStrings.cameraUnmutedResult))
        XCTAssertEqual(stop, .applied(message: SumiPermissionRuntimeControlsStrings.cameraStoppedResult))
        XCTAssertEqual(runtime.cameraRuntimeState, .none)
        XCTAssertNil(model.controls.first { $0.permissionType == .camera })
    }

    func testMuteUnmuteAndStopMicrophoneCallRuntimeControllerAndRefreshState() async {
        let runtime = FakeSumiRuntimePermissionController(microphoneRuntimeState: .active)
        let model = SumiPermissionRuntimeControlsViewModel()
        let webView = makeWebView()
        model.load(
            pageContext: pageContext(webView: webView),
            runtimeController: runtime,
            reloadRequired: false
        )

        _ = await model.perform(.muteMicrophone)
        _ = await model.perform(.unmuteMicrophone)
        let stop = await model.perform(.stopMicrophone)

        XCTAssertEqual(stop, .applied(message: SumiPermissionRuntimeControlsStrings.microphoneStoppedResult))
        XCTAssertEqual(runtime.microphoneRuntimeState, .none)
        XCTAssertNil(model.controls.first { $0.permissionType == .microphone })
    }

    func testGeolocationPauseResumeAndStopCallRuntimeController() async {
        let runtime = FakeSumiRuntimePermissionController(geolocationRuntimeState: .active)
        let model = SumiPermissionRuntimeControlsViewModel()
        let webView = makeWebView()
        model.load(
            pageContext: pageContext(webView: webView),
            runtimeController: runtime,
            reloadRequired: false
        )

        let pause = await model.perform(.pauseGeolocation)
        let resume = await model.perform(.resumeGeolocation)
        let stop = await model.perform(.stopGeolocationForVisit)

        XCTAssertEqual(pause, .applied(message: SumiPermissionRuntimeControlsStrings.locationPausedResult))
        XCTAssertEqual(resume, .applied(message: SumiPermissionRuntimeControlsStrings.locationResumedResult))
        XCTAssertEqual(stop, .applied(message: SumiPermissionRuntimeControlsStrings.locationStoppedResult))
        XCTAssertEqual(runtime.geolocationRuntimeState, .none)
    }

    func testResumeGeolocationFailsDeterministicallyWhenSitePermissionNoLongerAllowed() async {
        let runtime = FakeSumiRuntimePermissionController(geolocationRuntimeState: .paused)
        let model = SumiPermissionRuntimeControlsViewModel()
        let webView = makeWebView()
        model.load(
            pageContext: pageContext(webView: webView, geolocationAllowed: false),
            runtimeController: runtime,
            reloadRequired: false
        )

        let result = await model.perform(.resumeGeolocation)

        XCTAssertEqual(result, .denied(message: SumiPermissionRuntimeControlsStrings.locationNoLongerAllowed))
        XCTAssertEqual(runtime.geolocationRuntimeState, .paused)
    }

    func testUnsupportedOperationShowsDeterministicFailureWithoutMutation() async {
        let runtime = FakeSumiRuntimePermissionController(cameraRuntimeState: .active)
        runtime.unsupportedOperations.insert(.stopCamera)
        let model = SumiPermissionRuntimeControlsViewModel()
        let webView = makeWebView()
        model.load(
            pageContext: pageContext(webView: webView),
            runtimeController: runtime,
            reloadRequired: false
        )

        let result = await model.perform(.stopCamera)

        XCTAssertEqual(result, .unsupported(message: SumiPermissionRuntimeControlsStrings.unavailableInWebKit))
        XCTAssertEqual(runtime.cameraRuntimeState, .active)
        XCTAssertEqual(model.lastResult, result)
    }

    func testFailedOperationDoesNotCorruptState() async {
        let runtime = FakeSumiRuntimePermissionController(microphoneRuntimeState: .active)
        runtime.failedOperations[.setMicrophoneMuted(true)] = "device-busy"
        let model = SumiPermissionRuntimeControlsViewModel()
        let webView = makeWebView()
        model.load(
            pageContext: pageContext(webView: webView),
            runtimeController: runtime,
            reloadRequired: false
        )

        let result = await model.perform(.muteMicrophone)

        XCTAssertEqual(result, .failed(message: SumiPermissionRuntimeControlsStrings.updateFailed))
        XCTAssertEqual(runtime.microphoneRuntimeState, .active)
    }

    func testAutoplayReloadActionCallsReloadHookAndClearsReloadControl() async {
        let runtime = FakeSumiRuntimePermissionController()
        let model = SumiPermissionRuntimeControlsViewModel()
        let webView = makeWebView()
        var reloadCallCount = 0
        model.load(
            pageContext: pageContext(
                webView: webView,
                reloadPage: {
                    reloadCallCount += 1
                    return true
                }
            ),
            runtimeController: runtime,
            reloadRequired: true
        )

        let result = await model.perform(.reloadAutoplay)

        XCTAssertEqual(result, .applied(message: SumiPermissionRuntimeControlsStrings.autoplayReloadingResult))
        XCTAssertEqual(reloadCallCount, 1)
        XCTAssertNil(model.controls.first { $0.permissionType == .autoplay })
    }

    func testStalePageAndMissingWebViewFailSafely() async {
        let runtime = FakeSumiRuntimePermissionController(cameraRuntimeState: .active)
        let staleModel = SumiPermissionRuntimeControlsViewModel()
        let webView = makeWebView()
        staleModel.load(
            pageContext: pageContext(webView: webView, isCurrentPage: false),
            runtimeController: runtime,
            reloadRequired: false
        )

        let staleResult = await staleModel.perform(.muteCamera)

        let missingModel = SumiPermissionRuntimeControlsViewModel()
        missingModel.load(
            pageContext: pageContext(webView: nil),
            runtimeController: runtime,
            reloadRequired: false
        )
        let missingResult = await missingModel.perform(.muteCamera)

        XCTAssertEqual(staleResult, .failed(message: SumiPermissionRuntimeControlsStrings.pageChanged))
        XCTAssertEqual(missingResult, .failed(message: SumiPermissionRuntimeControlsStrings.noCurrentPage))
        XCTAssertEqual(runtime.cameraRuntimeState, .active)
    }

    private func actions(
        for permissionType: SumiPermissionType,
        in controls: [SumiPermissionRuntimeControl]
    ) -> [SumiPermissionRuntimeControl.Action.Kind] {
        controls.first { $0.permissionType == permissionType }?.actions.map(\.kind) ?? []
    }

    private func pageContext(
        webView: WKWebView?,
        isCurrentPage: Bool = true,
        geolocationAllowed: Bool = true,
        reloadPage: @escaping @MainActor () -> Bool = { true }
    ) -> SumiPermissionRuntimeControlsViewModel.PageContext {
        SumiPermissionRuntimeControlsViewModel.PageContext(
            tabId: "tab-a",
            pageId: "tab-a:1",
            navigationOrPageGeneration: "1",
            displayDomain: "example.com",
            currentWebView: { webView },
            isCurrentPage: { _, _, _ in isCurrentPage },
            reloadPage: reloadPage,
            isGeolocationStillAllowed: { geolocationAllowed }
        )
    }

    private func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        return WKWebView(frame: .zero, configuration: configuration)
    }
}
