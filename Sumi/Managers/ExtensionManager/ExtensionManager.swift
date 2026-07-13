//
//  ExtensionManager.swift
//  Sumi
//
//  WebExtension runtime rebuilt on top of native WebKit APIs.
//

import AppKit
import Combine
import Foundation
import OSLog
import SwiftData
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionManager: NSObject, ObservableObject {
    static let logger = Logger.sumi(category: "Extensions")
    static let safariWebExtensionURLScheme =
        ExtensionContextPreparation.webExtensionURLScheme
    static let registerSafariWebExtensionURLScheme =
        ExtensionContextPreparation.registerWebExtensionURLScheme
    @Published var actionStatesByExtensionID:
        [String: BrowserExtensionActionSurfaceState] = [:]
    @Published private(set) var isExtensionSupportAvailable =
        ExtensionUtils.isExtensionSupportAvailable
    var extensionsLoaded: Bool {
        get { runtimeSession.extensionsLoaded }
        set {
            guard runtimeSession.extensionsLoaded != newValue else { return }
            objectWillChange.send()
            runtimeSession.extensionsLoaded = newValue
        }
    }
    @Published var pinnedToolbarExtensionIDs: [String] = []

    enum ExtensionBackgroundWakeReason: String, Codable, CaseIterable {
        case startup
        case install
        case enable
        case actionPopup
        case toolbarAction
        case nativeMessaging
    }

    enum BackgroundRuntimeState: String, Codable, CaseIterable {
        case neverLoaded
        case wakeInFlight
        case loaded
        case loadFailed
    }

    struct ExtensionRuntimeMetrics: Codable, Equatable {
        var manifestValidationDuration: TimeInterval = 0
        var webExtensionCreationDuration: TimeInterval = 0
        var contextLoadDuration: TimeInterval = 0
        var backgroundWakeDuration: TimeInterval = 0
        var backgroundWakeCount: Int = 0
        var lastBackgroundWakeReason: ExtensionBackgroundWakeReason?
        var lastBackgroundWakeFailed = false
        var errorUpdateDuration: TimeInterval = 0
    }

    enum ExtensionRuntimeState: String, Codable, CaseIterable {
        case idle
        case loading
        case ready
        case unavailable
        case failed
    }

    enum ExtensionPermissionPromptDecision {
        case allow(expirationDate: Date?)
        case deny
    }

    enum ExtensionPermissionTargetKind: String, Codable {
        case permission
        case matchPattern
    }

    enum ExtensionStoredPermissionState: String, Codable {
        case allowed
        case denied
    }

    struct ExtensionStoredPermissionDecision: Codable, Equatable {
        var profileId: String
        var extensionId: String
        var targetKind: ExtensionPermissionTargetKind
        var target: String
        var state: ExtensionStoredPermissionState
        var expiresAt: Date?
        var updatedAt: Date

        func isExpired(now: Date = Date()) -> Bool {
            guard let expiresAt else { return false }
            return expiresAt <= now
        }
    }

    let context: ModelContext
    let browserConfiguration: BrowserConfiguration
    let moduleRegistry: SumiModuleRegistry
    let activePackageGenerations: ExtensionPackageGenerationRegistry
    let installationMetadataStore: ExtensionInstallationMetadataStore
    let siteAccessPolicyStore: SafariExtensionSiteAccessPolicyStore
    let extensionPreferences: UserDefaults
    let recentExtensionTabRequests = ExtensionRecentTabRequestHistory()
    let requestedTabLoadResolver = ExtensionRequestedTabLoadResolver()
    lazy var requestedTabTargetResolver = ExtensionRequestedTabTargetResolver(
        browserContext: { [weak self] in self?.requestedTabTargetQuery },
        profileRuntime: profileRuntime,
        runtime: { [weak self] in self?.runtime ?? .inactive },
        publications: windowPublications
    )
    lazy var extensionCreatedTabRegistrar = ExtensionCreatedTabRuntimeRegistrar(
        runtimeSession: runtimeSession,
        profileRuntime: profileRuntime,
        adapterStore: adapterStore,
        controllers: existingTabControllers,
        webViews: exactExtensionTabWebViews,
        controllerAdmission: webViewControllerAdmission,
        adapterResolution: adapterCatalog,
        contextLoading: initialDocumentRuntimePreparationOwner,
        publications: windowPublications,
        publicationAdmission: tabPublicationAdmission,
        events: tabLifecycleEvents,
        extensionsLoaded: { [weak self] in self?.extensionsLoaded == true },
        diagnostics: runtimeDiagnostics
    )
    lazy var initialTabPublicationPreparer =
        ExtensionInitialTabPublicationPreparer(
            runtimeSession: runtimeSession,
            profileRuntime: profileRuntime,
            adapterStore: adapterStore,
            controllerQuery: existingTabControllers,
            webViews: exactExtensionTabWebViews,
            controllerAdmission: webViewControllerAdmission,
            adapterResolution: adapterCatalog,
            contextLoading: initialDocumentRuntimePreparationOwner,
            windowPublications: windowPublications,
            events: tabLifecycleEvents,
            extensionsLoaded: {
                [weak self] in self?.extensionsLoaded == true
            },
            diagnostics: runtimeDiagnostics
        )
    lazy var requestedTabContextPreloader =
        ExtensionRequestedTabContextPreloader(
            loadResolver: requestedTabLoadResolver,
            placement: requestedTabTargetResolver,
            profileRuntime: profileRuntime,
            runtime: { [weak self] in self?.runtime ?? .inactive },
            contextLoading: initialDocumentRuntimePreparationOwner
        )
    lazy var requestedTabOpening = ExtensionRequestedTabOpeningService(
        recentRequests: recentExtensionTabRequests,
        loadResolver: requestedTabLoadResolver,
        placement: requestedTabTargetResolver,
        materializer: requestedTabWebViewMaterializer,
        registrar: extensionCreatedTabRegistrar,
        browserContext: { [weak self] in self?.extensionTabMutation },
        profileRuntime: profileRuntime,
        runtime: { [weak self] in self?.runtime ?? .inactive },
        hasTabAdapter: { [weak self] tab in
            self?.adapterCatalog.stableAdapter(for: tab) != nil
        }
    )
    #if DEBUG || SUMI_DIAGNOSTICS
        /// Single long-lived instance: the user-script registry keeps only a
        /// weak reference to the message handler.
        let accountForkDiagnosticsUserScript = SafariExtensionAccountForkDiagnosticsUserScript()
    #endif
    let installedExtensionCollection = InstalledExtensionCollection()
    lazy var installedExtensionCatalog = InstalledExtensionCatalog(
        environment: .makeLive(manager: self)
    )
    lazy var extensionRuntimeAccess = ExtensionRuntimeAccess(
        profileRuntime: profileRuntime,
        controllerProvisioningOwner: controllerProvisioningOwner,
        runtimeSession: runtimeSession,
        runtime: { [weak self] in self?.runtime ?? .inactive }
    )
    lazy var contextControllerTransaction =
        ExtensionContextControllerTransaction(
            authority: loadedContextAuthority,
            profileRuntime: profileRuntime,
            rollback: runtimeRollback,
            errorObservation: contextErrorObservation,
            runtimeSession: runtimeSession,
            diagnostics: runtimeDiagnostics,
            expectedControllerDelegate: controllerDelegateBridge,
            debugBeforeControllerLoad: { [weak self] in
                self?.currentBeforeControllerLoadHook()
            }
        )
    lazy var extensionContextLoader = ExtensionContextLoader(
        authority: loadedContextAuthority,
        profileRuntime: profileRuntime,
        controllerProvisioning: controllerProvisioningOwner,
        waitForWebsiteDataMutationAdmission: { [weak self] profileID in
            guard let self else { return false }
            return await self.runtime.waitForWebsiteDataMutationAdmission(
                profileID
            )
        },
        sourceCache: webExtensionRuntimeSourceCache,
        contextPreparation: contextPreparation,
        storagePlanner: webExtensionStorageCleanupPlanner,
        runtimeSession: runtimeSession,
        diagnostics: runtimeDiagnostics,
        expectedControllerDelegate: controllerDelegateBridge,
        controllerTransaction: contextControllerTransaction
    )
    lazy var installRuntimeActivation = ExtensionInstallRuntimeActivator(
        manager: self
    )
    lazy var loadedContextFinalizer = ExtensionLoadedContextFinalizer(
        authority: loadedContextAuthority,
        actionSurfaces: { [weak self] in self?.actionSurfacePublisher },
        residency: contextResidencyOwner,
        installationActivation: installRuntimeActivation
    )
    lazy var extensionRuntimeLoader = ExtensionRuntimeLoader(
        modelContext: context,
        metadataStore: installationMetadataStore,
        installedRecords: installedExtensionCollection,
        runtimeAccess: extensionRuntimeAccess,
        authority: loadedContextAuthority,
        rollback: runtimeRollback,
        contextLoader: extensionContextLoader,
        finalizer: loadedContextFinalizer,
        diagnostics: runtimeDiagnostics
    )
    lazy var installationRuntimeActivation =
        ExtensionInstallationRuntimeActivation(
            runtimeAccess: extensionRuntimeAccess,
            authority: loadedContextAuthority,
            rollback: runtimeRollback,
            contextLoader: extensionContextLoader,
            activation: installRuntimeActivation,
            residency: contextResidencyOwner
        )
    lazy var enabledRuntimeActivation = ExtensionEnabledRuntimeActivation(
        runtimeAccess: extensionRuntimeAccess,
        authority: loadedContextAuthority,
        loader: extensionRuntimeLoader,
        finalizer: loadedContextFinalizer
    )
    lazy var runtimeRecovery = ExtensionRuntimeRecovery(
        activation: enabledRuntimeActivation
    )
    lazy var runtimeRetirement = ExtensionRuntimeRetirement(
        scopedRetirement: scopedRuntimeRetirement,
        actionSurfaces: { [weak self] in self?.actionSurfacePublisher },
        resources: { [weak self] in
            self?.scopedRuntimeRetirementResources
                ?? .init(
                    auxiliaryWindows: nil,
                    nativeMessagingWakes: nil,
                    nativeMessagingRelay: nil
            )
        }
    )
    lazy var runtimeRollback = ExtensionRuntimeRollback(
        authority: loadedContextAuthority,
        retirement: runtimeRetirement
    )
    lazy var installedExtensionLifecycle = InstalledExtensionLifecycleService(
        environment: .makeLive(manager: self)
    )
    lazy var extensionInstaller = ExtensionInstallationService.makeLive(
        manager: self
    )
    lazy var actionPopupAnchorResolver = makeActionPopupAnchorResolver()
    lazy var actionPopupFailureDiagnostics = ExtensionActionPopupFailureDiagnostics(
        manager: self
    )
    lazy var actionSurfacePublisher = ExtensionActionSurfacePublisher(
        manager: self
    )
    lazy var windowVisibilityResolver =
        ExtensionWindowVisibilityResolver(manager: self)
    lazy var siteAccessPolicyCoordinator =
        ExtensionSiteAccessPolicyCoordinator(manager: self)
    lazy var backgroundWakeCoordinator =
        ExtensionBackgroundWakeCoordinator(manager: self)
    lazy var extensionWindowRequestRouter =
        ExtensionWindowRequestRouter(manager: self)

    lazy var toolbarPinningOwner = ExtensionToolbarPinningOwner(
        manager: self
    )
    lazy var hubOrderingOwner = ExtensionHubOrderingOwner(
        preferences: extensionPreferences,
        currentProfileId: { [weak self] in self?.profileRuntime.currentProfileId }
    )
    lazy var permissionDecisionStore = ExtensionPermissionDecisionStore(
        preferences: extensionPreferences,
        profileRuntime: profileRuntime
    )
    lazy var contextPreparation = ExtensionContextPreparation(
        siteAccessPolicyStore: siteAccessPolicyStore,
        installedExtensions: installedExtensionCollection,
        permissionDecisions: permissionDecisionStore,
        siteAccessPolicyDidPersist: { [weak self] in
            guard let self else { return }
            NotificationCenter.default.post(
                name: .sumiExtensionSiteAccessPoliciesDidChange,
                object: self
            )
        }
    )
    lazy var pageResolutionOwner = ExtensionPageResolutionOwner(
        manager: self
    )
    lazy var pageNavigationPreparationOwner =
        ExtensionPageNavigationPreparationOwner()
    var runtimePublicationComposition:
        ExtensionRuntimePublicationComposition?
    var normalTabRuntimeComposition:
        ExtensionNormalTabRuntimeComposition?
    var controllerRuntimeComposition:
        ExtensionControllerRuntimeComposition?
    lazy var runtimeDemandCoordinator = ExtensionRuntimeDemandCoordinator(
        installedExtensions: installedExtensionCollection,
        profileRuntime: profileRuntime,
        runtimeSession: runtimeSession,
        controllerProvisioning: controllerProvisioningOwner,
        runtimeProfileID: { [weak self] in
            self?.runtime.currentProfile()?.id
        },
        extensionSupportAvailable: isExtensionSupportAvailable,
        diagnostics: runtimeDiagnostics
    )
    lazy var profileRuntimeTransition = ExtensionProfileRuntimeTransition(
        installedExtensions: installedExtensionCollection,
        profileRuntime: profileRuntime,
        runtimeSession: runtimeSession,
        browserConfiguration: browserConfiguration,
        controllerProvisioning: controllerProvisioningOwner,
        inactiveContextRetirement: contextResidencyOwner,
        actionAnchors: actionPopupAnchorStore,
        toolbarProfiles: toolbarPinningOwner,
        extensionSupportAvailable: isExtensionSupportAvailable,
        reconcileProfile: { [weak self] profileID in
            self?.controllerRuntimeComposition?.reconciler.reconcile(
                profileID: profileID,
                reason: "ExtensionProfileRuntimeTransition"
            )
        },
        refreshActionSurfaces: { [weak self] profileID in
            self?.refreshActionSurfaceState(for: profileID)
        }
    )
    lazy var adapterCatalog = ExtensionAdapterCatalog(
        manager: self
    )
    lazy var contextErrorObservation = ExtensionContextErrorObservation(
        recordRuntimeMetric: { [runtimeSession] extensionId, update in
            runtimeSession.recordRuntimeMetric(
                for: extensionId,
                update: update
            )
        },
        trace: { [runtimeDiagnostics] message in
            runtimeDiagnostics.trace(message)
        }
    )
    lazy var contextRetirement = ExtensionContextRetirement(
        profileRuntime: profileRuntime,
        backgroundRuntimeState: backgroundRuntimeStateOwner,
        runtimeSession: runtimeSession,
        errorObservation: contextErrorObservation,
        diagnostics: runtimeDiagnostics,
        actionPopups: actionPopupRuntimeRetirement
    )
    lazy var contextLoadAdmission = ExtensionContextLoadAdmission(
        mutationRegistry: runtimeMutationRegistry,
        loadRegistry: contextLoadRegistry
    )
    lazy var loadedContextAuthority = ExtensionLoadedContextAuthority(
        profileRuntime: profileRuntime,
        admission: contextLoadAdmission,
        contextRetirement: contextRetirement
    )
    lazy var webExtensionRuntimeSourceCache =
        WebExtensionRuntimeSourceCache(admission: contextLoadAdmission)
    lazy var scopedRuntimeRetirement = ExtensionScopedRuntimeRetirement(
        profileRuntime: profileRuntime,
        mutationRegistry: runtimeMutationRegistry,
        loadRegistry: contextLoadRegistry,
        contextRetirement: contextRetirement,
        runtimeSession: runtimeSession,
        sourceCache: webExtensionRuntimeSourceCache,
        errorObservation: contextErrorObservation,
        nativeMessagingPorts: nativeMessagingPortRegistry,
        optionsWindows: optionsWindows,
        actionAnchors: actionAnchorStore,
        diagnostics: runtimeDiagnostics
    )
    lazy var controllerProvisioningOwner = ExtensionControllerProvisioningOwner(
        dependencies: .live(manager: self)
    )
    lazy var contextResidencyOwner = ExtensionContextResidencyOwner(
        dependencies: .live(manager: self)
    )
    private let unattachedTabWebViewResolver =
        ExtensionUnavailableTabWebViewProjection()

    var tabWebViewResolver: any ExtensionTabWebViewProjectionQuery {
        controllerRuntimeComposition?.tabWebViewResolver
            ?? unattachedTabWebViewResolver
    }

    var extensionTabProfiles: ExtensionTabProfileResolution {
        controllerRuntimeComposition!.profiles
    }
    var existingTabControllers: ExtensionExistingExactTabControllerQuery {
        controllerRuntimeComposition!.controllers
    }
    var exactExtensionTabWebViews: ExtensionExactTabWebViewQuery {
        controllerRuntimeComposition!.webViews
    }
    var webViewControllerAdmission: ExtensionWebViewControllerAdmission {
        controllerRuntimeComposition!.admission
    }
    var webViewControllerMismatch: ExtensionWebViewControllerMismatchQuery {
        controllerRuntimeComposition!.mismatch
    }
    var tabWebViewRuntimeRepair: ExtensionTabWebViewRuntimeRepair {
        controllerRuntimeComposition!.repair
    }
    var profileWebViewRuntimeReconciler:
        ExtensionProfileWebViewRuntimeReconciler {
        controllerRuntimeComposition!.reconciler
    }
    var contextTabCompatibility: ExtensionContextTabCompatibilityQuery {
        controllerRuntimeComposition!.contextCompatibility
    }
    lazy var extensionActionInvocation =
        ExtensionActionInvocationService.live(manager: self)
    lazy var nativeMessageSendSettlement = ExtensionNativeMessageSendSettlement(
        admission: controllerCallbackAdmission
    )
    lazy var nativePortConnectionSettlement =
        ExtensionNativePortConnectionSettlement(
            admission: controllerCallbackAdmission
        )
    private var nativeMessagingRelayOwnerStorage: ExtensionNativeMessagingRelayOwner?
    var nativeMessagingRelayOwner: ExtensionNativeMessagingRelayOwner {
        if let nativeMessagingRelayOwnerStorage {
            return nativeMessagingRelayOwnerStorage
        }
        let relayOwner = ExtensionNativeMessagingRelayOwner(manager: self)
        nativeMessagingRelayOwnerStorage = relayOwner
        return relayOwner
    }
    var loadedNativeMessagingRelayOwner: ExtensionNativeMessagingRelayOwner? {
        nativeMessagingRelayOwnerStorage
    }
    lazy var permissionsOriginsCompatibilityPreludeInstallationOwner =
        ExtensionPermissionsOriginsCompatibilityPreludeInstallationOwner(
            isPrivateUserScriptSPIAvailable: {
                SafariExtensionPermissionsOriginsCompatibility
                    .isPrivateUserScriptSPIAvailable
            },
            preludeTargets: { [weak self] profileId in
                guard let self else { return [] }
                return self.extensionContexts(for: profileId)
                    .map { extensionId, extensionContext in
                        ExtensionPermissionsOriginsCompatibilityPreludeInstallationOwner
                            .PreludeTarget(
                                extensionId: extensionId,
                                isLoaded: extensionContext.isLoaded,
                                baseURL: extensionContext.baseURL,
                                installPrelude: { userContentController in
                                    SafariExtensionPermissionsOriginsCompatibility
                                        .installPrelude(
                                            into: userContentController,
                                            extensionContext: extensionContext
                                        )
                                }
                            )
                    }
            },
            trace: { [weak self] message in
                self?.runtimeDiagnostics.trace(message)
            }
        )
    lazy var deferredRuntimeOwnerStore = ExtensionDeferredRuntimeOwnerStore(manager: self)
    let runtimeDiagnostics = ExtensionRuntimeDiagnostics()
    lazy var controllerDelegateBridge = ExtensionControllerDelegateBridge(manager: self)
    lazy var webViewConfigurationPreparation =
        ExtensionWebViewConfigurationPreparation(
            provisioning: controllerProvisioningOwner,
            preludes:
                permissionsOriginsCompatibilityPreludeInstallationOwner,
            resolveProfileID: { [weak self] explicitProfileID in
                guard let self else { return nil }
                return self.profileRuntime.resolvedProfileId(
                    explicitProfileId: explicitProfileID,
                    runtime: self.runtime
                )
            },
            requestRuntime: { [weak self] profileID in
                _ = self?.runtimeDemandCoordinator.request(
                    reason: .webViewConfiguration,
                    profileId: profileID
                )
            },
            diagnostics: runtimeDiagnostics
        )
    let actionPopupInvocationLedger = ExtensionActionPopupInvocationLedger()
    lazy var actionPopupCallbackAdmission = ExtensionActionPopupCallbackAdmission(
        runtimeBindingAdmission: controllerCallbackAdmission,
        installedExtensions: installedExtensionCollection
    )
    lazy var actionPopupTelemetry = makeActionPopupTelemetry()
    lazy var actionPopupSourceAdmission = makeActionPopupSourceAdmission()
    let actionPopupSessionLedger = ExtensionActionPopupSessionLedger()
    lazy var actionPopupFocusRestorer = ExtensionActionPopupFocusRestorer(
        windows: { [weak self] in self?.extensionWindowQuery },
        liveWebView: { [weak self] tab in
            self?.exactExtensionTabWebViews.liveWebView(for: tab)
        }
    )
    lazy var actionPopupRetirement = ExtensionActionPopupRetirementService(
        sessions: actionPopupSessionLedger,
        focusRestorer: actionPopupFocusRestorer,
        telemetry: actionPopupTelemetry
    )
    lazy var actionPopupCommitRecorder = ExtensionActionPopupCommitRecorder(
        sessions: actionPopupSessionLedger,
        telemetry: actionPopupTelemetry
    )
    lazy var actionPopupCoordinator = makeActionPopupCoordinator()
    lazy var actionPopupRuntimeRetirement = ExtensionActionPopupRuntimeRetirement(
        sessions: actionPopupRetirement,
        invocations: actionPopupInvocationLedger
    )
    lazy var actionPopupBindingRecovery = ExtensionActionPopupBindingRecovery(
        contextRetirement: contextRetirement,
        contextLoading: contextResidencyOwner,
        profileRuntime: profileRuntime
    )
    var isPopupActive: Bool { actionPopupSessionLedger.hasVisibleSession }
    lazy var keyboardCommandDispatchOwner = ExtensionKeyboardCommandDispatchOwner(
        manager: self
    )
    lazy var pageContextMenuItemsOwner = ExtensionPageContextMenuItemsOwner(
        manager: self
    )
    let profileRuntime: ExtensionProfileRuntime
    let runtimeMutationRegistry = ExtensionRuntimeMutationRegistry()
    let contextLoadRegistry = ExtensionContextLoadRegistry()
    lazy var contextPublications = ExtensionContextPublicationQuery(
        profileRuntime: profileRuntime
    )
    var profileRuntimeStateOwner: ExtensionProfileRuntimeStateOwner {
        ExtensionProfileRuntimeStateOwner(manager: self)
    }
    private let controllerIdentifierOwner =
        ExtensionControllerIdentifierOwner()
    var controllerIdentifier: UUID {
        controllerIdentifierOwner.identifier
    }

    weak var extensionWindowQuery: (any ExtensionWindowQuery)?
    weak var attachedBrowserManager: BrowserManager?
    weak var extensionTabQuery: (any ExtensionTabQuery)?
    weak var requestedTabTargetQuery: (any ExtensionTabTargetQuery)?
    weak var extensionTabMutation: (any ExtensionTabMutation)?
    weak var extensionWindowActivation: (any ExtensionWindowActivation)?
    weak var extensionWebViewHosting: (any ExtensionTabWebViewHosting)?
    weak var extensionAuxiliaryWindows: (any ExtensionAuxiliaryWindowControl)?
    weak var extensionWindowPresentation: (any ExtensionWindowPresentation)?
    weak var extensionRequestedWindowCreation:
        (any ExtensionRequestedWindowCreating)?
    var runtime = ExtensionManagerRuntime.inactive
    let runtimeSession = ExtensionRuntimeSession()
    let webExtensionStorageCleanupPlanner: WebExtensionStorageCleanupPlanner
    let backgroundRuntimeStateOwner = ExtensionBackgroundRuntimeStateOwner()
    lazy var runtimeActivityCancellation = ExtensionRuntimeActivityCancellation(
        loadRegistry: contextLoadRegistry,
        backgroundRuntimeState: backgroundRuntimeStateOwner,
        nativeMessagingPorts: nativeMessagingPortRegistry,
        diagnostics: runtimeDiagnostics
    )
    lazy var runtimeBookkeepingReset = ExtensionRuntimeBookkeepingReset(
        runtimeSession: runtimeSession,
        sourceCache: webExtensionRuntimeSourceCache,
        backgroundRuntimeState: backgroundRuntimeStateOwner,
        errorObservation: contextErrorObservation,
        recentTabRequests: recentExtensionTabRequests,
        permissionPreludes:
            permissionsOriginsCompatibilityPreludeInstallationOwner,
        controllerProvisioning: controllerProvisioningOwner,
        adapterStore: adapterStore,
        optionsWindows: optionsWindows,
        actionAnchors: actionAnchorStore,
        actionPopupAnchors: actionPopupAnchorStore,
        actionPopupInvocations: actionPopupInvocationLedger
    )
    lazy var controllerRuntimeRelease = ExtensionControllerRuntimeRelease(
        browserConfiguration: browserConfiguration,
        profileRuntime: profileRuntime,
        runtimeSession: runtimeSession
    )
    lazy var runtimeShutdown = ExtensionRuntimeShutdown(
        activityCancellation: runtimeActivityCancellation,
        mutationRegistry: runtimeMutationRegistry,
        scopedRetirement: scopedRuntimeRetirement,
        bookkeepingReset: runtimeBookkeepingReset,
        controllerRelease: controllerRuntimeRelease,
        profileRuntime: profileRuntime,
        runtimeSession: runtimeSession,
        sourceCache: webExtensionRuntimeSourceCache,
        errorObservation: contextErrorObservation,
        optionsWindows: optionsWindows,
        actionAnchors: actionAnchorStore,
        nativeMessagingPorts: nativeMessagingPortRegistry,
        diagnostics: runtimeDiagnostics
    )
    var nativeMessagingBackgroundWakeOwner:
        ExtensionNativeMessagingBackgroundWakeOwner {
        deferredRuntimeOwnerStore.nativeMessagingBackgroundWakeOwner
    }
    var loadedNativeMessagingBackgroundWakeOwner:
        ExtensionNativeMessagingBackgroundWakeOwner? {
        deferredRuntimeOwnerStore.loadedNativeMessagingBackgroundWakeOwner
    }

    var scopedRuntimeRetirementResources:
        ExtensionScopedRuntimeRetirement.Resources {
        .init(
            auxiliaryWindows: extensionAuxiliaryWindows,
            nativeMessagingWakes: loadedNativeMessagingBackgroundWakeOwner,
            nativeMessagingRelay:
                loadedNativeMessagingRelayOwner?.loadedRelay
        )
    }

    var initialDocumentRuntimePreparationOwner:
        ExtensionInitialDocumentRuntimePreparationOwner {
        deferredRuntimeOwnerStore.initialDocumentRuntimePreparationOwner
    }
    var loadedInitialDocumentRuntimePreparationOwner:
        ExtensionInitialDocumentRuntimePreparationOwner? {
        deferredRuntimeOwnerStore.loadedInitialDocumentRuntimePreparationOwner
    }

    let actionAnchorStore = ExtensionActionAnchorStore()
    let actionPopupAnchorStore = ExtensionActionPopupAnchorStore()
    let optionsWindows = ExtensionOptionsWindowService()
    let adapterStore = ExtensionBrowserAdapterStore()
    let nativeMessagingPortRegistry = ExtensionNativeMessagingPortRegistry()
    let permissionPromptPresenter = ExtensionPermissionPromptPresenter()
    lazy var controllerCallbackAdmission = ExtensionControllerCallbackAdmission(
        profileRuntime: profileRuntime,
        runtimeSession: runtimeSession
    )
    lazy var permissionCallbackSettlement =
        ExtensionPermissionCallbackSettlement(
            admission: controllerCallbackAdmission
        )
    lazy var urlPermissionCallbackSettlement =
        ExtensionURLPermissionCallbackSettlement(
            admission: controllerCallbackAdmission
        )

    nonisolated static let maxLiveExtensionContexts = 8
    init(
        context: ModelContext,
        initialProfile: Profile?,
        browserConfiguration: BrowserConfiguration? = nil,
        moduleRegistry: SumiModuleRegistry = .shared,
        extensionPreferences: UserDefaults = .standard
    ) {
        let signpostState = PerformanceTrace.beginInterval("ExtensionManager.init")
        defer {
            PerformanceTrace.endInterval("ExtensionManager.init", signpostState)
        }

        _ = Self.registerSafariWebExtensionURLScheme
        self.context = context
        self.browserConfiguration = browserConfiguration ?? .shared
        self.moduleRegistry = moduleRegistry
        self.extensionPreferences = extensionPreferences
        let activePackageGenerations = ExtensionPackageGenerationRegistry()
        self.activePackageGenerations = activePackageGenerations
        self.installationMetadataStore = ExtensionInstallationMetadataStore(
            context: context,
            activePackageGenerations: activePackageGenerations
        )
        self.siteAccessPolicyStore = SafariExtensionSiteAccessPolicyStore(
            preferences: extensionPreferences
        )
        self.profileRuntime = ExtensionProfileRuntime(
            initialProfileId: initialProfile?.id
        )
        let storageCleanupPlanner = WebExtensionStorageCleanupPlanner()
        self.webExtensionStorageCleanupPlanner = storageCleanupPlanner
        super.init()
        installedExtensionCollection.connectRecordChanges { [weak self] in
            self?.toolbarPinningOwner.reconcilePinnedToolbarExtensions()
        }
        toolbarPinningOwner.reloadPinnedToolbarExtensionsForCurrentProfile()
        // The deinit teardown path reaches these owners; forming their weak
        // captures during deallocation traps, so they must exist up front.
        _ = contextErrorObservation
        _ = scopedRuntimeRetirement
        _ = runtimeShutdown
        _ = controllerProvisioningOwner
        _ = permissionsOriginsCompatibilityPreludeInstallationOwner
        _ = deferredRuntimeOwnerStore

        guard isExtensionSupportAvailable else {
            extensionsLoaded = true
            runtimeSession.runtimeState = .unavailable
            return
        }

        installedExtensionCatalog.load()
        PerformanceTrace.emitEvent("ExtensionManager.lazyRuntimeDeferred")
    }

    isolated deinit {
        let signpostState = PerformanceTrace.beginInterval("ExtensionManager.deinit")
        defer {
            PerformanceTrace.endInterval("ExtensionManager.deinit", signpostState)
        }

        _ = shutDownExtensionRuntime(reason: "deinit")
        #if DEBUG
            clearDebugState()
        #endif

        controllerIdentifierOwner.removeTestStorageIfNeededForLoadedIdentifier()
    }

    func normalTabUserScripts() -> [SumiUserScript] {
        #if DEBUG || SUMI_DIAGNOSTICS
            [accountForkDiagnosticsUserScript]
        #else
            []
        #endif
    }

    // MARK: - Extension Window Facades

    // MARK: - Action Anchors & Options Windows

    func logExtensionLoadFailure(
        _ error: Error,
        extensionId: String,
        profileId: UUID,
        operation: String
    ) {
        Self.logger.error(
            "Failed to \(operation, privacy: .public) for extension \(extensionId, privacy: .public) profile \(profileId.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
        )
    }

    func logBackgroundWakeFailure(
        _ error: Error,
        extensionContext: WKWebExtensionContext,
        reason: ExtensionBackgroundWakeReason,
        operation: String
    ) {
        let extensionId = extensionID(for: extensionContext) ?? "(unknown)"
        let profileId = profileId(for: extensionContext)?.uuidString ?? "(unknown)"
        Self.logger.error(
            "Failed to \(operation, privacy: .public) for extension \(extensionId, privacy: .public) profile \(profileId, privacy: .public) reason \(reason.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)"
        )
    }

    func extensionsModuleEnabledForRuntimeBoundary() -> Bool {
        switch runtime.extensionsModuleEnabled() {
        case .enabled(let isEnabled):
            return isEnabled
        case .unavailable:
            return true
        }
    }

    func refreshActionSurfaceState(for profileId: UUID) {
        guard profileRuntime.currentProfileId == profileId else { return }
        for (extensionId, context) in extensionContexts(for: profileId) {
            guard profileRuntime.currentProfileId == profileId else { return }
            actionSurfacePublisher.publishActionSurfaceStateForLoadedContext(context)
            _ = extensionId
        }
    }

    nonisolated static var isWebKitRuntimeTraceEnabled: Bool {
        RuntimeDiagnostics.isVerboseEnabled
    }

    nonisolated static var shouldObserveExtensionErrors: Bool {
        RuntimeDiagnostics.isVerboseEnabled
    }

    private func currentBeforeControllerLoadHook()
        -> ExtensionContextControllerTransaction.BeforeControllerLoad? {
        #if DEBUG
            return testHooks.beforeControllerLoad
        #else
            return nil
        #endif
    }

    #if DEBUG
        struct TestHooks {
            var beforePersistInstalledRecord: ((InstalledExtension) throws -> Void)?
            var beforeControllerLoad:
                (@MainActor (
                    String,
                    ExtensionManager.WebExtensionStorageSnapshot
                ) throws -> Void)?
            var backgroundContentWake:
                (@MainActor (String, WKWebExtensionContext) async throws -> Void)?
            var permissionPromptDecision:
                ((WKWebExtensionContext, [String], String) -> ExtensionPermissionPromptDecision)?
            /// Fires exactly at the WebKit `performAction` dispatch boundary
            /// of an admitted action invocation.
            var didDispatchExtensionAction: ((String) -> Void)?
            var webExtensionDataCleanup: (@MainActor (String) async -> Bool)?
            var didOpenTab: ((UUID) -> Void)?
            var didOpenNormalWindow: ((UUID) -> Void)?
            var didDeferOpenTab: ((UUID, String) -> Void)?
            var didCloseTab: ((UUID) -> Void)?
            var didOpenAuxiliaryWindow: ((UUID) -> Void)?
            var didFocusAuxiliaryWindow: ((UUID) -> Void)?
            var didCloseAuxiliaryWindow: ((UUID) -> Void)?
            var didFocusWindow: ((UUID) -> Void)?
            var didActivateTab: ((UUID) -> Void)?
            var didSelectTab: ((UUID) -> Void)?
            var didDeselectTab: ((UUID) -> Void)?
            var didChangeTabProperties:
                ((UUID, WKWebExtension.TabChangedProperties) -> Void)?
        }

        var testHooks: TestHooks {
            get {
                ExtensionManagerDebugRegistry.hooks(for: ObjectIdentifier(self))
            }
            set {
                ExtensionManagerDebugRegistry.setHooks(
                    newValue,
                    for: ObjectIdentifier(self)
                )
            }
        }

        func clearDebugState() {
            ExtensionManagerDebugRegistry.clearHooks(for: ObjectIdentifier(self))
        }

        func dispatchAuxiliaryPublicationDebugEvent(
            _ event: ExtensionAuxiliaryPublicationDebugEvent
        ) {
            switch event {
            case .didOpenWindow(let sessionID):
                testHooks.didOpenAuxiliaryWindow?(sessionID)
            case .didOpenTab(_, let tabID):
                testHooks.didOpenTab?(tabID)
            case .didFocusWindow(let sessionID):
                testHooks.didFocusAuxiliaryWindow?(sessionID)
            case .didCloseTab(_, let tabID):
                testHooks.didCloseTab?(tabID)
            case .didCloseWindow(let sessionID):
                testHooks.didCloseAuxiliaryWindow?(sessionID)
            }
        }

        func dispatchNormalTabLifecycleDebugEvent(
            _ event: ExtensionNormalTabLifecycleDebugEvent
        ) {
            switch event {
            case .didActivateTab(let tabID):
                testHooks.didActivateTab?(tabID)
            case .didSelectTab(let tabID):
                testHooks.didSelectTab?(tabID)
            case .didDeselectTab(let tabID):
                testHooks.didDeselectTab?(tabID)
            }
        }

        func drainExtensionRuntimeTasksForTests() async {
            while true {
                let tasks =
                    (loadedInitialDocumentRuntimePreparationOwner?
                        .runtimeTasksForDrain() ?? [])
                    + (loadedDeferredTabRegistration?
                        .runtimeTasksForDrain() ?? [])
                    + (loadedNativeMessagingBackgroundWakeOwner?
                        .runtimeTasksForDrain() ?? [])
                let didDrainWakeTask = await backgroundRuntimeStateOwner
                    .drainWakeTasksForTests()

                guard tasks.isEmpty == false || didDrainWakeTask else { return }

                for task in tasks {
                    await task.value
                }
            }
        }
    #endif
}

#if DEBUG
    @available(macOS 15.5, *)
    @MainActor
    private final class ExtensionManagerDebugRegistry {
        private static let lock = NSLock()
        private static var hooksByManagerID:
            [ObjectIdentifier: ExtensionManager.TestHooks] = [:]

        static func hooks(for managerID: ObjectIdentifier) -> ExtensionManager.TestHooks {
            lock.lock()
            defer { lock.unlock() }
            return hooksByManagerID[managerID] ?? ExtensionManager.TestHooks()
        }

        static func setHooks(
            _ hooks: ExtensionManager.TestHooks,
            for managerID: ObjectIdentifier
        ) {
            lock.lock()
            hooksByManagerID[managerID] = hooks
            lock.unlock()
        }

        static func clearHooks(for managerID: ObjectIdentifier) {
            lock.lock()
            hooksByManagerID.removeValue(forKey: managerID)
            lock.unlock()
        }
    }
#endif
