import Combine
import Foundation
import WebKit

@MainActor
final class SumiPermissionRuntimeControlsViewModel: ObservableObject {
    struct PageContext {
        let tabId: String?
        let pageId: String?
        let navigationOrPageGeneration: String?
        let displayDomain: String
        let currentWebView: @MainActor () -> WKWebView?
        let isCurrentPage: @MainActor (_ tabId: String?, _ pageId: String?, _ navigationOrPageGeneration: String?) -> Bool
        let reloadPage: @MainActor () -> Bool
        let isGeolocationStillAllowed: @MainActor () async -> Bool
    }

    @Published private(set) var controls: [SumiPermissionRuntimeControl] = []
    @Published private(set) var lastResult: SumiPermissionRuntimeControlResult?

    private var pageContext: PageContext?
    private weak var runtimeController: (any SumiRuntimePermissionControlling)?
    private var observation: SumiRuntimePermissionObservation?
    private var runtimeState: SumiRuntimePermissionState?
    private var reloadRequired = false
    private var inProgressActionKind: SumiPermissionRuntimeControl.Action.Kind?
    private var onRuntimeStateChanged: (() -> Void)?

    var hasVisibleContent: Bool {
        !controls.isEmpty || lastResult != nil
    }

    func load(
        pageContext: PageContext?,
        runtimeController: any SumiRuntimePermissionControlling,
        reloadRequired: Bool,
        onRuntimeStateChanged: (() -> Void)? = nil
    ) {
        clearObservation()
        self.pageContext = pageContext
        self.runtimeController = runtimeController
        self.reloadRequired = reloadRequired
        self.onRuntimeStateChanged = onRuntimeStateChanged
        inProgressActionKind = nil

        guard let pageContext,
              pageContext.isCurrentPage(
                pageContext.tabId,
                pageContext.pageId,
                pageContext.navigationOrPageGeneration
              ),
              let webView = pageContext.currentWebView()
        else {
            runtimeState = nil
            controls = []
            return
        }

        let state = runtimeController.currentRuntimeState(
            for: webView,
            pageId: pageContext.pageId
        )
        runtimeState = state
        rebuildControls()

        observation = runtimeController.observeRuntimeState(
            for: webView,
            pageId: pageContext.pageId
        ) { [weak self] state in
            guard let self else { return }
            let didChange = self.runtimeState != state
            self.runtimeState = state
            self.rebuildControls()
            if didChange {
                self.onRuntimeStateChanged?()
            }
        }
    }

    func clear() {
        clearObservation()
        pageContext = nil
        runtimeController = nil
        runtimeState = nil
        reloadRequired = false
        inProgressActionKind = nil
        controls = []
        lastResult = nil
        onRuntimeStateChanged = nil
    }

    func setReloadRequired(_ reloadRequired: Bool) {
        guard self.reloadRequired != reloadRequired else { return }
        self.reloadRequired = reloadRequired
        rebuildControls()
    }

