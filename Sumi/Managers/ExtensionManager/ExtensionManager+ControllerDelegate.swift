import AppKit
import Foundation
import SwiftUI
import WebKit

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager: WKWebExtensionControllerDelegate {
    var extensionsModuleEnabledForDelegateCallbacks: Bool {
        browserManager?.extensionsModule.isEnabled
            ?? moduleRegistry.isEnabled(.extensions)
    }

    func consumeRecentlyOpenedExtensionTabRequest(for url: URL) -> Bool {
        requestedTabLifecycleOwner.consumeRecentlyOpenedTabRequest(for: url)
    }

    func recordRecentlyOpenedExtensionTabRequest(for url: URL?) {
        requestedTabLifecycleOwner.recordRecentlyOpenedTabRequest(for: url)
    }

    private nonisolated static func extensionPermissionTarget(for url: URL) -> String {
        if let host = url.host, host.isEmpty == false {
            return host
        }
        if let scheme = url.scheme, scheme.isEmpty == false {
            return "\(scheme):"
        }
        return "this site"
    }

    private static func extensionPermissionTarget(
        for matchPattern: WKWebExtension.MatchPattern
    ) -> String {
        if matchPattern.matchesAllURLs || matchPattern.matchesAllHosts {
            return "all websites"
        }
        if let host = matchPattern.host, host.isEmpty == false {
            return host
        }
        return matchPattern.string
    }

    func extensionLoadURL(
        for requestedURL: URL?,
        controller: WKWebExtensionController
    ) -> (url: URL?, context: WKWebExtensionContext?) {
        requestedTabLifecycleOwner.loadURL(
            for: requestedURL,
            controller: controller
        )
    }

    @discardableResult
    func prepareExtensionRequestedTabForInitialLoad(
        url: URL?,
        requestedWindow: (any WKWebExtensionWindow)?,
        controller: WKWebExtensionController,
        extensionContext: WKWebExtensionContext? = nil
    ) async throws -> UUID? {
        try await requestedTabLifecycleOwner.prepareInitialLoad(
            url: url,
            requestedWindow: requestedWindow,
            controller: controller,
            extensionContext: extensionContext,
            manager: self
        )
    }

    @discardableResult
    func prepareContentScriptContextsForExtensionRequestedInitialLoad(
        loadURL: URL?,
        webExtensionContextOverride: WKWebExtensionContext?,
        targetWindow: BrowserWindowState?,
        targetSpace: Space?,
        controller: WKWebExtensionController
    ) async -> UUID? {
        await requestedTabLifecycleOwner.prepareContentScriptContextsForInitialLoad(
            loadURL: loadURL,
            webExtensionContextOverride: webExtensionContextOverride,
            targetWindow: targetWindow,
            targetSpace: targetSpace,
            controller: controller,
            manager: self
        )
    }

    @discardableResult
    func openExtensionRequestedTab(
        url: URL?,
        shouldBeActive: Bool,
        shouldBePinned: Bool,
        requestedWindow: (any WKWebExtensionWindow)?,
        controller: WKWebExtensionController,
        extensionContext: WKWebExtensionContext? = nil,
        reason: String = #function
    ) throws -> Tab {
        try requestedTabLifecycleOwner.openTab(
            url: url,
            shouldBeActive: shouldBeActive,
            shouldBePinned: shouldBePinned,
            requestedWindow: requestedWindow,
            controller: controller,
            extensionContext: extensionContext,
            reason: reason,
            manager: self
        )
    }

    func materializeExtensionRequestedNormalTabIfNeeded(
        _ tab: Tab,
        isActive: Bool,
        targetWindow: BrowserWindowState?
    ) {
        requestedTabLifecycleOwner.materializeNormalTabIfNeeded(
            tab,
            isActive: isActive,
            targetWindow: targetWindow,
            manager: self
        )
    }

    func registerExtensionCreatedTabWithExtensionRuntime(
        _ tab: Tab,
        reason: String = #function
    ) {
        requestedTabLifecycleOwner.registerCreatedTabWithExtensionRuntime(
            tab,
            reason: reason,
            manager: self
        )
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        focusedWindowFor extensionContext: WKWebExtensionContext
    ) -> (any WKWebExtensionWindow)? {
        guard let browserContext = browserBridgeContext else { return nil }
        let contextProfileId = profileId(for: extensionContext)
        let ownerExtensionId = extensionID(for: extensionContext)
        let ownerMiniWindowAdapters: [ExtensionMiniWindowAdapter] = {
            guard let ownerExtensionId else { return [] }
            return extensionMiniWindowAdapters(
                ownerExtensionID: ownerExtensionId,
                profileId: contextProfileId
            )
        }()

        if let keyWindow = NSApp.keyWindow,
           let session = browserContext.auxiliaryWindowSession(for: keyWindow),
           let miniWindowAdapter = session.miniWindowAdapter,
           ownerMiniWindowAdapters.contains(where: { $0.sessionId == miniWindowAdapter.sessionId }) {
            browserContext.recordAuxiliaryWindowSessionFocus(session.id)
            return miniWindowAdapter
        }

        if let miniWindowAdapter = ownerMiniWindowAdapters.first {
            browserContext.recordAuxiliaryWindowSessionFocus(miniWindowAdapter.sessionId)
            return miniWindowAdapter
        }

        if let keyWindow = NSApp.keyWindow,
           let mainWindowState = browserContext.extensionWindowState(forAppKitWindow: keyWindow),
           contextProfileId.map({ windowMatchesProfile(mainWindowState, profileId: $0) }) ?? true {
            return windowAdapter(for: mainWindowState.id)
        }

        if let activeWindow = browserContext.activeExtensionWindowState,
           contextProfileId.map({ windowMatchesProfile(activeWindow, profileId: $0) }) ?? true {
            return windowAdapter(for: activeWindow.id)
        }
        return nil
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openWindowsFor extensionContext: WKWebExtensionContext
    ) -> [any WKWebExtensionWindow] {
        guard let browserContext = browserBridgeContext,
              let contextProfileId = profileId(for: extensionContext)
        else { return [] }

        let ownerMiniWindowAdapters: [ExtensionMiniWindowAdapter] = {
            guard let ownerExtensionId = extensionID(for: extensionContext) else { return [] }
            return extensionMiniWindowAdapters(
                ownerExtensionID: ownerExtensionId,
                profileId: contextProfileId
            )
        }()

        var openWindows: [any WKWebExtensionWindow] = ownerMiniWindowAdapters
        openWindows += browserContext.allExtensionWindowStates.compactMap { windowState -> (any WKWebExtensionWindow)? in
            guard windowMatchesProfile(windowState, profileId: contextProfileId) else {
                return nil
            }
            return windowAdapter(for: windowState.id)
        }

        return openWindows
    }

    func focusedOwnerMiniWindowAdapter(
        for extensionContext: WKWebExtensionContext
    ) -> ExtensionMiniWindowAdapter? {
        guard let ownerExtensionID = extensionID(for: extensionContext) else {
            return nil
        }

        let contextProfileId = profileId(for: extensionContext)
        let adapters = extensionMiniWindowAdapters(
            ownerExtensionID: ownerExtensionID,
            profileId: contextProfileId
        )
        return adapters.first
    }

    func extensionMiniWindowAdapters(
        ownerExtensionID: String,
        profileId: UUID?
    ) -> [ExtensionMiniWindowAdapter] {
        guard let browserContext = browserBridgeContext else { return [] }

        var adapters = adapterStore.miniWindowAdapters.values.compactMap { adapter -> ExtensionMiniWindowAdapter? in
            guard let session = browserContext.auxiliaryWindowSession(for: adapter.sessionId),
                  session.ownerExtensionID == ownerExtensionID,
                  session.window.isVisible,
                  let sessionAdapter = session.miniWindowAdapter,
                  let tab = browserContext.extensionTab(for: sessionAdapter.tabId)
            else {
                return nil
            }
            if let profileId, resolvedProfileId(for: tab) != profileId {
                return nil
            }
            return sessionAdapter
        }

        adapters.sort { lhs, rhs in
            lhs.sessionId.uuidString < rhs.sessionId.uuidString
        }

        if let focused = browserContext.focusedExtensionMiniWindowAdapter(
            forOwnerExtensionID: ownerExtensionID
        ),
           let focusedIndex = adapters.firstIndex(where: { $0.sessionId == focused.sessionId }) {
            adapters.insert(adapters.remove(at: focusedIndex), at: 0)
        }

        return adapters
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
        if let activeTab = browserBridgeContext?.currentExtensionTabForActiveWindow() {
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
                ExtensionManagerCallbackError.noPopupPopover.nsError()
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
                    ExtensionManagerCallbackError.extensionIdentifierUnavailable.nsError()
                )
                return
            }

            let profileId = self.profileId(for: extensionContext)
            let preferredWindowId = self.browserBridgeContext?.activeExtensionWindowState?.id
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
                    ExtensionManagerCallbackError
                        .actionPopupAnchorUnavailable(anchorSource: resolution.anchorSource?.rawValue)
                        .nsError()
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
        let manifest = extensionID(for: extensionContext)
            .flatMap { loadedExtensionManifests[$0] } ?? [:]
        let policyDeniedPermissions = permissions
            .filter { shouldDenyAutoGrantForWebKitRuntime($0, manifest: manifest) }
        for permission in policyDeniedPermissions {
            extensionContext.setPermissionStatus(.deniedExplicitly, for: permission)
        }

        let unresolvedPermissions = permissions.subtracting(policyDeniedPermissions).filter {
            isGrantedPermissionStatus(
                effectivePermissionStatus(for: $0, in: extensionContext, tab: tab)
            ) == false
        }
        let extensionId = extensionID(for: extensionContext)
        let profileId = profileId(for: extensionContext)
        let storedResolvedPermissions = ExtensionPermissionPromptRoutingOwner
            .applyStoredPermissionDecisions(
                to: unresolvedPermissions,
                in: extensionContext,
                extensionId: extensionId,
                profileId: profileId,
                manager: self
            )

        let promptPermissions = unresolvedPermissions.subtracting(storedResolvedPermissions)

        guard promptPermissions.isEmpty == false else {
            completionHandler(
                ExtensionPermissionPromptRoutingOwner.grantedPermissions(
                    from: permissions,
                    in: extensionContext,
                    tab: tab,
                    manager: self
                ),
                nil
            )
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                completionHandler([], nil)
                return
            }
            let decision = await self.promptForExtensionPermissionDecision(
                extensionContext: extensionContext,
                targets: promptPermissions.map(\.rawValue),
                reason: "promptForPermissions",
                dedupeKey: self.permissionPromptDedupeKey(
                    extensionContext: extensionContext,
                    targets: promptPermissions.map(\.rawValue)
                )
            )
            switch decision {
            case .allow(let expirationDate):
                for permission in promptPermissions {
                    extensionContext.setPermissionStatus(
                        .grantedExplicitly,
                        for: permission,
                        expirationDate: expirationDate
                    )
                    if let extensionId, let profileId {
                        self.persistExtensionPermissionDecision(
                            extensionId: extensionId,
                            profileId: profileId,
                            targetKind: .permission,
                            target: permission.rawValue,
                            state: .allowed,
                            expiresAt: expirationDate
                        )
                    }
                }
                completionHandler(
                    ExtensionPermissionPromptRoutingOwner.grantedPermissions(
                        from: permissions,
                        in: extensionContext,
                        tab: tab,
                        manager: self
                    ),
                    expirationDate
                )
            case .deny:
                for permission in promptPermissions {
                    extensionContext.setPermissionStatus(
                        .deniedExplicitly,
                        for: permission,
                        expirationDate: nil
                    )
                    if let extensionId, let profileId {
                        self.persistExtensionPermissionDecision(
                            extensionId: extensionId,
                            profileId: profileId,
                            targetKind: .permission,
                            target: permission.rawValue,
                            state: .denied,
                            expiresAt: nil
                        )
                    }
                }
                completionHandler(
                    ExtensionPermissionPromptRoutingOwner.grantedPermissions(
                        from: permissions,
                        in: extensionContext,
                        tab: tab,
                        manager: self
                    ),
                    nil
                )
            }
        }
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Set<WKWebExtension.MatchPattern>, Date?) -> Void
    ) {
        let unresolvedMatches = matchPatterns.filter {
            isGrantedPermissionStatus(
                effectivePermissionStatus(for: $0, in: extensionContext, tab: tab)
            ) == false
        }
        let extensionId = extensionID(for: extensionContext)
        let profileId = profileId(for: extensionContext)
        let policyResolvedMatches = ExtensionPermissionPromptRoutingOwner
            .applyConfiguredSiteAccessDecisions(
                to: unresolvedMatches,
                in: extensionContext,
                extensionId: extensionId,
                profileId: profileId,
                manager: self
            )

        let promptMatches = unresolvedMatches
            .subtracting(policyResolvedMatches)

        guard promptMatches.isEmpty == false else {
            completionHandler(
                ExtensionPermissionPromptRoutingOwner.grantedMatchPatterns(
                    from: matchPatterns,
                    in: extensionContext,
                    tab: tab,
                    manager: self
                ),
                nil
            )
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                completionHandler([], nil)
                return
            }
            let decision = await self.promptForExtensionPermissionDecision(
                extensionContext: extensionContext,
                targets: promptMatches.map(Self.extensionPermissionTarget(for:)),
                reason: "promptForPermissionMatchPatterns",
                dedupeKey: self.permissionPromptDedupeKey(
                    extensionContext: extensionContext,
                    targets: promptMatches.map(\.string)
                )
            )
            switch decision {
            case .allow(let expirationDate):
                for matchPattern in promptMatches {
                    extensionContext.setPermissionStatus(
                        .grantedExplicitly,
                        for: matchPattern,
                        expirationDate: expirationDate
                    )
                    if let extensionId, let profileId {
                        self.persistExtensionPermissionDecision(
                            extensionId: extensionId,
                            profileId: profileId,
                            targetKind: .matchPattern,
                            target: matchPattern.string,
                            state: .allowed,
                            expiresAt: expirationDate
                        )
                        self.setConfiguredSiteAccess(
                            .allow,
                            extensionId: extensionId,
                            profileId: profileId,
                            matchPatternString: matchPattern.string,
                            expiresAt: expirationDate
                        )
                    }
                }
                completionHandler(
                    ExtensionPermissionPromptRoutingOwner.grantedMatchPatterns(
                        from: matchPatterns,
                        in: extensionContext,
                        tab: tab,
                        manager: self
                    ),
                    expirationDate
                )
            case .deny:
                for matchPattern in promptMatches {
                    extensionContext.setPermissionStatus(
                        .deniedExplicitly,
                        for: matchPattern,
                        expirationDate: nil
                    )
                    if let extensionId, let profileId {
                        self.persistExtensionPermissionDecision(
                            extensionId: extensionId,
                            profileId: profileId,
                            targetKind: .matchPattern,
                            target: matchPattern.string,
                            state: .denied,
                            expiresAt: nil
                        )
                        self.setConfiguredSiteAccess(
                            .deny,
                            extensionId: extensionId,
                            profileId: profileId,
                            matchPatternString: matchPattern.string
                        )
                    }
                }
                completionHandler(
                    ExtensionPermissionPromptRoutingOwner.grantedMatchPatterns(
                        from: matchPatterns,
                        in: extensionContext,
                        tab: tab,
                        manager: self
                    ),
                    nil
                )
            }
        }
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissionToAccess urls: Set<URL>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Set<URL>, Date?) -> Void
    ) {
        let extensionId = extensionID(for: extensionContext)
        let profileId = profileId(for: extensionContext)
        let resolution = ExtensionPermissionPromptRoutingOwner.resolveURLPermissionsBeforePrompt(
            urls: urls,
            in: extensionContext,
            tab: tab,
            extensionId: extensionId,
            profileId: profileId,
            manager: self
        )

        guard resolution.unresolved.isEmpty == false else {
            completionHandler(resolution.autoGranted, nil)
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                completionHandler(resolution.autoGranted, nil)
                return
            }
            let promptPatterns = resolution.unresolved.compactMap {
                self.hostMatchPatternString(for: $0)
            }
            let decision = await self.promptForExtensionPermissionDecision(
                extensionContext: extensionContext,
                targets: resolution.unresolved.map(Self.extensionPermissionTarget(for:)),
                reason: "promptForPermissionToAccess",
                dedupeKey: self.permissionPromptDedupeKey(
                    extensionContext: extensionContext,
                    targets: promptPatterns.isEmpty
                        ? resolution.unresolved.map(Self.extensionPermissionTarget(for:))
                        : promptPatterns
                )
            )
            switch decision {
            case .allow(let expirationDate):
                for url in resolution.unresolved {
                    self.grantSiteAccess(
                        to: url,
                        in: extensionContext,
                        extensionId: extensionId,
                        profileId: profileId,
                        expirationDate: expirationDate
                    )
                    if let patternString = self.hostMatchPatternString(for: url),
                       let extensionId,
                       let profileId {
                        self.persistExtensionPermissionDecision(
                            extensionId: extensionId,
                            profileId: profileId,
                            targetKind: .matchPattern,
                            target: patternString,
                            state: .allowed,
                            expiresAt: expirationDate
                        )
                    }
                    SafariExtensionAutofillFillDiagnostics.recordHostPermission(
                        granted: true,
                        extensionId: extensionId,
                        reason: "promptAllowed"
                    )
                }
                completionHandler(
                    resolution.autoGranted.union(resolution.unresolved),
                    expirationDate
                )
            case .deny:
                for url in resolution.unresolved {
                    self.denySiteAccess(
                        to: url,
                        in: extensionContext,
                        extensionId: extensionId,
                        profileId: profileId
                    )
                    if let patternString = self.hostMatchPatternString(for: url),
                       let extensionId,
                       let profileId {
                        self.persistExtensionPermissionDecision(
                            extensionId: extensionId,
                            profileId: profileId,
                            targetKind: .matchPattern,
                            target: patternString,
                            state: .denied,
                            expiresAt: nil
                        )
                    }
                    SafariExtensionAutofillFillDiagnostics.recordHostPermission(
                        granted: false,
                        extensionId: extensionId,
                        reason: "promptDenied"
                    )
                }
                completionHandler(resolution.autoGranted, nil)
            }
        }
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewTabUsing configuration: WKWebExtension.TabConfiguration,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any WKWebExtensionTab)?, (any Error)?) -> Void
    ) {
        Task { @MainActor [weak self] in
            guard let self else {
                completionHandler(
                    nil,
                    ExtensionManagerCallbackError.extensionManagerUnavailable.nsError()
                )
                return
            }

            do {
                try await self.prepareExtensionRequestedTabForInitialLoad(
                    url: configuration.url,
                    requestedWindow: configuration.window,
                    controller: controller,
                    extensionContext: extensionContext
                )
                let newTab = try self.openExtensionRequestedTab(
                    url: configuration.url,
                    shouldBeActive: configuration.shouldBeActive,
                    shouldBePinned: configuration.shouldBePinned,
                    requestedWindow: configuration.window,
                    controller: controller,
                    extensionContext: extensionContext,
                    reason: "webExtensionController.openNewTabUsing"
                )
                completionHandler(self.stableAdapter(for: newTab), nil)
            } catch {
                completionHandler(
                    nil,
                    SumiWebExtensionCallbackErrorMapper.webExtensionCallbackError(from: error)
                )
            }
        }
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewWindowUsing configuration: WKWebExtension.WindowConfiguration,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any WKWebExtensionWindow)?, (any Error)?) -> Void
    ) {
        guard configuration.shouldBePrivate == false else {
            completionHandler(
                nil,
                ExtensionManagerCallbackError.privateWindowsUnsupported.nsError()
            )
            return
        }

        if configuration.windowType == .popup {
            Task { @MainActor [weak self] in
                guard let self, let browserContext = self.browserBridgeContext else {
                    completionHandler(
                        nil,
                        ExtensionManagerCallbackError.browserManagerUnavailable.nsError()
                    )
                    return
                }

                let parentWindow = browserContext.activeExtensionWindowState?.window
                let adapter = await browserContext.presentExtensionPopupWindow(
                    configuration: configuration,
                    controller: controller,
                    extensionContext: extensionContext,
                    extensionManager: self,
                    parentWindow: parentWindow
                )

                if let adapter {
                    completionHandler(adapter, nil)
                } else {
                    completionHandler(
                        nil,
                        ExtensionManagerCallbackError.extensionPopupWindowUnavailable.nsError()
                    )
                }
            }
            return
        }

        openExtensionWindowUsingTabURLs(
            configuration.tabURLs,
            controller: controller,
            extensionContext: extensionContext,
            createWindow: { [weak self] in
                self?.browserBridgeContext?.createExtensionWindow()
            },
            awaitWindowRegistration: { [weak self] existingWindowIDs in
                await self?.browserBridgeContext?.awaitNextExtensionWindow(
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
        let extensionId = extensionID(for: extensionContext)
        let extensionsModuleEnabled = extensionsModuleEnabledForDelegateCallbacks

        SumiNativeMessagingRuntimeCounters.recordDelegateSendMessageInvoked()
        SafariExtensionAutofillFillDiagnostics.recordNativeMessagingActivity(
            extensionId: extensionId
        )
        if extensionsModuleEnabled {
            scheduleNativeMessagingBackgroundWake(
                for: extensionContext,
                operation: "wake native messaging background before sendMessage"
            )
        }
        let profileId = profileId(for: extensionContext)
        let isPrivateBrowsing = isPrivateExtensionRuntimeProfile(profileId)
        let extensionDisplayName = ExtensionUtils.displayName(
            forExtensionID: extensionId,
            installedExtensions: installedExtensions
        )
        traceNativeMessagingContextBinding(
            phase: "delegateSendMessage",
            extensionId: extensionId,
            profileId: profileId,
            loadSource: nativeMessagingLoadSource(for: extensionId),
            webExtension: extensionContext.webExtension,
            extensionContext: extensionContext,
            controller: controller,
            configuration: extensionContext.webViewConfiguration
        )
        let messageShape = SafariExtensionNativeMessagingRoutingProbe
            .sanitizedMessageShape(for: message)
        #if DEBUG || SUMI_DIAGNOSTICS
            if RuntimeDiagnostics.isVerboseEnabled {
                RuntimeDiagnostics.debug(category: "SafariNativeMessagingRouting") {
                    """
                    WKWebExtensionControllerDelegate.sendMessage \
                    extBucket=\(SafariExtensionNativeMessagingRoutingProbe.extensionIdBucket(extensionId)) \
                    extLabel=\(SafariExtensionNativeMessagingRoutingProbe.sanitizedExtensionLabel(extensionDisplayName)) \
                    profile=\(SafariExtensionNativeMessagingRoutingProbe.profileIdBucket(profileId)) \
                    appId=\(applicationIdentifier ?? "(nil)") \
                    messageShape=\(messageShape.container) \
                    messageKeys=\(messageShape.keysForLog) \
                    messageTypeKeys=\(messageShape.typeKeysForLog)
                    """
                }
            }
        #endif
        nativeMessagingRelay.handleSendMessage(
            applicationIdentifier: applicationIdentifier,
            message: message,
            extensionId: extensionId,
            profileId: profileId,
            isPrivateBrowsing: isPrivateBrowsing,
            privateAccessAllowed: extensionContext.hasAccessToPrivateData,
            installedExtensions: installedExtensions,
            extensionDisplayName: extensionDisplayName,
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
        let extensionsModuleEnabled = extensionsModuleEnabledForDelegateCallbacks
        if extensionsModuleEnabled {
            scheduleNativeMessagingBackgroundWake(
                for: extensionContext,
                operation: "wake native messaging background before connect"
            )
        }

        let profileId = profileId(for: extensionContext)
        let isPrivateBrowsing = isPrivateExtensionRuntimeProfile(profileId)
        let extensionDisplayName = ExtensionUtils.displayName(
            forExtensionID: extensionId,
            installedExtensions: installedExtensions
        )
        traceNativeMessagingContextBinding(
            phase: "delegateConnectNative",
            extensionId: extensionId,
            profileId: profileId,
            loadSource: nativeMessagingLoadSource(for: extensionId),
            webExtension: extensionContext.webExtension,
            extensionContext: extensionContext,
            controller: controller,
            configuration: extensionContext.webViewConfiguration
        )
        #if DEBUG || SUMI_DIAGNOSTICS
            if RuntimeDiagnostics.isVerboseEnabled {
                RuntimeDiagnostics.debug(category: "SafariNativeMessagingRouting") {
                    """
                    WKWebExtensionControllerDelegate.connectUsing \
                    extBucket=\(SafariExtensionNativeMessagingRoutingProbe.extensionIdBucket(extensionId)) \
                    extLabel=\(SafariExtensionNativeMessagingRoutingProbe.sanitizedExtensionLabel(extensionDisplayName)) \
                    profile=\(SafariExtensionNativeMessagingRoutingProbe.profileIdBucket(profileId)) \
                    appId=\(port.applicationIdentifier ?? "(nil)")
                    """
                }
            }
        #endif

        let portKey = ObjectIdentifier(port)
        _ = nativeMessagingRelay.handleConnect(
            port: port,
            extensionId: extensionId,
            profileId: profileId,
            isPrivateBrowsing: isPrivateBrowsing,
            privateAccessAllowed: extensionContext.hasAccessToPrivateData,
            installedExtensions: installedExtensions,
            registerHandler: { [weak self] handler in
                guard let self else { return }
                self.nativeMessagingPortRegistry.register(
                    handler: handler,
                    portKey: portKey,
                    extensionId: extensionId,
                    profileId: profileId
                )
            },
            unregisterHandler: { [weak self] handler in
                guard let self else { return }
                self.nativeMessagingPortRegistry.unregister(
                    handler: handler,
                    portKey: portKey
                )
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
