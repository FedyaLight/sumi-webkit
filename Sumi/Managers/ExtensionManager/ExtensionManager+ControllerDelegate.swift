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

        tab.extensionRuntimeOpenNotifiedDocumentSequence = tab.extensionRuntimeDocumentSequence
        if let profileId = resolvedProfileId(for: tab) {
            tab.extensionRuntimeOpenNotifiedExtensionContextBindingGeneration =
                extensionContextBindingGeneration(for: profileId)
            tab.extensionRuntimeOpenNotifiedWithLoadedContexts =
                profileHasLoadedContentScriptContexts(profileId: profileId)
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
        if let windowId = browserManager?.windowRegistry?.activeWindow?.id {
            return windowAdapter(for: windowId)
        }
        return nil
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openWindowsFor extensionContext: WKWebExtensionContext
    ) -> [any WKWebExtensionWindow] {
        guard let browserManager,
              let contextProfileId = profileId(for: extensionContext)
        else { return [] }
        return browserManager.windowRegistry?.windows.compactMap { windowId, windowState in
            guard windowMatchesProfile(windowState, profileId: contextProfileId) else {
                return nil
            }
            return windowAdapter(for: windowId)
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
        let popupPhase: SafariExtensionPopupLifecyclePhase =
            isPopupActive ? .reopened : .opened

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
        if let activeTab = browserManager?.currentTabForActiveWindow() {
            grantActiveTabURLAccess(
                for: extensionContext,
                tab: activeTab,
                manifest: manifest
            )
            let seesCurrentTab =
                stableAdapter(for: activeTab) != nil
                && isTabEligibleForCurrentExtensionRuntime(activeTab)
            SafariExtensionAutofillFillDiagnostics.recordPopupTabVisibility(
                seesCurrentTab: seesCurrentTab,
                extensionId: extensionId,
                reason: "presentActionPopup"
            )
            if let extensionId {
                SafariExtensionAutofillFillDiagnostics.recordInlinePopupFocusSteal(
                    extensionId: extensionId,
                    reason: "presentActionPopup"
                )
                SafariExtensionAutofillFillDiagnostics.setPopupActive(true, extensionId: extensionId)
            }
            SafariExtensionAutofillFillDiagnostics.recordScriptingAvailability(
                extensionContext: extensionContext,
                manifest: manifest
            )
        } else {
            SafariExtensionAutofillFillDiagnostics.recordPopupTabVisibility(
                seesCurrentTab: false,
                extensionId: extensionId,
                reason: "presentActionPopupNoActiveTab"
            )
        }

        guard let popover = action.popupPopover else {
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

        if let popupWebView {
            if RuntimeDiagnostics.isDeveloperInspectionEnabled {
                popupWebView.isInspectable = true
            }
            // WebKit creates and preloads this web view with the extension
            // context configuration before this delegate method is called.
            // Retargeting its configuration here is too late to repair origin
            // or resource loading, and can invalidate extension-owned popup
            // pages that rely on nested extension resources.
            let popupUIDelegate = ExtensionActionPopupUIDelegate(
                manager: self,
                popover: popover
            )
            if let extensionId {
                extensionActionPopupUIDelegates[extensionId] = popupUIDelegate
            }
            popupWebView.uiDelegate = popupUIDelegate
            activeExtensionActionPopover = popover
        }

        if let extensionId {
            activePopupExtensionID = extensionId
            recordExtensionActionPopupPresentation(
                for: extensionId,
                popupWebView: popupWebView,
                phase: popupPhase
            )
        }

        DispatchQueue.main.async {
            popover.behavior = .transient
            popover.delegate = self
            self.isPopupActive = true

            guard let extensionId else {
                completionHandler(
                    NSError(
                        domain: "ExtensionManager",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "No extension identifier is available"]
                    )
                )
                return
            }

            let profileId = self.profileId(for: extensionContext)
            let preferredWindowId = self.browserManager?.windowRegistry?.activeWindow?.id
            let resolution = self.presentResolvedExtensionActionPopup(
                popover,
                for: extensionId,
                profileId: profileId,
                preferredWindowId: preferredWindowId
            )

            SafariExtensionAutofillFillDiagnostics.recordPopoverPresentation(
                anchorResolved: resolution.anchorResolved,
                extensionId: extensionId
            )

            guard resolution.anchorResolved else {
                completionHandler(
                    NSError(
                        domain: "ExtensionManager",
                        code: 2,
                        userInfo: [
                            NSLocalizedDescriptionKey: "No URL-hub anchor is available for the extension action popup",
                            "anchorSource": resolution.anchorSource?.rawValue ?? "nil",
                        ]
                    )
                )
                return
            }

            completionHandler(nil)
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

        let extensionId = extensionID(for: extensionContext)
        for url in urls {
            let status = extensionContext.permissionStatus(for: url)
            if isGrantedPermissionStatus(status) {
                autoGranted.insert(url)
                SafariExtensionAutofillFillDiagnostics.recordHostPermission(
                    granted: true,
                    extensionId: extensionId,
                    reason: "promptAlreadyGranted"
                )
            } else if explicitlyGrantURLIfCoveredByGrantedMatchPattern(
                url,
                in: extensionContext
            ) {
                autoGranted.insert(url)
                SafariExtensionAutofillFillDiagnostics.recordHostPermission(
                    granted: true,
                    extensionId: extensionId,
                    reason: "promptMatchPattern"
                )
            } else {
                extensionContext.setPermissionStatus(.deniedExplicitly, for: url)
                denied.insert(url)
                SafariExtensionAutofillFillDiagnostics.recordHostPermission(
                    granted: false,
                    extensionId: extensionId,
                    reason: "promptDenied"
                )
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
            completionHandler(
                nil,
                SumiWebExtensionCallbackErrorMapper.webExtensionCallbackError(from: error)
            )
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
        _ = controller
        SumiNativeMessagingRuntimeCounters.recordDelegateSendMessageInvoked()
        let extensionId = extensionID(for: extensionContext)
        SafariExtensionAutofillFillDiagnostics.recordNativeMessagingActivity(
            extensionId: extensionId
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = try? await self.ensureBackgroundAvailableIfRequired(
                for: extensionContext.webExtension,
                context: extensionContext,
                reason: .nativeMessaging
            )
        }
        let profileId = profileId(for: extensionContext)
        #if DEBUG || SUMI_DIAGNOSTICS
            if RuntimeDiagnostics.isVerboseEnabled {
                RuntimeDiagnostics.debug(category: "SafariNativeMessagingRouting") {
                    """
                    WKWebExtensionControllerDelegate.sendMessage \
                    ext=\(extensionId ?? "unknown") \
                    profile=\(SafariExtensionNativeMessagingRoutingProbe.profileIdBucket(profileId)) \
                    appId=\(applicationIdentifier ?? "(nil)")
                    """
                }
            }
        #endif
        safariNativeMessagingHost.handleSendMessage(
            applicationIdentifier: applicationIdentifier,
            message: message,
            extensionId: extensionId,
            profileId: profileId,
            installedExtensions: installedExtensions,
            replyHandler: SumiWebExtensionCallbackRelay.wrapNativeMessagingReplyHandler(
                api: .runtimeSendNativeMessage,
                extensionId: extensionId,
                replyHandler
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
        SumiNativeMessagingRuntimeCounters.recordDelegateConnectInvoked()
        let extensionId = extensionID(for: extensionContext)
        SafariExtensionAutofillFillDiagnostics.recordNativeMessagingActivity(
            extensionId: extensionId
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = try? await self.ensureBackgroundAvailableIfRequired(
                for: extensionContext.webExtension,
                context: extensionContext,
                reason: .nativeMessaging
            )
        }

        let portKey = ObjectIdentifier(port)
        let profileId = profileId(for: extensionContext)
        #if DEBUG || SUMI_DIAGNOSTICS
            if RuntimeDiagnostics.isVerboseEnabled {
                RuntimeDiagnostics.debug(category: "SafariNativeMessagingRouting") {
                    """
                    WKWebExtensionControllerDelegate.connectUsing \
                    ext=\(extensionId ?? "unknown") \
                    profile=\(SafariExtensionNativeMessagingRoutingProbe.profileIdBucket(profileId)) \
                    appId=\(port.applicationIdentifier ?? "(nil)")
                    """
                }
            }
        #endif
        _ = safariNativeMessagingHost.handleConnect(
            port: port,
            extensionId: extensionId,
            profileId: profileId,
            installedExtensions: installedExtensions,
            registerHandler: { [weak self] handler in
                guard let self else { return }
                self.nativeMessagePortHandlers[portKey] = handler
                if let extensionId {
                    self.nativeMessagePortExtensionIDs[portKey] = extensionId
                }
                if let profileId = self.profileId(for: extensionContext) {
                    self.nativeMessagePortProfileIDs[portKey] = profileId
                }
            },
            completionHandler: SumiWebExtensionCallbackRelay.wrapCompletionHandler(
                api: .connectNativePort,
                extensionId: extensionId,
                completionHandler
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