    func perform(
        _ actionKind: SumiPermissionRuntimeControl.Action.Kind
    ) async -> SumiPermissionRuntimeControlResult {
        if inProgressActionKind != nil {
            let result = SumiPermissionRuntimeControlResult.noOp(
                message: SumiPermissionRuntimeControlsStrings.alreadyCurrent
            )
            lastResult = result
            return result
        }

        guard let pageContext else {
            let result = SumiPermissionRuntimeControlResult.missingWebView()
            lastResult = result
            rebuildControls()
            return result
        }
        guard pageContext.isCurrentPage(
            pageContext.tabId,
            pageContext.pageId,
            pageContext.navigationOrPageGeneration
        ) else {
            let result = SumiPermissionRuntimeControlResult.stalePage()
            lastResult = result
            rebuildControls()
            return result
        }
        guard let webView = pageContext.currentWebView() else {
            let result = SumiPermissionRuntimeControlResult.missingWebView()
            lastResult = result
            rebuildControls()
            return result
        }
        guard controls.contains(where: { control in
            control.actions.contains { $0.kind == actionKind }
        }) else {
            let result = SumiPermissionRuntimeControlResult.stalePage()
            lastResult = result
            rebuildControls()
            return result
        }

        inProgressActionKind = actionKind
        rebuildControls()
        defer {
            inProgressActionKind = nil
            refreshRuntimeState(from: webView)
            rebuildControls()
        }

        let result: SumiPermissionRuntimeControlResult
        if actionKind == .reloadAutoplay {
            result = performAutoplayReload(pageContext: pageContext)
        } else {
            guard let runtimeController else {
                result = .unsupported(message: SumiPermissionRuntimeControlsStrings.unavailableInWebKit)
                lastResult = result
                return result
            }
            if actionKind == .resumeGeolocation {
                guard await pageContext.isGeolocationStillAllowed() else {
                    result = .locationNoLongerAllowed()
                    lastResult = result
                    return result
                }
            }
            let operationResult = await performRuntimeOperation(
                actionKind,
                runtimeController: runtimeController,
                webView: webView,
                pageId: pageContext.pageId
            )
            result = SumiPermissionRuntimeControlResult.from(
                operationResult,
                actionKind: actionKind
            )
        }

        lastResult = result
        return result
    }

    private func performAutoplayReload(
        pageContext: PageContext
    ) -> SumiPermissionRuntimeControlResult {
        guard pageContext.isCurrentPage(
            pageContext.tabId,
            pageContext.pageId,
            pageContext.navigationOrPageGeneration
        ) else {
            return .stalePage()
        }
        guard pageContext.reloadPage() else {
            return .failed(message: SumiPermissionRuntimeControlsStrings.noCurrentPage)
        }
        reloadRequired = false
        return .applied(message: SumiPermissionRuntimeControlsStrings.autoplayReloadingResult)
    }

    private func performRuntimeOperation(
        _ actionKind: SumiPermissionRuntimeControl.Action.Kind,
        runtimeController: any SumiRuntimePermissionControlling,
        webView: WKWebView,
        pageId: String?
    ) async -> SumiRuntimePermissionOperationResult {
        switch actionKind {
        case .muteCamera:
            return await runtimeController.setCameraMuted(true, for: webView)
        case .unmuteCamera:
            return await runtimeController.setCameraMuted(false, for: webView)
        case .stopCamera:
            return await runtimeController.stopCamera(for: webView)
        case .muteMicrophone:
            return await runtimeController.setMicrophoneMuted(true, for: webView)
        case .unmuteMicrophone:
            return await runtimeController.setMicrophoneMuted(false, for: webView)
        case .stopMicrophone:
            return await runtimeController.stopMicrophone(for: webView)
        case .pauseGeolocation:
            return await runtimeController.pauseGeolocation(pageId: pageId, for: webView)
        case .resumeGeolocation:
            return await runtimeController.resumeGeolocation(pageId: pageId, for: webView)
        case .stopGeolocationForVisit:
            return await runtimeController.stopGeolocation(pageId: pageId, for: webView)
        case .reloadAutoplay:
            return .noOp
        }
    }

    private func refreshRuntimeState(from webView: WKWebView) {
        guard let runtimeController else { return }
        runtimeState = runtimeController.currentRuntimeState(
            for: webView,
            pageId: pageContext?.pageId
        )
    }

    private func rebuildControls() {
        controls = Self.makeControls(
            runtimeState: runtimeState,
            reloadRequired: reloadRequired,
            displayDomain: pageContext?.displayDomain ?? SumiPermissionRuntimeControlsStrings.defaultDisplayDomain,
            inProgressActionKind: inProgressActionKind,
            lastResult: lastResult
        )
    }

    private func clearObservation() {
        observation?.cancel()
        observation = nil
    }

