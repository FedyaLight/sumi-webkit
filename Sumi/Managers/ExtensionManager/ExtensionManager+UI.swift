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

    static let extensionActionPopupMinimumContentSize = NSSize(width: 320, height: 480)

    func prepareExtensionActionPopupPresentation(_ popover: NSPopover) {
        if popover.contentSize.width < 8 || popover.contentSize.height < 8 {
            popover.contentSize = Self.extensionActionPopupMinimumContentSize
        }
    }

    func extensionActionPopupAnchorRect(for anchorView: NSView) -> CGRect {
        let bounds = anchorView.bounds
        guard bounds.width < 4 || bounds.height < 4 else {
            return bounds
        }
        let side = max(28, max(bounds.width, bounds.height))
        return CGRect(
            x: bounds.midX - side / 2,
            y: bounds.midY - side / 2,
            width: side,
            height: side
        )
    }

    func showExtensionActionPopup(
        _ popover: NSPopover,
        relativeTo anchorView: NSView,
        preferredEdge: NSRectEdge
    ) {
        prepareExtensionActionPopupPresentation(popover)
        popover.show(
            relativeTo: extensionActionPopupAnchorRect(for: anchorView),
            of: anchorView,
            preferredEdge: preferredEdge
        )
    }

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

    /// Publishes URL-hub action metadata when WebKit has not yet delivered `didUpdate action`.
    func publishActionSurfaceStateForLoadedContext(
        _ extensionContext: WKWebExtensionContext,
        preferredTab: Tab? = nil
    ) {
        guard extensionID(for: extensionContext) != nil else { return }

        let tab = preferredTab ?? browserManager?.currentTabForActiveWindow()
        let adapter = tab.flatMap { stableAdapter(for: $0) }
        guard let action = extensionContext.action(for: adapter) else { return }

        updateActionSurfaceState(for: action, extensionContext: extensionContext)
    }

    /// After enable/load, wake background workers and seed action surface for URL-hub.
    func finalizeEnabledExtensionRuntime(
        for extensionId: String,
        profileId: UUID? = nil
    ) async {
        let resolvedProfileId =
            profileId ?? currentProfileId ?? browserManager?.currentProfile?.id
        guard let resolvedProfileId,
              let extensionContext = getExtensionContext(
                  for: extensionId,
                  profileId: resolvedProfileId
              ) else { return }

        publishActionSurfaceStateForLoadedContext(extensionContext)

        let webExtension = extensionContext.webExtension
        do {
            _ = try await ensureBackgroundAvailableIfRequired(
                for: webExtension,
                context: extensionContext,
                reason: .enable
            )
        } catch {
            Self.logger.error(
                "Failed to wake background after enable for \(extensionId, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }

        reconcileOpenTabsAfterExtensionContextLoad(
            reason: "ExtensionManager.finalizeEnabledExtensionRuntime"
        )
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
                message: "The extension is not installed in Sumi's local extension store."
            )
        }
        extensionRuntimeTrace(
            "urlHubAction click extensionId=\(extensionId) manifestHash=\(installedExtension.manifestRootFingerprint) generatedBundlePath=\(installedExtension.packagePath) originalPackagePath=\(installedExtension.sourceBundlePath) extensionEnabled=\(installedExtension.isEnabled) runtimeState=\(runtimeState.rawValue) contextLoaded=\(getExtensionContext(for: extensionId) != nil) currentProfile=\(currentProfileId?.uuidString ?? "nil") tabProfile=\(currentTab?.profileId?.uuidString ?? "nil") tabOffRecord=\(currentTab?.isEphemeral ?? false) currentURLShape=\(sanitizedURLHubTraceURL(currentTab?.url))"
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
                message: "Private tabs are not eligible for extension action popups."
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

        guard let tabProfileId = resolvedProfileId(for: currentTab) else {
            return .blocked(
                .noEligibleTab,
                message: "No profile is available for the active tab."
            )
        }
        if latestActionPopupAnchorSessionByExtensionID[extensionId] == nil {
            let windowId =
                currentTab.primaryWindowId
                ?? browserManager?.windowRegistry?.activeWindow?.id
            if let windowId {
                _ = captureActionPopupAnchor(
                    extensionId: extensionId,
                    windowId: windowId,
                    profileId: tabProfileId
                )
            }
        }
        switchProfile(profileId: tabProfileId)
        _ = ensureExtensionController(for: tabProfileId)

        let extensionContext: WKWebExtensionContext
        do {
            guard let loadedContext = try await loadActionPopupContextIfNeeded(
                for: installedExtension,
                profileId: tabProfileId
            ) else {
                let failureBucket = classifyActionPopupRuntimeFailure(
                    extensionId: extensionId,
                    profileId: tabProfileId,
                    installedExtension: installedExtension
                )
                let diagnostics = actionPopupRuntimeDiagnosticLines(
                    extensionId: extensionId,
                    profileId: tabProfileId,
                    installedExtension: installedExtension,
                    failureBucket: failureBucket,
                    lastLoadError: lastExtensionLoadError(
                        extensionId: extensionId,
                        profileId: tabProfileId
                    )
                )
                return .blocked(
                    .contextUnavailable,
                    message: "\(installedExtension.name) has no enabled persisted local package record for WebKit context loading.",
                    diagnostics: diagnostics
                )
            }
            extensionContext = loadedContext
        } catch {
            let failureBucket = classifyActionPopupRuntimeFailure(
                extensionId: extensionId,
                profileId: tabProfileId,
                installedExtension: installedExtension
            )
            let diagnostics = actionPopupRuntimeDiagnosticLines(
                extensionId: extensionId,
                profileId: tabProfileId,
                installedExtension: installedExtension,
                failureBucket: failureBucket,
                lastLoadError: error
            )
            extensionRuntimeTrace(
                "urlHubAction selected context load failed extensionId=\(extensionId) bucket=\(failureBucket.rawValue) error=\(error.localizedDescription) \(diagnostics.joined(separator: " "))"
            )
            return .blocked(
                .runtimeLoadFailed,
                message: "\(installedExtension.name) WebKit context load failed for the selected local package: \(error.localizedDescription)",
                diagnostics: diagnostics
            )
        }

        guard extensionContext.isLoaded else {
            let failureBucket = classifyActionPopupRuntimeFailure(
                extensionId: extensionId,
                profileId: tabProfileId,
                installedExtension: installedExtension
            )
            let diagnostics = actionPopupRuntimeDiagnosticLines(
                extensionId: extensionId,
                profileId: tabProfileId,
                installedExtension: installedExtension,
                failureBucket: failureBucket,
                lastLoadError: lastExtensionLoadError(
                    extensionId: extensionId,
                    profileId: tabProfileId
                )
            )
            extensionRuntimeTrace(
                "urlHubAction runtime gate failed extensionId=\(extensionId) profileId=\(tabProfileId.uuidString) bucket=\(failureBucket.rawValue) \(diagnostics.joined(separator: " "))"
            )
            let blocker: BrowserExtensionActionPopupBlocker =
                failureBucket == .globalRuntimeLoadFailed
                    || failureBucket == .webExtensionCreationFailed
                    || failureBucket == .profileContextNotLoaded
                ? .runtimeLoadFailed
                : .runtimeUnavailable
            return .blocked(
                blocker,
                message: "\(installedExtension.name) could not load WebKit extension runtime for the action popup.",
                diagnostics: diagnostics
            )
        }
        extensionRuntimeTrace(
            "urlHubAction runtime ready extensionId=\(extensionId) profileId=\(tabProfileId.uuidString) loadedContexts=\(extensionContexts(for: tabProfileId).count) selectedContextLoaded=true"
        )

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

        grantActiveTabURLAccess(
            for: extensionContext,
            tab: currentTab,
            manifest: installedExtension.manifest
        )
        grantRequestedPermissions(
            to: extensionContext,
            webExtension: extensionContext.webExtension,
            manifest: installedExtension.manifest
        )
        grantRequestedMatchPatterns(
            to: extensionContext,
            webExtension: extensionContext.webExtension
        )

        extensionRuntimeTrace(
            "urlHubAction performAction extensionId=\(extensionId) actionLabel=\(action.label) actionEnabled=\(action.isEnabled) presentsPopup=\(action.presentsPopup)"
        )
        extensionContext.performAction(for: adapter)
        recordRuntimeMetric(for: extensionId) { metrics in
            metrics.lastBackgroundWakeReason = .actionPopup
            metrics.backgroundWakeCount += 1
        }
        return .openedPopup
    }

    private func loadActionPopupContextIfNeeded(
        for installedExtension: InstalledExtension,
        profileId: UUID
    ) async throws -> WKWebExtensionContext? {
        extensionRuntimeTrace(
            "urlHubAction loading selected context extensionId=\(installedExtension.id) profileId=\(profileId.uuidString) runtimeState=\(runtimeState.rawValue) packagePath=\(installedExtension.packagePath)"
        )
        return try await ensureExtensionLoaded(
            extensionId: installedExtension.id,
            profileId: profileId
        )
    }

    private func sanitizedURLHubTraceURL(_ url: URL?) -> String {
        guard let url, let scheme = url.scheme?.lowercased() else {
            return "nil"
        }
        if Self.extensionSchemes.contains(scheme) {
            return "\(scheme)://<extension>/\(url.lastPathComponent.isEmpty ? "<resource>" : url.lastPathComponent)"
        }
        if scheme == "http" || scheme == "https" {
            return "\(scheme)://<host>/<redacted-path>"
        }
        return "\(scheme)://<redacted>"
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
            ExtensionUtils.hostPatternMatchesURL($0, url: currentURL)
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
        profileId: UUID? = nil,
        reason: String = #function
    ) {
        let resolvedProfileId =
            profileId ?? currentProfileId ?? browserManager?.currentProfile?.id
        guard let resolvedProfileId else { return }

        _ = requestExtensionRuntime(reason: .webViewConfiguration)
        let requestedController = ensureExtensionController(for: resolvedProfileId)
        let existingController = configuration.webExtensionController
        let shouldAssignController =
            existingController == nil || existingController !== requestedController

        extensionRuntimeTrace(
            "prepareConfiguration reason=\(reason) profileId=\(resolvedProfileId.uuidString) configuration=\(extensionRuntimeConfigurationDescription(configuration)) userContentController=\(extensionRuntimeUserContentControllerDescription(configuration.userContentController)) existingController=\(extensionRuntimeControllerDescription(existingController)) targetController=\(extensionRuntimeControllerDescription(requestedController)) willAssign=\(shouldAssignController)"
        )

        if shouldAssignController {
            configuration.webExtensionController = requestedController
        }
        configuration.websiteDataStore = getExtensionDataStore(for: resolvedProfileId)
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
        let owningTab = (webView as? FocusableWKWebView)?.owningTab
        let didAttach = owningTab.map {
            attachExtensionControllerIfNeeded(to: webView, for: $0)
        } ?? false

        if let owningTab,
           didAttach == false,
           webView.configuration.webExtensionController == nil,
           canLateBindExtensionController(to: webView) == false,
           let coordinator = browserManager?.webViewCoordinator
        {
            coordinator.rebuildLiveWebViews(for: owningTab)
            registerTabWithExtensionRuntime(
                owningTab,
                reason: "prepareWebViewForExtensionRuntime.rebuild"
            )
        }

        extensionRuntimeTrace(
            "prepareWebView reason=\(reason) webView=\(extensionRuntimeWebViewDescription(webView)) configuration=\(extensionRuntimeConfigurationDescription(webView.configuration)) userContentController=\(extensionRuntimeUserContentControllerDescription(webView.configuration.userContentController)) currentURL=\(currentURL?.absoluteString ?? "nil") existingController=\(extensionRuntimeControllerDescription(existingController)) extensionController=\(extensionRuntimeControllerDescription(extensionController)) willAssign=\(didAttach)"
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
            for: browserManager?.currentProfile,
            surface: .extensionOptions,
            additionalUserScripts: baseConfiguration.userContentController.userScripts
        )
        let optionsProfileId =
            profileId(for: extensionContext)
            ?? currentProfileId
            ?? browserManager?.currentProfile?.id
        prepareWebViewConfigurationForExtensionRuntime(
            configuration,
            profileId: optionsProfileId,
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
        if let extensionId = activePopupExtensionID {
            Task { @MainActor [weak self] in
                guard let self else { return }
                let diagnostic = await SafariExtensionSessionDiagnosticsBuilder.build(
                    extensionId: extensionId,
                    phase: .closed,
                    extensionManager: self
                )
                SafariExtensionSessionDiagnosticsBuilder.logIfDiagnosticsEnabled(diagnostic)
                self.activePopupExtensionID = nil
            }
        }
    }

    func recordExtensionActionPopupPresentation(
        for extensionId: String,
        popupWebView: WKWebView?,
        phase: SafariExtensionPopupLifecyclePhase
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let diagnostic = await SafariExtensionSessionDiagnosticsBuilder.build(
                extensionId: extensionId,
                phase: phase,
                extensionManager: self,
                popupWebView: popupWebView
            )
            SafariExtensionSessionDiagnosticsBuilder.logIfDiagnosticsEnabled(diagnostic)
        }
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
