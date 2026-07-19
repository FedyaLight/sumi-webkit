import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
struct ExtensionContextLoadingAssemblyProduct {
    let admission: ExtensionContextLoadAdmission
    let authority: ExtensionLoadedContextAuthority
    let sourceCache: WebExtensionRuntimeSourceCache
    let publications: ExtensionContextPublicationQuery
}

@available(macOS 15.5, *)
@MainActor
struct ExtensionContextLifecycleCoreProduct {
    let errors: ExtensionContextErrorObservation
    let retirement: ExtensionContextRetirement
    let profileState: ExtensionProfileRuntimeStateOwner
    let retention: ExtensionContextRetentionOwner
    let settlement: ExtensionContextSettlementOwner
}

@available(macOS 15.5, *)
@MainActor
extension ExtensionManagerAssembler {
    static func assembleContextState(
        _ f: ExtensionManagerAssemblyFoundation,
        popupRetirement: ExtensionActionPopupRuntimeRetirement,
        bootstrapChromeAdmission: ExtensionBootstrapChromeAdmission
    ) -> (
        loading: ExtensionContextLoadingAssemblyProduct,
        lifecycle: ExtensionContextLifecycleCoreProduct
    ) {
        makeContextState(
            f,
            popupRetirement: popupRetirement,
            bootstrapChromeAdmission: bootstrapChromeAdmission
        )
    }

    private static func makeContextState(
        _ f: ExtensionManagerAssemblyFoundation,
        popupRetirement: ExtensionActionPopupRuntimeRetirement,
        bootstrapChromeAdmission: ExtensionBootstrapChromeAdmission
    ) -> (
        loading: ExtensionContextLoadingAssemblyProduct,
        lifecycle: ExtensionContextLifecycleCoreProduct
    ) {
        let errors = ExtensionContextErrorObservation(
            recordErrorUpdateDuration: { [metrics = f.runtime.metrics] extensionID, duration in
                metrics.recordErrorUpdateDuration(duration, for: extensionID)
            },
            trace: { [diagnostics = f.runtime.diagnostics] in diagnostics.trace($0) }
        )
        let retirement = ExtensionContextRetirement(
            profileRuntime: f.runtime.profileRuntime,
            backgroundRuntimeState: f.contexts.backgroundRuntimeState,
            runtimeResidency: f.runtime.residency,
            errorObservation: errors,
            diagnostics: f.runtime.diagnostics,
            actionPopups: popupRetirement,
            bootstrapChromeAdmission: bootstrapChromeAdmission
        )
        let admission = ExtensionContextLoadAdmission(
            mutationRegistry: f.contexts.runtimeMutationRegistry,
            loadRegistry: f.contexts.contextLoadRegistry
        )
        let profileState = ExtensionProfileRuntimeStateOwner(
            profileRuntime: f.runtime.profileRuntime,
            installedExtensions: f.contexts.installedExtensions,
            runtimeLifecycle: f.runtime.lifecycle
        )
        let loading = ExtensionContextLoadingAssemblyProduct(
            admission: admission,
            authority: ExtensionLoadedContextAuthority(
                profileRuntime: f.runtime.profileRuntime,
                admission: admission,
                contextRetirement: retirement
            ),
            sourceCache: WebExtensionRuntimeSourceCache(
                admission: admission
            ),
            publications: ExtensionContextPublicationQuery(
                profileRuntime: f.runtime.profileRuntime
            )
        )
        let lifecycle = ExtensionContextLifecycleCoreProduct(
            errors: errors,
            retirement: retirement,
            profileState: profileState,
            retention: ExtensionContextRetentionOwner(
                profileRuntime: f.runtime.profileRuntime,
                runtimeResidency: f.runtime.residency,
                extensionLoadRevisions: f.runtime.loadRevisions,
                loadRegistry: f.contexts.contextLoadRegistry,
                retirement: retirement,
                diagnostics: f.runtime.diagnostics
            ),
            settlement: ExtensionContextSettlementOwner(
                profileRuntime: f.runtime.profileRuntime,
                runtimeLifecycle: f.runtime.lifecycle,
                installedExtensions: f.contexts.installedExtensions,
                bootstrapChromeAdmission: bootstrapChromeAdmission,
                publishReadyProfile: {
                    [profileRuntime = f.runtime.profileRuntime,
                     browserConfiguration = f.controller.browserConfiguration,
                     reloads = f.browser.reloads]
                    profileID, controller in
                    guard profileRuntime.currentProfileId == profileID,
                          profileRuntime.controller(for: profileID) === controller
                    else { return false }
                    browserConfiguration.webViewConfiguration
                        .webExtensionController = controller
                    reloads.reconcile(
                        profileID: profileID,
                        reason: "ExtensionContextSettlementOwner"
                    )
                    return profileRuntime.currentProfileId == profileID
                        && profileRuntime.controller(for: profileID) === controller
                        && browserConfiguration.webViewConfiguration
                            .webExtensionController === controller
                },
                markPublicationReady: { [surface = f.actions.surfacePublication] in
                    _ = surface.markRuntimePublicationReady()
                },
                diagnostics: f.runtime.diagnostics
            )
        )
        return (loading, lifecycle)
    }
}
