import AppKit
import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    static let extensionActionPopupMinimumContentSize =
        ExtensionActionPopupPresentationOwner.minimumContentSize

    func prepareExtensionActionPopupPresentation(_ popover: NSPopover) {
        ExtensionActionPopupPresentationOwner.prepare(popover)
    }

    func extensionActionPopupAnchorRect(for anchorView: NSView) -> CGRect {
        ExtensionActionPopupPresentationOwner.anchorRect(for: anchorView)
    }

    func showExtensionActionPopup(
        _ popover: NSPopover,
        relativeTo anchorView: NSView,
        preferredEdge: NSRectEdge
    ) {
        ExtensionActionPopupPresentationOwner.show(
            popover,
            relativeTo: anchorView,
            preferredEdge: preferredEdge
        )
    }

    func updateActionSurfaceState(
        for action: WKWebExtension.Action,
        extensionContext: WKWebExtensionContext
    ) {
        guard let update = ExtensionActionSurfaceStatePresenter.makeUpdate(
            for: action,
            extensionID: extensionID(for: extensionContext)
        ) else { return }

        actionStatesByExtensionID[update.extensionID] = update.state
    }

    func clearActionSurfaceState(for extensionId: String) {
        actionStatesByExtensionID.removeValue(forKey: extensionId)
    }

    /// Publishes URL-hub action metadata when WebKit has not yet delivered `didUpdate action`.
    func publishActionSurfaceStateForLoadedContext(
        _ extensionContext: WKWebExtensionContext,
        preferredTab: Tab? = nil
    ) {
        guard let action = ExtensionActionSurfaceStatePresenter.actionForLoadedContext(
            extensionContext,
            preferredTab: preferredTab,
            currentTab: { browserBridgeContext?.currentExtensionTabForActiveWindow() },
            stableAdapter: { stableAdapter(for: $0) }
        ) else { return }

        updateActionSurfaceState(for: action, extensionContext: extensionContext)
    }

    func createAuxiliaryWebViewFromActionPopup(
        _ popupWebView: WKWebView,
        with configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        ExtensionActionPopupPresentationOwner.createAuxiliaryWebViewFromActionPopup(
            popupWebView,
            with: configuration,
            for: navigationAction,
            windowFeatures: windowFeatures,
            manager: self
        )
    }

    /// After context load, seed action state and optionally wake background for explicit
    /// lifecycle events such as user-enabled extension activation.
    func finalizeEnabledExtensionRuntime(
        for extensionId: String,
        profileId: UUID? = nil,
        backgroundWakeReason: ExtensionBackgroundWakeReason? = nil
    ) async {
        let resolvedProfileId = resolvedProfileId(explicitProfileId: profileId)
        guard let resolvedProfileId,
              let extensionContext = getExtensionContext(
                  for: extensionId,
                  profileId: resolvedProfileId
              ) else { return }

        publishActionSurfaceStateForLoadedContext(extensionContext)

        if let backgroundWakeReason {
            let webExtension = extensionContext.webExtension
            do {
                _ = try await ensureBackgroundAvailableIfRequired(
                    for: webExtension,
                    context: extensionContext,
                    reason: backgroundWakeReason
                )
            } catch {
                Self.logger.error(
                    "Failed to wake background for \(extensionId, privacy: .public) after \(backgroundWakeReason.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
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
            "urlHubAction click extensionId=\(extensionId) manifestHash=\(installedExtension.manifestRootFingerprint) resourcesPath=\(installedExtension.packagePath) sourceBundlePath=\(installedExtension.sourceBundlePath) extensionEnabled=\(installedExtension.isEnabled) runtimeState=\(runtimeState.rawValue) contextLoaded=\(getExtensionContext(for: extensionId) != nil) currentProfile=\(currentProfileId?.uuidString ?? "nil") tabProfile=\(currentTab?.profileId?.uuidString ?? "nil") tabOffRecord=\(currentTab?.isEphemeral ?? false) currentURLShape=\(sanitizedURLHubTraceURL(currentTab?.url))"
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
        if let currentTab {
            guard currentTab.isEphemeral == false else {
                return .blocked(
                    .noEligibleTab,
                    message: "Private tabs are not eligible for extension action popups."
                )
            }
        }
        guard isModuleWorkerUnsupported(installedExtension) == false else {
            return .blocked(
                .moduleWorkerUnsupported,
                message: "\(installedExtension.name) declares a module service worker, which remains unsupported in this popup path."
            )
        }
        extensionRuntimeTrace(
            "urlHubAction preflight passed extensionId=\(extensionId) localExperimentalRecordEnabled=true currentTabEligible=\(currentTab != nil) currentPagePermission=true moduleWorkerUnsupported=false"
        )

        guard let actionProfileId =
                currentTab.flatMap({ resolvedProfileId(for: $0) })
                ?? fallbackProfileId
        else {
            return .blocked(
                .noEligibleTab,
                message: "No profile is available for the extension action."
            )
        }
        if actionPopupAnchorStore.latestSessionToken(for: extensionId) == nil {
            let windowId =
                currentTab?.primaryWindowId
                ?? browserBridgeContext?.activeExtensionWindowState?.id
            if let windowId {
                _ = captureActionPopupAnchor(
                    extensionId: extensionId,
                    windowId: windowId,
                    profileId: actionProfileId
                )
            }
        }
        switchProfile(profileId: actionProfileId)
        _ = ensureExtensionController(for: actionProfileId)

        let extensionContext: WKWebExtensionContext
        do {
            guard let loadedContext = try await loadActionPopupContextIfNeeded(
                for: installedExtension,
                profileId: actionProfileId
            ) else {
                let failureBucket = classifyActionPopupRuntimeFailure(
                    extensionId: extensionId,
                    profileId: actionProfileId,
                    installedExtension: installedExtension
                )
                let diagnostics = actionPopupRuntimeDiagnosticLines(
                    extensionId: extensionId,
                    profileId: actionProfileId,
                    installedExtension: installedExtension,
                    failureBucket: failureBucket,
                    lastLoadError: lastExtensionLoadError(
                        extensionId: extensionId,
                        profileId: actionProfileId
                    )
                )
                return .blocked(
                    .contextUnavailable,
                    message: "\(installedExtension.name) has no enabled WebKit extension context for this profile.",
                    diagnostics: diagnostics
                )
            }
            extensionContext = loadedContext
        } catch {
            let failureBucket = classifyActionPopupRuntimeFailure(
                extensionId: extensionId,
                profileId: actionProfileId,
                installedExtension: installedExtension
            )
            let diagnostics = actionPopupRuntimeDiagnosticLines(
                extensionId: extensionId,
                profileId: actionProfileId,
                installedExtension: installedExtension,
                failureBucket: failureBucket,
                lastLoadError: error
            )
            extensionRuntimeTrace(
                "urlHubAction selected context load failed extensionId=\(extensionId) bucket=\(failureBucket.rawValue) error=\(error.localizedDescription) \(diagnostics.joined(separator: " "))"
            )
            return .blocked(
                .runtimeLoadFailed,
                message: "\(installedExtension.name) WebKit context load failed: \(error.localizedDescription)",
                diagnostics: diagnostics
            )
        }

        guard extensionContext.isLoaded else {
            let failureBucket = classifyActionPopupRuntimeFailure(
                extensionId: extensionId,
                profileId: actionProfileId,
                installedExtension: installedExtension
            )
            let diagnostics = actionPopupRuntimeDiagnosticLines(
                extensionId: extensionId,
                profileId: actionProfileId,
                installedExtension: installedExtension,
                failureBucket: failureBucket,
                lastLoadError: lastExtensionLoadError(
                    extensionId: extensionId,
                    profileId: actionProfileId
                )
            )
            extensionRuntimeTrace(
                "urlHubAction runtime gate failed extensionId=\(extensionId) profileId=\(actionProfileId.uuidString) bucket=\(failureBucket.rawValue) \(diagnostics.joined(separator: " "))"
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
            "urlHubAction runtime ready extensionId=\(extensionId) profileId=\(actionProfileId.uuidString) loadedContexts=\(extensionContexts(for: actionProfileId).count) selectedContextLoaded=true currentTabEligible=\(currentTab != nil)"
        )

        let adapter: ExtensionTabAdapter?
        if let currentTab {
            registerTabWithExtensionRuntime(
                currentTab,
                reason: "ExtensionManager.openActionPopupFromURLHub"
            )
            adapter = stableAdapter(for: currentTab)
        } else {
            adapter = nil
        }
        grantRequestedPermissions(
            to: extensionContext,
            webExtension: extensionContext.webExtension,
            manifest: installedExtension.manifest
        )
        grantRequestedMatchPatterns(
            to: extensionContext,
            webExtension: extensionContext.webExtension
        )
        if let currentTab {
            let hasActionPageAccess = await prepareActionClickPageAccess(
                for: extensionContext,
                installedExtension: installedExtension,
                tab: currentTab
            )
            guard hasActionPageAccess else {
                return .blocked(
                    .currentPagePermissionMissing,
                    message: "\(installedExtension.name) was not granted access to the current page."
                )
            }
        }

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

        extensionRuntimeTrace(
            "urlHubAction performAction extensionId=\(extensionId) actionLabel=\(action.label) actionEnabled=\(action.isEnabled) presentsPopup=\(action.presentsPopup)"
        )
        extensionContext.performAction(for: adapter)
        recordRuntimeMetric(for: extensionId) { metrics in
            metrics.lastBackgroundWakeReason = .actionPopup
            metrics.backgroundWakeCount += 1
        }
        return action.presentsPopup ? .openedPopup : .performedAction
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
        if ExtensionUtils.isExtensionOwnedURL(url) {
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

    private func prepareActionClickPageAccess(
        for extensionContext: WKWebExtensionContext,
        installedExtension: InstalledExtension,
        tab: Tab
    ) async -> Bool {
        let currentURL = tab.url
        guard ["http", "https"].contains(currentURL.scheme?.lowercased() ?? "") else {
            return true
        }

        let adapter = stableAdapter(for: tab)
        let manifest = installedExtension.manifest
        let permissions = stringArray(from: manifest["permissions"])
        let optionalPermissions = stringArray(from: manifest["optional_permissions"])
        if (permissions + optionalPermissions).contains("activeTab") {
            grantActiveTabURLAccess(
                for: extensionContext,
                tab: tab,
                manifest: manifest
            )
            return true
        }

        let status = effectivePermissionStatus(
            for: currentURL,
            in: extensionContext,
            tab: adapter
        )
        if isGrantedPermissionStatus(status) {
            return true
        }
        if status == .deniedExplicitly {
            return false
        }
        if explicitlyGrantURLIfCoveredByGrantedMatchPattern(
            currentURL,
            in: extensionContext,
            tab: adapter
        ) {
            return true
        }

        let decisionProfileId = tab.profileId ?? resolvedProfileId(for: tab) ?? currentProfileId
        if let extensionId = extensionID(for: extensionContext),
           let decisionProfileId {
            switch configuredSiteAccessLevel(
                for: currentURL,
                extensionId: extensionId,
                profileId: decisionProfileId
            ) {
            case .allow:
                grantSiteAccess(
                    to: currentURL,
                    in: extensionContext,
                    extensionId: extensionId,
                    profileId: decisionProfileId,
                    persistPolicy: false
                )
                return true
            case .deny:
                denySiteAccess(
                    to: currentURL,
                    in: extensionContext,
                    extensionId: extensionId,
                    profileId: decisionProfileId,
                    persistPolicy: false
                )
                SafariExtensionAutofillFillDiagnostics.recordHostPermission(
                    granted: false,
                    extensionId: installedExtension.id,
                    reason: "actionClickSiteAccessDenied"
                )
                return false
            case .ask:
                break
            }
        }

        guard hasActionCurrentPagePermission(
            installedExtension,
            currentURL: currentURL
        ) else {
            return true
        }

        let host = currentURL.host ?? currentURL.scheme ?? "this site"
        let patternString = hostMatchPatternString(for: currentURL)
        let decision = await promptForExtensionPermissionDecision(
            extensionContext: extensionContext,
            targets: [host],
            reason: "actionClickCurrentPageAccess",
            dedupeKey: permissionPromptDedupeKey(
                extensionContext: extensionContext,
                targets: patternString.map { [$0] } ?? [host]
            )
        )

        switch decision {
        case .allow(let expirationDate):
            grantSiteAccess(
                to: currentURL,
                in: extensionContext,
                extensionId: installedExtension.id,
                profileId: decisionProfileId,
                expirationDate: expirationDate
            )
            if let patternString, let decisionProfileId {
                persistExtensionPermissionDecision(
                    extensionId: installedExtension.id,
                    profileId: decisionProfileId,
                    targetKind: .matchPattern,
                    target: patternString,
                    state: .allowed,
                    expiresAt: expirationDate
                )
            }
            SafariExtensionAutofillFillDiagnostics.recordHostPermission(
                granted: true,
                extensionId: installedExtension.id,
                reason: "actionClickPromptAllowed"
            )
            return true
        case .deny:
            denySiteAccess(
                to: currentURL,
                in: extensionContext,
                extensionId: installedExtension.id,
                profileId: decisionProfileId
            )
            if let patternString, let decisionProfileId {
                persistExtensionPermissionDecision(
                    extensionId: installedExtension.id,
                    profileId: decisionProfileId,
                    targetKind: .matchPattern,
                    target: patternString,
                    state: .denied,
                    expiresAt: nil
                )
            }
            SafariExtensionAutofillFillDiagnostics.recordHostPermission(
                granted: false,
                extensionId: installedExtension.id,
                reason: "actionClickPromptDenied"
            )
            return false
        }
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
        let resolvedProfileId = resolvedProfileId(explicitProfileId: profileId)
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
        traceNativeMessagingContextBinding(
            phase: "prepareWebViewConfiguration",
            extensionId: nil,
            profileId: resolvedProfileId,
            controller: requestedController,
            configuration: configuration
        )
        configuration.websiteDataStore = getExtensionDataStore(for: resolvedProfileId)
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        installPermissionsOriginsCompatibilityPreludes(
            into: configuration.userContentController,
            profileId: resolvedProfileId
        )
    }

    func setActionAnchor(for extensionId: String, anchorView: NSView) {
        actionAnchorStore.setAnchor(for: extensionId, anchorView: anchorView)
    }

    func clearActionAnchors(for extensionId: String) {
        actionAnchorStore.clearAnchors(for: extensionId)
    }

    func closeOptionsWindow(for extensionId: String) {
        ExtensionOptionsWindowPresenter.closeWindow(for: extensionId, manager: self)
    }

    func closeAllOptionsWindows() {
        ExtensionOptionsWindowPresenter.closeAllWindows(manager: self)
    }

    func cleanupOptionsWindow(
        for extensionId: String,
        window: NSWindow? = nil,
        webView: WKWebView? = nil,
        shouldOrderOut: Bool
    ) {
        ExtensionOptionsWindowPresenter.cleanupWindow(
            for: extensionId,
            manager: self,
            window: window,
            webView: webView,
            shouldOrderOut: shouldOrderOut
        )
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
           webViewNeedsExtensionRuntimeRebuild(webView, for: owningTab),
           let coordinator = browserManager?.webViewCoordinator {
            SafariExtensionPermissionLifecycleDiagnostics.logReloadRebuild(
                SafariExtensionReloadRebuildSnapshot(
                    triggerReason: reason,
                    profileBucket: SafariExtensionPermissionLifecycleDiagnostics.bucket(
                        resolvedProfileId(for: owningTab)
                    ),
                    tabBucket: SafariExtensionPermissionLifecycleDiagnostics.bucket(owningTab.id),
                    host: SafariExtensionPermissionLifecycleDiagnostics.host(from: owningTab.url),
                    userActionCaused: false,
                    action: .destructiveRebuild
                )
            )
            coordinator.rebuildLiveWebViews(for: owningTab)
            owningTab.extensionPageRuntimeOwner.clearOpenNotificationGeneration()
            registerTabWithExtensionRuntime(
                owningTab,
                reason: "prepareWebViewForExtensionRuntime.rebuild"
            )
        }

        extensionRuntimeTrace(
            "prepareWebView reason=\(reason) webView=\(extensionRuntimeWebViewDescription(webView)) configuration=\(extensionRuntimeConfigurationDescription(webView.configuration)) userContentController=\(extensionRuntimeUserContentControllerDescription(webView.configuration.userContentController)) currentURL=\(currentURL?.absoluteString ?? "nil") existingController=\(extensionRuntimeControllerDescription(existingController)) extensionController=\(extensionRuntimeControllerDescription(extensionController)) willAssign=\(didAttach)"
        )
        traceNativeMessagingContextBinding(
            phase: "prepareWebView",
            extensionId: nil,
            profileId: owningTab.flatMap { resolvedProfileId(for: $0) },
            controller: webView.configuration.webExtensionController,
            configuration: webView.configuration,
            webView: webView
        )

        webView.configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        if let owningTab,
           let profileId = resolvedProfileId(for: owningTab) {
            installPermissionsOriginsCompatibilityPreludes(
                into: webView.configuration.userContentController,
                profileId: profileId
            )
        }
    }

    func openExtensionWindowUsingTabURLs(
        _ configuration: WKWebExtension.WindowConfiguration,
        controller: WKWebExtensionController,
        extensionContext: WKWebExtensionContext? = nil,
        createWindow: @escaping @MainActor () -> Void,
        awaitWindowRegistration: @escaping @MainActor (Set<UUID>) async -> BrowserWindowState?,
        completionHandler: @escaping ((any WKWebExtensionWindow)?, (any Error)?) -> Void
    ) {
        openExtensionWindowUsingTabURLs(
            configuration.tabURLs,
            controller: controller,
            extensionContext: extensionContext,
            createWindow: createWindow,
            awaitWindowRegistration: awaitWindowRegistration,
            completionHandler: completionHandler
        )
    }

    func openExtensionWindowUsingTabURLs(
        _ tabURLs: [URL],
        controller: WKWebExtensionController,
        extensionContext: WKWebExtensionContext? = nil,
        createWindow: @escaping @MainActor () -> Void,
        awaitWindowRegistration: @escaping @MainActor (Set<UUID>) async -> BrowserWindowState?,
        completionHandler: @escaping ((any WKWebExtensionWindow)?, (any Error)?) -> Void
    ) {
        guard let browserContext = browserBridgeContext else {
            completionHandler(
                nil,
                ExtensionManagerCallbackError.browserManagerUnavailable.nsError()
            )
            return
        }

        if let extensionContext,
           let firstURL = tabURLs.first,
           Self.isExtensionExternalWebPopupURL(firstURL),
           let contextProfileId = profileId(for: extensionContext),
           let activeWindow = browserContext.activeExtensionWindowState,
           windowMatchesProfile(activeWindow, profileId: contextProfileId) {
            Task { @MainActor [weak self] in
                guard let self, let browserContext = self.browserBridgeContext else {
                    completionHandler(
                        nil,
                        ExtensionManagerCallbackError.browserManagerUnavailable.nsError()
                    )
                    return
                }
                let targetSpace = browserContext.extensionTargetSpace(for: activeWindow)

                let resolvedExtensionLoad = self.extensionLoadURL(
                    for: firstURL,
                    controller: controller
                )
                await self.prepareContentScriptContextsForExtensionRequestedInitialLoad(
                    loadURL: resolvedExtensionLoad.url,
                    webExtensionContextOverride: resolvedExtensionLoad.context,
                    targetWindow: activeWindow,
                    targetSpace: targetSpace,
                    controller: controller
                )
                do {
                    _ = try self.openExtensionRequestedTab(
                        url: firstURL,
                        shouldBeActive: true,
                        shouldBePinned: false,
                        requestedWindow: self.windowAdapter(for: activeWindow.id),
                        controller: controller,
                        extensionContext: extensionContext,
                        reason: "webExtensionController.openNewWindowUsing.externalNormalTab"
                    )
                    completionHandler(self.windowAdapter(for: activeWindow.id), nil)
                } catch {
                    completionHandler(
                        nil,
                        ExtensionManagerCallbackError.extensionExternalTabUnavailable.nsError()
                    )
                }
            }
            return
        }

        let existingWindowIDs = Set(browserContext.allExtensionWindowStates.map(\.id))
        createWindow()

        Task { @MainActor [weak self] in
            guard let self, let browserContext = self.browserBridgeContext else {
                completionHandler(
                    nil,
                    ExtensionManagerCallbackError.browserManagerUnavailable.nsError()
                )
                return
            }

            guard let windowState = await awaitWindowRegistration(existingWindowIDs) else {
                completionHandler(
                    nil,
                    ExtensionManagerCallbackError.newWindowUnavailable.nsError()
                )
                return
            }

            let contextProfileId = extensionContext.flatMap { self.profileId(for: $0) }
            if let contextProfileId {
                windowState.currentProfileId = contextProfileId
                if let targetSpace = browserContext.extensionTargetSpace(for: windowState),
                   targetSpace.profileId == contextProfileId {
                    windowState.currentSpaceId = targetSpace.id
                } else {
                    completionHandler(
                        nil,
                        ExtensionManagerCallbackError.newWindowUnavailable.nsError()
                    )
                    return
                }
            }

            let targetSpace = browserContext.extensionTargetSpace(for: windowState)

            let createdTab: Tab
            if let firstURL = tabURLs.first {
                let resolvedExtensionLoad = self.extensionLoadURL(
                    for: firstURL,
                    controller: controller
                )
                await self.prepareContentScriptContextsForExtensionRequestedInitialLoad(
                    loadURL: resolvedExtensionLoad.url,
                    webExtensionContextOverride: resolvedExtensionLoad.context,
                    targetWindow: windowState,
                    targetSpace: targetSpace,
                    controller: controller
                )
                createdTab = browserContext.createExtensionTab(
                    url: resolvedExtensionLoad.url ?? firstURL,
                    in: targetSpace,
                    activate: false,
                    webExtensionContextOverride: resolvedExtensionLoad.context
                )
            } else {
                createdTab = browserContext.createExtensionTab(
                    url: nil,
                    in: targetSpace,
                    activate: false,
                    webExtensionContextOverride: nil
                )
            }

            self.materializeExtensionRequestedNormalTabIfNeeded(
                createdTab,
                isActive: true,
                targetWindow: windowState
            )
            browserContext.selectExtensionTab(createdTab, in: windowState)
            self.registerExtensionCreatedTabWithExtensionRuntime(
                createdTab,
                reason: "webExtensionController.openNewWindowUsing"
            )
            completionHandler(self.windowAdapter(for: windowState.id), nil)
        }
    }

    private nonisolated static func isExtensionExternalWebPopupURL(_ url: URL?) -> Bool {
        ExtensionActionPopupPresentationOwner.isExtensionExternalWebPopupURL(url)
    }

    func presentOptionsPageWindow(
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        ExtensionOptionsWindowPresenter.presentOptionsPageWindow(
            for: extensionContext,
            manager: self,
            completionHandler: completionHandler
        )
    }

}
