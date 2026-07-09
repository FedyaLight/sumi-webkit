//
//  ExtensionActionPopupSessionOwner.swift
//  Sumi
//
//  Owns the active extension action popup session: presenting the
//  WebKit-delivered popover, tracking the active popup identity and UI
//  delegates, and performing close-time and deferred context unload.
//

import AppKit
import WebKit
import SumiWebRuntime

@available(macOS 15.5, *)
@MainActor
final class ExtensionActionPopupSessionOwner: NSObject, NSPopoverDelegate {
    private weak var manager: ExtensionManager?

    private(set) var activeIdentity: ExtensionActionPopupIdentity?
    private var popupUIDelegates: [String: ExtensionActionPopupUIDelegate] = [:]
    private var deferredContextUnloadTasks:
        [ExtensionActionPopupIdentity: Task<Void, Never>] = [:]

    init(manager: ExtensionManager) {
        self.manager = manager
        super.init()
    }

    // MARK: - Presentation

    func presentActionPopup(
        _ action: WKWebExtension.Action,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let manager else {
            completionHandler(
                ExtensionManagerCallbackError.extensionManagerUnavailable.nsError()
            )
            return
        }

        manager.updateActionSurfaceState(
            for: action,
            extensionContext: extensionContext
        )

        let extensionId = manager.extensionID(for: extensionContext)
        let popupPhase: SafariExtensionPopupLifecyclePhase =
            manager.isPopupActive ? .reopened : .opened

        let manifest = extensionId.flatMap { manager.loadedExtensionManifests[$0] } ?? [:]

        manager.grantRequestedPermissions(
            to: extensionContext,
            webExtension: extensionContext.webExtension,
            manifest: manifest
        )
        manager.grantRequestedMatchPatterns(
            to: extensionContext,
            webExtension: extensionContext.webExtension
        )
        if let activeTab = manager.browserBridgeContext?.currentExtensionTabForActiveWindow() {
            let seesCurrentTab =
                manager.adapterResolutionOwner.stableAdapter(for: activeTab) != nil
                && manager.isTabEligibleForCurrentExtensionRuntime(activeTab)
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
                manager: manager,
                popover: popover
            )
            if let extensionId {
                popupUIDelegates[extensionId] = popupUIDelegate
            }
            popupWebView.uiDelegate = popupUIDelegate
        }

