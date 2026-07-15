import Foundation

@available(macOS 15.5, *)
@MainActor
struct ExtensionRuntimeRetirementAssemblyProduct {
    let scoped: ExtensionScopedRuntimeRetirement
    let runtime: ExtensionRuntimeRetirement
    let rollback: ExtensionRuntimeRollback
}

@available(macOS 15.5, *)
@MainActor
extension ExtensionManagerAssembler {
    static func assembleRetirement(
        _ f: ExtensionManagerAssemblyFoundation,
        contextLoading: ExtensionContextLoadingAssemblyProduct,
        contextLifecycle: ExtensionContextLifecycleCoreProduct,
        actionPolicy: ExtensionActionPolicyAssemblyProduct,
        nativeMessaging: ExtensionNativeMessagingAssemblyProduct
    ) -> ExtensionRuntimeRetirementAssemblyProduct {
        let scoped = ExtensionScopedRuntimeRetirement(
            profileRuntime: f.runtime.profileRuntime,
            mutationRegistry: f.contexts.runtimeMutationRegistry,
            loadRegistry: f.contexts.contextLoadRegistry,
            contextRetirement: contextLifecycle.retirement,
            runtimeCatalog: f.runtime.catalog,
            runtimeResidency: f.runtime.residency,
            sourceCache: contextLoading.sourceCache,
            errorObservation: contextLifecycle.errors,
            nativeMessagingPorts: f.controller.nativeMessagingPorts,
            optionsWindows: f.actions.optionsWindows,
            actionAnchors: f.actions.actionAnchors,
            diagnostics: f.runtime.diagnostics
        )
        let runtime = ExtensionRuntimeRetirement(
            scopedRetirement: scoped,
            actionSurfaces: actionPolicy.actionSurfaces,
            attachedRetirement: f.browser.retirement,
            nativeMessagingOwners: nativeMessaging.owners
        )
        return ExtensionRuntimeRetirementAssemblyProduct(
            scoped: scoped,
            runtime: runtime,
            rollback: ExtensionRuntimeRollback(
                authority: contextLoading.authority,
                retirement: runtime
            )
        )
    }
}
