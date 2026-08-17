import Foundation

/// Factory-only persistence roots for installation transactions.
@available(macOS 15.5, *)
@MainActor
struct ExtensionInstallationGraphFoundation {
    let database: SumiDatabase
    let activePackageGenerations: ExtensionPackageGenerationRegistry
    let metadataStore: ExtensionInstallationMetadataStore
}

/// Factory-only references to the separate runtime authorities. This value is
/// never retained and does not act as an authority itself.
@available(macOS 15.5, *)
@MainActor
struct ExtensionRuntimeAuthorityFoundation {
    let profileRuntime: ExtensionProfileRuntime
    let lifecycle: ExtensionRuntimeLifecycleAuthority
    let demand: ExtensionRuntimeDemandAuthority
    let loadStatus: ExtensionRuntimeLoadStatusAuthority
    let catalog: ExtensionRuntimeCatalog
    let residency: ExtensionRuntimeResidencyAuthority
    let metrics: ExtensionRuntimeMetricsAuthority
    let loadRevisions: ExtensionLoadRevisionAuthority
    let tabPublicationRevisions: ExtensionTabPublicationRevisionAuthority
    let diagnostics: ExtensionRuntimeDiagnostics
}

/// Factory-only inputs for context loading and demand-scoped preparation.
@available(macOS 15.5, *)
@MainActor
struct ExtensionContextGraphFoundation {
    let moduleRegistry: SumiModuleRegistry
    let safariExtensionImportStore: SafariExtensionImportStore
    let installedExtensions: InstalledExtensionCollection
    let recentTabRequests: ExtensionRecentTabRequestHistory
    let requestedTabLoadResolver: ExtensionRequestedTabLoadResolver
    let runtimeMutationRegistry: ExtensionRuntimeMutationRegistry
    let contextLoadRegistry: ExtensionContextLoadRegistry
    let storageCleanupPlanner: WebExtensionStorageCleanupPlanner
    let backgroundRuntimeState: ExtensionBackgroundRuntimeStateOwner
}

/// Factory-only state roots for action, popup, toolbar and site-access UI.
@available(macOS 15.5, *)
@MainActor
struct ExtensionActionGraphFoundation {
    let toolbarPinning: ExtensionToolbarPinningOwner
    let hubOrdering: ExtensionHubOrderingOwner
    let permissionDecisions: ExtensionPermissionDecisionStore
    let siteAccessPolicyStore: SafariExtensionSiteAccessPolicyStore
    let surfacePublication: ExtensionManagerSurfacePublication
    let actionAnchors: ExtensionActionAnchorStore
    let actionPopupAnchors: ExtensionActionPopupAnchorStore
    let actionPopupInvocations: ExtensionActionPopupInvocationLedger
    let actionPopupSessions: ExtensionActionPopupSessionLedger
    let optionsWindows: ExtensionOptionsWindowService
    let adapterStore: ExtensionBrowserAdapterStore
    #if DEBUG
        let debugSignals = ExtensionManagerDebugSignals()
    #endif
}

/// Factory-only controller resources.
@available(macOS 15.5, *)
@MainActor
struct ExtensionControllerGraphFoundation {
    let browserConfiguration: BrowserConfiguration
    let nativeMessagingPorts: ExtensionNativeMessagingPortRegistry
    let profileWebExtensionRuntime: SumiProfileWebExtensionRuntime
}

/// Factory-only, role-specific views over the single browser attachment
/// authority. No graph value or attached capability aggregate crosses the
/// assembler boundary.
@available(macOS 15.5, *)
@MainActor
struct ExtensionManagerBrowserFoundation {
    let attachment: ExtensionBrowserAttachmentAuthority
    let action: ExtensionBrowserAttachmentAuthority.ActionBrowserProjection
    let events: ExtensionBrowserAttachmentAuthority.BrowserEvents
    let websiteData:
        ExtensionBrowserAttachmentAuthority.WebsiteDataAdmission
    let reloads: ExtensionBrowserAttachmentAuthority.Reloads
    let retirement: ExtensionBrowserAttachmentAuthority.Retirement
}

/// Complete assembly input has six bounded, responsibility-shaped roots. No
/// runtime consumer retains this value or any of its subvalues.
@available(macOS 15.5, *)
@MainActor
struct ExtensionManagerAssemblyFoundation {
    let installation: ExtensionInstallationGraphFoundation
    let runtime: ExtensionRuntimeAuthorityFoundation
    let contexts: ExtensionContextGraphFoundation
    let actions: ExtensionActionGraphFoundation
    let controller: ExtensionControllerGraphFoundation
    let browser: ExtensionManagerBrowserFoundation
}

