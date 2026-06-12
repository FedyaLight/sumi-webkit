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
        if RuntimeDiagnostics.isRunningTests {
            return .allow(expirationDate: nil)
        }

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
        guard let requestedURL else {
            return (nil, nil)
        }

        let loadURL = ExtensionUtils.webKitLoadableExtensionURL(for: requestedURL)
        guard Self.isExtensionOwnedURL(loadURL) else {
            return (loadURL, nil)
        }
        return (loadURL, controller.extensionContext(for: loadURL))
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

        let resolvedExtensionLoad = extensionLoadURL(
            for: url,
            controller: controller
        )
        let webExtensionContextOverride = resolvedExtensionLoad.context
        let shouldUseTransientInternalTab = shouldOpenAsTransientInternalExtensionTab(
            loadURL: resolvedExtensionLoad.url,
            shouldBeActive: shouldBeActive,
            shouldBePinned: shouldBePinned,
            webExtensionContextOverride: webExtensionContextOverride
        )

        let newTab: Tab
        if shouldUseTransientInternalTab, let loadURL = resolvedExtensionLoad.url {
            newTab = browserManager.tabManager.createTransientExtensionTab(
                url: loadURL.absoluteString,
                in: targetSpace,
                webExtensionContextOverride: webExtensionContextOverride
            )
        } else if let loadURL = resolvedExtensionLoad.url {
            recordRecentlyOpenedExtensionTabRequest(for: url)
            newTab = browserManager.tabManager.createNewTab(
                url: loadURL.absoluteString,
                in: targetSpace,
                activate: shouldBeActive,
                webExtensionContextOverride: webExtensionContextOverride
            )
        } else {
            newTab = browserManager.tabManager.createNewTab(
                in: targetSpace,
                activate: shouldBeActive,
                webExtensionContextOverride: webExtensionContextOverride
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
        materializeExtensionOwnedTabIfNeeded(
            newTab,
            isActive: shouldBeActive,
            hasWindowSelection: targetWindow != nil
        )
        return newTab
    }

    private func shouldOpenAsTransientInternalExtensionTab(
        loadURL: URL?,
        shouldBeActive: Bool,
        shouldBePinned: Bool,
        webExtensionContextOverride: WKWebExtensionContext?
    ) -> Bool {
        guard shouldBeActive == false,
              shouldBePinned == false,
              webExtensionContextOverride != nil,
              let loadURL
        else {
            return false
        }
        return Self.isExtensionOwnedURL(loadURL)
    }

    private func materializeExtensionOwnedTabIfNeeded(
        _ tab: Tab,
        isActive: Bool,
        hasWindowSelection: Bool
    ) {
        guard tab.webExtensionContextOverride != nil else { return }
        guard ExtensionUtils.isExtensionOwnedURL(tab.url) else { return }
        guard tab.isUnloaded else { return }

        if isActive && hasWindowSelection {
            return
        }

        tab.loadWebViewIfNeeded()
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
        let manifest = extensionID(for: extensionContext)
            .flatMap { loadedExtensionManifests[$0] } ?? [:]
        let policyDeniedPermissions = permissions
            .filter { shouldDenyAutoGrantForWebKitRuntime($0, manifest: manifest) }
        for permission in policyDeniedPermissions {
            extensionContext.setPermissionStatus(.deniedExplicitly, for: permission)
        }

        let unresolvedPermissions = permissions.subtracting(policyDeniedPermissions).filter {
            isGrantedPermissionStatus(extensionContext.permissionStatus(for: $0)) == false
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
                isGrantedPermissionStatus(extensionContext.permissionStatus(for: $0))
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
                    self.isGrantedPermissionStatus(extensionContext.permissionStatus(for: $0))
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
                    self.isGrantedPermissionStatus(extensionContext.permissionStatus(for: $0))
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
            isGrantedPermissionStatus(extensionContext.permissionStatus(for: $0)) == false
        }
        let extensionId = extensionID(for: extensionContext)
        let profileId = profileId(for: extensionContext)
        var storedResolvedMatches = Set<WKWebExtension.MatchPattern>()
        for matchPattern in unresolvedMatches {
            guard let extensionId, let profileId,
                  let stored = storedExtensionPermissionDecision(
                      extensionId: extensionId,
                      profileId: profileId,
                      targetKind: .matchPattern,
                      target: matchPattern.string
                  )
            else { continue }
            let status: WKWebExtensionContext.PermissionStatus =
                stored.state == .allowed ? .grantedExplicitly : .deniedExplicitly
            extensionContext.setPermissionStatus(
                status,
                for: matchPattern,
                expirationDate: stored.expiresAt
            )
            storedResolvedMatches.insert(matchPattern)
        }

        let promptMatches = unresolvedMatches.subtracting(storedResolvedMatches)

        guard promptMatches.isEmpty == false else {
            let grantedMatches = matchPatterns.filter {
                isGrantedPermissionStatus(extensionContext.permissionStatus(for: $0))
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
                    }
                }
                let grantedMatches = matchPatterns.filter {
                    self.isGrantedPermissionStatus(extensionContext.permissionStatus(for: $0))
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
                    }
                }
                let grantedMatches = matchPatterns.filter {
                    self.isGrantedPermissionStatus(extensionContext.permissionStatus(for: $0))
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
            let status = extensionContext.permissionStatus(for: url)
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
                in: extensionContext
            ) {
                autoGranted.insert(url)
                SafariExtensionAutofillFillDiagnostics.recordHostPermission(
                    granted: true,
                    extensionId: extensionId,
                    reason: "promptMatchPattern"
                )
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
                       in: extensionContext
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
                    if let patternString = self.hostMatchPatternString(for: url),
                       let matchPattern = try? WKWebExtension.MatchPattern(
                           string: patternString
                       )
                    {
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
                                target: patternString,
                                state: .allowed,
                                expiresAt: expirationDate
                            )
                        }
                    }
                    extensionContext.setPermissionStatus(
                        .grantedExplicitly,
                        for: url,
                        expirationDate: expirationDate
                    )
                    SafariExtensionAutofillFillDiagnostics.recordHostPermission(
                        granted: true,
                        extensionId: extensionId,
                        reason: "promptAllowed"
                    )
                }
                completionHandler(autoGranted.union(unresolved), expirationDate)
            case .deny:
                for url in unresolved {
                    if let patternString = self.hostMatchPatternString(for: url),
                       let matchPattern = try? WKWebExtension.MatchPattern(
                           string: patternString
                       )
                    {
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
                                target: patternString,
                                state: .denied,
                                expiresAt: nil
                            )
                        }
                    }
                    extensionContext.setPermissionStatus(
                        .deniedExplicitly,
                        for: url,
                        expirationDate: nil
                    )
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
