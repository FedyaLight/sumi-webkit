import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
struct ExtensionActionPolicyAssemblyProduct {
    let toolbarPinning: ExtensionToolbarPinningOwner
    let hubOrdering: ExtensionHubOrderingOwner
    let permissionDecisions: ExtensionPermissionDecisionStore
    let contextPreparation: ExtensionContextPreparation
    let permissionPrompt: ExtensionPermissionPromptPresenter
    let siteAccess: ExtensionSiteAccessPolicyCoordinator
    let actionSurfaces: ExtensionActionSurfacePublisher
}

@available(macOS 15.5, *)
@MainActor
extension ExtensionManagerAssembler {
    static func assembleActionPolicy(
        _ f: ExtensionManagerAssemblyFoundation,
        contextAuthority: ExtensionLoadedContextAuthority,
        backgroundWakes: ExtensionBackgroundWakeCoordinator
    ) -> ExtensionActionPolicyAssemblyProduct {
        let permissionPrompt = ExtensionPermissionPromptPresenter()
        #if DEBUG
            permissionPrompt.installDebugInjectedDecision {
                [debug = f.actions.debugSignals]
                context, targets, reason in
                debug.permissionPromptDecision?(context, targets, reason)
            }
        #endif
        return assembleActionPolicy(
            f,
            contextAuthority: contextAuthority,
            permissionPrompt: permissionPrompt,
            ensureBackgroundAvailableIfRequired: {
                [backgroundWakes]
                webExtension, context, reason, isCurrent in
                _ = try await backgroundWakes
                    .ensureBackgroundAvailableIfRequired(
                        for: webExtension,
                        context: context,
                        reason: reason,
                        isCurrent: isCurrent
                    )
            },
            prepareBrowserProjection: {
                [reloads = f.browser.reloads] reason, profileID in
                reloads.finalizeRuntimeLoad(
                    reason: reason,
                    profileID: profileID
                )
            }
        )
    }

    private static func assembleActionPolicy(
        _ f: ExtensionManagerAssemblyFoundation,
        contextAuthority: ExtensionLoadedContextAuthority,
        permissionPrompt: ExtensionPermissionPromptPresenter,
        ensureBackgroundAvailableIfRequired: @escaping @MainActor (
            WKWebExtension,
            WKWebExtensionContext,
            ExtensionManager.ExtensionBackgroundWakeReason,
            @escaping @MainActor () -> Bool
        ) async throws -> Void,
        prepareBrowserProjection:
            @escaping @MainActor (String, UUID) -> Void
    ) -> ExtensionActionPolicyAssemblyProduct {
        let permissionDecisions = f.actions.permissionDecisions
        let contextPreparation = ExtensionContextPreparation(
            siteAccessPolicyStore: f.actions.siteAccessPolicyStore,
            installedExtensions: f.contexts.installedExtensions,
            permissionDecisions: permissionDecisions,
            siteAccessPolicyDidPersist: {
                [surface = f.actions.surfacePublication] in
                surface.publishSiteAccessPolicyChange()
            }
        )
        let siteAccess = ExtensionSiteAccessPolicyCoordinator(
            siteAccessPolicyStore: f.actions.siteAccessPolicyStore,
            installedExtensions: {
                [installed = f.contexts.installedExtensions] in
                installed.records
            },
            loadedExtensionManifest: { [catalog = f.runtime.catalog] in
                catalog.manifest(for: $0)
            },
            getExtensionContext: {
                [profileRuntime = f.runtime.profileRuntime]
                extensionID, profileID in
                profileRuntime.contexts(for: profileID)[extensionID]
            },
            reconcileOpenTabsAfterExtensionContextLoad: {
                [reloads = f.browser.reloads] reason, profileID in
                reloads.reloadLoadedRuntime(
                    reason: reason,
                    profileID: profileID
                )
            },
            postSiteAccessPoliciesDidChange: {
                [surface = f.actions.surfacePublication] in
                surface.publishSiteAccessPolicyChange()
            }
        )
        let actionSurfaces = makeActionSurfaces(
            f,
            authority: contextAuthority,
            ensureBackgroundAvailableIfRequired:
                ensureBackgroundAvailableIfRequired,
            prepareBrowserProjection: prepareBrowserProjection
        )
        return ExtensionActionPolicyAssemblyProduct(
            toolbarPinning: f.actions.toolbarPinning,
            hubOrdering: f.actions.hubOrdering,
            permissionDecisions: permissionDecisions,
            contextPreparation: contextPreparation,
            permissionPrompt: permissionPrompt,
            siteAccess: siteAccess,
            actionSurfaces: actionSurfaces
        )
    }
}