/// Ephemeral controller assembly product. Exact roles are distributed to their
/// consumers once; only `lifetime` enters the final controller graph.
@available(macOS 15.5, *)
@MainActor
struct ExtensionControllerAssemblyProduct {
    let lifetime: ExtensionControllerLifetimeOwner
    let provisioning: ExtensionControllerProvisioningOwner
    let delegateBridge: ExtensionControllerDelegateBridge
    let callbackAdmission: ExtensionControllerCallbackAdmission
    let browserCallbacks:
        ExtensionBrowserAttachmentAuthority.ControllerCallbacks
    let permissionPreludes:
        ExtensionPermissionsOriginsCompatibilityPreludeInstallationOwner
    let nativeMessagingSessions: ExtensionNativeMessagingSessionControl
}

/// Ephemeral context assembly product. Private authorities stay behind the
/// owner; only terminal roles needed by root consumers cross this boundary.
@available(macOS 15.5, *)
@MainActor
struct ExtensionContextLifecycleAssemblyProduct {
    let runtimeLifetime: ExtensionContextRuntimeLifetime
    let transactionLifetime: ExtensionContextTransactionResidenceOwner
    let publicationLifetime: ExtensionContextPublicationLifetime
    let runtimeDemand: ExtensionRuntimeDemandCoordinator
    let contextPublications: ExtensionContextPublicationQuery
    let profileTransition: ExtensionProfileRuntimeTransition
    let contextResidency: ExtensionContextResidencyOwner
    let websiteDataQuiescence: ExtensionWebsiteDataRuntimeQuiescence
}

/// Ephemeral normal-tab assembly product.
@available(macOS 15.5, *)
@MainActor
struct ExtensionNormalTabAssemblyProduct {
    let preparationLifetime: ExtensionNormalTabPreparationLifetime
    let publicationLifetime: ExtensionNormalTabPublicationLifetime
    let configurationPreparation: ExtensionWebViewConfigurationPreparation
    let deferredRuntimeOwners: ExtensionDeferredRuntimeOwnerStore
    let publicationEvidence: ExtensionRuntimePublicationEvidenceIssuer
    let lifecycle: ExtensionBrowserAttachmentAuthority.NormalTabLifecycle
    let requestedTabs: ExtensionBrowserAttachmentAuthority.RequestedTabs
    let query: ExtensionBrowserAttachmentAuthority.NormalTabQuery
}

/// Terminal action roles consumed by browser chrome and module surfaces.
@available(macOS 15.5, *)
@MainActor
struct ExtensionActionSurfaceAssemblyProduct {
    let publisher: ExtensionActionSurfacePublisher
    let invocation: ExtensionActionInvocationService
    let toolbarPinning: ExtensionToolbarPinningOwner
    let hubOrdering: ExtensionHubOrderingOwner
    let siteAccess: ExtensionSiteAccessPolicyCoordinator
}

/// Terminal popup and command roles installed into browser-bound routes.
@available(macOS 15.5, *)
@MainActor
struct ExtensionActionPresentationAssemblyProduct {
    let popupCallbackAdmission: ExtensionActionPopupCallbackAdmission
    let popupCoordinator: ExtensionActionPopupCoordinator
    let popupAnchorResolver: ExtensionActionPopupAnchorResolver
    let keyboardCommands: ExtensionKeyboardCommandDispatchOwner
}

/// Ephemeral action/UI assembly product.
@available(macOS 15.5, *)
@MainActor
struct ExtensionActionUIAssemblyProduct {
    let surfaceLifetime: ExtensionActionSurfaceResidenceOwner
    let policyLifetime: ExtensionActionPolicyResidenceOwner
    let popupLifetime: ExtensionActionPopupResidenceOwner
    let presentationLifetime: ExtensionActionPresentationResidenceOwner
    let surface: ExtensionActionSurfaceAssemblyProduct
    let presentation: ExtensionActionPresentationAssemblyProduct
}

/// Ephemeral installation/retirement assembly product.
@available(macOS 15.5, *)
@MainActor
struct ExtensionInstallationRetirementAssemblyProduct {
    let lifetime: ExtensionInstallationRetirementLifetimeOwner
    let catalog: InstalledExtensionCatalog
    let lifecycle: InstalledExtensionLifecycleService
    let installer: ExtensionInstallationService
    let runtimeTermination: ExtensionRuntimeTermination
}

/// Complete ephemeral output of the internal subsystem assembly stage. No
/// runtime consumer accepts this aggregate or any assembly product.
@available(macOS 15.5, *)
@MainActor
struct ExtensionManagerAssemblyResult {
    let profileWarmup: ExtensionProfileRuntimeWarmup
    let controller: ExtensionControllerAssemblyProduct
    let contexts: ExtensionContextLifecycleAssemblyProduct
    let normalTabs: ExtensionNormalTabAssemblyProduct
    let actions: ExtensionActionUIAssemblyProduct
    let installation: ExtensionInstallationRetirementAssemblyProduct
}