    static func makeControls(
        runtimeState: SumiRuntimePermissionState?,
        reloadRequired: Bool,
        displayDomain: String,
        inProgressActionKind: SumiPermissionRuntimeControl.Action.Kind? = nil,
        lastResult: SumiPermissionRuntimeControlResult? = nil
    ) -> [SumiPermissionRuntimeControl] {
        guard runtimeState != nil || reloadRequired else { return [] }
        var controls: [SumiPermissionRuntimeControl] = []
        if let runtimeState {
            if let camera = mediaControl(
                permissionType: .camera,
                state: runtimeState.camera,
                displayDomain: displayDomain,
                inProgressActionKind: inProgressActionKind,
                lastResult: lastResult
            ) {
                controls.append(camera)
            }
            if let microphone = mediaControl(
                permissionType: .microphone,
                state: runtimeState.microphone,
                displayDomain: displayDomain,
                inProgressActionKind: inProgressActionKind,
                lastResult: lastResult
            ) {
                controls.append(microphone)
            }
            if let location = geolocationControl(
                state: runtimeState.geolocation,
                displayDomain: displayDomain,
                inProgressActionKind: inProgressActionKind,
                lastResult: lastResult
            ) {
                controls.append(location)
            }
            if let screen = screenCaptureControl(
                state: runtimeState.screenCapture,
                displayDomain: displayDomain,
                inProgressActionKind: inProgressActionKind,
                lastResult: lastResult
            ) {
                controls.append(screen)
            }
        }
        if reloadRequired {
            controls.append(
                autoplayControl(
                    displayDomain: displayDomain,
                    inProgressActionKind: inProgressActionKind,
                    lastResult: lastResult
                )
            )
        }
        return controls
    }

    private static func mediaControl(
        permissionType: SumiPermissionType,
        state: SumiMediaCaptureRuntimeState,
        displayDomain: String,
        inProgressActionKind: SumiPermissionRuntimeControl.Action.Kind?,
        lastResult: SumiPermissionRuntimeControlResult?
    ) -> SumiPermissionRuntimeControl? {
        let descriptor = SumiPermissionIconCatalog.icon(for: permissionType, visualStyle: .active)
        let isCamera = permissionType == .camera
        let title = isCamera
            ? SumiPermissionRuntimeControlsStrings.cameraTitle
            : SumiPermissionRuntimeControlsStrings.microphoneTitle

        let actions: [SumiPermissionRuntimeControl.Action]
        let subtitle: String
        let runtimeStateDescription: String
        switch state {
        case .active:
            subtitle = isCamera
                ? SumiPermissionRuntimeControlsStrings.cameraActive
                : SumiPermissionRuntimeControlsStrings.microphoneActive
            runtimeStateDescription = "active"
            actions = [
                action(isCamera ? .muteCamera : .muteMicrophone),
                action(isCamera ? .stopCamera : .stopMicrophone),
            ]
        case .muted:
            subtitle = isCamera
                ? SumiPermissionRuntimeControlsStrings.cameraMuted
                : SumiPermissionRuntimeControlsStrings.microphoneMuted
            runtimeStateDescription = "muted"
            actions = [
                action(isCamera ? .unmuteCamera : .unmuteMicrophone),
                action(isCamera ? .stopCamera : .stopMicrophone),
            ]
        case .unavailable:
            subtitle = SumiPermissionRuntimeControlsStrings.unavailableInWebKit
            runtimeStateDescription = "unavailable"
            actions = []
        case .unsupported:
            subtitle = SumiPermissionRuntimeControlsStrings.unavailableInWebKit
            runtimeStateDescription = "unsupported"
            actions = []
        case .stopping:
            subtitle = SumiPermissionRuntimeControlsStrings.stopping
            runtimeStateDescription = "stopping"
            actions = []
        case .revoking:
            subtitle = SumiPermissionRuntimeControlsStrings.revoking
            runtimeStateDescription = "revoking"
            actions = []
        case .none:
            return nil
        }

        return SumiPermissionRuntimeControl(
            id: permissionType.identity,
            permissionType: permissionType,
            runtimeStateDescription: runtimeStateDescription,
            title: title,
            subtitle: subtitle,
            iconName: descriptor.chromeIconName,
            fallbackSystemName: descriptor.fallbackSystemName,
            actions: actions,
            disabledReason: actions.isEmpty ? subtitle : nil,
            inProgressActionKind: inProgressActionKind,
            lastResult: lastResult,
            accessibilityLabel: "\(title), \(subtitle), \(displayDomain)"
        )
    }

