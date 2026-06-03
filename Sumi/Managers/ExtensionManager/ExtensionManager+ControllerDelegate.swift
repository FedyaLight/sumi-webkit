import AppKit
import Foundation
import SwiftUI
import WebKit

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager: WKWebExtensionControllerDelegate {
    private nonisolated static func recentExtensionTabOpenRequestKey(
        for url: URL?
    ) -> String? {
        guard let url,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            return nil
        }
        return url.absoluteString
    }

    func consumeRecentlyOpenedExtensionTabRequest(for url: URL) -> Bool {
        guard let key = Self.recentExtensionTabOpenRequestKey(for: url) else {
            return false
        }

        return recentExtensionTabOpenRequests.consume(key: key)
    }

    private func recordRecentlyOpenedExtensionTabRequest(for url: URL?) {
        guard let key = Self.recentExtensionTabOpenRequestKey(for: url) else {
            return
        }
        recentExtensionTabOpenRequests.record(key: key)
    }

    @discardableResult
    func openExtensionRequestedTab(
        url: URL?,
        shouldBeActive: Bool,
        shouldBePinned: Bool,
        requestedWindow: (any WKWebExtensionWindow)?,
        controller: WKWebExtensionController,
        reason: String = #function
    ) throws -> Tab {
        guard let browserManager else {
            throw NSError(
                domain: "ExtensionManager",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Browser manager is unavailable"]
            )
        }

        let requestedWindowState = (requestedWindow as? ExtensionWindowAdapter)
            .flatMap { browserManager.windowRegistry?.windows[$0.windowId] }
        let targetWindow = requestedWindowState ?? browserManager.windowRegistry?.activeWindow
        let targetSpace = targetWindow?.currentSpaceId.flatMap { spaceID in
            browserManager.tabManager.spaces.first(where: { $0.id == spaceID })
        } ?? browserManager.tabManager.currentSpace

        let webViewConfigurationOverride: WKWebViewConfiguration?
        if Self.isExtensionOwnedURL(url),
           let url,
           let resolvedContext = controller.extensionContext(for: url)
        {
            webViewConfigurationOverride =
                resolvedContext.webViewConfiguration
                ?? browserConfiguration.webViewConfiguration
        } else {
            webViewConfigurationOverride = nil
        }

        let newTab: Tab
        if let url {
            recordRecentlyOpenedExtensionTabRequest(for: url)
            newTab = browserManager.tabManager.createNewTab(
                url: url.absoluteString,
                in: targetSpace,
                activate: shouldBeActive,
                webViewConfigurationOverride: webViewConfigurationOverride
            )
        } else {
            newTab = browserManager.tabManager.createNewTab(
                in: targetSpace,
                activate: shouldBeActive,
                webViewConfigurationOverride: webViewConfigurationOverride
            )
        }

        if shouldBePinned {
            let resolvedTargetSpaceId = targetSpace?.id ?? newTab.spaceId
            browserManager.tabManager.pinTab(
                newTab,
                context: .init(windowState: targetWindow, spaceId: resolvedTargetSpaceId)
            )
        }

        if shouldBeActive, let targetWindow {
            browserManager.selectTab(newTab, in: targetWindow)
        }

        registerExtensionCreatedTabWithExtensionRuntime(newTab, reason: reason)
        return newTab
    }

    func registerExtensionCreatedTabWithExtensionRuntime(
        _ tab: Tab,
        reason: String = #function
    ) {
        let generation = tabOpenNotificationGeneration
        tab.prepareExtensionRuntimeGeneration(generation)
        tab.extensionRuntimeEligibleGeneration = generation

        guard tab.lastExtensionOpenNotificationGeneration != generation else {
            extensionRuntimeTrace(
                "registerExtensionCreatedTab skip reason=\(reason) because=alreadyNotified generation=\(generation) \(extensionRuntimeTabDescription(tab))"
            )
            return
        }

        guard notifyTabOpened(tab) else {
            extensionRuntimeTrace(
                "registerExtensionCreatedTab skip reason=\(reason) because=notifyFailed generation=\(generation) \(extensionRuntimeTabDescription(tab))"
            )
            return
        }

        tab.didNotifyOpenToExtensions = true
        tab.lastExtensionOpenNotificationGeneration = generation
        extensionRuntimeTrace(
            "registerExtensionCreatedTab marked reason=\(reason) generation=\(generation) \(extensionRuntimeTabDescription(tab))"
        )
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        focusedWindowFor extensionContext: WKWebExtensionContext
    ) -> (any WKWebExtensionWindow)? {
        #if DEBUG
            recordNativeActionPopupRouteObservation(
                for: extensionContext,
                apiName: "webExtensionController.focusedWindowFor",
                sourceContext: "nativeActionPopupOrExtensionContext",
                targetContext: "SumiWindowAdapter",
                nativeBoundary: "WKWebExtensionControllerDelegate",
                metadataAvailable: false,
                notes: [
                    "WebKit requested focused-window state; the delegate does not expose the originating Chrome API.",
                ]
            )
        #endif
        if let windowId = browserManager?.windowRegistry?.activeWindow?.id {
            return windowAdapter(for: windowId)
        }
        return nil
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openWindowsFor extensionContext: WKWebExtensionContext
    ) -> [any WKWebExtensionWindow] {
        #if DEBUG
            recordNativeActionPopupRouteObservation(
                for: extensionContext,
                apiName: "webExtensionController.openWindowsFor",
                sourceContext: "nativeActionPopupOrExtensionContext",
                targetContext: "SumiWindowAdapter",
                nativeBoundary: "WKWebExtensionControllerDelegate",
                metadataAvailable: false,
                notes: [
                    "WebKit requested ordered-window state; this can support tabs/window queries but is not API-attributed.",
                ]
            )
        #endif
        guard let browserManager else { return [] }
        return browserManager.windowRegistry?.windows.keys.compactMap {
            windowAdapter(for: $0)
        } ?? []
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        didUpdate action: WKWebExtension.Action,
        forExtensionContext extensionContext: WKWebExtensionContext
    ) {
        updateActionSurfaceState(
            for: action,
            extensionContext: extensionContext
        )
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        presentActionPopup action: WKWebExtension.Action,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        updateActionSurfaceState(
            for: action,
            extensionContext: extensionContext
        )

        let extensionId = extensionID(for: extensionContext)

        let manifest = extensionId.flatMap { loadedExtensionManifests[$0] } ?? [:]

        grantRequestedPermissions(
            to: extensionContext,
            webExtension: extensionContext.webExtension,
            manifest: manifest
        )
        grantRequestedMatchPatterns(
            to: extensionContext,
            webExtension: extensionContext.webExtension
        )

        guard let popover = action.popupPopover else {
            #if DEBUG
                recordNativeActionPopupPresentationFailed(
                    extensionID: extensionId,
                    reason: "action.popupPopover unavailable"
                )
            #endif
            completionHandler(
                NSError(
                    domain: "ExtensionManager",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "No popup popover is available"]
                )
            )
            return
        }

        popover.behavior = .transient

        let popupWebView = action.popupWebView
        #if DEBUG
            recordNativeActionPopupPresentationBoundary(
                action: action,
                extensionContext: extensionContext,
                popover: popover,
                webView: popupWebView
            )
        #endif

        if let popupWebView,
           RuntimeDiagnostics.isDeveloperInspectionEnabled
        {
            popupWebView.isInspectable = true
        }

        DispatchQueue.main.async {
            let targetWindow = NSApp.keyWindow ?? NSApp.mainWindow

            popover.behavior = .transient
            popover.delegate = self
            self.isPopupActive = true

            if let extensionId,
               var anchors = self.actionAnchors[extensionId]
            {
                anchors.removeAll { $0.view == nil || $0.view?.window == nil }
                self.actionAnchors[extensionId] = anchors

                if let targetWindow,
                   let match = anchors.first(where: { $0.window === targetWindow }),
                   let view = match.view,
                   view.window != nil
                {
                    popover.show(
                        relativeTo: view.bounds,
                        of: view,
                        preferredEdge: .maxY
                    )
                    #if DEBUG
                        self.recordNativeActionPopupPopoverPresented(
                            extensionID: extensionId,
                            anchorKind: "storedAnchor.keyWindow"
                        )
                    #endif
                    completionHandler(nil)
                    return
                }

                if let validAnchor = anchors.first(where: { $0.view?.window != nil }),
                   let view = validAnchor.view
                {
                    popover.show(
                        relativeTo: view.bounds,
                        of: view,
                        preferredEdge: .maxY
                    )
                    #if DEBUG
                        self.recordNativeActionPopupPopoverPresented(
                            extensionID: extensionId,
                            anchorKind: "storedAnchor.fallbackWindow"
                        )
                    #endif
                    completionHandler(nil)
                    return
                }
            }

            if let window = targetWindow, let contentView = window.contentView {
                let rect = CGRect(
                    x: contentView.bounds.midX - 10,
                    y: contentView.bounds.maxY - 50,
                    width: 20,
                    height: 20
                )
                popover.show(
                    relativeTo: rect,
                    of: contentView,
                    preferredEdge: .minY
                )
                #if DEBUG
                    if let extensionId {
                        self.recordNativeActionPopupPopoverPresented(
                            extensionID: extensionId,
                            anchorKind: "windowContentFallback"
                        )
                    }
                #endif
                completionHandler(nil)
                return
            }

            #if DEBUG
                self.recordNativeActionPopupPresentationFailed(
                    extensionID: extensionId,
                    reason: "No window available"
                )
            #endif
            completionHandler(
                NSError(
                    domain: "ExtensionManager",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "No window available"]
                )
            )
        }
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissions permissions: Set<WKWebExtension.Permission>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Set<WKWebExtension.Permission>, Date?) -> Void
    ) {
        // Extension permissions remain outside the normal-tab website permission
        // architecture. Bridging them into site UI is deferred.
        let manifest = extensionID(for: extensionContext)
            .flatMap { loadedExtensionManifests[$0] } ?? [:]
        let policyDeniedPermissions = permissions
            .union(extensionContext.webExtension.optionalPermissions)
            .filter { shouldDenyAutoGrantForWebKitRuntime($0, manifest: manifest) }
        for permission in policyDeniedPermissions {
            extensionContext.setPermissionStatus(.deniedExplicitly, for: permission)
        }

        let grantedPermissions = permissions.filter {
            isGrantedPermissionStatus(extensionContext.permissionStatus(for: $0))
        }
        for permission in permissions.subtracting(grantedPermissions) {
            if policyDeniedPermissions.contains(permission) == false {
                extensionContext.setPermissionStatus(.deniedExplicitly, for: permission)
            }
        }

        completionHandler(grantedPermissions, nil)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Set<WKWebExtension.MatchPattern>, Date?) -> Void
    ) {
        // Extension match-pattern prompts are handled by WebExtension policy only;
        // they are not normal-tab website permission decisions.
        let grantedMatches = matchPatterns.filter {
            isGrantedPermissionStatus(extensionContext.permissionStatus(for: $0))
        }
        for matchPattern in matchPatterns.subtracting(grantedMatches) {
            extensionContext.setPermissionStatus(.deniedExplicitly, for: matchPattern)
        }

        completionHandler(grantedMatches, nil)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissionToAccess urls: Set<URL>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Set<URL>, Date?) -> Void
    ) {
        // Extension URL access prompts are deliberately separate from normal-tab
        // site permission storage and UI.
        var autoGranted = Set<URL>()
        var denied = Set<URL>()

        for url in urls {
            let status = extensionContext.permissionStatus(for: url)
            if isGrantedPermissionStatus(status) {
                autoGranted.insert(url)
            } else if explicitlyGrantURLIfCoveredByGrantedMatchPattern(
                url,
                in: extensionContext
            ) {
                autoGranted.insert(url)
            } else {
                extensionContext.setPermissionStatus(.deniedExplicitly, for: url)
                denied.insert(url)
            }
        }

        RuntimeDiagnostics.debug(
            "Handled URL access request silently for \(extensionContext.webExtension.displayName ?? extensionContext.uniqueIdentifier): granted=\(autoGranted.count) denied=\(denied.count)",
            category: "Extensions"
        )
        completionHandler(autoGranted, nil)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewTabUsing configuration: WKWebExtension.TabConfiguration,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any WKWebExtensionTab)?, (any Error)?) -> Void
    ) {
        do {
            let newTab = try openExtensionRequestedTab(
                url: configuration.url,
                shouldBeActive: configuration.shouldBeActive,
                shouldBePinned: configuration.shouldBePinned,
                requestedWindow: configuration.window,
                controller: controller,
                reason: "webExtensionController.openNewTabUsing"
            )
            completionHandler(stableAdapter(for: newTab), nil)
        } catch {
            completionHandler(nil, error)
        }
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewWindowUsing configuration: WKWebExtension.WindowConfiguration,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any WKWebExtensionWindow)?, (any Error)?) -> Void
    ) {
        _ = extensionContext
        openExtensionWindowUsingTabURLs(
            configuration.tabURLs,
            controller: controller,
            createWindow: { [weak browserManager] in
                browserManager?.createNewWindow()
            },
            awaitWindowRegistration: { [weak browserManager] existingWindowIDs in
                guard let windowRegistry = browserManager?.windowRegistry else {
                    return nil
                }
                return await windowRegistry.awaitNextRegisteredWindow(
                    excluding: existingWindowIDs
                )
            },
            completionHandler: completionHandler
        )
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        sendMessage message: Any,
        toApplicationWithIdentifier applicationIdentifier: String?,
        for extensionContext: WKWebExtensionContext,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) {
        let applicationId = applicationIdentifier ?? ""
        #if DEBUG
            recordNativeActionPopupRouteObservation(
                for: extensionContext,
                apiName: "runtime.sendNativeMessage",
                sourceContext: "nativeActionPopupOrExtensionContext",
                targetContext: "nativeApplication",
                nativeBoundary: "WKWebExtensionControllerDelegate.sendMessageToApplication",
                metadataAvailable: true,
                payloadShape: sanitizedNativeActionPopupPayloadShape(message),
                resultClassifier: "nativeMessagingUnavailable",
                notes: [
                    applicationIdentifier == nil
                        ? "applicationIdentifier absent"
                        : "applicationIdentifier present",
                    "No native host process is launched by this product delegate path.",
                ]
            )
        #endif
        _ = controller
        _ = message
        _ = extensionContext
        let lastErrorMessage =
            ChromeMV3NativeMessagingRuntimeErrorCode
            .hostManifestMissing.lastErrorMessage
        replyHandler(
            nil,
            NSError(
                domain: "ExtensionManager.NativeMessaging",
                code: 50,
                userInfo: [
                    NSLocalizedDescriptionKey: lastErrorMessage,
                    "SumiNativeMessagingDiagnostic":
                        "Product native messaging is unavailable; \(applicationId) can only be exercised by DEBUG/internal fixture diagnostics. No native host process was launched.",
                ]
            )
        )
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        connectUsing port: WKWebExtension.MessagePort,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        _ = controller
        _ = extensionContext
        let applicationId = port.applicationIdentifier ?? "unknown"
        #if DEBUG
            recordNativeActionPopupRouteObservation(
                for: extensionContext,
                apiName: "runtime.connectNative",
                sourceContext: "nativeActionPopupOrExtensionContext",
                targetContext: "nativeApplicationPort",
                nativeBoundary: "WKWebExtensionControllerDelegate.connectUsingMessagePort",
                metadataAvailable: true,
                payloadShape: port.applicationIdentifier == nil
                    ? "applicationIdentifier(absent)"
                    : "applicationIdentifier(present,length:\(port.applicationIdentifier?.count ?? 0))",
                resultClassifier: "nativeMessagingUnavailable",
                notes: [
                    "WKWebExtension.MessagePort is the native-application messaging port surface.",
                    "No native host process is launched by this product delegate path.",
                ]
            )
        #endif
        let lastErrorMessage =
            ChromeMV3NativeMessagingRuntimeErrorCode
            .hostManifestMissing.lastErrorMessage
        port.disconnect()
        completionHandler(
            NSError(
                domain: "ExtensionManager.NativeMessaging",
                code: 50,
                userInfo: [
                    NSLocalizedDescriptionKey: lastErrorMessage,
                    "SumiNativeMessagingDiagnostic":
                        "Product native messaging Port is unavailable; \(applicationId) can only be exercised by DEBUG/internal fixture diagnostics. No native host process was launched.",
                ]
            )
        )
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openOptionsPageFor extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        presentOptionsPageWindow(
            for: extensionContext,
            completionHandler: completionHandler
        )
    }
}