        if let extensionId {
            activeIdentity = ExtensionActionPopupIdentity(
                extensionId: extensionId,
                profileId: manager.profileId(for: extensionContext)
            )
            recordActionPopupPresentation(
                for: extensionId,
                popupWebView: popupWebView,
                phase: popupPhase
            )
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, let manager = self.manager else {
                completionHandler(
                    ExtensionManagerCallbackError.extensionManagerUnavailable.nsError()
                )
                return
            }
            popover.behavior = .transient
            popover.delegate = self
            manager.isPopupActive = true

            guard let extensionId else {
                completionHandler(
                    ExtensionManagerCallbackError.extensionIdentifierUnavailable.nsError()
                )
                return
            }

            let profileId = manager.profileId(for: extensionContext)
            let preferredWindowId = manager.browserBridgeContext?.activeExtensionWindowState.flatMap { windowState in
                guard let profileId else { return windowState.id }
                return manager.windowMatchesProfile(windowState, profileId: profileId) ? windowState.id : nil
            }
            let resolution = manager.actionPopupAnchorResolutionOwner.presentResolvedExtensionActionPopup(
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

    private func recordActionPopupPresentation(
        for extensionId: String,
        popupWebView: WKWebView?,
        phase: SafariExtensionPopupLifecyclePhase
    ) {
        if phase == .opened || phase == .reopened {
            SumiNativeMessagingRuntimeCounters.recordPopupOpened(extensionId: extensionId)
        }
        guard RuntimeDiagnostics.isVerboseEnabled else { return }
        Task { @MainActor [weak self] in
            guard let manager = self?.manager else { return }
            await SafariExtensionSessionDiagnosticsBuilder.logIfDiagnosticsEnabled {
                await SafariExtensionSessionDiagnosticsBuilder.build(
                    extensionId: extensionId,
                    phase: phase,
                    extensionManager: manager,
                    popupWebView: popupWebView
                )
            }
        }
    }

    // MARK: - NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        manager?.isPopupActive = false
        if let popupIdentity = activeIdentity {
            let extensionId = popupIdentity.extensionId
            SafariExtensionAutofillFillDiagnostics.setPopupActive(false, extensionId: extensionId)
            restoreInlineUIHostingFocusIfNeeded()
            SafariExtensionAutofillFillDiagnostics.logSnapshotIfEnabled(
                context: "popoverDidClose"
            )
            SumiNativeMessagingRuntimeCounters.recordPopupClosed(extensionId: extensionId)
            popupUIDelegates.removeValue(forKey: extensionId)
            scheduleOrPerformDeferredContextUnload(
                forExtensionId: extensionId,
                profileId: popupIdentity.profileId
            )
            guard RuntimeDiagnostics.isVerboseEnabled else { return }
            Task { @MainActor [weak self] in
                guard let self, let manager = self.manager else { return }
                await SafariExtensionSessionDiagnosticsBuilder.logIfDiagnosticsEnabled {
                    await SafariExtensionSessionDiagnosticsBuilder.build(
                        extensionId: extensionId,
                        phase: .closed,
                        extensionManager: manager
                    )
                }
                if SafariExtensionAutofillFillDiagnostics.shouldDeferNativeMessagingTeardownOnPopupClose()
                    == false {
                    self.activeIdentity = nil
                }
            }
        }
    }

    private func restoreInlineUIHostingFocusIfNeeded() {
        guard SafariExtensionAutofillFillDiagnostics
            .shouldRestoreInlineUIHostingFocusAfterPopupClose()
        else {
            return
        }
        guard let manager,
              let tab = manager.browserBridgeContext?.currentExtensionTabForActiveWindow(),
              let webView = manager.resolvedLiveWebView(for: tab),
              let window = webView.window,
              webView.superview != nil
        else {
            return
        }
        guard !webView.sumiIsInFullscreenElementPresentation else { return }

        DispatchQueue.main.async { [weak webView, weak window] in
            guard let webView, let window else { return }
            guard window.firstResponder !== webView else { return }
            _ = window.makeFirstResponder(webView)
        }
    }

    // MARK: - Context Unload

    private func performContextUnload(
        forExtensionId extensionId: String,
        profileId: UUID?
    ) {
        guard let manager else { return }
        manager.safariNativeMessagingHost.clearLaunchSessionOnExtensionContextUnload(
            forExtensionId: extensionId,
            profileId: profileId
        )
        manager.pruneNativeMessagePortHandlerEntries(
            forExtensionId: extensionId,
            profileId: profileId
        )
    }

    private func scheduleOrPerformDeferredContextUnload(
        forExtensionId extensionId: String,
        profileId: UUID?
    ) {
        if SafariExtensionAutofillFillDiagnostics.shouldDeferNativeMessagingTeardownOnPopupClose() {
            scheduleDeferredContextUnload(
                forExtensionId: extensionId,
                profileId: profileId
            )
            return
        }
        SafariExtensionAutofillFillDiagnostics.endFillSession(extensionId: extensionId)
        performContextUnload(
            forExtensionId: extensionId,
            profileId: profileId
        )
        activeIdentity = nil
    }

    private func scheduleDeferredContextUnload(
        forExtensionId extensionId: String,
        profileId: UUID?
    ) {
        let identity = ExtensionActionPopupIdentity(
            extensionId: extensionId,
            profileId: profileId
        )
        cancelDeferredContextUnload(identity)
        deferredContextUnloadTasks[identity] = Task { @MainActor [weak self] in
            try? await Task.sleep(
                for: SafariExtensionAutofillFillDiagnostics.deferredFillTeardownTimeout
            )
            guard !Task.isCancelled else { return }
            self?.completeDeferredContextUnload(
                identity,
                reason: "timeout"
            )
        }
    }

    func completeDeferredContextUnload(
        forExtensionId extensionId: String,
        reason: String
    ) {
        let identities = deferredContextUnloadTasks.keys.filter {
            $0.extensionId == extensionId
        }
        guard !identities.isEmpty else { return }
        for identity in identities {
            completeDeferredContextUnload(identity, reason: reason)
        }
    }

    private func completeDeferredContextUnload(
        _ identity: ExtensionActionPopupIdentity,
        reason: String
    ) {
        cancelDeferredContextUnload(identity)
        SafariExtensionAutofillFillDiagnostics.beginIntentionalDeferredTeardown()
        defer {
            SafariExtensionAutofillFillDiagnostics.endIntentionalDeferredTeardown()
        }
        SafariExtensionAutofillFillDiagnostics.endFillSession(extensionId: identity.extensionId)
        performContextUnload(
            forExtensionId: identity.extensionId,
            profileId: identity.profileId
        )
        if activeIdentity == identity {
            activeIdentity = nil
        }
        SafariExtensionAutofillFillDiagnostics.logSnapshotIfEnabled(
            context: "deferredPopupContextUnload:\(reason)"
        )
    }

    func cancelDeferredContextUnload(forExtensionId extensionId: String) {
        let identities = deferredContextUnloadTasks.keys.filter {
            $0.extensionId == extensionId
        }
        for identity in identities {
            cancelDeferredContextUnload(identity)
        }
    }

    private func cancelDeferredContextUnload(_ identity: ExtensionActionPopupIdentity) {
        deferredContextUnloadTasks[identity]?.cancel()
        deferredContextUnloadTasks.removeValue(forKey: identity)
    }
}
