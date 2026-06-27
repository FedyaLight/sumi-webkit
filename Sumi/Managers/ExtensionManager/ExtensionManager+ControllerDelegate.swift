import AppKit
import Foundation
import SwiftUI
import WebKit

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager: WKWebExtensionControllerDelegate {
    func consumeRecentlyOpenedExtensionTabRequest(for url: URL) -> Bool {
        requestedTabLifecycleOwner.consumeRecentlyOpenedTabRequest(for: url)
    }

    func recordRecentlyOpenedExtensionTabRequest(for url: URL?) {
        requestedTabLifecycleOwner.recordRecentlyOpenedTabRequest(for: url)
    }

    private func extensionDisplayName(for extensionContext: WKWebExtensionContext) -> String {
        extensionContext.webExtension.displayName
            ?? extensionContext.webExtension.displayShortName
            ?? "This extension"
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

    private nonisolated static func summarizedPermissionTargets(
        _ targets: [String]
    ) -> [String] {
        let uniqueTargets = Array(Set(targets)).sorted()
        guard uniqueTargets.count > 4 else { return uniqueTargets }
        return Array(uniqueTargets.prefix(4)) + ["and \(uniqueTargets.count - 4) more"]
    }

    func promptForExtensionPermissionDecision(
        extensionContext: WKWebExtensionContext,
        targets: [String],
        reason: String,
        dedupeKey: String? = nil
    ) async -> ExtensionPermissionPromptDecision {
        #if DEBUG
            if let permissionPromptDecision = testHooks.permissionPromptDecision {
                return permissionPromptDecision(extensionContext, targets, reason)
            }
        #endif

        return await enqueueExtensionPermissionPrompt(
            key: dedupeKey ?? permissionPromptDedupeKey(
                extensionContext: extensionContext,
                targets: targets
            )
        ) {
            self.presentExtensionPermissionPrompt(
                extensionContext: extensionContext,
                targets: targets,
                reason: reason
            )
        }
    }

    private func enqueueExtensionPermissionPrompt(
        key: String,
        _ operation: @escaping @MainActor () -> ExtensionPermissionPromptDecision
    ) async -> ExtensionPermissionPromptDecision {
        await withCheckedContinuation { continuation in
            if extensionPermissionPromptWaitersByKey[key] != nil {
                extensionPermissionPromptWaitersByKey[key]?.append(continuation)
                return
            }
            extensionPermissionPromptWaitersByKey[key] = [continuation]
            extensionPermissionPromptQueue.append {
                let decision = operation()
                let waiters = self.extensionPermissionPromptWaitersByKey
                    .removeValue(forKey: key) ?? []
                for waiter in waiters {
                    waiter.resume(returning: decision)
                }
            }
            drainExtensionPermissionPromptQueueIfNeeded()
        }
    }

    private func drainExtensionPermissionPromptQueueIfNeeded() {
        guard isPresentingExtensionPermissionPrompt == false else { return }
        guard extensionPermissionPromptQueue.isEmpty == false else { return }

        isPresentingExtensionPermissionPrompt = true
        let operation = extensionPermissionPromptQueue.removeFirst()
        Task { @MainActor [weak self] in
            operation()
            guard let self else { return }
            self.isPresentingExtensionPermissionPrompt = false
            self.drainExtensionPermissionPromptQueueIfNeeded()
        }
    }

    private func presentExtensionPermissionPrompt(
        extensionContext: WKWebExtensionContext,
        targets: [String],
        reason: String
    ) -> ExtensionPermissionPromptDecision {
        let summarizedTargets = Self.summarizedPermissionTargets(targets)
        let targetSummary = summarizedTargets.joined(separator: ", ")
        let extensionName = extensionDisplayName(for: extensionContext)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText =
            "Extension \"\(extensionName)\" requests permission to access \(targetSummary)."
        alert.informativeText =
            "This extension can read and alter webpages on the requested site."
        alert.addButton(withTitle: "Allow for 1 Day")
        alert.addButton(withTitle: "Always Allow")
        alert.addButton(withTitle: "Deny")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        let decision: ExtensionPermissionPromptDecision
        switch response {
        case .alertFirstButtonReturn:
            decision = .allow(expirationDate: Date(timeIntervalSinceNow: 24 * 60 * 60))
        case .alertSecondButtonReturn:
            decision = .allow(expirationDate: nil)
        default:
            decision = .deny
        }

        RuntimeDiagnostics.debug(category: "SafariExtensionPermissions") {
            let granted: Bool
            let expiration: String
            switch decision {
            case .allow(let expirationDate):
                granted = true
                expiration = expirationDate == nil ? "never" : "temporary"
            case .deny:
                granted = false
                expiration = "nil"
            }
            return """
            prompt result reason=\(reason) ext=\(self.extensionID(for: extensionContext) ?? "unknown") \
            targetCount=\(targets.count) granted=\(granted) expiration=\(expiration)
            """
        }

        return decision
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
        guard let browserManager else { return nil }
        let auxiliaryWindowManager = browserManager.auxiliaryWindowManager
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
           let session = auxiliaryWindowManager.session(for: keyWindow),
           let miniWindowAdapter = session.miniWindowAdapter,
           ownerMiniWindowAdapters.contains(where: { $0.sessionId == miniWindowAdapter.sessionId })
        {
            auxiliaryWindowManager.recordAuxiliarySessionFocus(session.id)
            return miniWindowAdapter
        }

        if let miniWindowAdapter = ownerMiniWindowAdapters.first {
            auxiliaryWindowManager.recordAuxiliarySessionFocus(miniWindowAdapter.sessionId)
            return miniWindowAdapter
        }

        if let keyWindow = NSApp.keyWindow,
           let mainWindowState = browserManager.windowRegistry?.windows.values.first(where: {
               $0.window === keyWindow
           }),
           contextProfileId.map({ windowMatchesProfile(mainWindowState, profileId: $0) }) ?? true
        {
            return windowAdapter(for: mainWindowState.id)
        }

        if let activeWindow = browserManager.windowRegistry?.activeWindow,
           contextProfileId.map({ windowMatchesProfile(activeWindow, profileId: $0) }) ?? true
        {
            return windowAdapter(for: activeWindow.id)
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

        let ownerMiniWindowAdapters: [ExtensionMiniWindowAdapter] = {
            guard let ownerExtensionId = extensionID(for: extensionContext) else { return [] }
            return extensionMiniWindowAdapters(
                ownerExtensionID: ownerExtensionId,
                profileId: contextProfileId
            )
        }()

        var openWindows: [any WKWebExtensionWindow] = ownerMiniWindowAdapters
        openWindows += browserManager.windowRegistry?.windows.compactMap { windowId, windowState -> (any WKWebExtensionWindow)? in
            guard windowMatchesProfile(windowState, profileId: contextProfileId) else {
                return nil
            }
            return windowAdapter(for: windowId)
        } ?? []

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
        guard let browserManager else { return [] }

        let auxiliaryWindowManager = browserManager.auxiliaryWindowManager
        var adapters = miniWindowAdapters.values.compactMap { adapter -> ExtensionMiniWindowAdapter? in
            guard let session = auxiliaryWindowManager.session(for: adapter.sessionId),
                  session.ownerExtensionID == ownerExtensionID,
                  session.window.isVisible,
                  let sessionAdapter = session.miniWindowAdapter,
                  let tab = browserManager.tabManager.tab(for: sessionAdapter.tabId)
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

        if let focused = auxiliaryWindowManager.focusedMiniWindowAdapter(
            forOwnerExtensionID: ownerExtensionID
        ),
           let focusedIndex = adapters.firstIndex(where: { $0.sessionId == focused.sessionId })
        {
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
        if let activeTab = browserManager?.currentTabForActiveWindow() {
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
        var storedResolvedPermissions = Set<WKWebExtension.Permission>()
        for permission in unresolvedPermissions {
            guard let extensionId, let profileId,
                  let stored = storedExtensionPermissionDecision(
                      extensionId: extensionId,
                      profileId: profileId,
                      targetKind: .permission,
                      target: permission.rawValue
                  )
            else { continue }
            let status: WKWebExtensionContext.PermissionStatus =
                stored.state == .allowed ? .grantedExplicitly : .deniedExplicitly
            extensionContext.setPermissionStatus(
                status,
                for: permission,
                expirationDate: stored.expiresAt
            )
            storedResolvedPermissions.insert(permission)
        }

        let promptPermissions = unresolvedPermissions.subtracting(storedResolvedPermissions)

        guard promptPermissions.isEmpty == false else {
            let grantedPermissions = permissions.filter {
                isGrantedPermissionStatus(
                    effectivePermissionStatus(for: $0, in: extensionContext, tab: tab)
                )
            }
            completionHandler(grantedPermissions, nil)
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
                let grantedPermissions = permissions.filter {
                    self.isGrantedPermissionStatus(
                        self.effectivePermissionStatus(for: $0, in: extensionContext, tab: tab)
                    )
                }
                completionHandler(grantedPermissions, expirationDate)
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
                let grantedPermissions = permissions.filter {
                    self.isGrantedPermissionStatus(
                        self.effectivePermissionStatus(for: $0, in: extensionContext, tab: tab)
                    )
                }
                completionHandler(grantedPermissions, nil)
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
        var policyResolvedMatches = Set<WKWebExtension.MatchPattern>()
        for matchPattern in unresolvedMatches {
            guard let extensionId, let profileId else { continue }
            switch configuredSiteAccessLevel(
                for: matchPattern,
                extensionId: extensionId,
                profileId: profileId
            ) {
            case .allow:
                extensionContext.setPermissionStatus(
                    .grantedExplicitly,
                    for: matchPattern
                )
                policyResolvedMatches.insert(matchPattern)
            case .deny:
                extensionContext.setPermissionStatus(
                    .deniedExplicitly,
                    for: matchPattern
                )
                policyResolvedMatches.insert(matchPattern)
            case .ask:
                break
            }
        }

        let promptMatches = unresolvedMatches
            .subtracting(policyResolvedMatches)

        guard promptMatches.isEmpty == false else {
            let grantedMatches = matchPatterns.filter {
                isGrantedPermissionStatus(
                    effectivePermissionStatus(for: $0, in: extensionContext, tab: tab)
                )
            }
            completionHandler(grantedMatches, nil)
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
                let grantedMatches = matchPatterns.filter {
                    self.isGrantedPermissionStatus(
                        self.effectivePermissionStatus(for: $0, in: extensionContext, tab: tab)
                    )
                }
                completionHandler(grantedMatches, expirationDate)
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
                let grantedMatches = matchPatterns.filter {
                    self.isGrantedPermissionStatus(
                        self.effectivePermissionStatus(for: $0, in: extensionContext, tab: tab)
                    )
                }
                completionHandler(grantedMatches, nil)
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
        var autoGranted = Set<URL>()
        var unresolved = Set<URL>()

        let extensionId = extensionID(for: extensionContext)
        let profileId = profileId(for: extensionContext)
        for url in urls {
            let status = effectivePermissionStatus(for: url, in: extensionContext, tab: tab)
            if isGrantedPermissionStatus(status) {
                autoGranted.insert(url)
                SafariExtensionAutofillFillDiagnostics.recordHostPermission(
                    granted: true,
                    extensionId: extensionId,
                    reason: "promptAlreadyGranted"
                )
            } else if status == .deniedExplicitly {
                SafariExtensionAutofillFillDiagnostics.recordHostPermission(
                    granted: false,
                    extensionId: extensionId,
                    reason: "promptAlreadyDenied"
                )
            } else if explicitlyGrantURLIfCoveredByGrantedMatchPattern(
                url,
                in: extensionContext,
                tab: tab
            ) {
                autoGranted.insert(url)
                SafariExtensionAutofillFillDiagnostics.recordHostPermission(
                    granted: true,
                    extensionId: extensionId,
                    reason: "promptMatchPattern"
                )
            } else if let extensionId,
                      let profileId,
                      ["http", "https"].contains(url.scheme?.lowercased() ?? "")
            {
                switch configuredSiteAccessLevel(
                    for: url,
                    extensionId: extensionId,
                    profileId: profileId
                ) {
                case .allow:
                    grantSiteAccess(
                        to: url,
                        in: extensionContext,
                        extensionId: extensionId,
                        profileId: profileId,
                        persistPolicy: false
                    )
                    autoGranted.insert(url)
                    SafariExtensionAutofillFillDiagnostics.recordHostPermission(
                        granted: true,
                        extensionId: extensionId,
                        reason: "promptSiteAccessAllowed"
                    )
                case .deny:
                    denySiteAccess(
                        to: url,
                        in: extensionContext,
                        extensionId: extensionId,
                        profileId: profileId,
                        persistPolicy: false
                    )
                    SafariExtensionAutofillFillDiagnostics.recordHostPermission(
                        granted: false,
                        extensionId: extensionId,
                        reason: "promptSiteAccessDenied"
                    )
                case .ask:
                    unresolved.insert(url)
                }
            } else if let patternString = hostMatchPatternString(for: url),
                      let extensionId,
                      let profileId,
                      let stored = storedExtensionPermissionDecision(
                          extensionId: extensionId,
                          profileId: profileId,
                          targetKind: .matchPattern,
                          target: patternString
                      ),
                      let matchPattern = try? WKWebExtension.MatchPattern(
                          string: patternString
                      )
            {
                let storedStatus: WKWebExtensionContext.PermissionStatus =
                    stored.state == .allowed ? .grantedExplicitly : .deniedExplicitly
                extensionContext.setPermissionStatus(
                    storedStatus,
                    for: matchPattern,
                    expirationDate: stored.expiresAt
                )
                if stored.state == .allowed,
                   explicitlyGrantURLIfCoveredByGrantedMatchPattern(
                       url,
                       in: extensionContext,
                       tab: tab
                   )
                {
                    autoGranted.insert(url)
                    SafariExtensionAutofillFillDiagnostics.recordHostPermission(
                        granted: true,
                        extensionId: extensionId,
                        reason: "promptStoredMatchPattern"
                    )
                } else {
                    SafariExtensionAutofillFillDiagnostics.recordHostPermission(
                        granted: false,
                        extensionId: extensionId,
                        reason: "promptStoredDeniedMatchPattern"
                    )
                }
            } else {
                unresolved.insert(url)
            }
        }

        guard unresolved.isEmpty == false else {
            completionHandler(autoGranted, nil)
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                completionHandler(autoGranted, nil)
                return
            }
            let promptPatterns = unresolved.compactMap {
                self.hostMatchPatternString(for: $0)
            }
            let decision = await self.promptForExtensionPermissionDecision(
                extensionContext: extensionContext,
                targets: unresolved.map(Self.extensionPermissionTarget(for:)),
                reason: "promptForPermissionToAccess",
                dedupeKey: self.permissionPromptDedupeKey(
                    extensionContext: extensionContext,
                    targets: promptPatterns.isEmpty
                        ? unresolved.map(Self.extensionPermissionTarget(for:))
                        : promptPatterns
                )
            )
            switch decision {
            case .allow(let expirationDate):
                for url in unresolved {
                    self.grantSiteAccess(
                        to: url,
                        in: extensionContext,
                        extensionId: extensionId,
                        profileId: profileId,
                        expirationDate: expirationDate
                    )
                    if let patternString = self.hostMatchPatternString(for: url),
                       let extensionId,
                       let profileId
                    {
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
                completionHandler(autoGranted.union(unresolved), expirationDate)
            case .deny:
                for url in unresolved {
                    self.denySiteAccess(
                        to: url,
                        in: extensionContext,
                        extensionId: extensionId,
                        profileId: profileId
                    )
                    if let patternString = self.hostMatchPatternString(for: url),
                       let extensionId,
                       let profileId
                    {
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
                completionHandler(autoGranted, nil)
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
                    NSError(
                        domain: "ExtensionManager",
                        code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "Extension manager is unavailable"]
                    )
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
                NSError(
                    domain: "ExtensionManager",
                    code: 7,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Sumi does not support private extension windows without an isolated private extension runtime"
                    ]
                )
            )
            return
        }

        if configuration.windowType == .popup {
            Task { @MainActor [weak self, weak browserManager] in
                guard let self, let browserManager else {
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

                let parentWindow = browserManager.windowRegistry?.activeWindow?.window
                let adapter = await browserManager.auxiliaryWindowManager.presentExtensionPopupWindow(
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
                        NSError(
                            domain: "ExtensionManager",
                            code: 6,
                            userInfo: [NSLocalizedDescriptionKey: "Sumi could not open the extension popup window"]
                        )
                    )
                }
            }
            return
        }

        openExtensionWindowUsingTabURLs(
            configuration.tabURLs,
            controller: controller,
            extensionContext: extensionContext,
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
        let extensionId = extensionID(for: extensionContext)
        let extensionsModuleEnabled =
            browserManager?.extensionsModule.isEnabled
            ?? SumiModuleRegistry.shared.isEnabled(.extensions)

        SumiNativeMessagingRuntimeCounters.recordDelegateSendMessageInvoked()
        SafariExtensionAutofillFillDiagnostics.recordNativeMessagingActivity(
            extensionId: extensionId
        )
        if extensionsModuleEnabled {
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    _ = try await self.ensureBackgroundAvailableIfRequired(
                        for: extensionContext.webExtension,
                        context: extensionContext,
                        reason: .nativeMessaging
                    )
                } catch {
                    self.logBackgroundWakeFailure(
                        error,
                        extensionContext: extensionContext,
                        reason: .nativeMessaging,
                        operation: "wake native messaging background before sendMessage"
                    )
                }
            }
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
        let extensionsModuleEnabled =
            browserManager?.extensionsModule.isEnabled
            ?? SumiModuleRegistry.shared.isEnabled(.extensions)
        if extensionsModuleEnabled {
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    _ = try await self.ensureBackgroundAvailableIfRequired(
                        for: extensionContext.webExtension,
                        context: extensionContext,
                        reason: .nativeMessaging
                    )
                } catch {
                    self.logBackgroundWakeFailure(
                        error,
                        extensionContext: extensionContext,
                        reason: .nativeMessaging,
                        operation: "wake native messaging background before connect"
                    )
                }
            }
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
                self.nativeMessagePortHandlers[portKey] = handler
                if let extensionId {
                    self.nativeMessagePortExtensionIDs[portKey] = extensionId
                }
                if let profileId {
                    self.nativeMessagePortProfileIDs[portKey] = profileId
                }
            },
            unregisterHandler: { [weak self] handler in
                guard let self else { return }
                if let current = self.nativeMessagePortHandlers[portKey],
                   current !== handler
                {
                    return
                }
                self.nativeMessagePortHandlers.removeValue(forKey: portKey)
                self.nativeMessagePortExtensionIDs.removeValue(forKey: portKey)
                self.nativeMessagePortProfileIDs.removeValue(forKey: portKey)
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
