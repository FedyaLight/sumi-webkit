import Foundation

/// Ephemeral root-assembly result. It exists only between the stateless
/// assembler and `ExtensionManager.init`; consumers never receive it.
@available(macOS 15.5, *)
@MainActor
struct ExtensionManagerRootGraphs {
    let controller: ExtensionControllerGraph
    let contexts: ExtensionContextLifecycleGraph
    let normalTabs: ExtensionNormalTabGraph
    let runtimePublication: ExtensionRuntimePublicationGraph
    let actions: ExtensionActionUIGraph
    let installation: ExtensionInstallationRetirementGraph
}

/// The sole construction site for the six manager-owned immutable graphs.
/// All cyclic WebKit callbacks are closed in locals before any graph is
/// returned, so `ExtensionManager` never enters a partially assembled state.
@available(macOS 15.5, *)
@MainActor
enum ExtensionManagerRootAssembler {
    static func assemble(
        database: SumiDatabase,
        initialProfile: Profile?,
        browserConfiguration: BrowserConfiguration,
        moduleRegistry: SumiModuleRegistry,
        extensionPreferences: UserDefaults,
        profileReferenceAdmission: ProfileReferenceAdmissionLedger,
        assemblySeams: ExtensionManagerAssemblySeams
    ) -> ExtensionManagerRootGraphs {
        let runtimeLoadStatus = ExtensionRuntimeLoadStatusAuthority()
        let surface = ExtensionManagerSurfacePublication(
            runtimeLoadStatus: runtimeLoadStatus
        )
        let packageGenerations = ExtensionPackageGenerationRegistry()
        let metadataStore = ExtensionInstallationMetadataStore(
            database: database,
            activePackageGenerations: packageGenerations
        )
        let siteAccessStore = SafariExtensionSiteAccessPolicyStore(
            database: database
        )
        let profileRuntime = ExtensionProfileRuntime(
            initialProfileId: initialProfile?.id,
            initialProfile: initialProfile,
            profileReferenceAdmission: profileReferenceAdmission
        )
        let diagnostics = ExtensionRuntimeDiagnostics()
        let loadRevisions = ExtensionLoadRevisionAuthority()
        #if DEBUG
            let browserAttachment = ExtensionBrowserAttachmentAuthority(
                didInstall: assemblySeams.attachedRuntimeDidInstall
            )
        #else
            let browserAttachment = ExtensionBrowserAttachmentAuthority()
        #endif
        let browserEvents = ExtensionBrowserAttachmentAuthority.BrowserEvents(
            attachment: browserAttachment,
            runtimeLoadStatus: runtimeLoadStatus,
            profileRuntime: profileRuntime,
            extensionLoadRevisions: loadRevisions,
            diagnostics: diagnostics
        )
        let publicationReloads = ExtensionBrowserAttachmentAuthority.Reloads(
            attachment: browserAttachment,
            runtimeLoadStatus: runtimeLoadStatus,
            browserEvents: browserEvents
        )
        let actionBrowser =
            ExtensionBrowserAttachmentAuthority.ActionBrowserProjection(
                attachment: browserAttachment,
                profileRuntime: profileRuntime
            )
        let storagePlanner = WebExtensionStorageCleanupPlanner()
        let recentTabRequests = ExtensionRecentTabRequestHistory()
        let requestedTabLoadResolver = ExtensionRequestedTabLoadResolver()
        let installedExtensions = InstalledExtensionCollection()
        let toolbarPinning = ExtensionToolbarPinningOwner(
            database: database,
            currentProfileId: { [profileRuntime] in
                profileRuntime.currentProfileId
            },
            installedExtensionIDs: { [installedExtensions] in
                Set(installedExtensions.records.map(\.id))
            },
            publishedPinnedIDs: { [surface] in
                surface.pinnedToolbarExtensionIDs
            },
            setPublishedPinnedIDs: { [surface] ids in
                surface.replacePinnedToolbarExtensionIDs(ids)
            }
        )
        let hubOrdering = ExtensionHubOrderingOwner(
            database: database
        )
        let permissionDecisions = ExtensionPermissionDecisionStore(
            database: database,
            profileRuntime: profileRuntime
        )
        let mutationRegistry = ExtensionRuntimeMutationRegistry()
        let loadRegistry = ExtensionContextLoadRegistry()
        let runtimeLifecycle = ExtensionRuntimeLifecycleAuthority()
        let runtimeDemand = ExtensionRuntimeDemandAuthority()
        let runtimeCatalog = ExtensionRuntimeCatalog()
        let runtimeResidency = ExtensionRuntimeResidencyAuthority()
        let runtimeMetrics = ExtensionRuntimeMetricsAuthority()
        let tabRevisions = ExtensionTabPublicationRevisionAuthority()
        let backgroundState = ExtensionBackgroundRuntimeStateOwner()
        let actionAnchors = ExtensionActionAnchorStore()
        let popupAnchors = ExtensionActionPopupAnchorStore()
        let popupInvocations = ExtensionActionPopupInvocationLedger()
        let popupSessions = ExtensionActionPopupSessionLedger()
        let optionsWindows = ExtensionOptionsWindowService()
        let adapterStore = ExtensionBrowserAdapterStore()
        let nativePorts = ExtensionNativeMessagingPortRegistry()

        let actionFoundation = ExtensionActionGraphFoundation(
            toolbarPinning: toolbarPinning,
            hubOrdering: hubOrdering,
            permissionDecisions: permissionDecisions,
            siteAccessPolicyStore: siteAccessStore,
            surfacePublication: surface,
            actionAnchors: actionAnchors,
            actionPopupAnchors: popupAnchors,
            actionPopupInvocations: popupInvocations,
            actionPopupSessions: popupSessions,
            optionsWindows: optionsWindows,
            adapterStore: adapterStore
        )
        let foundation = ExtensionManagerAssemblyFoundation(
                installation: ExtensionInstallationGraphFoundation(
                    database: database,
                    activePackageGenerations: packageGenerations,
                    metadataStore: metadataStore
                ),
                runtime: ExtensionRuntimeAuthorityFoundation(
                    profileRuntime: profileRuntime,
                    lifecycle: runtimeLifecycle,
                    demand: runtimeDemand,
                    loadStatus: runtimeLoadStatus,
                    catalog: runtimeCatalog,
                    residency: runtimeResidency,
                    metrics: runtimeMetrics,
                    loadRevisions: loadRevisions,
                    tabPublicationRevisions: tabRevisions,
                    diagnostics: diagnostics
                ),
                contexts: ExtensionContextGraphFoundation(
                    moduleRegistry: moduleRegistry,
                    safariExtensionImportStore: SafariExtensionImportStore(
                        database: database
                    ),
                    installedExtensions: installedExtensions,
                    recentTabRequests: recentTabRequests,
                    requestedTabLoadResolver: requestedTabLoadResolver,
                    runtimeMutationRegistry: mutationRegistry,
                    contextLoadRegistry: loadRegistry,
                    storageCleanupPlanner: storagePlanner,
                    backgroundRuntimeState: backgroundState
                ),
                actions: actionFoundation,
                controller: ExtensionControllerGraphFoundation(
                    browserConfiguration: browserConfiguration,
                    nativeMessagingPorts: nativePorts
                ),
                browser: ExtensionManagerBrowserFoundation(
                    attachment: browserAttachment,
                    action: actionBrowser,
                    events: browserEvents,
                    websiteData:
                        ExtensionBrowserAttachmentAuthority
                        .WebsiteDataAdmission(
                            attachment: browserAttachment
                        ),
                    reloads: publicationReloads,
                    retirement:
                        ExtensionBrowserAttachmentAuthority.Retirement(
                            attachment: browserAttachment
                    )
                )
            )
        #if DEBUG
            let assembled = ExtensionManagerAssembler.assemble(
                foundation,
                testInspectionDidAssemble:
                    assemblySeams.inspectionDidAssemble,
                testAssemblyOverrides: assemblySeams.assemblyOverrides
            )
        #else
            let assembled = ExtensionManagerAssembler.assemble(foundation)
        #endif
        return ExtensionManagerGraphFinalizer.finalize(
            foundation,
            assembled: assembled
        )
    }
}
