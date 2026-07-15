import Foundation

/// Final manager-owned controller lifetime. Controller roles were distributed
/// only while the root assembled their consumers and cannot be recovered here.
@available(macOS 15.5, *)
@MainActor
struct ExtensionControllerGraph {
    let lifetime: ExtensionControllerLifetimeOwner
}

/// Final manager-owned context lifecycle and its terminal manager use cases.
/// Raw authorities and stores remain private inside `lifetime`.
@available(macOS 15.5, *)
@MainActor
struct ExtensionContextLifecycleGraph {
    let runtimeLifetime: ExtensionContextRuntimeLifetime
    let transactionLifetime: ExtensionContextTransactionResidenceOwner
    let publicationLifetime: ExtensionContextPublicationLifetime
    let control: ExtensionManagerLifetimeControl
    let websiteDataQuiescence: ExtensionWebsiteDataRuntimeQuiescence
    #if DEBUG
        let testTaskDrain: ExtensionRuntimeTaskDrain
    #endif
}

/// Final manager-owned normal-tab lifetime. The single factory constructs the
/// product-facing browser runtime without publishing its captured roles.
@available(macOS 15.5, *)
@MainActor
struct ExtensionNormalTabGraph {
    let preparationLifetime: ExtensionNormalTabPreparationLifetime
    let publicationLifetime: ExtensionNormalTabPublicationLifetime
    let moduleRuntimeFactory: ExtensionModuleBrowserRuntimeFactory
}

/// Final manager-owned action/UI lifetime and bounded product-facing roles.
/// None of these products exposes the retained action nodes.
@available(macOS 15.5, *)
@MainActor
struct ExtensionActionUIGraph {
    let surfaceLifetime: ExtensionActionSurfaceResidenceOwner
    let policyLifetime: ExtensionActionPolicyResidenceOwner
    let popupLifetime: ExtensionActionPopupResidenceOwner
    let presentationLifetime: ExtensionActionPresentationResidenceOwner
    let surfaceBinding: BrowserExtensionSurfaceBinding
    let toolbarRuntime: ExtensionToolbarRuntime
    let autofillRuntime: SafariExtensionAutofillRuntime
    let compatibilityDiagnostics:
        ExtensionCompatibilityDiagnosticsSnapshotProvider
    #if DEBUG
        let debugSignals: ExtensionManagerDebugSignals
    #endif
}

/// Final manager-owned installation/retirement lifetime and its two terminal
/// entry points. Persistence, catalog and cleanup nodes cannot be recovered.
@available(macOS 15.5, *)
@MainActor
struct ExtensionInstallationRetirementGraph {
    let lifetime: ExtensionInstallationRetirementLifetimeOwner
    let settingsCatalog: ExtensionSettingsCatalogBinding
    let runtimeTermination: ExtensionRuntimeTermination
}
