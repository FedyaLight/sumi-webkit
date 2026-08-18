#if DEBUG
import Foundation
import WebKit

    /// Explicit white-box test seam assembled alongside the production root.
    /// `ExtensionManager` never retains this value; a test that needs internal
    /// roles must capture the bounded group it exercises.
@available(macOS 15.5, *)
@MainActor
struct ExtensionManagerTestInspection {
        typealias DidAssemble = @MainActor (Self) -> Void

        let controller: ControllerRoles
        let contextState: ContextStateRoles
        let runtimeAuthorities: RuntimeAuthorityRoles
        let contextCoordination: ContextCoordinationRoles
        let normalTabs: NormalTabRoles
        let actionSurfaces: ActionSurfaceRoles
        let actionPolicy: ActionPolicyRoles
        let popups: PopupRoles
        let installation: InstallationRoles
        let retirement: RetirementRoles
        let nativeMessaging: NativeMessagingRoles
        let browserPublication: BrowserPublicationRoles

        struct ControllerRoles {
            let browserConfiguration: BrowserConfiguration
            let provisioning: ExtensionControllerProvisioningOwner
            let delegateBridge: ExtensionControllerDelegateBridge
            let callbackAdmission: ExtensionControllerCallbackAdmission
            let delegateReadiness: ExtensionControllerDelegateReadiness
            let permissionPreludes:
                ExtensionPermissionsOriginsCompatibilityPreludeInstallationOwner
        }

        struct ContextStateRoles {
            let profiles: ExtensionProfileRuntime
            let profileState: ExtensionProfileRuntimeStateOwner
            let publications: ExtensionContextPublicationQuery
            let loadedContexts: ExtensionLoadedContextAuthority
            let errors: ExtensionContextErrorObservation
            let background: ExtensionBackgroundRuntimeStateOwner
            let sourceCache: WebExtensionRuntimeSourceCache
            let retirement: ExtensionContextRetirement
        }

        struct RuntimeAuthorityRoles {
            let lifecycle: ExtensionRuntimeLifecycleAuthority
            let demand: ExtensionRuntimeDemandAuthority
            let loadStatus: ExtensionRuntimeLoadStatusAuthority
            let catalog: ExtensionRuntimeCatalog
            let residency: ExtensionRuntimeResidencyAuthority
            let metrics: ExtensionRuntimeMetricsAuthority
            let loadRevisions: ExtensionLoadRevisionAuthority
            let tabPublicationRevisions:
                ExtensionTabPublicationRevisionAuthority
        }

        struct ContextCoordinationRoles {
            let mutations: ExtensionRuntimeMutationRegistry
            let loads: ExtensionContextLoadRegistry
            let demand: ExtensionRuntimeDemandCoordinator
            let profileTransition: ExtensionProfileRuntimeTransition
            let profileWarmup: ExtensionProfileRuntimeWarmup
            let residency: ExtensionContextResidencyOwner
            let loader: ExtensionRuntimeLoader
            let diagnostics: ExtensionRuntimeDiagnostics
            let runtimeAccess: ExtensionRuntimeAccess
        }

        struct NormalTabRoles {
            let configuration: ExtensionWebViewConfigurationPreparation
            let deferredRuntime: ExtensionDeferredRuntimeOwnerStore
            let recentRequests: ExtensionRecentTabRequestHistory
            let loadResolver: ExtensionRequestedTabLoadResolver
            let adapters: ExtensionBrowserAdapterStore
            let publicationEvidence:
                ExtensionRuntimePublicationEvidenceIssuer
            let requestedTabs:
                ExtensionBrowserAttachmentAuthority.RequestedTabs
        }

        struct ActionSurfaceRoles {
            let installedExtensions: InstalledExtensionCollection
            let publication: ExtensionManagerSurfacePublication
            let publisher: ExtensionActionSurfacePublisher
            let invocation: ExtensionActionInvocationService
            let toolbarPinning: ExtensionToolbarPinningOwner
            let hubOrdering: ExtensionHubOrderingOwner
            let keyboardCommands: ExtensionKeyboardCommandDispatchOwner
            let optionsWindows: ExtensionOptionsWindowService
        }

        struct ActionPolicyRoles {
            let store: SafariExtensionSiteAccessPolicyStore
            let siteAccess: ExtensionSiteAccessPolicyCoordinator
            let permissionDecisions: ExtensionPermissionDecisionStore
            let permissionPrompt: ExtensionPermissionPromptPresenter
            let contextPreparation: ExtensionContextPreparation
            let popupFailureDiagnostics:
                ExtensionActionPopupFailureDiagnostics
        }

        struct PopupRoles {
            let actionAnchors: ExtensionActionAnchorStore
            let anchors: ExtensionActionPopupAnchorStore
            let invocations: ExtensionActionPopupInvocationLedger
            let sessions: ExtensionActionPopupSessionLedger
            let callbackAdmission: ExtensionActionPopupCallbackAdmission
            let coordinator: ExtensionActionPopupCoordinator
            let anchorResolver: ExtensionActionPopupAnchorResolver
            let runtimeRetirement: ExtensionActionPopupRuntimeRetirement
        }

        struct InstallationRoles {
            let metadata: ExtensionInstallationMetadataStore
            let catalog: InstalledExtensionCatalog
            let lifecycle: InstalledExtensionLifecycleService
            let installer: ExtensionInstallationService
            let runtimeActivation: ExtensionInstallRuntimeActivator
            let storageCleanup: WebExtensionStorageCleanupOwner
        }

        struct RetirementRoles {
            let scoped: ExtensionScopedRuntimeRetirement
            let runtime: ExtensionRuntimeRetirement
            let rollback: ExtensionRuntimeRollback
            let activityCancellation: ExtensionRuntimeActivityCancellation
            let bookkeepingReset: ExtensionRuntimeBookkeepingReset
            let controllerRelease: ExtensionControllerRuntimeRelease
            let shutdown: ExtensionRuntimeShutdown
            let termination: ExtensionRuntimeTermination
        }

        struct NativeMessagingRoles {
            let ports: ExtensionNativeMessagingPortRegistry
            let owners: ExtensionDemandScopedNativeMessagingOwners
            let backgroundWakes: ExtensionBackgroundWakeCoordinator
            let messageSettlement: ExtensionNativeMessageSendSettlement
            let portSettlement: ExtensionNativePortConnectionSettlement
            let sessions: ExtensionNativeMessagingSessionControl

            @MainActor
            var loadedRelay: SumiNativeMessagingRelay? {
                var relay: SumiNativeMessagingRelay?
                owners.withLoadedRelayOwner { relay = $0.loadedRelay }
                return relay
            }

            @MainActor
            var hasLoadedWakeOwner: Bool {
                var isLoaded = false
                owners.withLoadedWakeOwner { _ in isLoaded = true }
                return isLoaded
            }
        }

        struct BrowserPublicationRoles {
            let attachment: ExtensionBrowserAttachmentAuthority
            let events: ExtensionBrowserAttachmentAuthority.BrowserEvents
            let reloads: ExtensionBrowserAttachmentAuthority.Reloads
        }
}
#endif