    private static func geolocationControl(
        state: SumiGeolocationRuntimeState,
        displayDomain: String,
        inProgressActionKind: SumiPermissionRuntimeControl.Action.Kind?,
        lastResult: SumiPermissionRuntimeControlResult?
    ) -> SumiPermissionRuntimeControl? {
        let descriptor = SumiPermissionIconCatalog.icon(for: .geolocation, visualStyle: .active)
        let actions: [SumiPermissionRuntimeControl.Action]
        let subtitle: String
        let runtimeStateDescription: String
        switch state {
        case .active:
            subtitle = SumiPermissionRuntimeControlsStrings.locationActive
            runtimeStateDescription = "active"
            actions = [
                action(.pauseGeolocation),
                action(.stopGeolocationForVisit),
            ]
        case .paused:
            subtitle = SumiPermissionRuntimeControlsStrings.locationPaused
            runtimeStateDescription = "paused"
            actions = [
                action(.resumeGeolocation),
                action(.stopGeolocationForVisit),
            ]
        case .unavailable:
            subtitle = SumiPermissionRuntimeControlsStrings.unavailableInWebKit
            runtimeStateDescription = "unavailable"
            actions = []
        case .unsupportedProvider:
            subtitle = SumiPermissionRuntimeControlsStrings.unavailableInWebKit
            runtimeStateDescription = "unsupported"
            actions = []
        case .revoked, .none:
            return nil
        }

        return SumiPermissionRuntimeControl(
            id: SumiPermissionType.geolocation.identity,
            permissionType: .geolocation,
            runtimeStateDescription: runtimeStateDescription,
            title: SumiPermissionRuntimeControlsStrings.locationTitle,
            subtitle: subtitle,
            iconName: descriptor.chromeIconName,
            fallbackSystemName: descriptor.fallbackSystemName,
            actions: actions,
            disabledReason: actions.isEmpty ? subtitle : nil,
            inProgressActionKind: inProgressActionKind,
            lastResult: lastResult,
            accessibilityLabel: "\(SumiPermissionRuntimeControlsStrings.locationTitle), \(subtitle), \(displayDomain)"
        )
    }

    private static func screenCaptureControl(
        state: SumiMediaCaptureRuntimeState,
        displayDomain: String,
        inProgressActionKind: SumiPermissionRuntimeControl.Action.Kind?,
        lastResult: SumiPermissionRuntimeControlResult?
    ) -> SumiPermissionRuntimeControl? {
        switch state {
        case .active, .muted, .stopping, .revoking:
            let descriptor = SumiPermissionIconCatalog.icon(for: .screenCapture, visualStyle: .active)
            let subtitle = SumiPermissionRuntimeControlsStrings.screenSharingControlledByWebKit
            return SumiPermissionRuntimeControl(
                id: SumiPermissionType.screenCapture.identity,
                permissionType: .screenCapture,
                runtimeStateDescription: state.rawValue,
                title: SumiPermissionRuntimeControlsStrings.screenSharingTitle,
                subtitle: subtitle,
                iconName: descriptor.chromeIconName,
                fallbackSystemName: descriptor.fallbackSystemName,
                actions: [],
                disabledReason: subtitle,
                inProgressActionKind: inProgressActionKind,
                lastResult: lastResult,
                accessibilityLabel: "\(SumiPermissionRuntimeControlsStrings.screenSharingTitle), \(subtitle), \(displayDomain)"
            )
        case .unsupported, .unavailable, .none:
            return nil
        }
    }

