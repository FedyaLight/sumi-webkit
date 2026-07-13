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
    static let safariWebExtensionURLScheme = "safari-web-extension"
    static let registerSafariWebExtensionURLScheme: Void = {
        WKWebExtension.MatchPattern.registerCustomURLScheme(
            safariWebExtensionURLScheme
        )
    }()
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
    @Published var isPopupActive = false
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

    struct WebExtensionRuntimeSourceKey: Equatable {
        let sourceKind: WebExtensionSourceKind
        let sourceBundlePath: String
        let packageRootPath: String
    }

    enum ExtensionRuntimeState: String, Codable, CaseIterable {
        case idle
        case loading
        case ready
        case unavailable
        case failed
    }

    enum ExtensionRuntimeRequestReason: String, Codable, CaseIterable {
        case attach
        case webViewConfiguration
        case install
        case enable
        case refresh
        case extensionAction
        case resetReload
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
    lazy var requestedTabWebViewMaterializer =
        ExtensionRequestedTabWebViewMaterializer(
            browserContext: { [weak self] in self?.extensionWebViewHosting },
            profileRuntime: profileRuntime,
            runtime: { [weak self] in self?.runtime ?? .inactive },
            runtimePreparation: webViewRuntimePreparationOwner,
            controllerBinding: controllerAttachmentOwner
        )
    lazy var extensionCreatedTabRegistrar = ExtensionCreatedTabRuntimeRegistrar(
        runtimeSession: runtimeSession,
        profileRuntime: profileRuntime,
        adapterStore: adapterStore,
        controllerBinding: controllerAttachmentOwner,
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
            controllerQuery: controllerAttachmentOwner,
            controllerAttachment: controllerAttachmentOwner,
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
    lazy var extensionRuntimeLoader = ExtensionRuntimeLoader(
        environment: .makeLive(manager: self)
    )
    lazy var installedExtensionLifecycle = InstalledExtensionLifecycleService(
        environment: .makeLive(manager: self)
    )
    lazy var extensionInstaller = ExtensionInstallationService(
        environment: .makeLive(manager: self)
    )
    lazy var actionPopupAnchorResolver = ExtensionActionPopupAnchorResolver(
        manager: self
    )
    lazy var actionPopupFailureDiagnostics = ExtensionActionPopupFailureDiagnostics(
        manager: self
    )
    lazy var actionSurfacePublisher = ExtensionActionSurfacePublisher(
        manager: self
    )
    lazy var runtimeBundle = ExtensionRuntimeBundle(manager: self)

    lazy var toolbarPinningOwner = ExtensionToolbarPinningOwner(
        manager: self
    )
    lazy var hubOrderingOwner = ExtensionHubOrderingOwner(
        preferences: extensionPreferences,
        currentProfileId: { [weak self] in self?.profileRuntime.currentProfileId }
    )
    lazy var permissionDecisionStore = ExtensionPermissionDecisionStore(
        manager: self
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
    lazy var runtimeLifecycleOwner = ExtensionRuntimeLifecycleOwner(
        dependencies: .live(manager: self)
    )
    lazy var adapterCatalog = ExtensionAdapterCatalog(
        manager: self
    )
    lazy var errorObservationOwner = ExtensionErrorObservationOwner(
        manager: self
    )
    lazy var controllerProvisioningOwner = ExtensionControllerProvisioningOwner(
        dependencies: .live(manager: self)
    )
    lazy var runtimeStateResetOwner = ExtensionRuntimeStateResetOwner(
        dependencies: .live(manager: self)
    )
    lazy var contextResidencyOwner = ExtensionContextResidencyOwner(
        dependencies: .live(manager: self)
    )
    lazy var controllerAttachmentOwner = ExtensionControllerAttachmentOwner(
        dependencies: .live(manager: self)
    )
    lazy var tabWebViewResolver = ExtensionTabWebViewResolver(
        profileRuntime: profileRuntime,
        contextPublications: contextPublications,
        controllerAttachment: controllerAttachmentOwner,
        profileID: { [weak self] tab in
            self?.resolvedProfileId(for: tab)
        },
        tabIsCurrent: { [weak self] tab in
            self?.extensionTabQuery?.extensionTab(for: tab.id) === tab
        },
        liveWebView: { [weak self] tab in
            self?.extensionWebViewHosting?.extensionLiveWebView(for: tab)
        }
    )
    lazy var extensionActionInvocation = ExtensionActionInvocationService(
        environment: .makeLive(manager: self)
    )
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
    lazy var webViewRuntimePreparationOwner = ExtensionWebViewRuntimePreparationOwner(
        dependencies: .live(manager: self)
    )
    lazy var actionPopupSessionOwner = ExtensionActionPopupSessionOwner(manager: self)
    lazy var keyboardCommandDispatchOwner = ExtensionKeyboardCommandDispatchOwner(
        manager: self
    )
    lazy var pageContextMenuItemsOwner = ExtensionPageContextMenuItemsOwner(
        manager: self
    )
    let profileRuntime: ExtensionProfileRuntime
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
    let installCapabilityOwner: SafariExtensionInstallCapabilityOwner
    let backgroundRuntimeStateOwner = ExtensionBackgroundRuntimeStateOwner()
    let runtimeTeardownOwner = ExtensionRuntimeTeardownOwner()
    var nativeMessagingBackgroundWakeOwner:
        ExtensionNativeMessagingBackgroundWakeOwner {
        deferredRuntimeOwnerStore.nativeMessagingBackgroundWakeOwner
    }
    var loadedNativeMessagingBackgroundWakeOwner:
        ExtensionNativeMessagingBackgroundWakeOwner? {
        deferredRuntimeOwnerStore.loadedNativeMessagingBackgroundWakeOwner
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
        self.installationMetadataStore = ExtensionInstallationMetadataStore(
            context: context
        )
        self.siteAccessPolicyStore = SafariExtensionSiteAccessPolicyStore(
            preferences: extensionPreferences
        )
        self.profileRuntime = ExtensionProfileRuntime(
            initialProfileId: initialProfile?.id
        )
        let storageCleanupPlanner = WebExtensionStorageCleanupPlanner()
        self.webExtensionStorageCleanupPlanner = storageCleanupPlanner
        self.installCapabilityOwner = SafariExtensionInstallCapabilityOwner(
            storageCleanupPlanner: storageCleanupPlanner
        )
        super.init()
        installedExtensionCollection.connectRecordChanges { [weak self] in
            self?.toolbarPinningOwner.reconcilePinnedToolbarExtensions()
        }
        toolbarPinningOwner.reloadPinnedToolbarExtensionsForCurrentProfile()
        SafariExtensionAutofillFillDiagnostics.deferredFillCompletionHandler = {
            [weak self] extensionId in
            guard let extensionId else { return }
            self?.actionPopupSessionOwner.completeDeferredContextUnload(
                forExtensionId: extensionId,
                reason: "relaySucceeded"
            )
        }

        // The deinit teardown path reaches these owners; forming their weak
        // captures during deallocation traps, so they must exist up front.
        _ = errorObservationOwner
        _ = controllerProvisioningOwner
        _ = runtimeStateResetOwner
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

        tearDownExtensionRuntime(
            reason: "deinit",
            removeUIState: true,
            releaseController: true
        )
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

    func refreshActionSurfaceStateForCurrentProfile() {
        guard let profileId = profileRuntime.currentProfileId else { return }
        for (extensionId, context) in extensionContexts(for: profileId) {
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

    #if DEBUG
        struct TestHooks {
            var beforePersistInstalledRecord: ((InstalledExtension) throws -> Void)?
            var beforeControllerLoad:
                ((String, ExtensionManager.WebExtensionStorageSnapshot) throws -> Void)?
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
