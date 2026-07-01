import Foundation
import WebKit

@MainActor
final class TabWebKitPermissionUIDelegateOwner {
    private unowned let tab: Tab

    init(tab: Tab) {
        self.tab = tab
    }

    func runOpenPanel(
        _ webView: WKWebView,
        parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        // WebKit uses nil here to report open-panel cancellation.
        // swiftlint:disable:next discouraged_optional_collection
        completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void
    ) {
        guard let permissionBridges = tab.permissionRuntime.permissionBridges(),
              let tabContext = filePickerPermissionTabContext(for: webView)
        else {
            RuntimeDiagnostics.emit("📁 [Tab] Denying file picker because browser/profile context is unavailable.")
            completionHandler(nil)
            return
        }

        let activationState = tab.popupUserActivationTracker.activationState(webKitUserInitiated: nil)
        let request = SumiFilePickerPermissionRequest(
            parameters: parameters,
            frame: frame,
            userActivation: activationState
        )
        permissionBridges.filePickerPermissionBridge.handleOpenPanel(
            request,
            tabContext: tabContext,
            webView: webView,
            currentPageId: { [weak tab] in tab?.currentPermissionPageId() },
            completionHandler: completionHandler
        )
        tab.popupUserActivationTracker.consumeIfUserActivated(activationState)
    }

    @available(macOS 13.0, *)
    func requestMediaCaptureAuthorization(
        _ webView: WKWebView,
        type: WKMediaCaptureType,
        origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        RuntimeDiagnostics.emit(
            "🔐 [Tab] Media capture authorization requested for type: \(type.rawValue) from origin: \(origin)"
        )
        guard let permissionBridges = tab.permissionRuntime.permissionBridges(),
              let tabContext = mediaCaptureTabContext(for: webView)
        else {
            RuntimeDiagnostics.emit(
                "🔐 [Tab] Denying media capture because browser/profile context is unavailable."
            )
            decisionHandler(.deny)
            return
        }

        let mediaRequest = SumiWebKitMediaCaptureRequest(
            mediaType: type,
            origin: origin,
            frame: frame
        )

        permissionBridges.webKitPermissionBridge.handleMediaCaptureAuthorization(
            mediaRequest,
            tabContext: tabContext,
            webView: webView,
            decisionHandler: decisionHandler
        )
    }

    func requestDisplayCapturePermission(
        _ webView: WKWebView,
        origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        decisionHandler: @escaping (Int) -> Void
    ) {
        RuntimeDiagnostics.emit(
            "🔐 [Tab] Display capture authorization requested from origin: \(origin)"
        )
        guard let permissionBridges = tab.permissionRuntime.permissionBridges(),
              let tabContext = mediaCaptureTabContext(for: webView)
        else {
            RuntimeDiagnostics.emit(
                "🔐 [Tab] Denying display capture because browser/profile context is unavailable."
            )
            decisionHandler(SumiWebKitDisplayCapturePermissionDecision.deny.rawValue)
            return
        }

        let displayRequest = SumiWebKitDisplayCaptureRequest(
            origin: origin,
            frame: frame
        )

        permissionBridges.webKitPermissionBridge.handleDisplayCaptureAuthorization(
            displayRequest,
            tabContext: tabContext,
            webView: webView,
            decisionHandler: decisionHandler
        )
    }

    func requestUserMediaAuthorization(
        _ webView: WKWebView,
        devicesRawValue: UInt,
        requestURL: URL,
        mainFrameURL: URL,
        decisionHandler: @escaping (Bool) -> Void
    ) {
        let devices = SumiWebKitLegacyCaptureDevices(rawValue: devicesRawValue)
        let permissionTypes = SumiWebKitDisplayCaptureDecisionMapper.permissionTypes(
            forLegacyCaptureDevices: devices
        )
        guard !permissionTypes.isEmpty,
              let permissionBridges = tab.permissionRuntime.permissionBridges(),
              let tabContext = mediaCaptureTabContext(for: webView, fallbackMainFrameURL: mainFrameURL)
        else {
            RuntimeDiagnostics.emit(
                "🔐 [Tab] Denying legacy media capture because browser/profile context is unavailable or devices are unsupported."
            )
            decisionHandler(false)
            return
        }

        let requestingOrigin = SumiPermissionOrigin(url: requestURL)
        let isMainFrame = requestURL.absoluteString == mainFrameURL.absoluteString
        if devices.contains(.display) {
            let displayRequest = SumiWebKitDisplayCaptureRequest(
                permissionTypes: permissionTypes,
                requestingOrigin: requestingOrigin,
                isMainFrame: isMainFrame
            )
            permissionBridges.webKitPermissionBridge.handleDisplayCaptureAuthorization(
                displayRequest,
                tabContext: tabContext,
                webView: webView
            ) { decision in
                decisionHandler(decision != SumiWebKitDisplayCapturePermissionDecision.deny.rawValue)
            }
            return
        }

        let mediaRequest = SumiWebKitMediaCaptureRequest(
            permissionTypes: permissionTypes,
            requestingOrigin: requestingOrigin,
            isMainFrame: isMainFrame
        )
        permissionBridges.webKitPermissionBridge.handleLegacyMediaCaptureAuthorization(
            mediaRequest,
            tabContext: tabContext,
            webView: webView,
            decisionHandler: decisionHandler
        )
    }

