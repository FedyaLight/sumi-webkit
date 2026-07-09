//
//  ExtensionWebViewRuntimePreparationOwner.swift
//  Sumi
//
//  Owns preparing WebView configurations and live WebViews for the extension
//  runtime: controller assignment, data store selection, compatibility
//  preludes, and reload-triggered destructive rebuilds.
//

import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionWebViewRuntimePreparationOwner {
    struct Dependencies {
        let runtime: @MainActor () -> ExtensionManagerRuntime
        let resolvedProfileId: @MainActor (UUID?) -> UUID?
        let resolvedProfileIdForTab: @MainActor (Tab) -> UUID?
        let requestExtensionRuntime: @MainActor (ExtensionManager.ExtensionRuntimeRequestReason) -> Void
        let ensureExtensionController: @MainActor (UUID) -> WKWebExtensionController?
        let currentExtensionController: @MainActor () -> WKWebExtensionController?
        let websiteDataStore: @MainActor (UUID) -> WKWebsiteDataStore?
        let installPermissionsOriginsCompatibilityPreludes:
            @MainActor (WKUserContentController, UUID) -> Void
        let attachExtensionControllerIfNeeded: @MainActor (WKWebView, Tab) -> Bool
        let webViewNeedsExtensionRuntimeRebuild: @MainActor (WKWebView, Tab) -> Bool
        let registerTabWithExtensionRuntime: @MainActor (Tab, String) -> Void
        let traceControllerBinding:
            @MainActor (String, UUID?, WKWebExtensionController?, WKWebViewConfiguration?, WKWebView?) -> Void
        let controllerDescription: @MainActor (WKWebExtensionController?) -> String
        let configurationDescription: @MainActor (WKWebViewConfiguration?) -> String
        let userContentControllerDescription: @MainActor (WKUserContentController?) -> String
        let webViewDescription: @MainActor (WKWebView?) -> String
        let trace: @MainActor (() -> String) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func prepareWebViewConfigForExtensionRuntime(
        _ configuration: WKWebViewConfiguration,
        profileId: UUID?,
        reason: String
    ) {
        let resolvedProfileId = dependencies.resolvedProfileId(profileId)
        guard let resolvedProfileId else { return }

        dependencies.requestExtensionRuntime(.webViewConfiguration)
        let requestedController = dependencies.ensureExtensionController(resolvedProfileId)
        let existingController = configuration.webExtensionController
        let shouldAssignController =
            existingController == nil || existingController !== requestedController

        dependencies.trace {
            "prepareConfiguration reason=\(reason) profileId=\(resolvedProfileId.uuidString) configuration=\(self.dependencies.configurationDescription(configuration)) userContentController=\(self.dependencies.userContentControllerDescription(configuration.userContentController)) existingController=\(self.dependencies.controllerDescription(existingController)) targetController=\(self.dependencies.controllerDescription(requestedController)) willAssign=\(shouldAssignController)"
        }

        if shouldAssignController {
            configuration.webExtensionController = requestedController
        }
        dependencies.traceControllerBinding(
            "prepareWebViewConfiguration",
            resolvedProfileId,
            requestedController,
            configuration,
            nil
        )
        if let dataStore = dependencies.websiteDataStore(resolvedProfileId) {
            configuration.websiteDataStore = dataStore
        }
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        dependencies.installPermissionsOriginsCompatibilityPreludes(
            configuration.userContentController,
            resolvedProfileId
        )
    }

    func prepareWebViewForExtensionRuntime(
        _ webView: WKWebView,
        currentURL: URL?,
        reason: String
    ) {
        let existingController = webView.configuration.webExtensionController
        let owningTab = (webView as? FocusableWKWebView)?.owningTab
        let didAttach = owningTab.map {
            dependencies.attachExtensionControllerIfNeeded(webView, $0)
        } ?? false

        if let owningTab,
           didAttach == false,
           dependencies.webViewNeedsExtensionRuntimeRebuild(webView, owningTab),
           dependencies.runtime().browserRuntimeAvailable() {
            SafariExtensionPermissionLifecycleDiagnostics.logReloadRebuild(
                SafariExtensionReloadRebuildSnapshot(
                    triggerReason: reason,
                    profileBucket: SafariExtensionPermissionLifecycleDiagnostics.bucket(
                        dependencies.resolvedProfileIdForTab(owningTab)
                    ),
                    tabBucket: SafariExtensionPermissionLifecycleDiagnostics.bucket(owningTab.id),
                    host: SafariExtensionPermissionLifecycleDiagnostics.host(from: owningTab.url),
                    userActionCaused: false,
                    action: .destructiveRebuild
                )
            )
            dependencies.runtime().rebuildLiveWebViews(owningTab)
            owningTab.extensionPageRuntimeOwner.clearOpenNotificationGeneration()
            dependencies.registerTabWithExtensionRuntime(
                owningTab,
                "prepareWebViewForExtensionRuntime.rebuild"
            )
        }

        dependencies.trace {
            "prepareWebView reason=\(reason) webView=\(self.dependencies.webViewDescription(webView)) configuration=\(self.dependencies.configurationDescription(webView.configuration)) userContentController=\(self.dependencies.userContentControllerDescription(webView.configuration.userContentController)) currentURL=\(currentURL?.absoluteString ?? "nil") existingController=\(self.dependencies.controllerDescription(existingController)) extensionController=\(self.dependencies.controllerDescription(self.dependencies.currentExtensionController())) willAssign=\(didAttach)"
        }
        dependencies.traceControllerBinding(
            "prepareWebView",
            owningTab.flatMap { dependencies.resolvedProfileIdForTab($0) },
            webView.configuration.webExtensionController,
            webView.configuration,
            webView
        )

        webView.configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        if let owningTab,
           let profileId = dependencies.resolvedProfileIdForTab(owningTab) {
            dependencies.installPermissionsOriginsCompatibilityPreludes(
                webView.configuration.userContentController,
                profileId
            )
        }
    }
}

@available(macOS 15.5, *)
extension ExtensionWebViewRuntimePreparationOwner.Dependencies {
    @MainActor
    static func live(manager: ExtensionManager) -> Self {
        Self(
            runtime: { [weak manager] in
                manager?.runtime ?? .inactive
            },
            resolvedProfileId: { [weak manager] profileId in
                manager?.resolvedProfileId(explicitProfileId: profileId)
            },
            resolvedProfileIdForTab: { [weak manager] tab in
                manager?.resolvedProfileId(for: tab)
            },
            requestExtensionRuntime: { [weak manager] reason in
                _ = manager?.requestExtensionRuntime(reason: reason)
            },
            ensureExtensionController: { [weak manager] profileId in
                manager?.ensureExtensionController(for: profileId)
            },
            currentExtensionController: { [weak manager] in
                manager?.extensionController
            },
            websiteDataStore: { [weak manager] profileId in
                manager?.getExtensionDataStore(for: profileId)
            },
            installPermissionsOriginsCompatibilityPreludes: { [weak manager] controller, profileId in
                manager?.permissionsOriginsCompatibilityPreludeInstallationOwner.installPreludes(
                    into: controller,
                    profileId: profileId
                )
            },
            attachExtensionControllerIfNeeded: { [weak manager] webView, tab in
                manager?.attachExtensionControllerIfNeeded(to: webView, for: tab) ?? false
            },
            webViewNeedsExtensionRuntimeRebuild: { [weak manager] webView, tab in
                manager?.webViewNeedsExtensionRuntimeRebuild(webView, for: tab) ?? false
            },
            registerTabWithExtensionRuntime: { [weak manager] tab, reason in
                manager?.registerTabWithExtensionRuntime(tab, reason: reason)
            },
            traceControllerBinding: { [weak manager] phase, profileId, controller, configuration, webView in
                manager?.traceNativeMessagingContextBinding(
                    phase: phase,
                    extensionId: nil,
                    profileId: profileId,
                    controller: controller,
                    configuration: configuration,
                    webView: webView
                )
            },
            controllerDescription: { [weak manager] controller in
                manager?.extensionRuntimeControllerDescription(controller) ?? "nil"
            },
            configurationDescription: { [weak manager] configuration in
                manager?.extensionRuntimeConfigurationDescription(configuration) ?? "nil"
            },
            userContentControllerDescription: { [weak manager] userContentController in
                manager?.extensionRuntimeUserContentControllerDescription(userContentController)
                    ?? "nil"
            },
            webViewDescription: { webView in
                ExtensionRuntimeDiagnosticsOwner.objectDescription(webView)
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
    func prepareWebViewConfigForExtensionRuntime(
        _ configuration: WKWebViewConfiguration,
        profileId: UUID? = nil,
        reason: String = #function
    ) {
        webViewRuntimePreparationOwner.prepareWebViewConfigForExtensionRuntime(
            configuration,
            profileId: profileId,
            reason: reason
        )
    }

    func prepareWebViewForExtensionRuntime(
        _ webView: WKWebView,
        currentURL: URL? = nil,
        reason: String = #function
    ) {
        webViewRuntimePreparationOwner.prepareWebViewForExtensionRuntime(
            webView,
            currentURL: currentURL,
            reason: reason
        )
    }
}
