import AppKit
import Foundation
import SwiftUI
import WebKit

@available(macOS 15.5, *)
@MainActor
private enum SafariNativeMessageRouter {
    private static var sleepDelay: TimeInterval {
        RuntimeDiagnostics.isRunningTests ? 0.05 : 30
    }

    private static var missingHostDelay: TimeInterval {
        RuntimeDiagnostics.isRunningTests ? 0.05 : 5
    }

    static func route(
        message: Any,
        for extensionContext: WKWebExtensionContext,
        manager: ExtensionManager,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) -> Bool {
        guard let message = message as? [String: Any],
              let command = message["command"] as? String else {
            return false
        }

        if command == "showPopover" {
            let currentTab = manager.browserManager?.windowRegistry?.activeWindow.flatMap {
                manager.browserManager?.currentTab(for: $0)
            }
            let adapter = currentTab.flatMap { manager.stableAdapter(for: $0) }
            extensionContext.performAction(for: adapter)
            replyHandler(["success": true], nil)
            return true
        }

        switch command {
        case "sleep":
            delayedReply(after: sleepDelay, value: NSNull(), replyHandler: replyHandler)
        case "copyToClipboard":
            if let value = message["data"] as? String {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
            }
            replyHandler(true, nil)
        case "readFromClipboard":
            replyHandler(NSPasteboard.general.string(forType: .string) ?? "", nil)
        default:
            return false
        }

        return true
    }

    static func replyForMissingNativeHost(
        applicationId: String,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) {
        RuntimeDiagnostics.debug(
            "Native messaging host \(applicationId) is not registered for Sumi; returning delayed null response",
            category: "Extensions"
        )
        delayedReply(after: missingHostDelay, value: NSNull(), replyHandler: replyHandler)
    }

    private static func delayedReply(
        after delay: TimeInterval,
        value: Any,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            replyHandler(value, nil)
        }
    }
}

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
        if let windowId = browserManager?.windowRegistry?.activeWindow?.id {
            return windowAdapter(for: windowId)
        }
        return nil
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openWindowsFor extensionContext: WKWebExtensionContext
    ) -> [any WKWebExtensionWindow] {
        guard let browserManager else { return [] }
        return browserManager.windowRegistry?.windows.keys.compactMap {
            windowAdapter(for: $0)
        } ?? []
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        presentActionPopup action: WKWebExtension.Action,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let manifest = extensionID(for: extensionContext)
            .flatMap { loadedExtensionManifests[$0] } ?? [:]

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

        if let popupWebView = action.popupWebView,
           RuntimeDiagnostics.isDeveloperInspectionEnabled {
            popupWebView.isInspectable = true
        }

        DispatchQueue.main.async {
            let targetWindow = NSApp.keyWindow ?? NSApp.mainWindow

            popover.behavior = .transient
            popover.delegate = self
            self.isPopupActive = true

            if let extensionId = self.extensionID(for: extensionContext),
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
                completionHandler(nil)
                return
            }

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
        let manifest = extensionID(for: extensionContext)
            .flatMap { loadedExtensionManifests[$0] } ?? [:]
        let policyDeniedPermissions = permissions
            .union(extensionContext.webExtension.optionalPermissions)
            .filter { shouldDenyAutoGrantForSafariOnlyRuntime($0, manifest: manifest) }
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

        if SafariNativeMessageRouter.route(
            message: message,
            for: extensionContext,
            manager: self,
            replyHandler: replyHandler
        ) {
            return
        }

        let browserSupportDirectory = ExtensionUtils.applicationSupportRoot()
        let appBundleURL = Bundle.main.bundleURL
        guard NativeMessagingHandler.resolveManifestURL(
            applicationId: applicationId,
            browserSupportDirectory: browserSupportDirectory,
            appBundleURL: appBundleURL
        ) != nil else {
            SafariNativeMessageRouter.replyForMissingNativeHost(
                applicationId: applicationId,
                replyHandler: replyHandler
            )
            return
        }

        let handler = NativeMessagingHandler(
            applicationId: applicationId,
            browserSupportDirectory: browserSupportDirectory,
            appBundleURL: appBundleURL
        )
        handler.sendMessage(message) { response, error in
            replyHandler(response, error)
        }
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        connectUsing port: WKWebExtension.MessagePort,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        guard let applicationId = port.applicationIdentifier else {
            completionHandler(nil)
            return
        }
        let extensionId = self.extensionID(for: extensionContext)

        let handler = NativeMessagingHandler(
            applicationId: applicationId,
            browserSupportDirectory: ExtensionUtils.applicationSupportRoot(),
            appBundleURL: Bundle.main.bundleURL
        )

        let portID = ObjectIdentifier(port)
        nativeMessagePortHandlers[portID] = handler
        if let extensionId {
            nativeMessagePortExtensionIDs[portID] = extensionId
        }
        handler.connect(port: port) { [weak self] in
            self?.nativeMessagePortHandlers.removeValue(forKey: portID)
            self?.nativeMessagePortExtensionIDs.removeValue(forKey: portID)
        }
        completionHandler(nil)
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