    func requestStorageAccessPanel(
        _ webView: WKWebView,
        requestingDomain: String,
        currentDomain: String,
        completionHandler: @escaping (Bool) -> Void
    ) {
        guard let permissionBridges = tab.permissionRuntime.permissionBridges(),
              let tabContext = storageAccessTabContext(for: webView)
        else {
            RuntimeDiagnostics.emit("🍪 [Tab] Denying storage access because browser/profile context is unavailable.")
            completionHandler(false)
            return
        }

        permissionBridges.storageAccessPermissionBridge.handleStorageAccessRequest(
            SumiStorageAccessRequest(
                requestingDomain: requestingDomain,
                currentDomain: currentDomain
            ),
            tabContext: tabContext,
            webView: webView,
            completionHandler: completionHandler
        )
    }

    func requestStorageAccessPanel(
        _ webView: WKWebView,
        requestingDomain: String,
        currentDomain: String,
        quirkDomains: [String: [String]],
        completionHandler: @escaping (Bool) -> Void
    ) {
        guard let permissionBridges = tab.permissionRuntime.permissionBridges(),
              let tabContext = storageAccessTabContext(for: webView)
        else {
            RuntimeDiagnostics.emit("🍪 [Tab] Denying quirk-domain storage access because browser/profile context is unavailable.")
            completionHandler(false)
            return
        }

        permissionBridges.storageAccessPermissionBridge.handleStorageAccessRequest(
            SumiStorageAccessRequest(
                requestingDomain: requestingDomain,
                currentDomain: currentDomain,
                quirkDomains: Array(quirkDomains.keys).sorted()
            ),
            tabContext: tabContext,
            webView: webView,
            completionHandler: completionHandler
        )
    }

    func requestLegacyGeolocationPermission(
        _ webView: WKWebView,
        frame: WKFrameInfo,
        decisionHandler: @escaping (Bool) -> Void
    ) {
        RuntimeDiagnostics.emit(
            "🔐 [Tab] Legacy geolocation authorization requested from frame: \(String(describing: frame.sumiWebKitRequestURL))"
        )
        guard let permissionBridges = tab.permissionRuntime.permissionBridges(),
              let tabContext = geolocationTabContext(for: webView)
        else {
            RuntimeDiagnostics.emit(
                "🔐 [Tab] Denying geolocation because browser/profile context is unavailable."
            )
            decisionHandler(false)
            return
        }

        permissionBridges.webKitGeolocationBridge.handleLegacyGeolocationAuthorization(
            SumiWebKitGeolocationRequest(frame: frame),
            tabContext: tabContext,
            webView: webView,
            decisionHandler: decisionHandler
        )
    }

    @available(macOS 27.0, *)
    func requestGeolocationPermission(
        _ webView: WKWebView,
        origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void
    ) {
        RuntimeDiagnostics.emit(
            "🔐 [Tab] Geolocation authorization requested from origin: \(origin)"
        )
        guard let permissionBridges = tab.permissionRuntime.permissionBridges(),
              let tabContext = geolocationTabContext(for: webView)
        else {
            RuntimeDiagnostics.emit(
                "🔐 [Tab] Denying geolocation because browser/profile context is unavailable."
            )
            decisionHandler(.deny)
            return
        }

        permissionBridges.webKitGeolocationBridge.handleGeolocationAuthorization(
            SumiWebKitGeolocationRequest(origin: origin, frame: frame),
            tabContext: tabContext,
            webView: webView,
            decisionHandler: decisionHandler
        )
    }

    private func geolocationTabContext(
        for webView: WKWebView
    ) -> SumiWebKitGeolocationTabContext? {
        tab.permissionSurfaceOwner.geolocationContext(for: webView)
    }

    private func mediaCaptureTabContext(
        for webView: WKWebView,
        fallbackMainFrameURL: URL? = nil
    ) -> SumiWebKitMediaCaptureTabContext? {
        tab.permissionSurfaceOwner.mediaCaptureContext(
            for: webView,
            fallbackMainFrameURL: fallbackMainFrameURL
        )
    }

    private func filePickerPermissionTabContext(
        for webView: WKWebView
    ) -> SumiFilePickerPermissionTabContext? {
        tab.permissionSurfaceOwner.filePickerContext(for: webView)
    }

    private func storageAccessTabContext(
        for webView: WKWebView
    ) -> SumiStorageAccessTabContext? {
        tab.permissionSurfaceOwner.storageAccessContext(for: webView)
    }
}