    private static func autoplayControl(
        displayDomain: String,
        inProgressActionKind: SumiPermissionRuntimeControl.Action.Kind?,
        lastResult: SumiPermissionRuntimeControlResult?
    ) -> SumiPermissionRuntimeControl {
        let descriptor = SumiPermissionIconCatalog.icon(for: .autoplay, visualStyle: .reloadRequired)
        return SumiPermissionRuntimeControl(
            id: SumiPermissionType.autoplay.identity,
            permissionType: .autoplay,
            runtimeStateDescription: "reload-required",
            title: SumiPermissionRuntimeControlsStrings.autoplayTitle,
            subtitle: SumiPermissionRuntimeControlsStrings.autoplayReloadRequired,
            iconName: descriptor.chromeIconName,
            fallbackSystemName: descriptor.fallbackSystemName,
            actions: [action(.reloadAutoplay)],
            disabledReason: nil,
            inProgressActionKind: inProgressActionKind,
            lastResult: lastResult,
            accessibilityLabel: "\(SumiPermissionRuntimeControlsStrings.autoplayTitle), \(SumiPermissionRuntimeControlsStrings.autoplayReloadRequired), \(displayDomain)"
        )
    }

    private static func action(
        _ kind: SumiPermissionRuntimeControl.Action.Kind
    ) -> SumiPermissionRuntimeControl.Action {
        switch kind {
        case .muteCamera:
            return .init(
                kind: kind,
                title: SumiPermissionRuntimeControlsStrings.muteCamera,
                accessibilityLabel: SumiPermissionRuntimeControlsStrings.muteCamera,
                isDestructive: false
            )
        case .unmuteCamera:
            return .init(
                kind: kind,
                title: SumiPermissionRuntimeControlsStrings.unmuteCamera,
                accessibilityLabel: SumiPermissionRuntimeControlsStrings.unmuteCamera,
                isDestructive: false
            )
        case .stopCamera:
            return .init(
                kind: kind,
                title: SumiPermissionRuntimeControlsStrings.stopCamera,
                accessibilityLabel: SumiPermissionRuntimeControlsStrings.stopCameraAccessibility,
                isDestructive: true
            )
        case .muteMicrophone:
            return .init(
                kind: kind,
                title: SumiPermissionRuntimeControlsStrings.muteMicrophone,
                accessibilityLabel: SumiPermissionRuntimeControlsStrings.muteMicrophone,
                isDestructive: false
            )
        case .unmuteMicrophone:
            return .init(
                kind: kind,
                title: SumiPermissionRuntimeControlsStrings.unmuteMicrophone,
                accessibilityLabel: SumiPermissionRuntimeControlsStrings.unmuteMicrophone,
                isDestructive: false
            )
        case .stopMicrophone:
            return .init(
                kind: kind,
                title: SumiPermissionRuntimeControlsStrings.stopMicrophone,
                accessibilityLabel: SumiPermissionRuntimeControlsStrings.stopMicrophoneAccessibility,
                isDestructive: true
            )
        case .pauseGeolocation:
            return .init(
                kind: kind,
                title: SumiPermissionRuntimeControlsStrings.pauseLocation,
                accessibilityLabel: SumiPermissionRuntimeControlsStrings.pauseLocationAccessibility,
                isDestructive: false
            )
        case .resumeGeolocation:
            return .init(
                kind: kind,
                title: SumiPermissionRuntimeControlsStrings.resumeLocation,
                accessibilityLabel: SumiPermissionRuntimeControlsStrings.resumeLocationAccessibility,
                isDestructive: false
            )
        case .stopGeolocationForVisit:
            return .init(
                kind: kind,
                title: SumiPermissionRuntimeControlsStrings.stopLocationThisVisit,
                accessibilityLabel: SumiPermissionRuntimeControlsStrings.stopLocationAccessibility,
                isDestructive: true
            )
        case .reloadAutoplay:
            return .init(
                kind: kind,
                title: SumiPermissionRuntimeControlsStrings.reloadAutoplay,
                accessibilityLabel: SumiPermissionRuntimeControlsStrings.reloadAutoplayAccessibility,
                isDestructive: false
            )
        }
    }
}
