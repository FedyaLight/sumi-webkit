//
//  ExtensionControllerAttachmentOwner.swift
//  Sumi
//
//  Owns attaching per-profile extension controllers to live tab WebViews,
//  deciding when a WebView needs a destructive runtime rebuild, and resolving
//  the live WebView an extension context may target.
//

import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionControllerAttachmentOwner {
    struct Dependencies {
        let profileRuntimeOwner: ExtensionProfileRuntimeOwner
        let runtime: @MainActor () -> ExtensionManagerRuntime
        let resolvedProfileId: @MainActor (Tab) -> UUID?
        let profileIdForController: @MainActor (WKWebExtensionController) -> UUID?
        let profileIdForContext: @MainActor (WKWebExtensionContext) -> UUID?
        let hasEnabledInstalledExtensions: @MainActor () -> Bool
        let allowsRuntimeWithoutEnabledExtensions: @MainActor () -> Bool
        let extensionsLoaded: @MainActor () -> Bool
        let tabOpenNotificationGeneration: @MainActor () -> UInt64
        let ensureExtensionController: @MainActor (UUID) -> WKWebExtensionController?
        let canLateBindExtensionController: @MainActor (WKWebView) -> Bool
        let installPermissionsOriginsCompatibilityPreludes:
            @MainActor (WKUserContentController, UUID) -> Void
        let liveWebViews: @MainActor (Tab) -> [WKWebView]
        let allKnownTabs: @MainActor () -> [Tab]
        let tabNeedsExtensionContentScriptRebind: @MainActor (Tab) -> Bool
        let registerTabWithExtensionRuntime: @MainActor (Tab, String) -> Void
        let tabDescription: @MainActor (Tab) -> String
        let webViewDescription: @MainActor (WKWebView) -> String
        let recordFrameResolution: @MainActor (Bool, WKWebExtensionContext, String) -> Void
        let trace: @MainActor (() -> String) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func extensionController(for tab: Tab) -> WKWebExtensionController? {
        guard let profileId = dependencies.resolvedProfileId(tab) else { return nil }
        if let controller = dependencies.profileRuntimeOwner.controller(for: profileId) {
            return controller
        }
        guard dependencies.hasEnabledInstalledExtensions()
            || dependencies.allowsRuntimeWithoutEnabledExtensions()
        else {
            return nil
        }
        return dependencies.ensureExtensionController(profileId)
    }

    func tabMatchesExtensionContext(
        _ tab: Tab,
        extensionContext: WKWebExtensionContext
    ) -> Bool {
        guard tab.isEphemeral == false else { return false }
        guard let contextProfileId = dependencies.profileIdForContext(extensionContext),
              let tabProfileId = dependencies.resolvedProfileId(tab)
        else {
            return false
        }
        return contextProfileId == tabProfileId
    }

    func resolvedLiveWebView(for tab: Tab) -> WKWebView? {
        let runtime = dependencies.runtime()
        let windowId = runtime.windowStateContainingTab(tab)?.id
            ?? runtime.primaryTrackedWindowId(tab.id)
        if let windowId,
           let webView = runtime.windowOwnedWebView(tab, windowId) {
            return webView
        }

        return ownedUntrackedCurrentWebView(for: tab)
    }

    func ownedUntrackedCurrentWebView(for tab: Tab) -> WKWebView? {
        dependencies.runtime().untrackedOwnedWebView(tab)
    }

    @discardableResult
    func attachExtensionControllerIfNeeded(
        to webView: WKWebView,
        for tab: Tab
    ) -> Bool {
        guard tab.isEphemeral == false else { return false }
        guard let profileId = dependencies.resolvedProfileId(tab) else { return false }

        let expectedController: WKWebExtensionController
        if let existing = dependencies.profileRuntimeOwner.controller(for: profileId) {
            expectedController = existing
        } else if dependencies.hasEnabledInstalledExtensions()
            || dependencies.allowsRuntimeWithoutEnabledExtensions() {
            guard let provisioned = dependencies.ensureExtensionController(profileId) else {
                return false
            }
            expectedController = provisioned
        } else {
            return false
        }

        if let existingController = webView.configuration.webExtensionController {
            if existingController === expectedController {
                dependencies.installPermissionsOriginsCompatibilityPreludes(
                    webView.configuration.userContentController,
                    profileId
                )
                return true
            }
            return false
        }

        guard dependencies.canLateBindExtensionController(webView) else { return false }

        webView.configuration.webExtensionController = expectedController
        webView.configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        dependencies.installPermissionsOriginsCompatibilityPreludes(
            webView.configuration.userContentController,
            profileId
        )
        return true
    }

    func extensionWebView(
        for tab: Tab,
        extensionContext: WKWebExtensionContext
    ) -> WKWebView? {
        guard tabMatchesExtensionContext(tab, extensionContext: extensionContext),
              let webView = resolvedLiveWebView(for: tab)
        else {
            dependencies.recordFrameResolution(
                false,
                extensionContext,
                "extensionWebViewMissingLiveTarget"
            )
            return nil
        }

        guard attachExtensionControllerIfNeeded(to: webView, for: tab),
              let profileId = dependencies.resolvedProfileId(tab),
              let expectedController = dependencies.profileRuntimeOwner.controller(for: profileId),
              webView.configuration.webExtensionController === expectedController
        else {
            dependencies.recordFrameResolution(
                false,
                extensionContext,
                "extensionWebViewControllerMismatch"
            )
            return nil
        }

        dependencies.recordFrameResolution(
            true,
            extensionContext,
            "extensionWebViewReady"
        )
        return webView
    }

    func ensureExtensionControllerAttachedForTab(
        _ tab: Tab,
        reason: String,
        allowWhenExtensionsNotLoaded: Bool = false
    ) {
        guard tab.isEphemeral == false else { return }
        guard dependencies.extensionsLoaded() || allowWhenExtensionsNotLoaded else { return }
        guard dependencies.resolvedProfileId(tab) != nil else { return }

        var needsRebuild = false
        for webView in dependencies.liveWebViews(tab) {
            let attached = attachExtensionControllerIfNeeded(to: webView, for: tab)
            dependencies.trace {
                "ensureExtensionControllerAttachedForTab webView=\(self.dependencies.webViewDescription(webView)) attached=\(attached) \(self.dependencies.tabDescription(tab))"
            }
            if attached == false,
               webViewNeedsExtensionRuntimeRebuild(webView, for: tab) {
                needsRebuild = true
                break
            }
        }

        if needsRebuild,
           dependencies.runtime().browserRuntimeAvailable() {
            dependencies.trace {
                "ensureExtensionControllerAttachedForTab rebuild reason=\(reason) controllerMismatch=true contentScriptRebind=\(self.dependencies.tabNeedsExtensionContentScriptRebind(tab)) \(self.dependencies.tabDescription(tab))"
            }
            SafariExtensionPermissionLifecycleDiagnostics.logReloadRebuild(
                SafariExtensionReloadRebuildSnapshot(
                    triggerReason: reason,
                    profileBucket: SafariExtensionPermissionLifecycleDiagnostics.bucket(
                        dependencies.resolvedProfileId(tab)
                    ),
                    tabBucket: SafariExtensionPermissionLifecycleDiagnostics.bucket(tab.id),
                    host: SafariExtensionPermissionLifecycleDiagnostics.host(from: tab.url),
                    userActionCaused: false,
                    action: .destructiveRebuild
                )
            )
            tab.extensionPageRuntimeOwner.resetDocumentBindingForContentScriptRebind()
            dependencies.runtime().rebuildLiveWebViews(tab)
            // WebKit only injects manifest content scripts when the controller is on the
            // configuration before navigation; allow `notifyTabOpenedIfNeeded` to run again.
            tab.extensionPageRuntimeOwner.clearOpenNotificationGeneration()
        }
    }

    func webViewNeedsExtensionRuntimeRebuild(
        _ webView: WKWebView,
        for tab: Tab
    ) -> Bool {
        webViewNeedsExtensionRuntimeRebuild(
            currentController: webView.configuration.webExtensionController,
            currentURL: webView.url,
            for: tab
        )
    }

    func webViewNeedsExtensionRuntimeRebuild(
        currentController: WKWebExtensionController?,
        currentURL: URL?,
        for tab: Tab
    ) -> Bool {
        guard let profileId = dependencies.resolvedProfileId(tab) else {
            return ExtensionRuntimeWebViewBindingPolicy.needsRuntimeRebuild(
                currentController: currentController,
                expectedController: nil,
                currentURL: currentURL
            )
        }

        if let currentController,
           let currentProfileId = dependencies.profileIdForController(currentController),
           currentProfileId != profileId {
            return true
        }

        let expectedController =
            dependencies.profileRuntimeOwner.controller(for: profileId)
            ?? extensionController(for: tab)
        return ExtensionRuntimeWebViewBindingPolicy.needsRuntimeRebuild(
            currentController: currentController,
            expectedController: expectedController,
            currentURL: currentURL
        )
    }

    func updateWebViewsForProfile(
        _ profileId: UUID,
        allowWhenExtensionsNotLoaded: Bool = false
    ) {
        guard dependencies.profileRuntimeOwner.controller(for: profileId) != nil else { return }
        guard dependencies.runtime().browserRuntimeAvailable() else { return }

        for tab in dependencies.allKnownTabs() {
            guard dependencies.resolvedProfileId(tab) == profileId else { continue }
            guard tab.isEphemeral == false else { continue }
            ensureExtensionControllerAttachedForTab(
                tab,
                reason: "updateWebViewsForProfile",
                allowWhenExtensionsNotLoaded: allowWhenExtensionsNotLoaded
            )
        }
    }

    func reconcileTabAfterContentScriptContextsLoaded(
        _ tab: Tab,
        reason: String
    ) {
        guard tab.isEphemeral == false else { return }
        if tab.extensionPageRuntimeOwner.hasOpenNotificationForCurrentDocumentWithLoadedContexts(
            generation: dependencies.tabOpenNotificationGeneration()
        ) {
            return
        }

        if tab.extensionPageRuntimeOwner.hasCommittedDocumentBinding(),
           dependencies.tabNeedsExtensionContentScriptRebind(tab) {
            ensureExtensionControllerAttachedForTab(tab, reason: reason)
            return
        }

        tab.extensionPageRuntimeOwner.clearOpenNotificationGeneration()
        dependencies.registerTabWithExtensionRuntime(tab, reason)
    }
}

@available(macOS 15.5, *)
extension ExtensionControllerAttachmentOwner.Dependencies {
    @MainActor
    static func live(manager: ExtensionManager) -> Self {
        Self(
            profileRuntimeOwner: manager.profileRuntimeOwner,
            runtime: { [weak manager] in
                manager?.runtime ?? .inactive
            },
            resolvedProfileId: { [weak manager] tab in
                manager?.resolvedProfileId(for: tab)
            },
            profileIdForController: { [weak manager] controller in
                manager?.profileId(for: controller)
            },
            profileIdForContext: { [weak manager] context in
                manager?.profileId(for: context)
            },
            hasEnabledInstalledExtensions: { [weak manager] in
                manager?.hasEnabledInstalledExtensions ?? false
            },
            allowsRuntimeWithoutEnabledExtensions: { [weak manager] in
                manager?.allowsRuntimeWithoutEnabledExtensions ?? false
            },
            extensionsLoaded: { [weak manager] in
                manager?.extensionsLoaded ?? false
            },
            tabOpenNotificationGeneration: { [weak manager] in
                manager?.tabOpenNotificationGeneration ?? 0
            },
            ensureExtensionController: { [weak manager] profileId in
                manager?.ensureExtensionController(for: profileId)
            },
            canLateBindExtensionController: { [weak manager] webView in
                manager?.canLateBindExtensionController(to: webView) ?? false
            },
            installPermissionsOriginsCompatibilityPreludes: { [weak manager] controller, profileId in
                manager?.permissionsOriginsCompatibilityPreludeInstallationOwner.installPreludes(
                    into: controller,
                    profileId: profileId
                )
            },
            liveWebViews: { [weak manager] tab in
                manager?.liveWebViews(for: tab) ?? []
            },
            allKnownTabs: { [weak manager] in
                manager?.allKnownTabs() ?? []
            },
            tabNeedsExtensionContentScriptRebind: { [weak manager] tab in
                manager?.tabNeedsExtensionContentScriptRebind(tab) ?? false
            },
            registerTabWithExtensionRuntime: { [weak manager] tab, reason in
                manager?.registerTabWithExtensionRuntime(tab, reason: reason)
            },
            tabDescription: { [weak manager] tab in
                manager?.runtimeDiagnosticsOwner.tabDescription(tab) ?? "tab=\(tab.id.uuidString.prefix(8))"
            },
            webViewDescription: { webView in
                ExtensionRuntimeDiagnosticsOwner.objectDescription(webView)
            },
            recordFrameResolution: { [weak manager] resolved, context, reason in
                SafariExtensionAutofillFillDiagnostics.recordFrameResolution(
                    resolved: resolved,
                    extensionId: manager?.extensionID(for: context),
                    reason: reason
                )
            },
            trace: { [weak manager] message in
                manager?.extensionRuntimeTrace(message())
            }
        )
    }
}

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    func extensionController(for tab: Tab) -> WKWebExtensionController? {
        controllerAttachmentOwner.extensionController(for: tab)
    }

    func tabMatchesExtensionContext(
        _ tab: Tab,
        extensionContext: WKWebExtensionContext
    ) -> Bool {
        controllerAttachmentOwner.tabMatchesExtensionContext(
            tab,
            extensionContext: extensionContext
        )
    }

    func resolvedLiveWebView(for tab: Tab) -> WKWebView? {
        controllerAttachmentOwner.resolvedLiveWebView(for: tab)
    }

    func ownedUntrackedCurrentWebView(for tab: Tab) -> WKWebView? {
        controllerAttachmentOwner.ownedUntrackedCurrentWebView(for: tab)
    }

    @discardableResult
    func attachExtensionControllerIfNeeded(
        to webView: WKWebView,
        for tab: Tab
    ) -> Bool {
        controllerAttachmentOwner.attachExtensionControllerIfNeeded(to: webView, for: tab)
    }

    func extensionWebView(
        for tab: Tab,
        extensionContext: WKWebExtensionContext
    ) -> WKWebView? {
        controllerAttachmentOwner.extensionWebView(
            for: tab,
            extensionContext: extensionContext
        )
    }

    func ensureExtensionControllerAttachedForTab(
        _ tab: Tab,
        reason: String = #function,
        allowWhenExtensionsNotLoaded: Bool = false
    ) {
        controllerAttachmentOwner.ensureExtensionControllerAttachedForTab(
            tab,
            reason: reason,
            allowWhenExtensionsNotLoaded: allowWhenExtensionsNotLoaded
        )
    }

    func webViewNeedsExtensionRuntimeRebuild(
        _ webView: WKWebView,
        for tab: Tab
    ) -> Bool {
        controllerAttachmentOwner.webViewNeedsExtensionRuntimeRebuild(webView, for: tab)
    }

    func webViewNeedsExtensionRuntimeRebuild(
        currentController: WKWebExtensionController?,
        currentURL: URL?,
        for tab: Tab
    ) -> Bool {
        controllerAttachmentOwner.webViewNeedsExtensionRuntimeRebuild(
            currentController: currentController,
            currentURL: currentURL,
            for: tab
        )
    }

    func updateWebViewsForProfile(
        _ profileId: UUID,
        allowWhenExtensionsNotLoaded: Bool = false
    ) {
        controllerAttachmentOwner.updateWebViewsForProfile(
            profileId,
            allowWhenExtensionsNotLoaded: allowWhenExtensionsNotLoaded
        )
    }

    func reconcileTabAfterContentScriptContextsLoaded(
        _ tab: Tab,
        reason: String = #function
    ) {
        controllerAttachmentOwner.reconcileTabAfterContentScriptContextsLoaded(
            tab,
            reason: reason
        )
    }
}
