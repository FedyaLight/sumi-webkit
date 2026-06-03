import AppKit
import Foundation
import SwiftUI
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionOptionsWindowDelegate: NSObject, NSWindowDelegate, WKUIDelegate {
    private let extensionId: String
    private weak var manager: ExtensionManager?
    private weak var webView: WKWebView?
    var isCleaningUp = false

    init(
        extensionId: String,
        manager: ExtensionManager,
        webView: WKWebView
    ) {
        self.extensionId = extensionId
        self.manager = manager
        self.webView = webView
        super.init()
    }

    func windowWillClose(_ notification: Notification) {
        guard isCleaningUp == false else { return }
        manager?.cleanupOptionsWindow(
            for: extensionId,
            window: notification.object as? NSWindow,
            webView: webView,
            shouldOrderOut: false
        )
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard isCleaningUp == false else { return }
        manager?.cleanupOptionsWindow(
            for: extensionId,
            window: webView.window,
            webView: webView,
            shouldOrderOut: true
        )
    }
}

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager: NSPopoverDelegate {
    func updateActionSurfaceState(
        for action: WKWebExtension.Action,
        extensionContext: WKWebExtensionContext
    ) {
        guard let extensionId = extensionID(for: extensionContext) else {
            return
        }

        actionStatesByExtensionID[extensionId] =
            BrowserExtensionActionSurfaceState(
                extensionID: extensionId,
                label: action.label,
                badgeText: action.badgeText,
                hasUnreadBadgeText: action.hasUnreadBadgeText,
                isEnabled: action.isEnabled,
                presentsPopup: action.presentsPopup,
                icon: action.icon(for: CGSize(width: 18, height: 18))
            )
    }

    func clearActionSurfaceState(for extensionId: String) {
        actionStatesByExtensionID.removeValue(forKey: extensionId)
    }

    func openActionPopupFromURLHub(
        extensionId: String,
        currentTab: Tab?
    ) async -> BrowserExtensionActionPopupRequestResult {
        guard let installedExtension = installedExtensions.first(where: {
            $0.id == extensionId
        }) else {
            return .blocked(
                .extensionNotInstalled,
                message: "The extension is not installed in Sumi's local MV3 action surface."
            )
        }
        extensionRuntimeTrace(
            "urlHubAction click extensionId=\(extensionId) manifestHash=\(installedExtension.manifestRootFingerprint) generatedBundlePath=\(installedExtension.packagePath) originalPackagePath=\(installedExtension.sourceBundlePath) extensionEnabled=\(installedExtension.isEnabled) runtimeState=\(runtimeState.rawValue) contextLoaded=\(getExtensionContext(for: extensionId) != nil) currentProfile=\(currentProfileId?.uuidString ?? "nil") tabProfile=\(currentTab?.profileId?.uuidString ?? "nil") tabOffRecord=\(currentTab?.isEphemeral ?? false) currentURL=\(currentTab?.url.absoluteString ?? "nil")"
        )
        guard installedExtension.isEnabled else {
            return .blocked(
                .extensionDisabled,
                message: "\(installedExtension.name) is disabled."
            )
        }
        guard installedExtension.hasAction else {
            return .blocked(
                .actionMissing,
                message: "\(installedExtension.name) does not declare a Chrome action."
            )
        }
        guard installedExtension.defaultPopupPath != nil else {
            return .blocked(
                .noActionPopup,
                message: "\(installedExtension.name) does not declare action.default_popup; action-click dispatch is deferred."
            )
        }
        guard let currentTab else {
            return .blocked(
                .noEligibleTab,
                message: "No active eligible tab is available for the extension action."
            )
        }
        guard currentTab.isEphemeral == false else {
            return .blocked(
                .noEligibleTab,
                message: "Private tabs are not eligible for local MV3 action popups."
            )
        }
        guard hasActionCurrentPagePermission(
            installedExtension,
            currentURL: currentTab.url
        ) else {
            return .blocked(
                .currentPagePermissionMissing,
                message: "\(installedExtension.name) does not have host permission or activeTab for the current page."
            )
        }
        guard isModuleWorkerUnsupported(installedExtension) == false else {
            return .blocked(
                .moduleWorkerUnsupported,
                message: "\(installedExtension.name) declares a module service worker, which remains unsupported in this popup path."
            )
        }
        extensionRuntimeTrace(
            "urlHubAction preflight passed extensionId=\(extensionId) localExperimentalRecordEnabled=true currentTabEligible=true currentPagePermission=true moduleWorkerUnsupported=false"
        )

        guard await requestExtensionRuntimeAndWait(reason: .extensionAction) else {
            return .blocked(
                runtimeState == .failed ? .runtimeLoadFailed : .runtimeUnavailable,
                message: "\(installedExtension.name) could not load WebKit extension runtime for the action popup."
            )
        }
        extensionRuntimeTrace(
            "urlHubAction runtime ready extensionId=\(extensionId) loadedContexts=\(extensionContexts.count) selectedContextLoaded=\(getExtensionContext(for: extensionId) != nil)"
        )

        let extensionContext: WKWebExtensionContext
        do {
            guard let loadedContext = try await loadActionPopupContextIfNeeded(
                for: installedExtension
            ) else {
                return .blocked(
                    .contextUnavailable,
                    message: "\(installedExtension.name) has no enabled persisted local package record for WebKit context loading."
                )
            }
            extensionContext = loadedContext
        } catch {
            extensionRuntimeTrace(
                "urlHubAction selected context load failed extensionId=\(extensionId) error=\(error.localizedDescription)"
            )
            return .blocked(
                .runtimeLoadFailed,
                message: "\(installedExtension.name) WebKit context load failed for the selected local package: \(error.localizedDescription)"
            )
        }

        let adapter = stableAdapter(for: currentTab)
        guard let action = extensionContext.action(for: adapter) else {
            return .blocked(
                .actionMissing,
                message: "WebKit did not expose an action for \(installedExtension.name)."
            )
        }

        updateActionSurfaceState(
            for: action,
            extensionContext: extensionContext
        )

        guard action.isEnabled else {
            return .blocked(
                .actionDisabled,
                message: "\(action.label) is disabled for the current page."
            )
        }
        guard action.presentsPopup else {
            return .blocked(
                .noActionPopup,
                message: "\(action.label) has no WebKit action popup for the current page."
            )
        }

        extensionRuntimeTrace(
            "urlHubAction performAction extensionId=\(extensionId) actionLabel=\(action.label) actionEnabled=\(action.isEnabled) presentsPopup=\(action.presentsPopup)"
        )
        extensionContext.performAction(for: adapter)
        recordRuntimeMetric(for: extensionId) { metrics in
            metrics.lastBackgroundWakeReason = .actionPopup
            metrics.backgroundWakeCount += 1
        }
        #if DEBUG
        return .openedPopup(
            sanitizedBridgeSnapshot: nil,
            diagnostics: [
                "URL-hub opened the real WebKit action popup through WKWebExtensionContext.performAction.",
                "No ChromeMV3PopupOptionsJSBridgeHandler is installed on WebKit's native action.popupWebView, so no Sumi popup bridge route records were available immediately after popup open.",
                "Snapshot retrieval is passive and did not create a popup, runtime, service-worker, content-script endpoint, native host, timer, or bridge by itself.",
            ]
        )
        #else
        return .openedPopup
        #endif
    }

    private func loadActionPopupContextIfNeeded(
        for installedExtension: InstalledExtension
    ) async throws -> WKWebExtensionContext? {
        if let extensionContext = getExtensionContext(for: installedExtension.id) {
            return extensionContext
        }

        guard let entity = try extensionEntity(for: installedExtension.id),
              entity.isEnabled
        else {
            return nil
        }

        extensionRuntimeTrace(
            "urlHubAction loading selected missing context extensionId=\(installedExtension.id) runtimeState=\(runtimeState.rawValue) packagePath=\(entity.packagePath)"
        )
        _ = try await loadEnabledExtension(
            from: entity,
            expectedLoadGeneration: extensionLoadGeneration
        )
        return getExtensionContext(for: installedExtension.id)
    }

    private func isModuleWorkerUnsupported(
        _ installedExtension: InstalledExtension
    ) -> Bool {
        guard let background = installedExtension.manifest["background"]
                as? [String: Any],
              let type = background["type"] as? String
        else {
            return false
        }
        return type.caseInsensitiveCompare("module") == .orderedSame
    }

    private func hasActionCurrentPagePermission(
        _ installedExtension: InstalledExtension,
        currentURL: URL
    ) -> Bool {
        guard ["http", "https"].contains(currentURL.scheme?.lowercased() ?? "") else {
            return false
        }

        let manifest = installedExtension.manifest
        let permissions = stringArray(from: manifest["permissions"])
        let optionalPermissions = stringArray(from: manifest["optional_permissions"])
        if (permissions + optionalPermissions).contains("activeTab") {
            return true
        }

        let contentScriptMatches =
            (manifest["content_scripts"] as? [[String: Any]] ?? [])
                .flatMap { stringArray(from: $0["matches"]) }
        let hostPatterns =
            stringArray(from: manifest["host_permissions"])
            + permissions.filter(Self.isHostPermissionPattern)
            + contentScriptMatches

        return hostPatterns.contains {
            ChromeMV3HostMatchPattern($0).matches(
                url: currentURL.absoluteString
            )
        }
    }

    private static func isHostPermissionPattern(_ value: String) -> Bool {
        value == "<all_urls>"
            || value.hasPrefix("http://")
            || value.hasPrefix("https://")
            || value.hasPrefix("*://")
    }

    private func stringArray(from value: Any?) -> [String] {
        value as? [String] ?? []
    }

    func prepareWebViewConfigurationForExtensionRuntime(
        _ configuration: WKWebViewConfiguration,
        reason: String = #function
    ) {
        let requestedController = requestExtensionRuntime(
            reason: .webViewConfiguration
        )
        let existingController = configuration.webExtensionController
        let shouldAssignController = existingController == nil && requestedController != nil

        extensionRuntimeTrace(
            "prepareConfiguration reason=\(reason) configuration=\(extensionRuntimeConfigurationDescription(configuration)) userContentController=\(extensionRuntimeUserContentControllerDescription(configuration.userContentController)) existingController=\(extensionRuntimeControllerDescription(existingController)) targetController=\(extensionRuntimeControllerDescription(requestedController)) willAssign=\(shouldAssignController)"
        )

        if shouldAssignController {
            configuration.webExtensionController = requestedController
        }
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
    }

    func setActionAnchor(for extensionId: String, anchorView: NSView) {
        pruneActionAnchors(for: extensionId, keeping: anchorView)

        let anchor = WeakAnchor(view: anchorView, window: anchorView.window)
        var anchors = actionAnchors[extensionId] ?? []

        if let index = anchors.firstIndex(where: { $0.view === anchorView }) {
            anchors[index] = anchor
        } else {
            anchors.append(anchor)
        }
        actionAnchors[extensionId] = anchors

        let viewIdentifier = ObjectIdentifier(anchorView)
        anchorView.postsFrameChangedNotifications = true

        if anchorObserverTokens[extensionId]?[viewIdentifier] != nil {
            return
        }

        let token = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: anchorView,
            queue: .main
        ) { [weak self, weak anchorView] _ in
            guard let anchorView else { return }
            Task { @MainActor [weak self] in
                guard let index = self?.actionAnchors[extensionId]?.firstIndex(where: { $0.view === anchorView }) else {
                    return
                }
                self?.actionAnchors[extensionId]?[index] = WeakAnchor(
                    view: anchorView,
                    window: anchorView.window
                )
                self?.pruneActionAnchors(for: extensionId, keeping: anchorView)
            }
        }

        anchorObserverTokens[extensionId, default: [:]][viewIdentifier] = token
        enforceActionAnchorLimit(for: extensionId, keeping: anchorView)
    }

    func clearActionAnchors(for extensionId: String) {
        removeAnchorObservers(for: extensionId)
        actionAnchors.removeValue(forKey: extensionId)
    }

    func closeOptionsWindow(for extensionId: String) {
        cleanupOptionsWindow(for: extensionId, shouldOrderOut: true)
    }

    func closeAllOptionsWindows() {
        Array(optionsWindows.keys).forEach { closeOptionsWindow(for: $0) }
    }

    func cleanupOptionsWindow(
        for extensionId: String,
        window: NSWindow? = nil,
        webView: WKWebView? = nil,
        shouldOrderOut: Bool
    ) {
        guard let resolvedWindow = window ?? optionsWindows[extensionId] else {
            optionsWindowDelegates.removeValue(forKey: extensionId)
            return
        }

        let delegate = optionsWindowDelegates[extensionId]
        delegate?.isCleaningUp = true

        let resolvedWebView = webView ?? resolvedWindow.contentView.flatMap {
            Self.firstWebView(in: $0)
        }
        if let resolvedWebView {
            SumiAuxiliaryWebViewShutdown.perform(
                on: resolvedWebView,
                browserManager: browserManager,
                reason: "Extension options window cleanup"
            )
        }

        if shouldOrderOut {
            resolvedWindow.orderOut(nil)
        }
        resolvedWindow.contentViewController = nil
        resolvedWindow.contentView = nil
        resolvedWindow.delegate = nil
        optionsWindows.removeValue(forKey: extensionId)
        optionsWindowDelegates.removeValue(forKey: extensionId)
    }

    func prepareWebViewForExtensionRuntime(
        _ webView: WKWebView,
        currentURL: URL? = nil,
        reason: String = #function
    ) {
        let existingController = webView.configuration.webExtensionController

        extensionRuntimeTrace(
            "prepareWebView reason=\(reason) webView=\(extensionRuntimeWebViewDescription(webView)) configuration=\(extensionRuntimeConfigurationDescription(webView.configuration)) userContentController=\(extensionRuntimeUserContentControllerDescription(webView.configuration.userContentController)) currentURL=\(currentURL?.absoluteString ?? "nil") existingController=\(extensionRuntimeControllerDescription(existingController)) extensionController=\(extensionRuntimeControllerDescription(extensionController)) willAssign=false"
        )

        webView.configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        installExternallyConnectableNativeBridgeIfNeeded(
            into: webView.configuration.userContentController
        )
        updateExternallyConnectableNavigationLifecycle(
            for: webView,
            currentURL: currentURL
        )
    }

    func openExtensionWindowUsingTabURLs(
        _ tabURLs: [URL],
        controller: WKWebExtensionController,
        createWindow: @escaping @MainActor () -> Void,
        awaitWindowRegistration: @escaping @MainActor (Set<UUID>) async -> BrowserWindowState?,
        completionHandler: @escaping ((any WKWebExtensionWindow)?, (any Error)?) -> Void
    ) {
        guard let browserManager, let windowRegistry = browserManager.windowRegistry else {
            completionHandler(
                nil,
                NSError(
                    domain: "ExtensionManager",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "Browser manager is unavailable"]
                )
            )
            return
        }

        if let firstURL = tabURLs.first,
           OAuthDetector.isLikelyOAuthPopupURL(firstURL),
           let activeWindow = windowRegistry.activeWindow
        {
            let targetSpace = activeWindow.currentSpaceId.flatMap { spaceID in
                browserManager.tabManager.spaces.first(where: { $0.id == spaceID })
            } ?? browserManager.tabManager.currentSpace

            let createdTab = browserManager.tabManager.createNewTab(
                url: firstURL.absoluteString,
                in: targetSpace,
                activate: false
            )

            if Self.isExtensionOwnedURL(firstURL),
               let resolvedContext = controller.extensionContext(for: firstURL)
            {
                createdTab.applyWebViewConfigurationOverride(
                    resolvedContext.webViewConfiguration
                        ?? browserConfiguration.webViewConfiguration
                )
            }

            browserManager.selectTab(createdTab, in: activeWindow)
            completionHandler(windowAdapter(for: activeWindow.id), nil)
            return
        }

        let existingWindowIDs = Set(windowRegistry.windows.keys)
        createWindow()

        Task { @MainActor [weak self, weak browserManager] in
            guard let self, let browserManager else { return }

            guard let windowState = await awaitWindowRegistration(existingWindowIDs) else {
                completionHandler(nil, NSError(
                    domain: "ExtensionManager",
                    code: 5,
                    userInfo: [NSLocalizedDescriptionKey: "Sumi could not resolve the new window"]
                ))
                return
            }

            let targetSpace = windowState.currentSpaceId.flatMap { spaceID in
                browserManager.tabManager.spaces.first(where: { $0.id == spaceID })
            } ?? browserManager.tabManager.currentSpace

            let createdTab: Tab
            if let firstURL = tabURLs.first {
                createdTab = browserManager.tabManager.createNewTab(
                    url: firstURL.absoluteString,
                    in: targetSpace,
                    activate: false
                )

                if Self.isExtensionOwnedURL(firstURL),
                   let resolvedContext = controller.extensionContext(for: firstURL)
                {
                    createdTab.applyWebViewConfigurationOverride(
                        resolvedContext.webViewConfiguration
                            ?? browserConfiguration.webViewConfiguration
                    )
                }
            } else {
                createdTab = browserManager.tabManager.createNewTab(
                    in: targetSpace,
                    activate: false
                )
            }

            browserManager.selectTab(createdTab, in: windowState)
            completionHandler(self.windowAdapter(for: windowState.id), nil)
        }
    }

    func presentOptionsPageWindow(
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let displayName =
            extensionContext.webExtension.displayName ?? "Extension"
        guard let extensionId = extensionID(for: extensionContext),
              let installedExtension = installedExtensions.first(where: { $0.id == extensionId })
        else {
            completionHandler(ExtensionUtils.optionsPageNotFoundError())
            return
        }

        let extensionRoot = URL(
            fileURLWithPath: installedExtension.packagePath,
            isDirectory: true
        ).resolvingSymlinksInPath().standardizedFileURL
        let manifest = loadedExtensionManifests[extensionId] ?? installedExtension.manifest

        let diskResolvedURL = try? ExtensionUtils.resolvedOptionsPageURL(
            sdkURL: nil,
            persistedPath: installedExtension.optionsPagePath,
            manifest: manifest,
            extensionRoot: extensionRoot
        )

        let sdkURL = extensionContext.optionsPageURL
        let manifestURL = computeOptionsPageURL(for: extensionContext)
        let optionsURL: URL?
        if let diskResolvedURL {
            optionsURL = diskResolvedURL
        } else if let sdkURL {
            optionsURL = sdkURL
        } else if let manifestURL {
            optionsURL = manifestURL
        } else {
            optionsURL = nil
        }

        guard let optionsURL else {
            completionHandler(ExtensionUtils.optionsPageNotFoundError())
            return
        }

        let baseConfiguration =
            extensionContext.webViewConfiguration
            ?? browserConfiguration.webViewConfiguration
        let configuration = browserConfiguration.auxiliaryWebViewConfiguration(
            from: baseConfiguration,
            surface: .extensionOptions,
            additionalUserScripts: baseConfiguration.userContentController.userScripts
        )
        prepareWebViewConfigurationForExtensionRuntime(
            configuration,
            reason: "ExtensionManager.openOptionsPage.configuration"
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        if RuntimeDiagnostics.isDeveloperInspectionEnabled {
            webView.isInspectable = true
        }
        webView.allowsBackForwardNavigationGestures = true
        prepareWebViewForExtensionRuntime(
            webView,
            currentURL: optionsURL,
            reason: "ExtensionManager.openOptionsPage"
        )

        if optionsURL.isFileURL {
            do {
                let validatedOptionsURL = try ExtensionUtils.validatedExtensionPageURL(
                    optionsURL,
                    within: extensionRoot
                )
                webView.loadFileURL(
                    validatedOptionsURL,
                    allowingReadAccessTo: extensionRoot
                )
            } catch {
                completionHandler(error)
                return
            }
        } else {
            webView.load(URLRequest(url: optionsURL))
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(displayName) – Options"

        let container = NSView(frame: window.contentView?.bounds ?? .zero)
        container.translatesAutoresizingMaskIntoConstraints = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        window.contentView = container
        window.center()

        closeOptionsWindow(for: extensionId)
        let delegate = ExtensionOptionsWindowDelegate(
            extensionId: extensionId,
            manager: self,
            webView: webView
        )
        webView.uiDelegate = delegate
        window.delegate = delegate
        optionsWindows[extensionId] = window
        optionsWindowDelegates[extensionId] = delegate
        window.orderFront(nil)

        completionHandler(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        isPopupActive = false
    }

    private func removeAnchorObservers(for extensionId: String) {
        guard let tokens = anchorObserverTokens.removeValue(forKey: extensionId) else {
            return
        }

        for (_, token) in tokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func pruneActionAnchors(
        for extensionId: String,
        keeping anchorView: NSView? = nil
    ) {
        guard var anchors = actionAnchors[extensionId] else {
            return
        }

        anchors.removeAll { anchor in
            guard let view = anchor.view else { return true }
            if let anchorView, view === anchorView {
                return false
            }
            return anchor.window == nil || view.window == nil
        }

        if anchors.isEmpty {
            actionAnchors.removeValue(forKey: extensionId)
        } else {
            actionAnchors[extensionId] = anchors
        }

        let liveViewIDs = Set(anchors.compactMap { anchor -> ObjectIdentifier? in
            guard let view = anchor.view else { return nil }
            return ObjectIdentifier(view)
        })
        let keptViewID = anchorView.map(ObjectIdentifier.init)

        guard var tokens = anchorObserverTokens[extensionId] else {
            return
        }

        for viewID in Array(tokens.keys) {
            guard liveViewIDs.contains(viewID) == false,
                  viewID != keptViewID
            else {
                continue
            }
            if let token = tokens.removeValue(forKey: viewID) {
                NotificationCenter.default.removeObserver(token)
            }
        }

        if tokens.isEmpty {
            anchorObserverTokens.removeValue(forKey: extensionId)
        } else {
            anchorObserverTokens[extensionId] = tokens
        }
    }

    private func enforceActionAnchorLimit(
        for extensionId: String,
        keeping anchorView: NSView
    ) {
        let maxAnchors = 32
        guard var anchors = actionAnchors[extensionId],
              anchors.count > maxAnchors else {
            return
        }

        var removedViewIDs: [ObjectIdentifier] = []
        while anchors.count > maxAnchors {
            guard let removalIndex = anchors.firstIndex(where: { anchor in
                guard let view = anchor.view else { return true }
                return view !== anchorView
            }) else {
                break
            }

            if let view = anchors[removalIndex].view {
                removedViewIDs.append(ObjectIdentifier(view))
            }
            anchors.remove(at: removalIndex)
        }

        actionAnchors[extensionId] = anchors

        guard var tokens = anchorObserverTokens[extensionId] else {
            return
        }

        for viewID in removedViewIDs {
            if let token = tokens.removeValue(forKey: viewID) {
                NotificationCenter.default.removeObserver(token)
            }
        }

        if tokens.isEmpty {
            anchorObserverTokens.removeValue(forKey: extensionId)
        } else {
            anchorObserverTokens[extensionId] = tokens
        }
    }

    private static func firstWebView(in root: NSView) -> WKWebView? {
        if let webView = root as? WKWebView {
            return webView
        }

        for subview in root.subviews {
            if let webView = firstWebView(in: subview) {
                return webView
            }
        }
        return nil
    }

    private func showErrorAlert(_ error: ExtensionError) {
        let alert = NSAlert()
        alert.messageText = "Extension Error"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
