import AppKit
import Foundation
import SwiftData
import WebKit

@MainActor
final class SumiExtensionsModule {
    static let shared = SumiExtensionsModule()

    private let moduleRegistry: SumiModuleRegistry
    private let context: ModelContext?
    private let browserConfiguration: BrowserConfiguration
    private let initialProfileProvider: @MainActor () -> Profile?
    private let managerFactory: @MainActor (
        ModelContext,
        Profile?,
        BrowserConfiguration
    ) -> ExtensionManager
    private let chromeMV3EmptyControllerOwnerFactory: @MainActor (
        ChromeMV3ControllerCreationGateDecision,
        WKWebsiteDataStore,
        UUID
    ) -> ChromeMV3EmptyControllerOwner?
    private let chromeMV3PopupOptionsWebViewFactory:
        @MainActor () -> ChromeMV3PopupOptionsWebViewFactory

    let surfaceStore: BrowserExtensionSurfaceStore

    private var cachedManager: ExtensionManager?
    private var cachedChromeMV3EmptyControllerOwner:
        ChromeMV3EmptyControllerOwner?
    private var cachedChromeMV3PopupOptionsHostController:
        ChromeMV3ProductPopupOptionsHostController?
    private var lastChromeMV3PopupOptionsRunResult:
        ChromeMV3ProductPopupOptionsRunResult?
    private let chromeMV3PermissionEventDispatcher =
        ChromeMV3PermissionEventDispatchRegistry()
    #if DEBUG
        private var cachedChromeMV3ExtensionObjectProbeOwner:
            ChromeMV3ExtensionObjectProbeOwner?
        private var cachedChromeMV3DetachedContextOwner:
            ChromeMV3DetachedContextOwner?
        private var cachedChromeMV3ControllerLoadOwner:
            ChromeMV3ControllerLoadOwner?
        private var lastChromeMV3WebKitObjectAcceptanceReport:
            ChromeMV3WebKitObjectAcceptanceReport?
        private var lastChromeMV3ContextReadinessReport:
            ChromeMV3ContextReadinessReport?
        private var lastChromeMV3ContextCreationGateReport:
            ChromeMV3ContextCreationGateReport?
        private var lastChromeMV3ControllerLoadGateReport:
            ChromeMV3ControllerLoadGateReport?
        private var lastChromeMV3RuntimeMinimalSmokeReport:
            ChromeMV3RuntimeMinimalSmokeReport?
        private var lastChromeMV3RuntimeContentScriptSmokeReport:
            ChromeMV3ContentScriptSmokeReport?
        private var lastChromeMV3RuntimeContentScriptLocalFixtureRunnerReport:
            ChromeMV3ContentScriptLocalFixtureRunnerReport?
        private var lastChromeMV3RuntimeExtensionPageHostReport:
            ChromeMV3ExtensionPageHostReport?
        private var lastChromeMV3RuntimeJSMessagingMVPReport:
            ChromeMV3RuntimeJSMessagingMVPReport?
        private var lastChromeMV3TabsScriptingMVPReport:
            ChromeMV3TabsScriptingMVPReport?
        private var lastChromeMV3RuntimeBridgePrerequisitesReport:
            ChromeMV3RuntimeBridgePrerequisitesReport?
        private var lastChromeMV3RuntimeBridgeReadinessReport:
            ChromeMV3RuntimeBridgeReadinessReport?
        private var lastChromeMV3StorageBrokerReadinessReport:
            ChromeMV3StorageBrokerReadinessReport?
        private var lastChromeMV3StorageAPIOperationsReport:
            ChromeMV3StorageAPIOperationsReport?
        private var lastChromeMV3StorageLocalImplementationReport:
            ChromeMV3StorageLocalImplementationReport?
        private var lastChromeMV3RuntimeMessagingContractReport:
            ChromeMV3RuntimeMessagingContractReport?
        private var lastChromeMV3RuntimeMessageDispatcherSkeletonReport:
            ChromeMV3RuntimeMessageDispatcherSkeletonReport?
        private var lastChromeMV3JSBridgeContractReport:
            ChromeMV3JSBridgeContractReport?
        private var lastChromeMV3NativeMessagingReadinessReport:
            ChromeMV3NativeMessagingReadinessReport?
        private var lastChromeMV3NativeMessagingImplementationReport:
            ChromeMV3NativeMessagingImplementationReport?
        private var lastChromeMV3RuntimeListenerContractReport:
            ChromeMV3RuntimeListenerContractReport?
        private var lastChromeMV3ServiceWorkerLifecycleReport:
            ChromeMV3ServiceWorkerLifecycleReport?
        private var lastChromeMV3ServiceWorkerSharedLifecycleSessionReport:
            ChromeMV3ServiceWorkerSharedLifecycleSessionReport?
        private var lastChromeMV3PermissionBrokerReadinessReport:
            ChromeMV3PermissionBrokerReadinessReport?
        private var lastChromeMV3PermissionLifecycleReport:
            ChromeMV3PermissionLifecycleReport?
        private var lastChromeMV3PermissionsAPIContractReport:
            ChromeMV3PermissionsAPIContractReport?
        private var lastChromeMV3PermissionImplementationReport:
            ChromeMV3PermissionImplementationReport?
        private var lastChromeMV3PasswordManagerFixtureReport:
            ChromeMV3PasswordManagerFixtureReport?
        private var lastChromeMV3PasswordManagerCompatibilityReport:
            ChromeMV3PasswordManagerCompatibilityReport?
        private var lastChromeMV3ExtensionEventAPIsReport:
            ChromeMV3ExtensionEventAPIsReport?
        private var lastChromeMV3NetworkCompatibilityReport:
            ChromeMV3NetworkCompatibilityReport?
        private var lastChromeMV3SidePanelOffscreenIdentityReport:
            ChromeMV3SidePanelOffscreenIdentityCompatibilityReport?
        private var lastChromeMV3EndToEndInstallDiagnosticsReport:
            ChromeMV3EndToEndInstallDiagnosticsReport?
    #endif
    weak var browserManager: BrowserManager?
    #if DEBUG
        private var lastChromeMV3LiveNormalTabAttachmentSnapshot:
            ChromeMV3LiveNormalTabAttachmentRecorderSnapshot?
        var chromeMV3InternalNormalTabConfigurationAttachmentAllowed = false {
            didSet {
                guard oldValue,
                      chromeMV3InternalNormalTabConfigurationAttachmentAllowed == false
                else { return }
                cachedChromeMV3EmptyControllerOwner?
                    .markNormalTabAttachmentGateClosed(
                        trigger: .normalTabAttachmentGateOff
                    )
            }
        }
    #endif

    init(
        moduleRegistry: SumiModuleRegistry = .shared,
        context: ModelContext? = nil,
        browserConfiguration: BrowserConfiguration? = nil,
        initialProfileProvider: @escaping @MainActor () -> Profile? = { nil },
        // Explicit injection seam for focused tests; production constructs lazily only when enabled.
        managerFactory: @escaping @MainActor (
            ModelContext,
            Profile?,
            BrowserConfiguration
        ) -> ExtensionManager = {
            ExtensionManager(
                context: $0,
                initialProfile: $1,
                browserConfiguration: $2
            )
        },
        chromeMV3EmptyControllerOwnerFactory: @escaping @MainActor (
            ChromeMV3ControllerCreationGateDecision,
            WKWebsiteDataStore,
            UUID
        ) -> ChromeMV3EmptyControllerOwner? = {
            ChromeMV3EmptyControllerFactory.makeOwner(
                gateDecision: $0,
                defaultWebsiteDataStore: $1,
                controllerIdentifier: $2
            )
        },
        chromeMV3PopupOptionsWebViewFactory:
            @escaping @MainActor () -> ChromeMV3PopupOptionsWebViewFactory = {
                ChromeMV3ProductPopupOptionsWKWebViewFactory()
            },
        surfaceStore: BrowserExtensionSurfaceStore? = nil
    ) {
        self.moduleRegistry = moduleRegistry
        self.context = context
        self.browserConfiguration = browserConfiguration ?? .shared
        self.initialProfileProvider = initialProfileProvider
        self.managerFactory = managerFactory
        self.chromeMV3EmptyControllerOwnerFactory =
            chromeMV3EmptyControllerOwnerFactory
        self.chromeMV3PopupOptionsWebViewFactory =
            chromeMV3PopupOptionsWebViewFactory
        self.surfaceStore = surfaceStore ?? BrowserExtensionSurfaceStore(
            extensionManager: nil
        )
    }

    var isEnabled: Bool {
        moduleRegistry.isEnabled(.extensions)
    }

    var hasLoadedRuntime: Bool {
        cachedManager != nil
    }

    func attach(browserManager: BrowserManager) {
        self.browserManager = browserManager
        cachedManager?.attach(browserManager: browserManager)
    }

    func setEnabled(_ isEnabled: Bool) {
        moduleRegistry.setEnabled(isEnabled, for: .extensions)
        if isEnabled == false {
            #if DEBUG
                if #available(macOS 15.5, *) {
                    tearDownChromeMV3ControllerLoadOwner()
                    tearDownChromeMV3DetachedContextOwner()
                    tearDownChromeMV3ExtensionObjectProbeOwner()
                    lastChromeMV3WebKitObjectAcceptanceReport = nil
                    lastChromeMV3ContextReadinessReport = nil
                    lastChromeMV3ContextCreationGateReport = nil
                    lastChromeMV3ControllerLoadGateReport = nil
                    lastChromeMV3RuntimeMinimalSmokeReport = nil
                    lastChromeMV3RuntimeContentScriptSmokeReport = nil
                    lastChromeMV3RuntimeContentScriptLocalFixtureRunnerReport = nil
                    lastChromeMV3RuntimeExtensionPageHostReport = nil
                    lastChromeMV3RuntimeJSMessagingMVPReport = nil
                    lastChromeMV3TabsScriptingMVPReport = nil
                    lastChromeMV3RuntimeBridgePrerequisitesReport = nil
                    lastChromeMV3RuntimeBridgeReadinessReport = nil
                    lastChromeMV3StorageBrokerReadinessReport = nil
                    lastChromeMV3StorageAPIOperationsReport = nil
                    lastChromeMV3StorageLocalImplementationReport = nil
                    lastChromeMV3RuntimeMessagingContractReport = nil
                    lastChromeMV3RuntimeMessageDispatcherSkeletonReport = nil
                    lastChromeMV3JSBridgeContractReport = nil
                    lastChromeMV3NativeMessagingReadinessReport = nil
                    lastChromeMV3NativeMessagingImplementationReport = nil
                    lastChromeMV3RuntimeListenerContractReport = nil
                    lastChromeMV3ServiceWorkerLifecycleReport = nil
                    lastChromeMV3ServiceWorkerSharedLifecycleSessionReport = nil
                    lastChromeMV3PermissionBrokerReadinessReport = nil
                    lastChromeMV3PermissionLifecycleReport = nil
                    lastChromeMV3PermissionsAPIContractReport = nil
                    lastChromeMV3PermissionImplementationReport = nil
                    lastChromeMV3PasswordManagerFixtureReport = nil
                    lastChromeMV3PasswordManagerCompatibilityReport = nil
                    lastChromeMV3NetworkCompatibilityReport = nil
                    lastChromeMV3SidePanelOffscreenIdentityReport = nil
                    lastChromeMV3EndToEndInstallDiagnosticsReport = nil
                }
            #endif
            tearDownChromeMV3PopupOptionsHostController(reason: .moduleDisabled)
            tearDownChromeMV3EmptyControllerOwner()
            tearDownLoadedRuntime(reason: "SumiExtensionsModule.setEnabled(false)")
        }
    }

    func managerIfLoadedAndEnabled() -> ExtensionManager? {
        guard isEnabled else { return nil }
        return cachedManager
    }

    func managerIfEnabled() -> ExtensionManager? {
        guard isEnabled else { return nil }

        if let cachedManager {
            return cachedManager
        }

        guard let context else { return nil }

        let manager = managerFactory(
            context,
            browserManager?.currentProfile ?? initialProfileProvider(),
            browserConfiguration
        )
        cachedManager = manager
        if let browserManager {
            manager.attach(browserManager: browserManager)
        }
        surfaceStore.bind(manager)
        return manager
    }

    func chromeMV3ProfileHostIfEnabled(
        candidateRewrittenVariants: [ChromeMV3RewrittenVariantCandidate] = []
    ) -> ChromeMV3ProfileHost? {
        guard isEnabled else { return nil }

        return makeChromeMV3ProfileHost(
            candidateRewrittenVariants: candidateRewrittenVariants
        ).host
    }

    func chromeMV3InventoryDiagnosticsIfEnabled(
        rootURL: URL
    ) -> ChromeMV3ProfileHostDiagnostics? {
        guard isEnabled else { return nil }

        let inventory = ChromeMV3CandidateInventoryReader()
            .readInventory(rootURL: rootURL)
        let candidates = inventory.candidates.map(\.profileHostCandidate)
        let probeDiagnostics: ChromeMV3ExtensionObjectProbeDiagnostics?
        let objectAcceptanceReport: ChromeMV3WebKitObjectAcceptanceReport?
        let contextReadinessReport: ChromeMV3ContextReadinessReport?
        let contextCreationGateReport: ChromeMV3ContextCreationGateReport?
        let controllerLoadGateReport: ChromeMV3ControllerLoadGateReport?
        let runtimeMinimalSmokeReport:
            ChromeMV3RuntimeMinimalSmokeReport?
        let runtimeContentScriptSmokeReport:
            ChromeMV3ContentScriptSmokeReport?
        let runtimeContentScriptLocalFixtureRunnerReport:
            ChromeMV3ContentScriptLocalFixtureRunnerReport?
        let runtimeExtensionPageHostReport:
            ChromeMV3ExtensionPageHostReport?
        let runtimeJSMessagingMVPReport:
            ChromeMV3RuntimeJSMessagingMVPReport?
        let tabsScriptingMVPReport:
            ChromeMV3TabsScriptingMVPReport?
        let runtimeBridgePrerequisitesReport:
            ChromeMV3RuntimeBridgePrerequisitesReport?
        let runtimeBridgeReadinessReport:
            ChromeMV3RuntimeBridgeReadinessReport?
        let storageBrokerReadinessReportSummary:
            ChromeMV3StorageBrokerReadinessReportSummary?
        let storageAPIOperationsReportSummary:
            ChromeMV3StorageAPIOperationsReportSummary?
        let storageLocalImplementationReportSummary:
            ChromeMV3StorageLocalImplementationReportSummary?
        let runtimeMessagingContractReportSummary:
            ChromeMV3RuntimeMessagingContractReportSummary?
        let runtimeMessageDispatcherSkeletonReportSummary:
            ChromeMV3RuntimeMessageDispatcherSkeletonReportSummary?
        let jsBridgeContractReportSummary:
            ChromeMV3JSBridgeContractReportSummary?
        let nativeMessagingReadinessReportSummary:
            ChromeMV3NativeMessagingReadinessReportSummary?
        let runtimeListenerContractReportSummary:
            ChromeMV3RuntimeListenerContractReportSummary?
        let serviceWorkerLifecycleReportSummary:
            ChromeMV3ServiceWorkerLifecycleReportSummary?
        let extensionEventAPIsReportSummary:
            ChromeMV3ExtensionEventAPIsReportSummary?
        let networkCompatibilityReportSummary:
            ChromeMV3NetworkCompatibilityReportSummary?
        let sidePanelOffscreenIdentityReportSummary:
            ChromeMV3SidePanelOffscreenIdentityReportSummary?
        let permissionBrokerReadinessReportSummary:
            ChromeMV3PermissionBrokerReadinessReportSummary?
        let permissionLifecycleReportSummary:
            ChromeMV3PermissionLifecycleReportSummary?
        let permissionsAPIContractReportSummary:
            ChromeMV3PermissionsAPIContractReportSummary?
        let permissionImplementationReportSummary:
            ChromeMV3PermissionImplementationReportSummary?
        #if DEBUG
            if #available(macOS 15.5, *) {
                probeDiagnostics =
                    cachedChromeMV3ExtensionObjectProbeOwner?.diagnostics()
                objectAcceptanceReport =
                    lastChromeMV3WebKitObjectAcceptanceReport
                contextReadinessReport =
                    lastChromeMV3ContextReadinessReport
                contextCreationGateReport =
                    lastChromeMV3ContextCreationGateReport
                controllerLoadGateReport =
                    lastChromeMV3ControllerLoadGateReport
                runtimeMinimalSmokeReport =
                    lastChromeMV3RuntimeMinimalSmokeReport
                runtimeContentScriptSmokeReport =
                    lastChromeMV3RuntimeContentScriptSmokeReport
                runtimeContentScriptLocalFixtureRunnerReport =
                    lastChromeMV3RuntimeContentScriptLocalFixtureRunnerReport
                runtimeExtensionPageHostReport =
                    lastChromeMV3RuntimeExtensionPageHostReport
                runtimeJSMessagingMVPReport =
                    lastChromeMV3RuntimeJSMessagingMVPReport
                tabsScriptingMVPReport =
                    lastChromeMV3TabsScriptingMVPReport
                runtimeBridgePrerequisitesReport =
                    lastChromeMV3RuntimeBridgePrerequisitesReport
                runtimeBridgeReadinessReport =
                    lastChromeMV3RuntimeBridgeReadinessReport
                storageBrokerReadinessReportSummary =
                    lastChromeMV3StorageBrokerReadinessReport?.summary
                storageAPIOperationsReportSummary =
                    lastChromeMV3StorageAPIOperationsReport?.summary
                storageLocalImplementationReportSummary =
                    lastChromeMV3StorageLocalImplementationReport?.summary
                runtimeMessagingContractReportSummary =
                    lastChromeMV3RuntimeMessagingContractReport?.summary
                runtimeMessageDispatcherSkeletonReportSummary =
                    lastChromeMV3RuntimeMessageDispatcherSkeletonReport?
                    .summary
                jsBridgeContractReportSummary =
                    lastChromeMV3JSBridgeContractReport?.summary
                nativeMessagingReadinessReportSummary =
                    lastChromeMV3NativeMessagingReadinessReport?.summary
                runtimeListenerContractReportSummary =
                    lastChromeMV3RuntimeListenerContractReport?.summary
                serviceWorkerLifecycleReportSummary =
                    lastChromeMV3ServiceWorkerLifecycleReport?.summary
                extensionEventAPIsReportSummary =
                    lastChromeMV3ExtensionEventAPIsReport?.summary
                networkCompatibilityReportSummary =
                    lastChromeMV3NetworkCompatibilityReport?.summary
                sidePanelOffscreenIdentityReportSummary =
                    lastChromeMV3SidePanelOffscreenIdentityReport?.summary
                permissionBrokerReadinessReportSummary =
                    lastChromeMV3PermissionBrokerReadinessReport?.summary
                permissionLifecycleReportSummary =
                    lastChromeMV3PermissionLifecycleReport?.summary
                permissionsAPIContractReportSummary =
                    lastChromeMV3PermissionsAPIContractReport?.summary
                permissionImplementationReportSummary =
                    lastChromeMV3PermissionImplementationReport?.summary
            } else {
                probeDiagnostics = nil
                objectAcceptanceReport = nil
                contextReadinessReport = nil
                contextCreationGateReport = nil
                controllerLoadGateReport = nil
                runtimeMinimalSmokeReport = nil
                runtimeContentScriptSmokeReport = nil
                runtimeContentScriptLocalFixtureRunnerReport = nil
                runtimeExtensionPageHostReport = nil
                runtimeJSMessagingMVPReport = nil
                tabsScriptingMVPReport = nil
                runtimeBridgePrerequisitesReport = nil
                runtimeBridgeReadinessReport = nil
                storageBrokerReadinessReportSummary = nil
                storageAPIOperationsReportSummary = nil
                storageLocalImplementationReportSummary = nil
                runtimeMessagingContractReportSummary = nil
                runtimeMessageDispatcherSkeletonReportSummary = nil
                jsBridgeContractReportSummary = nil
                nativeMessagingReadinessReportSummary = nil
                runtimeListenerContractReportSummary = nil
                serviceWorkerLifecycleReportSummary = nil
                extensionEventAPIsReportSummary = nil
                networkCompatibilityReportSummary = nil
                sidePanelOffscreenIdentityReportSummary = nil
                permissionBrokerReadinessReportSummary = nil
                permissionLifecycleReportSummary = nil
                permissionsAPIContractReportSummary = nil
                permissionImplementationReportSummary = nil
            }
        #else
            probeDiagnostics = nil
            objectAcceptanceReport = nil
            contextReadinessReport = nil
            contextCreationGateReport = nil
            controllerLoadGateReport = nil
            runtimeMinimalSmokeReport = nil
            runtimeContentScriptSmokeReport = nil
            runtimeContentScriptLocalFixtureRunnerReport = nil
            runtimeExtensionPageHostReport = nil
            runtimeJSMessagingMVPReport = nil
            tabsScriptingMVPReport = nil
            runtimeBridgePrerequisitesReport = nil
            runtimeBridgeReadinessReport = nil
            storageBrokerReadinessReportSummary = nil
            storageAPIOperationsReportSummary = nil
            storageLocalImplementationReportSummary = nil
            runtimeMessagingContractReportSummary = nil
            runtimeMessageDispatcherSkeletonReportSummary = nil
            jsBridgeContractReportSummary = nil
            nativeMessagingReadinessReportSummary = nil
            runtimeListenerContractReportSummary = nil
            serviceWorkerLifecycleReportSummary = nil
            extensionEventAPIsReportSummary = nil
            networkCompatibilityReportSummary = nil
            sidePanelOffscreenIdentityReportSummary = nil
            permissionBrokerReadinessReportSummary = nil
            permissionLifecycleReportSummary = nil
            permissionsAPIContractReportSummary = nil
            permissionImplementationReportSummary = nil
        #endif
        return chromeMV3ProfileHostIfEnabled(
            candidateRewrittenVariants: candidates
        )?.diagnostics(
            candidateInventory: inventory,
            extensionObjectProbeDiagnostics: probeDiagnostics,
            extensionObjectAcceptanceReport: objectAcceptanceReport,
            contextReadinessReport: contextReadinessReport,
            contextCreationGateReport: contextCreationGateReport,
            controllerLoadGateReport: controllerLoadGateReport,
            runtimeMinimalSmokeReport: runtimeMinimalSmokeReport,
            runtimeContentScriptSmokeReport:
                runtimeContentScriptSmokeReport,
            runtimeContentScriptLocalFixtureRunnerReport:
                runtimeContentScriptLocalFixtureRunnerReport,
            runtimeExtensionPageHostReport:
                runtimeExtensionPageHostReport,
            runtimeJSMessagingMVPReport:
                runtimeJSMessagingMVPReport,
            tabsScriptingMVPReport:
                tabsScriptingMVPReport,
            runtimeBridgePrerequisitesReport:
                runtimeBridgePrerequisitesReport,
            runtimeBridgeReadinessReport:
                runtimeBridgeReadinessReport,
            storageBrokerReadinessReportSummary:
                storageBrokerReadinessReportSummary,
            storageAPIOperationsReportSummary:
                storageAPIOperationsReportSummary,
            storageLocalImplementationReportSummary:
                storageLocalImplementationReportSummary,
            runtimeMessagingContractReportSummary:
                runtimeMessagingContractReportSummary,
            runtimeMessageDispatcherSkeletonReportSummary:
                runtimeMessageDispatcherSkeletonReportSummary,
            jsBridgeContractReportSummary:
                jsBridgeContractReportSummary,
            nativeMessagingReadinessReportSummary:
                nativeMessagingReadinessReportSummary,
            runtimeListenerContractReportSummary:
                runtimeListenerContractReportSummary,
            serviceWorkerLifecycleReportSummary:
                serviceWorkerLifecycleReportSummary,
            extensionEventAPIsReportSummary:
                extensionEventAPIsReportSummary,
            networkCompatibilityReportSummary:
                networkCompatibilityReportSummary,
            sidePanelOffscreenIdentityReportSummary:
                sidePanelOffscreenIdentityReportSummary,
            permissionBrokerReadinessReportSummary:
                permissionBrokerReadinessReportSummary,
            permissionLifecycleReportSummary:
                permissionLifecycleReportSummary,
            permissionsAPIContractReportSummary:
                permissionsAPIContractReportSummary,
            permissionImplementationReportSummary:
                permissionImplementationReportSummary
        )
    }

    func chromeMV3ControllerCreationGateDecisionIfEnabled(
        explicitControllerCreationAllowed: Bool,
        requestedContextLoading: Bool = false,
        requestedNormalTabAttachment: Bool = false,
        candidateRewrittenVariants: [ChromeMV3RewrittenVariantCandidate] = []
    ) -> ChromeMV3ControllerCreationGateDecision? {
        guard isEnabled else { return nil }

        let host = makeChromeMV3ProfileHost(
            candidateRewrittenVariants: candidateRewrittenVariants
        ).host
        return host.controllerCreationGateDecision(
            extensionsModuleEnabled: true,
            explicitControllerCreationAllowed: explicitControllerCreationAllowed,
            requestedContextLoading: requestedContextLoading,
            requestedNormalTabAttachment: requestedNormalTabAttachment
        )
    }

    @discardableResult
    func createChromeMV3EmptyControllerOwnerIfEnabled(
        explicitControllerCreationAllowed: Bool,
        candidateRewrittenVariants: [ChromeMV3RewrittenVariantCandidate] = []
    ) -> ChromeMV3EmptyControllerOwner? {
        guard isEnabled else { return nil }

        let profileHost = makeChromeMV3ProfileHost(
            candidateRewrittenVariants: candidateRewrittenVariants
        )
        let decision = profileHost.host.controllerCreationGateDecision(
            extensionsModuleEnabled: true,
            explicitControllerCreationAllowed: explicitControllerCreationAllowed
        )

        guard decision.canCreateControllerNow else {
            return nil
        }

        if let cachedChromeMV3EmptyControllerOwner {
            return cachedChromeMV3EmptyControllerOwner
        }

        guard let profile = profileHost.profile else {
            return nil
        }

        let owner = chromeMV3EmptyControllerOwnerFactory(
            decision,
            profile.dataStore,
            profile.id
        )
        cachedChromeMV3EmptyControllerOwner = owner
        return owner
    }

    func chromeMV3EmptyControllerDiagnosticsIfEnabled(
        explicitControllerCreationAllowed: Bool,
        candidateRewrittenVariants: [ChromeMV3RewrittenVariantCandidate] = []
    ) -> ChromeMV3EmptyControllerDiagnostics? {
        guard isEnabled else { return nil }

        if let cachedChromeMV3EmptyControllerOwner {
            return cachedChromeMV3EmptyControllerOwner.diagnostics()
        }

        guard let decision = chromeMV3ControllerCreationGateDecisionIfEnabled(
            explicitControllerCreationAllowed: explicitControllerCreationAllowed,
            candidateRewrittenVariants: candidateRewrittenVariants
        ) else {
            return nil
        }

        return ChromeMV3EmptyControllerDiagnostics.notCreated(
            gateDecision: decision
        )
    }

    func chromeMV3ControllerDataStoreIdentityDiagnosticsIfEnabled(
        explicitControllerCreationAllowed: Bool,
        candidateRewrittenVariants: [ChromeMV3RewrittenVariantCandidate] = []
    ) -> ChromeMV3ControllerDataStoreIdentityDiagnostics? {
        guard isEnabled else { return nil }

        if let cachedChromeMV3EmptyControllerOwner {
            return cachedChromeMV3EmptyControllerOwner.diagnostics()
                .dataStoreIdentityPolicy
        }

        guard let decision = chromeMV3ControllerCreationGateDecisionIfEnabled(
            explicitControllerCreationAllowed: explicitControllerCreationAllowed,
            candidateRewrittenVariants: candidateRewrittenVariants
        ) else {
            return nil
        }

        return ChromeMV3ControllerDataStoreIdentityPolicy.evaluate(
            profileIdentifier: decision.input.profileIdentifier,
            dataStoreIdentity: decision.input.profileDataStoreIdentity,
            controllerCreated: false
        )
    }

    func chromeMV3ControllerAttachmentPreflightIfEnabled(
        surface: ChromeMV3WebViewSurface,
        runtimePreflight: ChromeMV3RuntimePreflightResult? = nil,
        explicitControllerCreationAllowed: Bool = false,
        candidateRewrittenVariants: [ChromeMV3RewrittenVariantCandidate] = []
    ) -> ChromeMV3ControllerAttachmentPreflight? {
        guard isEnabled else { return nil }

        let profileHost = makeChromeMV3ProfileHost(
            candidateRewrittenVariants: candidateRewrittenVariants
        ).host
        let eligibility = ChromeMV3WebViewEligibilityPolicy.evaluate(
            surface: surface,
            extensionModuleEnabled: profileHost.isActive,
            profileHostActive: profileHost.isActive
        )
        let controllerDiagnostics =
            chromeMV3EmptyControllerDiagnosticsIfEnabled(
                explicitControllerCreationAllowed:
                    explicitControllerCreationAllowed,
                candidateRewrittenVariants: candidateRewrittenVariants
            )

        return ChromeMV3ControllerAttachmentPreflightEvaluator.evaluate(
            surface: surface,
            eligibility: eligibility,
            controllerDiagnostics: controllerDiagnostics,
            runtimePreflight: runtimePreflight,
            moduleState: profileHost.moduleState
        )
    }

    #if DEBUG
        @available(macOS 15.5, *)
        func chromeMV3NormalTabConfigurationAttachmentRequestIfEnabled(
            explicitInternalNormalTabAttachmentAllowed: Bool,
            surface: ChromeMV3WebViewSurface = .normalTab,
            requestedContextLoading: Bool = false,
            canLoadContextNow: Bool = false,
            runtimeLoadable: Bool = false,
            attemptMetadata:
                ChromeMV3NormalTabConfigurationAttachmentAttemptMetadata =
                    ChromeMV3NormalTabConfigurationAttachmentAttemptMetadata(),
            candidateRewrittenVariants: [ChromeMV3RewrittenVariantCandidate] = []
        ) -> ChromeMV3NormalTabConfigurationAttachmentRequest? {
            guard isEnabled else { return nil }

            let profileHost = makeChromeMV3ProfileHost(
                candidateRewrittenVariants: candidateRewrittenVariants
            ).host
            return ChromeMV3NormalTabConfigurationAttachmentRequest(
                owner: cachedChromeMV3EmptyControllerOwner,
                extensionsModuleEnabled: true,
                profileHostEnabled: profileHost.isActive,
                explicitInternalNormalTabAttachmentAllowed:
                    explicitInternalNormalTabAttachmentAllowed,
                surface: surface,
                requestedContextLoading: requestedContextLoading,
                canLoadContextNow: canLoadContextNow,
                runtimeLoadable: runtimeLoadable,
                attemptMetadata: attemptMetadata
            )
        }

        @available(macOS 15.5, *)
        func chromeMV3NormalTabConfigurationAttachmentRequestForLiveNormalTabIfEnabled(
            surface: ChromeMV3WebViewSurface,
            attemptMetadata:
                ChromeMV3NormalTabConfigurationAttachmentAttemptMetadata
        ) -> ChromeMV3NormalTabConfigurationAttachmentRequest? {
            chromeMV3NormalTabConfigurationAttachmentRequestIfEnabled(
                explicitInternalNormalTabAttachmentAllowed:
                    chromeMV3InternalNormalTabConfigurationAttachmentAllowed,
                surface: surface,
                attemptMetadata: attemptMetadata
            )
        }

        @available(macOS 15.5, *)
        func markChromeMV3LiveNormalTabWebViewCreatedIfTracked(
            configuration: WKWebViewConfiguration,
            reason: String
        ) {
            cachedChromeMV3EmptyControllerOwner?
                .markNormalTabWebViewCreated(configuration: configuration)
            lastChromeMV3LiveNormalTabAttachmentSnapshot =
                cachedChromeMV3EmptyControllerOwner?
                .liveNormalTabAttachmentDiagnostics()
                ?? lastChromeMV3LiveNormalTabAttachmentSnapshot
        }

        @available(macOS 15.5, *)
        func chromeMV3LiveNormalTabAttachmentDiagnosticsSnapshot()
            -> ChromeMV3LiveNormalTabAttachmentRecorderSnapshot?
        {
            cachedChromeMV3EmptyControllerOwner?
                .liveNormalTabAttachmentDiagnostics()
                ?? lastChromeMV3LiveNormalTabAttachmentSnapshot
        }

        @available(macOS 15.5, *)
        func chromeMV3ExtensionObjectProbeGateDecisionIfEnabled(
            explicitInternalExtensionObjectProbeAllowed: Bool,
            candidate: ChromeMV3RewrittenVariantCandidate,
            runtimeLoadabilityReport: ChromeMV3RuntimeLoadabilityReport?,
            requestedContextCreation: Bool = false,
            requestedContextLoading: Bool = false,
            requestedControllerLoad: Bool = false,
            requestedExtensionCodeExecution: Bool = false,
            requestedUserScriptRegistration: Bool = false,
            requestedNativeMessagingLaunch: Bool = false
        ) -> ChromeMV3ExtensionObjectProbeGateDecision? {
            guard isEnabled else { return nil }

            let profileHost = makeChromeMV3ProfileHost(
                candidateRewrittenVariants: [candidate]
            ).host
            return ChromeMV3ExtensionObjectProbeGate.evaluate(
                input: chromeMV3ExtensionObjectProbeGateInput(
                    profileHost: profileHost,
                    explicitInternalExtensionObjectProbeAllowed:
                        explicitInternalExtensionObjectProbeAllowed,
                    candidate: candidate,
                    runtimeLoadabilityReport: runtimeLoadabilityReport,
                    requestedContextCreation: requestedContextCreation,
                    requestedContextLoading: requestedContextLoading,
                    requestedControllerLoad: requestedControllerLoad,
                    requestedExtensionCodeExecution:
                        requestedExtensionCodeExecution,
                    requestedUserScriptRegistration:
                        requestedUserScriptRegistration,
                    requestedNativeMessagingLaunch:
                        requestedNativeMessagingLaunch
                )
            )
        }

        @available(macOS 15.5, *)
        func chromeMV3ExtensionObjectProbeDiagnosticsIfEnabled(
            explicitInternalExtensionObjectProbeAllowed: Bool,
            candidate: ChromeMV3RewrittenVariantCandidate,
            runtimeLoadabilityReport: ChromeMV3RuntimeLoadabilityReport?
        ) -> ChromeMV3ExtensionObjectProbeDiagnostics? {
            guard isEnabled else { return nil }

            if let cachedChromeMV3ExtensionObjectProbeOwner {
                return cachedChromeMV3ExtensionObjectProbeOwner.diagnostics()
            }

            guard
                let decision =
                    chromeMV3ExtensionObjectProbeGateDecisionIfEnabled(
                        explicitInternalExtensionObjectProbeAllowed:
                            explicitInternalExtensionObjectProbeAllowed,
                        candidate: candidate,
                        runtimeLoadabilityReport: runtimeLoadabilityReport
                    )
            else {
                return nil
            }

            return decision.canCreateExtensionObjectNow
                ? ChromeMV3ExtensionObjectProbeDiagnostics.notAttempted(
                    gateDecision: decision
                )
                : ChromeMV3ExtensionObjectProbeDiagnostics.blocked(
                    gateDecision: decision
                )
        }

        @available(macOS 15.5, *)
        func chromeMV3WebKitObjectAcceptanceReportIfEnabled(
            explicitInternalExtensionObjectProbeAllowed: Bool,
            candidate: ChromeMV3RewrittenVariantCandidate,
            runtimeLoadabilityReport: ChromeMV3RuntimeLoadabilityReport?,
            probeDiagnostics: ChromeMV3ExtensionObjectProbeDiagnostics? = nil,
            writeReport: Bool = false
        ) -> ChromeMV3WebKitObjectAcceptanceReport? {
            guard isEnabled else { return nil }
            guard
                let decision =
                    chromeMV3ExtensionObjectProbeGateDecisionIfEnabled(
                        explicitInternalExtensionObjectProbeAllowed:
                            explicitInternalExtensionObjectProbeAllowed,
                        candidate: candidate,
                        runtimeLoadabilityReport: runtimeLoadabilityReport
                    )
            else {
                return nil
            }

            let diagnostics = probeDiagnostics
                ?? cachedChromeMV3ExtensionObjectProbeOwner?.diagnostics()
            let report = ChromeMV3WebKitObjectAcceptanceReportGenerator
                .makeReport(
                    candidate: candidate,
                    gateDecision: decision,
                    probeDiagnostics: diagnostics,
                    runtimeLoadabilityReport: runtimeLoadabilityReport
                )
            lastChromeMV3WebKitObjectAcceptanceReport = report

            guard writeReport else { return report }
            let rootURL = URL(
                fileURLWithPath: report.rewrittenBundleRootPath,
                isDirectory: true
            )
            return (try? ChromeMV3WebKitObjectAcceptanceReportWriter.write(
                report,
                toRewrittenBundleRoot: rootURL
            )) ?? report
        }

        @available(macOS 15.5, *)
        func chromeMV3ContextReadinessReportIfEnabled(
            explicitControllerCreationAllowed: Bool,
            candidate: ChromeMV3RewrittenVariantCandidate,
            runtimeLoadabilityReport: ChromeMV3RuntimeLoadabilityReport?,
            objectAcceptanceReport:
                ChromeMV3WebKitObjectAcceptanceReport? = nil,
            probeDiagnostics:
                ChromeMV3ExtensionObjectProbeDiagnostics? = nil,
            writeReport: Bool = false
        ) -> ChromeMV3ContextReadinessReport? {
            guard isEnabled else { return nil }

            let rootURL = URL(
                fileURLWithPath: candidate.rewrittenVariantRootPath,
                isDirectory: true
            ).standardizedFileURL
            let loadedObjectAcceptanceReport =
                objectAcceptanceReport == nil
                    ? ChromeMV3ContextReadinessReportGenerator
                        .loadObjectAcceptanceReport(
                            fromRewrittenBundleRoot: rootURL
                        )
                    : nil
            let resolvedObjectAcceptanceReport =
                objectAcceptanceReport
                    ?? loadedObjectAcceptanceReport?.report
                    ?? lastChromeMV3WebKitObjectAcceptanceReport
            let resolvedObjectAcceptanceReportPath =
                loadedObjectAcceptanceReport?.path
                    ?? resolvedObjectAcceptanceReport.map { _ in
                        rootURL
                            .appendingPathComponent(
                                ChromeMV3WebKitObjectAcceptanceReportWriter
                                    .reportFileName
                            )
                            .path
                    }
            let resolvedObjectAcceptanceReportHash =
                loadedObjectAcceptanceReport?.sha256
            let emptyControllerDiagnostics =
                chromeMV3EmptyControllerDiagnosticsIfEnabled(
                    explicitControllerCreationAllowed:
                        explicitControllerCreationAllowed,
                    candidateRewrittenVariants: [candidate]
                )
            let liveSnapshot =
                chromeMV3LiveNormalTabAttachmentDiagnosticsSnapshot()
            let report = ChromeMV3ContextReadinessReportGenerator.makeReport(
                candidate: candidate,
                objectAcceptanceReport: resolvedObjectAcceptanceReport,
                objectAcceptanceReportPath:
                    resolvedObjectAcceptanceReportPath,
                objectAcceptanceReportSHA256:
                    resolvedObjectAcceptanceReportHash,
                objectProbeDiagnostics: probeDiagnostics
                    ?? cachedChromeMV3ExtensionObjectProbeOwner?
                    .diagnostics(),
                emptyControllerDiagnostics: emptyControllerDiagnostics,
                liveNormalTabAttachmentSnapshot: liveSnapshot,
                runtimeLoadabilityReport: runtimeLoadabilityReport
            )
            lastChromeMV3ContextReadinessReport = report

            guard writeReport else { return report }
            return (try? ChromeMV3ContextReadinessReportWriter.write(
                report,
                toRewrittenBundleRoot: rootURL
            )) ?? report
        }

        @available(macOS 15.5, *)
        func chromeMV3RuntimeBridgePrerequisitesReportIfEnabled(
            fromRewrittenBundleRoot rootURL: URL,
            writeReport: Bool = false
        ) -> ChromeMV3RuntimeBridgePrerequisitesReport? {
            guard isEnabled else { return nil }

            let rootURL = rootURL.standardizedFileURL
            let report: ChromeMV3RuntimeBridgePrerequisitesReport
            do {
                report = try ChromeMV3RuntimeBridgePrerequisitesReportGenerator
                    .makeReport(
                        loadingContextReadinessReportFrom: rootURL
                    )
            } catch {
                return nil
            }
            lastChromeMV3RuntimeBridgePrerequisitesReport = report

            guard writeReport else { return report }
            return (try? ChromeMV3RuntimeBridgePrerequisitesReportWriter.write(
                report,
                toRewrittenBundleRoot: rootURL
            )) ?? report
        }

        @available(macOS 15.5, *)
        func chromeMV3RuntimeBridgeReadinessReportIfEnabled(
            fromRewrittenBundleRoot rootURL: URL,
            writeReport: Bool = false
        ) -> ChromeMV3RuntimeBridgeReadinessReport? {
            guard isEnabled else { return nil }

            let rootURL = rootURL.standardizedFileURL
            let report: ChromeMV3RuntimeBridgeReadinessReport
            do {
                report = try ChromeMV3RuntimeBridgeReadinessReportGenerator
                    .makeReport(
                        loadingReportsFrom: rootURL
                    )
            } catch {
                return nil
            }
            var linkedReport = report
            linkedReport.runtimeJSMessagingMVPSummary =
                lastChromeMV3RuntimeJSMessagingMVPReport?.summary
            linkedReport.tabsScriptingMVPSummary =
                lastChromeMV3TabsScriptingMVPReport?.summary
            lastChromeMV3RuntimeBridgeReadinessReport = linkedReport

            guard writeReport else { return linkedReport }
            return (try? ChromeMV3RuntimeBridgeReadinessReportWriter.write(
                linkedReport,
                toRewrittenBundleRoot: rootURL
            )) ?? linkedReport
        }

        @available(macOS 15.5, *)
        func chromeMV3ContextCreationGateDecisionIfEnabled(
            explicitInternalContextCreationAllowed: Bool,
            candidate: ChromeMV3RewrittenVariantCandidate,
            objectAcceptanceReport:
                ChromeMV3WebKitObjectAcceptanceReport? = nil,
            runtimeBridgeReadinessReport:
                ChromeMV3RuntimeBridgeReadinessReport? = nil,
            requestedContextLoading: Bool = false,
            requestedControllerLoad: Bool = false,
            requestedExtensionCodeExecution: Bool = false,
            requestedUserScriptRegistration: Bool = false,
            requestedNativeMessagingLaunch: Bool = false,
            sdkCompatibility: ChromeMV3ContextCreationSDKCompatibility =
                .currentAppleSDK
        ) -> ChromeMV3ContextCreationGateDecision? {
            guard isEnabled else { return nil }

            let profileHost = makeChromeMV3ProfileHost(
                candidateRewrittenVariants: [candidate]
            ).host
            let resolvedObjectAcceptanceReport =
                objectAcceptanceReport
                    ?? lastChromeMV3WebKitObjectAcceptanceReport
                    ?? loadChromeMV3WebKitObjectAcceptanceReport(
                        fromRewrittenBundleRootPath:
                            candidate.rewrittenVariantRootPath
                    )
            let resolvedRuntimeBridgeReadinessReport =
                runtimeBridgeReadinessReport
                    ?? lastChromeMV3RuntimeBridgeReadinessReport
                    ?? loadChromeMV3RuntimeBridgeReadinessReport(
                        fromRewrittenBundleRootPath:
                            candidate.rewrittenVariantRootPath
                    )
            let probeOwner = cachedChromeMV3ExtensionObjectProbeOwner
            let probeDiagnostics = probeOwner?.diagnostics()
            let emptyControllerDiagnostics =
                chromeMV3EmptyControllerDiagnosticsIfEnabled(
                    explicitControllerCreationAllowed: true,
                    candidateRewrittenVariants: [candidate]
                )
            let liveSnapshot =
                chromeMV3LiveNormalTabAttachmentDiagnosticsSnapshot()

            return ChromeMV3ContextCreationGate.evaluate(
                input: ChromeMV3ContextCreationGateInput(
                    candidateID: candidate.id,
                    generatedRewrittenRootPath:
                        URL(
                            fileURLWithPath:
                                candidate.rewrittenVariantRootPath,
                            isDirectory: true
                        ).standardizedFileURL.path,
                    extensionsModuleEnabled: true,
                    profileHostModuleState: profileHost.moduleState,
                    profileIdentifier: profileHost.profileIdentifier,
                    explicitInternalContextCreationAllowed:
                        explicitInternalContextCreationAllowed,
                    acceptedWebExtensionObjectAvailable:
                        probeOwner?
                        .hasAcceptedWebExtensionObjectForDetachedContext(
                            objectAcceptanceReport:
                                resolvedObjectAcceptanceReport
                        ) ?? false,
                    objectProbeDiagnostics: probeDiagnostics,
                    objectAcceptanceReport:
                        resolvedObjectAcceptanceReport,
                    emptyControllerDiagnostics: emptyControllerDiagnostics,
                    liveNormalTabAttachmentSnapshot: liveSnapshot,
                    runtimeBridgeReadinessReport:
                        resolvedRuntimeBridgeReadinessReport,
                    sdkCompatibility: sdkCompatibility,
                    requestedContextLoading: requestedContextLoading,
                    requestedControllerLoad: requestedControllerLoad,
                    requestedExtensionCodeExecution:
                        requestedExtensionCodeExecution,
                    requestedUserScriptRegistration:
                        requestedUserScriptRegistration,
                    requestedNativeMessagingLaunch:
                        requestedNativeMessagingLaunch
                )
            )
        }

        @available(macOS 15.5, *)
        func chromeMV3ContextCreationGateReportIfEnabled(
            explicitInternalContextCreationAllowed: Bool,
            candidate: ChromeMV3RewrittenVariantCandidate,
            objectAcceptanceReport:
                ChromeMV3WebKitObjectAcceptanceReport? = nil,
            runtimeBridgeReadinessReport:
                ChromeMV3RuntimeBridgeReadinessReport? = nil,
            writeReport: Bool = false,
            sdkCompatibility: ChromeMV3ContextCreationSDKCompatibility =
                .currentAppleSDK
        ) -> ChromeMV3ContextCreationGateReport? {
            guard isEnabled else { return nil }
            guard
                let decision =
                    chromeMV3ContextCreationGateDecisionIfEnabled(
                        explicitInternalContextCreationAllowed:
                            explicitInternalContextCreationAllowed,
                        candidate: candidate,
                        objectAcceptanceReport: objectAcceptanceReport,
                        runtimeBridgeReadinessReport:
                            runtimeBridgeReadinessReport,
                        sdkCompatibility: sdkCompatibility
                    )
            else {
                return nil
            }

            let report = ChromeMV3ContextCreationGateReportGenerator
                .makeReport(
                    decision: decision,
                    detachedContextOwnerDiagnostics:
                        cachedChromeMV3DetachedContextOwner?
                        .diagnostics(),
                    controllerLoadGateReportSummary:
                        lastChromeMV3ControllerLoadGateReport?.summary
                )
            lastChromeMV3ContextCreationGateReport = report

            guard writeReport else { return report }
            let rootURL = URL(
                fileURLWithPath: candidate.rewrittenVariantRootPath,
                isDirectory: true
            ).standardizedFileURL
            return (try? ChromeMV3ContextCreationGateReportWriter.write(
                report,
                toRewrittenBundleRoot: rootURL
            )) ?? report
        }

        @available(macOS 15.5, *)
        @discardableResult
        func createChromeMV3DetachedContextIfEnabled(
            explicitInternalContextCreationAllowed: Bool,
            candidate: ChromeMV3RewrittenVariantCandidate,
            objectAcceptanceReport:
                ChromeMV3WebKitObjectAcceptanceReport? = nil,
            runtimeBridgeReadinessReport:
                ChromeMV3RuntimeBridgeReadinessReport? = nil,
            writeReport: Bool = false,
            sdkCompatibility: ChromeMV3ContextCreationSDKCompatibility =
                .currentAppleSDK
        ) -> ChromeMV3DetachedContextOwnerDiagnostics? {
            guard isEnabled else { return nil }
            guard
                let decision =
                    chromeMV3ContextCreationGateDecisionIfEnabled(
                        explicitInternalContextCreationAllowed:
                            explicitInternalContextCreationAllowed,
                        candidate: candidate,
                        objectAcceptanceReport: objectAcceptanceReport,
                        runtimeBridgeReadinessReport:
                            runtimeBridgeReadinessReport,
                        sdkCompatibility: sdkCompatibility
                    )
            else {
                return nil
            }

            let resolvedObjectAcceptanceReport =
                objectAcceptanceReport
                    ?? lastChromeMV3WebKitObjectAcceptanceReport
                    ?? loadChromeMV3WebKitObjectAcceptanceReport(
                        fromRewrittenBundleRootPath:
                            candidate.rewrittenVariantRootPath
                    )
            let acceptedObject =
                cachedChromeMV3ExtensionObjectProbeOwner?
                .acceptedWebExtensionObjectForDetachedContext(
                    objectAcceptanceReport:
                        resolvedObjectAcceptanceReport
                )
            let owner: ChromeMV3DetachedContextOwner
            if let cachedChromeMV3DetachedContextOwner,
               cachedChromeMV3DetachedContextOwner
                .diagnostics()
                .gateDecision
                .input
                .candidateID == decision.input.candidateID
            {
                owner = cachedChromeMV3DetachedContextOwner
            } else {
                cachedChromeMV3DetachedContextOwner?.tearDown()
                owner = ChromeMV3DetachedContextOwner(
                    gateDecision: decision
                )
                cachedChromeMV3DetachedContextOwner = owner
            }

            let diagnostics = owner.createDetachedContextIfAllowed(
                acceptedWebExtension: acceptedObject
            )
            let report = ChromeMV3ContextCreationGateReportGenerator
                .makeReport(
                    decision: decision,
                    detachedContextOwnerDiagnostics: diagnostics,
                    controllerLoadGateReportSummary:
                        lastChromeMV3ControllerLoadGateReport?.summary
                )
            lastChromeMV3ContextCreationGateReport = report

            if writeReport {
                let rootURL = URL(
                    fileURLWithPath: candidate.rewrittenVariantRootPath,
                    isDirectory: true
                ).standardizedFileURL
                _ = try? ChromeMV3ContextCreationGateReportWriter.write(
                    report,
                    toRewrittenBundleRoot: rootURL
                )
            }
            return diagnostics
        }

        @available(macOS 15.5, *)
        func chromeMV3ControllerLoadGateDecisionIfEnabled(
            explicitInternalControllerLoadProbeAllowed: Bool,
            candidate: ChromeMV3RewrittenVariantCandidate,
            objectAcceptanceReport:
                ChromeMV3WebKitObjectAcceptanceReport? = nil,
            runtimeBridgeReadinessReport:
                ChromeMV3RuntimeBridgeReadinessReport? = nil,
            requestedProductRuntimeExposure: Bool = false,
            requestedExtensionCodeExecution: Bool = false,
            requestedUserScriptRegistration: Bool = false,
            requestedNativeMessagingLaunch: Bool = false,
            sdkCompatibility: ChromeMV3ControllerLoadSDKCompatibility =
                .currentAppleSDK
        ) -> ChromeMV3ControllerLoadGateDecision? {
            guard isEnabled else { return nil }

            let profileHost = makeChromeMV3ProfileHost(
                candidateRewrittenVariants: [candidate]
            ).host
            let resolvedObjectAcceptanceReport =
                objectAcceptanceReport
                    ?? lastChromeMV3WebKitObjectAcceptanceReport
                    ?? loadChromeMV3WebKitObjectAcceptanceReport(
                        fromRewrittenBundleRootPath:
                            candidate.rewrittenVariantRootPath
                    )
            let resolvedRuntimeBridgeReadinessReport =
                runtimeBridgeReadinessReport
                    ?? lastChromeMV3RuntimeBridgeReadinessReport
                    ?? loadChromeMV3RuntimeBridgeReadinessReport(
                        fromRewrittenBundleRootPath:
                            candidate.rewrittenVariantRootPath
                    )
            let probeOwner = cachedChromeMV3ExtensionObjectProbeOwner
            let probeDiagnostics = probeOwner?.diagnostics()
            let detachedDiagnostics =
                cachedChromeMV3DetachedContextOwner?.diagnostics()
            let emptyControllerDiagnostics =
                chromeMV3EmptyControllerDiagnosticsIfEnabled(
                    explicitControllerCreationAllowed: true,
                    candidateRewrittenVariants: [candidate]
                )
            let acceptedObjectAvailable =
                probeOwner?
                .hasAcceptedWebExtensionObjectForDetachedContext(
                    objectAcceptanceReport:
                        resolvedObjectAcceptanceReport
                ) ?? false
            let rootPath = URL(
                fileURLWithPath: candidate.rewrittenVariantRootPath,
                isDirectory: true
            ).standardizedFileURL.path
            let minimalPolicy = ChromeMV3MinimalInertFixturePolicy.evaluate(
                generatedRewrittenRootPath: rootPath,
                acceptedWebExtensionObjectAvailable:
                    acceptedObjectAvailable,
                detachedContextCreated:
                    detachedDiagnostics?.contextObjectCreated ?? false
            )

            return ChromeMV3ControllerLoadGate.evaluate(
                input: ChromeMV3ControllerLoadGateInput(
                    candidateID: candidate.id,
                    generatedRewrittenRootPath: rootPath,
                    extensionsModuleEnabled: true,
                    profileHostModuleState: profileHost.moduleState,
                    profileIdentifier: profileHost.profileIdentifier,
                    explicitInternalControllerLoadProbeAllowed:
                        explicitInternalControllerLoadProbeAllowed,
                    acceptedWebExtensionObjectAvailable:
                        acceptedObjectAvailable,
                    objectProbeDiagnostics: probeDiagnostics,
                    objectAcceptanceReport:
                        resolvedObjectAcceptanceReport,
                    detachedContextOwnerDiagnostics:
                        detachedDiagnostics,
                    emptyControllerDiagnostics:
                        emptyControllerDiagnostics,
                    liveNormalTabAttachmentSnapshot:
                        chromeMV3LiveNormalTabAttachmentDiagnosticsSnapshot(),
                    runtimeBridgeReadinessReport:
                        resolvedRuntimeBridgeReadinessReport,
                    minimalInertFixturePolicy: minimalPolicy,
                    sdkCompatibility: sdkCompatibility,
                    requestedProductRuntimeExposure:
                        requestedProductRuntimeExposure,
                    requestedExtensionCodeExecution:
                        requestedExtensionCodeExecution,
                    requestedUserScriptRegistration:
                        requestedUserScriptRegistration,
                    requestedNativeMessagingLaunch:
                        requestedNativeMessagingLaunch
                )
            )
        }

        @available(macOS 15.5, *)
        func chromeMV3ControllerLoadGateReportIfEnabled(
            explicitInternalControllerLoadProbeAllowed: Bool,
            candidate: ChromeMV3RewrittenVariantCandidate,
            objectAcceptanceReport:
                ChromeMV3WebKitObjectAcceptanceReport? = nil,
            runtimeBridgeReadinessReport:
                ChromeMV3RuntimeBridgeReadinessReport? = nil,
            writeReport: Bool = false,
            sdkCompatibility: ChromeMV3ControllerLoadSDKCompatibility =
                .currentAppleSDK
        ) -> ChromeMV3ControllerLoadGateReport? {
            guard isEnabled else { return nil }
            guard
                let decision = chromeMV3ControllerLoadGateDecisionIfEnabled(
                    explicitInternalControllerLoadProbeAllowed:
                        explicitInternalControllerLoadProbeAllowed,
                    candidate: candidate,
                    objectAcceptanceReport: objectAcceptanceReport,
                    runtimeBridgeReadinessReport:
                        runtimeBridgeReadinessReport,
                    sdkCompatibility: sdkCompatibility
                )
            else {
                return nil
            }

            let report = ChromeMV3ControllerLoadGateReportGenerator
                .makeReport(
                    decision: decision,
                    loadOwnerDiagnostics:
                        cachedChromeMV3ControllerLoadOwner?.diagnostics()
                )
            lastChromeMV3ControllerLoadGateReport = report

            guard writeReport else { return report }
            let rootURL = URL(
                fileURLWithPath: candidate.rewrittenVariantRootPath,
                isDirectory: true
            ).standardizedFileURL
            return (try? ChromeMV3ControllerLoadGateReportWriter.write(
                report,
                toRewrittenBundleRoot: rootURL
            )) ?? report
        }

        @available(macOS 15.5, *)
        @discardableResult
        func loadChromeMV3DetachedContextIntoControllerIfEnabled(
            explicitInternalControllerLoadProbeAllowed: Bool,
            candidate: ChromeMV3RewrittenVariantCandidate,
            objectAcceptanceReport:
                ChromeMV3WebKitObjectAcceptanceReport? = nil,
            runtimeBridgeReadinessReport:
                ChromeMV3RuntimeBridgeReadinessReport? = nil,
            writeReport: Bool = false,
            sdkCompatibility: ChromeMV3ControllerLoadSDKCompatibility =
                .currentAppleSDK
        ) -> ChromeMV3ControllerLoadOwnerDiagnostics? {
            guard isEnabled else { return nil }
            guard
                let decision = chromeMV3ControllerLoadGateDecisionIfEnabled(
                    explicitInternalControllerLoadProbeAllowed:
                        explicitInternalControllerLoadProbeAllowed,
                    candidate: candidate,
                    objectAcceptanceReport: objectAcceptanceReport,
                    runtimeBridgeReadinessReport:
                        runtimeBridgeReadinessReport,
                    sdkCompatibility: sdkCompatibility
                )
            else {
                return nil
            }

            let resolvedObjectAcceptanceReport =
                objectAcceptanceReport
                    ?? lastChromeMV3WebKitObjectAcceptanceReport
                    ?? loadChromeMV3WebKitObjectAcceptanceReport(
                        fromRewrittenBundleRootPath:
                            candidate.rewrittenVariantRootPath
                    )
            let acceptedObject =
                cachedChromeMV3ExtensionObjectProbeOwner?
                .acceptedWebExtensionObjectForDetachedContext(
                    objectAcceptanceReport:
                        resolvedObjectAcceptanceReport
                )
            let owner: ChromeMV3ControllerLoadOwner
            if let cachedChromeMV3ControllerLoadOwner,
               cachedChromeMV3ControllerLoadOwner
                .diagnostics()
                .gateDecision
                .input
                .candidateID == decision.input.candidateID
            {
                owner = cachedChromeMV3ControllerLoadOwner
            } else {
                cachedChromeMV3ControllerLoadOwner?.tearDown()
                owner = ChromeMV3ControllerLoadOwner(
                    gateDecision: decision
                )
                cachedChromeMV3ControllerLoadOwner = owner
            }

            let diagnostics = owner.loadContextIntoControllerIfAllowed(
                emptyControllerOwner: cachedChromeMV3EmptyControllerOwner,
                detachedContextOwner: cachedChromeMV3DetachedContextOwner,
                acceptedWebExtension: acceptedObject
            )
            let report = ChromeMV3ControllerLoadGateReportGenerator
                .makeReport(
                    decision: decision,
                    loadOwnerDiagnostics: diagnostics
                )
            lastChromeMV3ControllerLoadGateReport = report

            if writeReport {
                let rootURL = URL(
                    fileURLWithPath: candidate.rewrittenVariantRootPath,
                    isDirectory: true
                ).standardizedFileURL
                _ = try? ChromeMV3ControllerLoadGateReportWriter.write(
                    report,
                    toRewrittenBundleRoot: rootURL
                )
            }
            return diagnostics
        }

        @available(macOS 15.5, *)
        @discardableResult
        func tearDownChromeMV3ControllerLoadIfEnabled()
            -> ChromeMV3ControllerLoadOwnerDiagnostics?
        {
            guard isEnabled else { return nil }
            let diagnostics =
                cachedChromeMV3ControllerLoadOwner?.tearDown()
            cachedChromeMV3ControllerLoadOwner = nil
            return diagnostics
        }

        @available(macOS 15.5, *)
        func chromeMV3RuntimeMinimalSmokeHarnessReportIfEnabled(
            explicitInternalSmokeHarnessAllowed: Bool,
            explicitSyntheticWebViewCreationAllowed: Bool = false,
            candidate: ChromeMV3RewrittenVariantCandidate,
            objectAcceptanceReport:
                ChromeMV3WebKitObjectAcceptanceReport? = nil,
            runtimeBridgeReadinessReport:
                ChromeMV3RuntimeBridgeReadinessReport? = nil,
            writeReport: Bool = false,
            tearDownLoadedContextAndControllerAfterRun: Bool = true
        ) -> ChromeMV3RuntimeMinimalSmokeReport? {
            guard isEnabled else { return nil }

            let resolvedObjectAcceptanceReport =
                objectAcceptanceReport
                    ?? lastChromeMV3WebKitObjectAcceptanceReport
                    ?? loadChromeMV3WebKitObjectAcceptanceReport(
                        fromRewrittenBundleRootPath:
                            candidate.rewrittenVariantRootPath
                    )
            let resolvedRuntimeBridgeReadinessReport =
                runtimeBridgeReadinessReport
                    ?? lastChromeMV3RuntimeBridgeReadinessReport
                    ?? loadChromeMV3RuntimeBridgeReadinessReport(
                        fromRewrittenBundleRootPath:
                            candidate.rewrittenVariantRootPath
                    )
            let report = ChromeMV3RuntimeMinimalSmokeHarness.run(
                candidate: candidate,
                extensionsModuleEnabled: true,
                explicitInternalSmokeHarnessAllowed:
                    explicitInternalSmokeHarnessAllowed,
                explicitSyntheticWebViewCreationAllowed:
                    explicitSyntheticWebViewCreationAllowed,
                objectAcceptanceReport:
                    resolvedObjectAcceptanceReport,
                runtimeBridgeReadinessReport:
                    resolvedRuntimeBridgeReadinessReport,
                emptyControllerOwner:
                    cachedChromeMV3EmptyControllerOwner,
                detachedContextOwner:
                    cachedChromeMV3DetachedContextOwner,
                controllerLoadOwner:
                    cachedChromeMV3ControllerLoadOwner,
                liveNormalTabAttachmentSnapshot:
                    chromeMV3LiveNormalTabAttachmentDiagnosticsSnapshot(),
                tearDownLoadedContextAndControllerAfterRun:
                    tearDownLoadedContextAndControllerAfterRun,
                diagnosticsResetForFutureRuns:
                    tearDownLoadedContextAndControllerAfterRun
            )
            lastChromeMV3RuntimeMinimalSmokeReport = report

            if report.teardownResult.diagnosticsResetForFutureRuns {
                cachedChromeMV3ControllerLoadOwner = nil
                cachedChromeMV3DetachedContextOwner = nil
                cachedChromeMV3EmptyControllerOwner = nil
            }

            if writeReport {
                let rootURL = URL(
                    fileURLWithPath: candidate.rewrittenVariantRootPath,
                    isDirectory: true
                ).standardizedFileURL
                _ = try? ChromeMV3RuntimeMinimalSmokeReportWriter.write(
                    report,
                    toRewrittenBundleRoot: rootURL
                )
            }
            return report
        }

        @available(macOS 15.5, *)
        func chromeMV3RuntimeContentScriptSmokeReportIfEnabled(
            explicitInternalContentScriptSmokeAllowed: Bool,
            explicitSyntheticWebViewCreationAllowed: Bool = false,
            explicitSyntheticNavigationAllowed: Bool = false,
            explicitTestDOMInspectionAllowed: Bool = false,
            candidate: ChromeMV3RewrittenVariantCandidate,
            objectAcceptanceReport:
                ChromeMV3WebKitObjectAcceptanceReport? = nil,
            runtimeBridgeReadinessReport:
                ChromeMV3RuntimeBridgeReadinessReport? = nil,
            writeReport: Bool = false,
            tearDownLoadedContextAndControllerAfterRun: Bool = true
        ) -> ChromeMV3ContentScriptSmokeReport? {
            guard isEnabled else { return nil }

            let resolvedObjectAcceptanceReport =
                objectAcceptanceReport
                    ?? lastChromeMV3WebKitObjectAcceptanceReport
                    ?? loadChromeMV3WebKitObjectAcceptanceReport(
                        fromRewrittenBundleRootPath:
                            candidate.rewrittenVariantRootPath
                    )
            let resolvedRuntimeBridgeReadinessReport =
                runtimeBridgeReadinessReport
                    ?? lastChromeMV3RuntimeBridgeReadinessReport
                    ?? loadChromeMV3RuntimeBridgeReadinessReport(
                        fromRewrittenBundleRootPath:
                            candidate.rewrittenVariantRootPath
                    )
            let report = ChromeMV3ContentScriptSmokeHarness.run(
                candidate: candidate,
                extensionsModuleEnabled: true,
                explicitInternalContentScriptSmokeAllowed:
                    explicitInternalContentScriptSmokeAllowed,
                explicitSyntheticWebViewCreationAllowed:
                    explicitSyntheticWebViewCreationAllowed,
                explicitSyntheticNavigationAllowed:
                    explicitSyntheticNavigationAllowed,
                explicitTestDOMInspectionAllowed:
                    explicitTestDOMInspectionAllowed,
                objectAcceptanceReport:
                    resolvedObjectAcceptanceReport,
                runtimeBridgeReadinessReport:
                    resolvedRuntimeBridgeReadinessReport,
                emptyControllerOwner:
                    cachedChromeMV3EmptyControllerOwner,
                detachedContextOwner:
                    cachedChromeMV3DetachedContextOwner,
                controllerLoadOwner:
                    cachedChromeMV3ControllerLoadOwner,
                liveNormalTabAttachmentSnapshot:
                    chromeMV3LiveNormalTabAttachmentDiagnosticsSnapshot(),
                tearDownLoadedContextAndControllerAfterRun:
                    tearDownLoadedContextAndControllerAfterRun
            )
            lastChromeMV3RuntimeContentScriptSmokeReport = report

            if report.gateDecision.canRunContentScriptSmokeNow,
               let minimalReport = lastChromeMV3RuntimeMinimalSmokeReport {
                var linkedMinimalReport = minimalReport
                linkedMinimalReport.contentScriptSmokeSummary = report.summary
                lastChromeMV3RuntimeMinimalSmokeReport = linkedMinimalReport
            }
            if report.gateDecision.canRunContentScriptSmokeNow,
               var linkedReadinessReport =
                lastChromeMV3RuntimeBridgeReadinessReport
                    ?? resolvedRuntimeBridgeReadinessReport {
                linkedReadinessReport.contentScriptSmokeSummary =
                    report.summary
                lastChromeMV3RuntimeBridgeReadinessReport =
                    linkedReadinessReport
            }

            if tearDownLoadedContextAndControllerAfterRun {
                cachedChromeMV3ControllerLoadOwner = nil
                cachedChromeMV3DetachedContextOwner = nil
                cachedChromeMV3EmptyControllerOwner = nil
            }

            if writeReport {
                let rootURL = URL(
                    fileURLWithPath: candidate.rewrittenVariantRootPath,
                    isDirectory: true
                ).standardizedFileURL
                _ = try? ChromeMV3ContentScriptSmokeReportWriter.write(
                    report,
                    toRewrittenBundleRoot: rootURL
                )
            }
            return report
        }

        @available(macOS 15.5, *)
        func chromeMV3RuntimeContentScriptSmokeReportWithTestDOMInspectionIfEnabled(
            explicitInternalContentScriptSmokeAllowed: Bool,
            explicitSyntheticWebViewCreationAllowed: Bool,
            explicitSyntheticNavigationAllowed: Bool,
            explicitTestDOMInspectionAllowed: Bool,
            candidate: ChromeMV3RewrittenVariantCandidate,
            objectAcceptanceReport:
                ChromeMV3WebKitObjectAcceptanceReport? = nil,
            runtimeBridgeReadinessReport:
                ChromeMV3RuntimeBridgeReadinessReport? = nil,
            writeReport: Bool = false,
            tearDownLoadedContextAndControllerAfterRun: Bool = true
        ) async -> ChromeMV3ContentScriptSmokeReport? {
            guard isEnabled else { return nil }

            let resolvedObjectAcceptanceReport =
                objectAcceptanceReport
                    ?? lastChromeMV3WebKitObjectAcceptanceReport
                    ?? loadChromeMV3WebKitObjectAcceptanceReport(
                        fromRewrittenBundleRootPath:
                            candidate.rewrittenVariantRootPath
                    )
            let resolvedRuntimeBridgeReadinessReport =
                runtimeBridgeReadinessReport
                    ?? lastChromeMV3RuntimeBridgeReadinessReport
                    ?? loadChromeMV3RuntimeBridgeReadinessReport(
                        fromRewrittenBundleRootPath:
                            candidate.rewrittenVariantRootPath
                    )
            let report =
                await ChromeMV3ContentScriptSmokeHarness
                .runWithTestDOMInspection(
                    candidate: candidate,
                    extensionsModuleEnabled: true,
                    explicitInternalContentScriptSmokeAllowed:
                        explicitInternalContentScriptSmokeAllowed,
                    explicitSyntheticWebViewCreationAllowed:
                        explicitSyntheticWebViewCreationAllowed,
                    explicitSyntheticNavigationAllowed:
                        explicitSyntheticNavigationAllowed,
                    explicitTestDOMInspectionAllowed:
                        explicitTestDOMInspectionAllowed,
                    objectAcceptanceReport:
                        resolvedObjectAcceptanceReport,
                    runtimeBridgeReadinessReport:
                        resolvedRuntimeBridgeReadinessReport,
                    emptyControllerOwner:
                        cachedChromeMV3EmptyControllerOwner,
                    detachedContextOwner:
                        cachedChromeMV3DetachedContextOwner,
                    controllerLoadOwner:
                        cachedChromeMV3ControllerLoadOwner,
                    liveNormalTabAttachmentSnapshot:
                        chromeMV3LiveNormalTabAttachmentDiagnosticsSnapshot(),
                    tearDownLoadedContextAndControllerAfterRun:
                        tearDownLoadedContextAndControllerAfterRun
                )
            lastChromeMV3RuntimeContentScriptSmokeReport = report

            if report.gateDecision.canRunContentScriptSmokeNow,
               let minimalReport = lastChromeMV3RuntimeMinimalSmokeReport {
                var linkedMinimalReport = minimalReport
                linkedMinimalReport.contentScriptSmokeSummary = report.summary
                lastChromeMV3RuntimeMinimalSmokeReport = linkedMinimalReport
            }
            if report.gateDecision.canRunContentScriptSmokeNow,
               var linkedReadinessReport =
                lastChromeMV3RuntimeBridgeReadinessReport
                    ?? resolvedRuntimeBridgeReadinessReport {
                linkedReadinessReport.contentScriptSmokeSummary =
                    report.summary
                lastChromeMV3RuntimeBridgeReadinessReport =
                    linkedReadinessReport
            }

            if tearDownLoadedContextAndControllerAfterRun {
                cachedChromeMV3ControllerLoadOwner = nil
                cachedChromeMV3DetachedContextOwner = nil
                cachedChromeMV3EmptyControllerOwner = nil
            }

            if writeReport {
                let rootURL = URL(
                    fileURLWithPath: candidate.rewrittenVariantRootPath,
                    isDirectory: true
                ).standardizedFileURL
                _ = try? ChromeMV3ContentScriptSmokeReportWriter.write(
                    report,
                    toRewrittenBundleRoot: rootURL
                )
            }
            return report
        }

        @available(macOS 15.5, *)
        func chromeMV3RuntimeContentScriptLocalFixtureRunnerReportIfEnabled(
            explicitInternalLocalFixtureRunnerAllowed: Bool,
            explicitLocalHTTPServerAllowed: Bool,
            explicitSyntheticWebViewCreationAllowed: Bool,
            explicitSyntheticNavigationAllowed: Bool,
            explicitTestDOMInspectionAllowed: Bool,
            candidate: ChromeMV3RewrittenVariantCandidate,
            objectAcceptanceReport:
                ChromeMV3WebKitObjectAcceptanceReport? = nil,
            runtimeBridgeReadinessReport:
                ChromeMV3RuntimeBridgeReadinessReport? = nil,
            writeReport: Bool = false,
            tearDownLoadedContextAndControllerAfterRun: Bool = true
        ) async -> ChromeMV3ContentScriptLocalFixtureRunnerReport? {
            guard isEnabled else { return nil }

            let resolvedObjectAcceptanceReport =
                objectAcceptanceReport
                    ?? lastChromeMV3WebKitObjectAcceptanceReport
                    ?? loadChromeMV3WebKitObjectAcceptanceReport(
                        fromRewrittenBundleRootPath:
                            candidate.rewrittenVariantRootPath
                    )
            let resolvedRuntimeBridgeReadinessReport =
                runtimeBridgeReadinessReport
                    ?? lastChromeMV3RuntimeBridgeReadinessReport
                    ?? loadChromeMV3RuntimeBridgeReadinessReport(
                        fromRewrittenBundleRootPath:
                            candidate.rewrittenVariantRootPath
                    )
            let report =
                await ChromeMV3ContentScriptLocalFixtureRunner.run(
                    candidate: candidate,
                    extensionsModuleEnabled: true,
                    explicitInternalLocalFixtureRunnerAllowed:
                        explicitInternalLocalFixtureRunnerAllowed,
                    explicitLocalHTTPServerAllowed:
                        explicitLocalHTTPServerAllowed,
                    explicitSyntheticWebViewCreationAllowed:
                        explicitSyntheticWebViewCreationAllowed,
                    explicitSyntheticNavigationAllowed:
                        explicitSyntheticNavigationAllowed,
                    explicitTestDOMInspectionAllowed:
                        explicitTestDOMInspectionAllowed,
                    objectAcceptanceReport:
                        resolvedObjectAcceptanceReport,
                    runtimeBridgeReadinessReport:
                        resolvedRuntimeBridgeReadinessReport,
                    emptyControllerOwner:
                        cachedChromeMV3EmptyControllerOwner,
                    detachedContextOwner:
                        cachedChromeMV3DetachedContextOwner,
                    controllerLoadOwner:
                        cachedChromeMV3ControllerLoadOwner,
                    liveNormalTabAttachmentSnapshot:
                        chromeMV3LiveNormalTabAttachmentDiagnosticsSnapshot(),
                    tearDownLoadedContextAndControllerAfterRun:
                        tearDownLoadedContextAndControllerAfterRun
                )
            lastChromeMV3RuntimeContentScriptLocalFixtureRunnerReport = report

            if var linkedSmokeReport =
                lastChromeMV3RuntimeContentScriptSmokeReport {
                linkedSmokeReport.localFixtureRunnerSummary = report.summary
                lastChromeMV3RuntimeContentScriptSmokeReport =
                    linkedSmokeReport
            }
            if var linkedReadinessReport =
                lastChromeMV3RuntimeBridgeReadinessReport
                    ?? resolvedRuntimeBridgeReadinessReport {
                linkedReadinessReport.contentScriptLocalFixtureRunnerSummary =
                    report.summary
                lastChromeMV3RuntimeBridgeReadinessReport =
                    linkedReadinessReport
            }

            if tearDownLoadedContextAndControllerAfterRun {
                cachedChromeMV3ControllerLoadOwner = nil
                cachedChromeMV3DetachedContextOwner = nil
                cachedChromeMV3EmptyControllerOwner = nil
            }

            if writeReport {
                let rootURL = URL(
                    fileURLWithPath: candidate.rewrittenVariantRootPath,
                    isDirectory: true
                ).standardizedFileURL
                _ = try? ChromeMV3ContentScriptLocalFixtureRunnerReportWriter
                    .write(
                        report,
                        toRewrittenBundleRoot: rootURL
                    )
            }
            return report
        }

        @available(macOS 15.5, *)
        func chromeMV3RuntimeExtensionPageHostReportIfEnabled(
            selectedKind: ChromeMV3ExtensionPageKind,
            explicitInternalExtensionPageHostAllowed: Bool,
            explicitSyntheticWebViewCreationAllowed: Bool,
            explicitSyntheticNavigationAllowed: Bool,
            explicitTestDOMInspectionAllowed: Bool,
            candidate: ChromeMV3RewrittenVariantCandidate,
            objectAcceptanceReport:
                ChromeMV3WebKitObjectAcceptanceReport? = nil,
            runtimeBridgeReadinessReport:
                ChromeMV3RuntimeBridgeReadinessReport? = nil,
            writeReport: Bool = false,
            tearDownLoadedContextAndControllerAfterRun: Bool = false
        ) async -> ChromeMV3ExtensionPageHostReport? {
            guard isEnabled else { return nil }

            let resolvedObjectAcceptanceReport =
                objectAcceptanceReport
                    ?? lastChromeMV3WebKitObjectAcceptanceReport
                    ?? loadChromeMV3WebKitObjectAcceptanceReport(
                        fromRewrittenBundleRootPath:
                            candidate.rewrittenVariantRootPath
                    )
            let resolvedRuntimeBridgeReadinessReport =
                runtimeBridgeReadinessReport
                    ?? lastChromeMV3RuntimeBridgeReadinessReport
                    ?? loadChromeMV3RuntimeBridgeReadinessReport(
                        fromRewrittenBundleRootPath:
                            candidate.rewrittenVariantRootPath
                    )
            let report =
                await ChromeMV3ExtensionPageHostHarness.run(
                    candidate: candidate,
                    selectedKind: selectedKind,
                    extensionsModuleEnabled: true,
                    explicitInternalExtensionPageHostAllowed:
                        explicitInternalExtensionPageHostAllowed,
                    explicitSyntheticWebViewCreationAllowed:
                        explicitSyntheticWebViewCreationAllowed,
                    explicitSyntheticNavigationAllowed:
                        explicitSyntheticNavigationAllowed,
                    explicitTestDOMInspectionAllowed:
                        explicitTestDOMInspectionAllowed,
                    objectAcceptanceReport:
                        resolvedObjectAcceptanceReport,
                    runtimeBridgeReadinessReport:
                        resolvedRuntimeBridgeReadinessReport,
                    emptyControllerOwner:
                        cachedChromeMV3EmptyControllerOwner,
                    detachedContextOwner:
                        cachedChromeMV3DetachedContextOwner,
                    controllerLoadOwner:
                        cachedChromeMV3ControllerLoadOwner,
                    liveNormalTabAttachmentSnapshot:
                        chromeMV3LiveNormalTabAttachmentDiagnosticsSnapshot(),
                    tearDownLoadedContextAndControllerAfterRun:
                        tearDownLoadedContextAndControllerAfterRun
                )
            var linkedPageReport = report
            linkedPageReport.runtimeJSMessagingMVPSummary =
                lastChromeMV3RuntimeJSMessagingMVPReport?.summary
            lastChromeMV3RuntimeExtensionPageHostReport = linkedPageReport

            if var linkedReadinessReport =
                lastChromeMV3RuntimeBridgeReadinessReport
                    ?? resolvedRuntimeBridgeReadinessReport {
                linkedReadinessReport.extensionPageHostSummary =
                    linkedPageReport.summary
                lastChromeMV3RuntimeBridgeReadinessReport =
                    linkedReadinessReport
            }
            if var linkedBridgeReport = lastChromeMV3JSBridgeContractReport {
                linkedBridgeReport.extensionPageHostSummary =
                    linkedPageReport.summary
                lastChromeMV3JSBridgeContractReport = linkedBridgeReport
            }

            if tearDownLoadedContextAndControllerAfterRun {
                cachedChromeMV3ControllerLoadOwner = nil
                cachedChromeMV3DetachedContextOwner = nil
                cachedChromeMV3EmptyControllerOwner = nil
            }

            if writeReport {
                let rootURL = URL(
                    fileURLWithPath: candidate.rewrittenVariantRootPath,
                    isDirectory: true
                ).standardizedFileURL
                _ = try? ChromeMV3ExtensionPageHostReportWriter.write(
                    linkedPageReport,
                    toRewrittenBundleRoot: rootURL
                )
            }
            return linkedPageReport
        }

        @available(macOS 15.5, *)
        @discardableResult
        func tearDownChromeMV3RuntimeContentScriptLocalFixtureRunnerIfEnabled()
            -> ChromeMV3RuntimeMinimalSmokeTeardownResult?
        {
            guard isEnabled else { return nil }
            lastChromeMV3RuntimeContentScriptLocalFixtureRunnerReport = nil
            return tearDownChromeMV3RuntimeContentScriptSmokeIfEnabled()
        }

        @available(macOS 15.5, *)
        @discardableResult
        func tearDownChromeMV3RuntimeExtensionPageHostIfEnabled()
            -> ChromeMV3RuntimeMinimalSmokeTeardownResult?
        {
            guard isEnabled else { return nil }
            lastChromeMV3RuntimeExtensionPageHostReport = nil
            return tearDownChromeMV3RuntimeMinimalSmokeHarnessIfEnabled()
        }

        @available(macOS 15.5, *)
        @discardableResult
        func tearDownChromeMV3RuntimeMinimalSmokeHarnessIfEnabled()
            -> ChromeMV3RuntimeMinimalSmokeTeardownResult?
        {
            guard isEnabled else { return nil }
            let loadDiagnostics =
                cachedChromeMV3ControllerLoadOwner?.tearDown()
            let detachedDiagnostics =
                cachedChromeMV3DetachedContextOwner?.tearDown()
            let controllerDiagnostics =
                cachedChromeMV3EmptyControllerOwner?.tearDown(
                    trigger: .explicitReset
                )
            cachedChromeMV3ControllerLoadOwner = nil
            cachedChromeMV3DetachedContextOwner = nil
            cachedChromeMV3EmptyControllerOwner = nil
            return ChromeMV3RuntimeMinimalSmokeReportGenerator
                .teardownResult(
                    webViewCreated: false,
                    configurationCreated: false,
                    syntheticConfigurationAttachedAfterTeardown: false,
                    loadedOwnerDiagnostics: loadDiagnostics,
                    detachedContextReleased:
                        detachedDiagnostics?.state == .released,
                    controllerOwnerTornDown:
                        controllerDiagnostics?.controllerState == .tornDown,
                    diagnosticsResetForFutureRuns: true
                )
        }

        @available(macOS 15.5, *)
        @discardableResult
        func tearDownChromeMV3RuntimeContentScriptSmokeIfEnabled()
            -> ChromeMV3RuntimeMinimalSmokeTeardownResult?
        {
            guard isEnabled else { return nil }
            let loadDiagnostics =
                cachedChromeMV3ControllerLoadOwner?.tearDown()
            let detachedDiagnostics =
                cachedChromeMV3DetachedContextOwner?.tearDown()
            let controllerDiagnostics =
                cachedChromeMV3EmptyControllerOwner?.tearDown(
                    trigger: .explicitReset
                )
            cachedChromeMV3ControllerLoadOwner = nil
            cachedChromeMV3DetachedContextOwner = nil
            cachedChromeMV3EmptyControllerOwner = nil
            return ChromeMV3RuntimeMinimalSmokeReportGenerator
                .teardownResult(
                    webViewCreated: false,
                    configurationCreated: false,
                    syntheticConfigurationAttachedAfterTeardown: false,
                    loadedOwnerDiagnostics: loadDiagnostics,
                    detachedContextReleased:
                        detachedDiagnostics?.state == .released,
                    controllerOwnerTornDown:
                        controllerDiagnostics?.controllerState == .tornDown,
                    diagnosticsResetForFutureRuns: true
                )
        }

        @available(macOS 15.5, *)
        func chromeMV3StorageBrokerReadinessReportIfEnabled(
            fromRewrittenBundleRoot rootURL: URL,
            writeReport: Bool = false
        ) -> ChromeMV3StorageBrokerReadinessReport? {
            guard isEnabled else { return nil }

            let rootURL = rootURL.standardizedFileURL
            let report: ChromeMV3StorageBrokerReadinessReport
            do {
                report = try ChromeMV3StorageBrokerReadinessReportGenerator
                    .makeReport(
                        loadingPrerequisitesReportFrom: rootURL
                    )
            } catch {
                return nil
            }
            lastChromeMV3StorageBrokerReadinessReport = report

            guard writeReport else { return report }
            return (try? ChromeMV3StorageBrokerReadinessReportWriter.write(
                report,
                toRewrittenBundleRoot: rootURL
            )) ?? report
        }

        @available(macOS 15.5, *)
        func chromeMV3StorageAPIOperationsReportIfEnabled(
            fromRewrittenBundleRoot rootURL: URL,
            writeReport: Bool = false
        ) -> ChromeMV3StorageAPIOperationsReport? {
            guard isEnabled else { return nil }

            let rootURL = rootURL.standardizedFileURL
            let report: ChromeMV3StorageAPIOperationsReport
            do {
                report = try ChromeMV3StorageAPIOperationsReportGenerator
                    .makeReport(
                        loadingPrerequisitesReportFrom: rootURL
                    )
            } catch {
                return nil
            }
            lastChromeMV3StorageAPIOperationsReport = report

            guard writeReport else { return report }
            return (try? ChromeMV3StorageAPIOperationsReportWriter.write(
                report,
                toRewrittenBundleRoot: rootURL
            )) ?? report
        }

        @available(macOS 15.5, *)
        func chromeMV3StorageLocalImplementationReportIfEnabled(
            fromRewrittenBundleRoot rootURL: URL,
            writeReport: Bool = false
        ) -> ChromeMV3StorageLocalImplementationReport? {
            guard isEnabled else { return nil }

            let rootURL = rootURL.standardizedFileURL
            let report: ChromeMV3StorageLocalImplementationReport
            do {
                report = try ChromeMV3StorageLocalImplementationReportGenerator
                    .makeReport(
                        loadingPrerequisitesReportFrom: rootURL
                    )
            } catch {
                return nil
            }
            lastChromeMV3StorageLocalImplementationReport = report

            guard writeReport else { return report }
            return (try? ChromeMV3StorageLocalImplementationReportWriter.write(
                report,
                toRewrittenBundleRoot: rootURL
            )) ?? report
        }

        @available(macOS 15.5, *)
        func chromeMV3RuntimeMessagingContractReportIfEnabled(
            fromRewrittenBundleRoot rootURL: URL,
            writeReport: Bool = false
        ) -> ChromeMV3RuntimeMessagingContractReport? {
            guard isEnabled else { return nil }

            let rootURL = rootURL.standardizedFileURL
            let report: ChromeMV3RuntimeMessagingContractReport
            do {
                report = try ChromeMV3RuntimeMessagingContractReportGenerator
                    .makeReport(
                        loadingPrerequisitesReportFrom: rootURL
                    )
            } catch {
                return nil
            }
            lastChromeMV3RuntimeMessagingContractReport = report

            guard writeReport else { return report }
            return (try? ChromeMV3RuntimeMessagingContractReportWriter.write(
                report,
                toRewrittenBundleRoot: rootURL
            )) ?? report
        }

        @available(macOS 15.5, *)
        func chromeMV3RuntimeMessageDispatcherSkeletonReportIfEnabled(
            fromRewrittenBundleRoot rootURL: URL,
            writeReport: Bool = false
        ) -> ChromeMV3RuntimeMessageDispatcherSkeletonReport? {
            guard isEnabled else { return nil }

            let rootURL = rootURL.standardizedFileURL
            let report: ChromeMV3RuntimeMessageDispatcherSkeletonReport
            do {
                report = try ChromeMV3RuntimeMessageDispatcherSkeletonReportGenerator
                    .makeReport(
                        loadingPrerequisitesReportFrom: rootURL
                    )
            } catch {
                return nil
            }
            lastChromeMV3RuntimeMessageDispatcherSkeletonReport = report

            guard writeReport else { return report }
            return (try? ChromeMV3RuntimeMessageDispatcherSkeletonReportWriter
                .write(
                    report,
                    toRewrittenBundleRoot: rootURL
                )) ?? report
        }

        @available(macOS 15.5, *)
        func chromeMV3JSBridgeContractReportIfEnabled(
            fromRewrittenBundleRoot rootURL: URL,
            writeReport: Bool = false
        ) -> ChromeMV3JSBridgeContractReport? {
            guard isEnabled else { return nil }

            let rootURL = rootURL.standardizedFileURL
            let report: ChromeMV3JSBridgeContractReport
            do {
                report = try ChromeMV3JSBridgeContractReportGenerator
                    .makeReport(
                        loadingPrerequisitesReportFrom: rootURL
                    )
            } catch {
                return nil
            }
            var linkedReport = report
            linkedReport.runtimeJSMessagingMVPSummary =
                lastChromeMV3RuntimeJSMessagingMVPReport?.summary
            linkedReport.tabsScriptingMVPSummary =
                lastChromeMV3TabsScriptingMVPReport?.summary
            lastChromeMV3JSBridgeContractReport = linkedReport

            guard writeReport else { return linkedReport }
            return (try? ChromeMV3JSBridgeContractReportWriter.write(
                linkedReport,
                toRewrittenBundleRoot: rootURL
            )) ?? linkedReport
        }

        @available(macOS 15.5, *)
        func chromeMV3RuntimeJSMessagingMVPReportIfEnabled(
            fromRewrittenBundleRoot rootURL: URL,
            writeReport: Bool = false
        ) -> ChromeMV3RuntimeJSMessagingMVPReport? {
            guard isEnabled else { return nil }

            let rootURL = rootURL.standardizedFileURL
            let extensionID =
                lastChromeMV3RuntimeBridgePrerequisitesReport?.candidateID
                ?? lastChromeMV3JSBridgeContractReport?.extensionID
                ?? "runtime-js-mvp-extension"
            let profileID =
                lastChromeMV3JSBridgeContractReport?.profileID
                ?? "runtime-js-mvp-profile"
            let report =
                ChromeMV3RuntimeJSMessagingMVPReportGenerator.makeReport(
                    extensionID: extensionID,
                    profileID: profileID
                )
            lastChromeMV3RuntimeJSMessagingMVPReport = report

            if var linkedReadinessReport =
                lastChromeMV3RuntimeBridgeReadinessReport {
                linkedReadinessReport.runtimeJSMessagingMVPSummary =
                    report.summary
                lastChromeMV3RuntimeBridgeReadinessReport =
                    linkedReadinessReport
            }
            if var linkedBridgeReport = lastChromeMV3JSBridgeContractReport {
                linkedBridgeReport.runtimeJSMessagingMVPSummary =
                    report.summary
                lastChromeMV3JSBridgeContractReport = linkedBridgeReport
            }
            if var linkedExtensionPageReport =
                lastChromeMV3RuntimeExtensionPageHostReport {
                linkedExtensionPageReport.runtimeJSMessagingMVPSummary =
                    report.summary
                lastChromeMV3RuntimeExtensionPageHostReport =
                    linkedExtensionPageReport
            }

            guard writeReport else { return report }
            return (try? ChromeMV3RuntimeJSMessagingMVPReportWriter.write(
                report,
                toRewrittenBundleRoot: rootURL
            )) ?? report
        }

        @available(macOS 15.5, *)
        func chromeMV3TabsScriptingMVPReportIfEnabled(
            fromRewrittenBundleRoot rootURL: URL,
            writeReport: Bool = false
        ) -> ChromeMV3TabsScriptingMVPReport? {
            guard isEnabled else { return nil }

            let rootURL = rootURL.standardizedFileURL
            let extensionID =
                lastChromeMV3RuntimeBridgePrerequisitesReport?.candidateID
                ?? lastChromeMV3RuntimeJSMessagingMVPReport?.extensionID
                ?? lastChromeMV3JSBridgeContractReport?.extensionID
                ?? "tabs-scripting-js-mvp-extension"
            let profileID =
                lastChromeMV3RuntimeJSMessagingMVPReport?.profileID
                ?? lastChromeMV3JSBridgeContractReport?.profileID
                ?? "tabs-scripting-js-mvp-profile"
            let report =
                ChromeMV3TabsScriptingMVPReportGenerator.makeReport(
                    extensionID: extensionID,
                    profileID: profileID
                )
            lastChromeMV3TabsScriptingMVPReport = report

            if var linkedReadinessReport =
                lastChromeMV3RuntimeBridgeReadinessReport {
                linkedReadinessReport.tabsScriptingMVPSummary =
                    report.summary
                lastChromeMV3RuntimeBridgeReadinessReport =
                    linkedReadinessReport
            }
            if var linkedBridgeReport = lastChromeMV3JSBridgeContractReport {
                linkedBridgeReport.tabsScriptingMVPSummary =
                    report.summary
                lastChromeMV3JSBridgeContractReport = linkedBridgeReport
            }

            guard writeReport else { return report }
            return (try? ChromeMV3TabsScriptingMVPReportWriter.write(
                report,
                toRewrittenBundleRoot: rootURL
            )) ?? report
        }

        @available(macOS 15.5, *)
        func chromeMV3TabsScriptingWebKitSyntheticHarnessReportIfEnabled(
            fromRewrittenBundleRoot rootURL: URL,
            writeReport: Bool = false
        ) async -> ChromeMV3TabsScriptingMVPReport? {
            guard isEnabled else { return nil }

            let rootURL = rootURL.standardizedFileURL
            let extensionID =
                lastChromeMV3RuntimeBridgePrerequisitesReport?.candidateID
                ?? lastChromeMV3RuntimeJSMessagingMVPReport?.extensionID
                ?? lastChromeMV3JSBridgeContractReport?.extensionID
                ?? "tabs-scripting-js-mvp-extension"
            let profileID =
                lastChromeMV3RuntimeJSMessagingMVPReport?.profileID
                ?? lastChromeMV3JSBridgeContractReport?.profileID
                ?? "tabs-scripting-js-mvp-profile"
            let configuration =
                ChromeMV3TabsScriptingJSBridgeConfiguration.syntheticHarness(
                    extensionID: extensionID,
                    profileID: profileID
                )
            let result =
                await ChromeMV3TabsScriptingJSSyntheticHarness.run(
                    scriptBody:
                        ChromeMV3TabsScriptingJSSyntheticHarness
                        .reportVerificationScriptBody,
                    configuration: configuration
                )
            let report = result.report
            lastChromeMV3TabsScriptingMVPReport = report

            if var linkedReadinessReport =
                lastChromeMV3RuntimeBridgeReadinessReport {
                linkedReadinessReport.tabsScriptingMVPSummary =
                    report.summary
                lastChromeMV3RuntimeBridgeReadinessReport =
                    linkedReadinessReport
            }
            if var linkedBridgeReport = lastChromeMV3JSBridgeContractReport {
                linkedBridgeReport.tabsScriptingMVPSummary =
                    report.summary
                lastChromeMV3JSBridgeContractReport = linkedBridgeReport
            }

            guard writeReport else { return report }
            return (try? ChromeMV3TabsScriptingMVPReportWriter.write(
                report,
                toRewrittenBundleRoot: rootURL
            )) ?? report
        }

        @available(macOS 15.5, *)
        func chromeMV3StorageLocalWebKitSyntheticHarnessReportIfEnabled(
            fromRewrittenBundleRoot rootURL: URL,
            writeReport: Bool = false
        ) async -> ChromeMV3StorageLocalImplementationReport? {
            guard isEnabled else { return nil }

            let rootURL = rootURL.standardizedFileURL
            let extensionID =
                lastChromeMV3RuntimeBridgePrerequisitesReport?.candidateID
                ?? lastChromeMV3TabsScriptingMVPReport?.extensionID
                ?? lastChromeMV3RuntimeJSMessagingMVPReport?.extensionID
                ?? lastChromeMV3JSBridgeContractReport?.extensionID
                ?? "storage-local-js-mvp-extension"
            let profileID =
                lastChromeMV3TabsScriptingMVPReport?.profileID
                ?? lastChromeMV3RuntimeJSMessagingMVPReport?.profileID
                ?? lastChromeMV3JSBridgeContractReport?.profileID
                ?? "storage-local-js-mvp-profile"
            let configuration =
                ChromeMV3StorageLocalRuntimeConfiguration.syntheticHarness(
                    extensionID: extensionID,
                    profileID: profileID
                )
            let result =
                await ChromeMV3StorageLocalJSSyntheticHarness.run(
                    scriptBody:
                        ChromeMV3StorageLocalJSSyntheticHarness
                        .reportVerificationScriptBody,
                    configuration: configuration
                )
            let report = result.report
            lastChromeMV3StorageLocalImplementationReport = report

            guard writeReport else { return report }
            return (try? ChromeMV3StorageLocalImplementationReportWriter.write(
                report,
                toRewrittenBundleRoot: rootURL
            )) ?? report
        }

        @available(macOS 15.5, *)
        @discardableResult
        func tearDownChromeMV3TabsScriptingMVPIfEnabled() -> Bool {
            guard isEnabled else { return false }
            lastChromeMV3TabsScriptingMVPReport = nil
            return true
        }

        @available(macOS 15.5, *)
        @discardableResult
        func tearDownChromeMV3StorageLocalImplementationIfEnabled() -> Bool {
            guard isEnabled else { return false }
            lastChromeMV3StorageLocalImplementationReport = nil
            return true
        }

        @available(macOS 15.5, *)
        @discardableResult
        func tearDownChromeMV3NativeMessagingImplementationIfEnabled() -> Bool {
            guard isEnabled else { return false }
            lastChromeMV3NativeMessagingImplementationReport = nil
            return true
        }

        @available(macOS 15.5, *)
        func chromeMV3NativeMessagingReadinessReportIfEnabled(
            fromRewrittenBundleRoot rootURL: URL,
            requestedHostName: String? = nil,
            lookupPolicy: ChromeMV3NativeHostLookupPolicy = .macOS(),
            writeReport: Bool = false
        ) -> ChromeMV3NativeMessagingReadinessReport? {
            guard isEnabled else { return nil }

            let rootURL = rootURL.standardizedFileURL
            let report: ChromeMV3NativeMessagingReadinessReport
            do {
                report = try ChromeMV3NativeMessagingReadinessReportGenerator
                    .makeReport(
                        loadingPrerequisitesReportFrom: rootURL,
                        requestedHostName: requestedHostName,
                        lookupPolicy: lookupPolicy
                    )
            } catch {
                return nil
            }
            lastChromeMV3NativeMessagingReadinessReport = report

            guard writeReport else { return report }
            return (try? ChromeMV3NativeMessagingReadinessReportWriter.write(
                report,
                toRewrittenBundleRoot: rootURL
            )) ?? report
        }

        @available(macOS 15.5, *)
        func chromeMV3NativeMessagingImplementationReportIfEnabled(
            fromRewrittenBundleRoot rootURL: URL,
            fixtureHostRootURL: URL? = nil,
            writeReport: Bool = false
        ) -> ChromeMV3NativeMessagingImplementationReport? {
            guard isEnabled else { return nil }

            let rootURL = rootURL.standardizedFileURL
            let extensionID =
                lastChromeMV3RuntimeBridgePrerequisitesReport?.candidateID
                ?? lastChromeMV3RuntimeJSMessagingMVPReport?.extensionID
                ?? lastChromeMV3JSBridgeContractReport?.extensionID
                ?? "abcdefghijklmnopabcdefghijklmnop"
            let profileID =
                lastChromeMV3RuntimeJSMessagingMVPReport?.profileID
                ?? lastChromeMV3JSBridgeContractReport?.profileID
                ?? "native-messaging-fixture-profile"
            let fixtureRoot =
                (fixtureHostRootURL ?? rootURL.appendingPathComponent(
                    "NativeMessagingFixtureHosts",
                    isDirectory: true
                )).standardizedFileURL
            let report: ChromeMV3NativeMessagingImplementationReport
            do {
                report = try ChromeMV3NativeMessagingImplementationReportGenerator
                    .makeReport(
                        extensionID: extensionID,
                        profileID: profileID,
                        fixtureHostRootURL: fixtureRoot
                    )
            } catch {
                return nil
            }
            lastChromeMV3NativeMessagingImplementationReport = report

            guard writeReport else { return report }
            return (try? ChromeMV3NativeMessagingImplementationReportWriter
                .write(
                    report,
                    toRewrittenBundleRoot: rootURL
                )) ?? report
        }

        @available(macOS 15.5, *)
        func chromeMV3RuntimeListenerContractReportIfEnabled(
            fromRewrittenBundleRoot rootURL: URL,
            writeReport: Bool = false
        ) -> ChromeMV3RuntimeListenerContractReport? {
            guard isEnabled else { return nil }

            let rootURL = rootURL.standardizedFileURL
            let report: ChromeMV3RuntimeListenerContractReport
            do {
                report = try ChromeMV3RuntimeListenerContractReportGenerator
                    .makeReport(
                        loadingPrerequisitesReportFrom: rootURL
                    )
            } catch {
                return nil
            }
            lastChromeMV3RuntimeListenerContractReport = report

            guard writeReport else { return report }
            return (try? ChromeMV3RuntimeListenerContractReportWriter.write(
                report,
                toRewrittenBundleRoot: rootURL
            )) ?? report
        }

        @available(macOS 15.5, *)
        func chromeMV3ServiceWorkerLifecycleReportIfEnabled(
            fromRewrittenBundleRoot rootURL: URL,
            writeReport: Bool = false
        ) -> ChromeMV3ServiceWorkerLifecycleReport? {
            guard isEnabled else { return nil }

            let rootURL = rootURL.standardizedFileURL
            let report: ChromeMV3ServiceWorkerLifecycleReport
            do {
                report = try ChromeMV3ServiceWorkerLifecycleReportGenerator
                    .makeReport(
                        loadingPrerequisitesReportFrom: rootURL
                    )
            } catch {
                return nil
            }
            lastChromeMV3ServiceWorkerLifecycleReport = report

            guard writeReport else { return report }
            return (try? ChromeMV3ServiceWorkerLifecycleReportWriter.write(
                report,
                toRewrittenBundleRoot: rootURL
            )) ?? report
        }

        @available(macOS 15.5, *)
        func chromeMV3ServiceWorkerSharedLifecycleSessionReportIfEnabled(
            fromRewrittenBundleRoot rootURL: URL,
            writeReport: Bool = false
        ) -> ChromeMV3ServiceWorkerSharedLifecycleSessionReport? {
            guard isEnabled else { return nil }

            let rootURL = rootURL.standardizedFileURL
            let extensionID =
                lastChromeMV3RuntimeBridgePrerequisitesReport?.candidateID
                ?? lastChromeMV3TabsScriptingMVPReport?.extensionID
                ?? lastChromeMV3RuntimeJSMessagingMVPReport?.extensionID
                ?? lastChromeMV3JSBridgeContractReport?.extensionID
                ?? "password-manager-synthetic-extension"
            let profileID =
                lastChromeMV3TabsScriptingMVPReport?.profileID
                ?? lastChromeMV3RuntimeJSMessagingMVPReport?.profileID
                ?? lastChromeMV3JSBridgeContractReport?.profileID
                ?? "password-manager-synthetic-profile"
            guard let report =
                ChromeMV3ServiceWorkerSharedLifecycleSessionReportGenerator
                .makeReport(
                    extensionID: extensionID,
                    profileID: profileID,
                    moduleState: .enabled,
                    explicitInternalLifecycleAllowed: true
                )
            else { return nil }
            lastChromeMV3ServiceWorkerSharedLifecycleSessionReport = report

            guard writeReport else { return report }
            return (try? ChromeMV3ServiceWorkerSharedLifecycleSessionReportWriter
                .write(report, toRewrittenBundleRoot: rootURL)) ?? report
        }

        @available(macOS 15.5, *)
        func chromeMV3ExtensionEventAPIsReportIfEnabled(
            fromRewrittenBundleRoot rootURL: URL,
            writeReport: Bool = false
        ) -> ChromeMV3ExtensionEventAPIsReport? {
            guard isEnabled else { return nil }

            let rootURL = rootURL.standardizedFileURL
            let extensionID =
                lastChromeMV3RuntimeBridgePrerequisitesReport?.candidateID
                ?? lastChromeMV3TabsScriptingMVPReport?.extensionID
                ?? lastChromeMV3RuntimeJSMessagingMVPReport?.extensionID
                ?? lastChromeMV3JSBridgeContractReport?.extensionID
                ?? "extension-event-apis-mvp-extension"
            let profileID =
                lastChromeMV3TabsScriptingMVPReport?.profileID
                ?? lastChromeMV3RuntimeJSMessagingMVPReport?.profileID
                ?? lastChromeMV3JSBridgeContractReport?.profileID
                ?? "extension-event-apis-mvp-profile"
            let report =
                ChromeMV3ExtensionEventAPIsReportGenerator.makeReport(
                    extensionID: extensionID,
                    profileID: profileID,
                    moduleState: .enabled
                )
            lastChromeMV3ExtensionEventAPIsReport = report

            guard writeReport else { return report }
            return (try? ChromeMV3ExtensionEventAPIsReportWriter.write(
                report,
                toRewrittenBundleRoot: rootURL
            )) ?? report
        }

        @available(macOS 15.5, *)
        func chromeMV3ExtensionEventAPIsWebKitSyntheticHarnessReportIfEnabled(
            fromRewrittenBundleRoot rootURL: URL,
            writeReport: Bool = false
        ) async -> ChromeMV3ExtensionEventAPIsReport? {
            guard isEnabled else { return nil }

            let rootURL = rootURL.standardizedFileURL
            let extensionID =
                lastChromeMV3RuntimeBridgePrerequisitesReport?.candidateID
                ?? lastChromeMV3TabsScriptingMVPReport?.extensionID
                ?? lastChromeMV3RuntimeJSMessagingMVPReport?.extensionID
                ?? lastChromeMV3JSBridgeContractReport?.extensionID
                ?? "extension-event-apis-mvp-extension"
            let profileID =
                lastChromeMV3TabsScriptingMVPReport?.profileID
                ?? lastChromeMV3RuntimeJSMessagingMVPReport?.profileID
                ?? lastChromeMV3JSBridgeContractReport?.profileID
                ?? "extension-event-apis-mvp-profile"
            let configuration =
                ChromeMV3ExtensionEventAPIsConfiguration.syntheticHarness(
                    extensionID: extensionID,
                    profileID: profileID
                )
            let result =
                await ChromeMV3ExtensionEventAPIsSyntheticHarness.run(
                    scriptBody:
                        ChromeMV3ExtensionEventAPIsSyntheticHarness
                        .reportVerificationScriptBody,
                    configuration: configuration
                )
            let report = result.report
            lastChromeMV3ExtensionEventAPIsReport = report

            guard writeReport else { return report }
            return (try? ChromeMV3ExtensionEventAPIsReportWriter.write(
                report,
                toRewrittenBundleRoot: rootURL
            )) ?? report
        }

        @available(macOS 15.5, *)
        func chromeMV3NetworkCompatibilityReportIfEnabled(
            fromRewrittenBundleRoot rootURL: URL,
            manifest: ChromeMV3Manifest? = nil,
            writeReport: Bool = false
        ) -> ChromeMV3NetworkCompatibilityReport? {
            guard isEnabled else { return nil }

            let rootURL = rootURL.standardizedFileURL
            let resolvedManifest =
                manifest
                ?? (try? ChromeMV3ManifestValidator.validateManifestFile(
                    at: rootURL.appendingPathComponent("manifest.json")
                ))
            let extensionID =
                lastChromeMV3RuntimeBridgePrerequisitesReport?.candidateID
                ?? lastChromeMV3TabsScriptingMVPReport?.extensionID
                ?? lastChromeMV3RuntimeJSMessagingMVPReport?.extensionID
                ?? lastChromeMV3JSBridgeContractReport?.extensionID
                ?? "network-compatibility-extension"
            let profileID =
                lastChromeMV3TabsScriptingMVPReport?.profileID
                ?? lastChromeMV3RuntimeJSMessagingMVPReport?.profileID
                ?? lastChromeMV3JSBridgeContractReport?.profileID
                ?? "network-compatibility-profile"
            let report =
                ChromeMV3NetworkCompatibilityReportGenerator.makeReport(
                    manifest: resolvedManifest,
                    generatedBundleRootURL: rootURL,
                    extensionID: extensionID,
                    profileID: profileID,
                    moduleState: .enabled
                )
            lastChromeMV3NetworkCompatibilityReport = report

            guard writeReport else { return report }
            return (try? ChromeMV3NetworkCompatibilityReportWriter.write(
                report,
                toRewrittenBundleRoot: rootURL
            )) ?? report
        }

        @available(macOS 15.5, *)
        func chromeMV3SidePanelOffscreenIdentityCompatibilityReportIfEnabled(
            fromRewrittenBundleRoot rootURL: URL,
            manifest: ChromeMV3Manifest? = nil,
            syntheticIdentityFixture:
                ChromeMV3IdentitySyntheticFixture = .none,
            webKitSyntheticJSExecutionSummary:
                ChromeMV3SidePanelOffscreenIdentityWebKitSyntheticJSExecutionSummary
                = .notRun,
            writeReport: Bool = false
        ) -> ChromeMV3SidePanelOffscreenIdentityCompatibilityReport? {
            guard isEnabled else { return nil }

            let rootURL = rootURL.standardizedFileURL
            let resolvedManifest =
                manifest
                ?? (try? ChromeMV3ManifestValidator.validateManifestFile(
                    at: rootURL.appendingPathComponent("manifest.json")
                ))
            let extensionID =
                lastChromeMV3RuntimeBridgePrerequisitesReport?.candidateID
                ?? lastChromeMV3TabsScriptingMVPReport?.extensionID
                ?? lastChromeMV3RuntimeJSMessagingMVPReport?.extensionID
                ?? lastChromeMV3JSBridgeContractReport?.extensionID
                ?? "sidepanel-offscreen-identity-extension"
            let profileID =
                lastChromeMV3TabsScriptingMVPReport?.profileID
                ?? lastChromeMV3RuntimeJSMessagingMVPReport?.profileID
                ?? lastChromeMV3JSBridgeContractReport?.profileID
                ?? "sidepanel-offscreen-identity-profile"
            let report =
                ChromeMV3SidePanelOffscreenIdentityCompatibilityReportGenerator
                .makeReport(
                    manifest: resolvedManifest,
                    generatedBundleRootURL: rootURL,
                    extensionID: extensionID,
                    profileID: profileID,
                    moduleState: .enabled,
                    syntheticIdentityFixture: syntheticIdentityFixture,
                    webKitSyntheticJSExecutionSummary:
                        webKitSyntheticJSExecutionSummary
                )
            lastChromeMV3SidePanelOffscreenIdentityReport = report

            guard writeReport else { return report }
            return (try?
                ChromeMV3SidePanelOffscreenIdentityCompatibilityReportWriter
                .write(report, toRewrittenBundleRoot: rootURL)) ?? report
        }

        @available(macOS 15.5, *)
        @discardableResult
        func tearDownChromeMV3SidePanelOffscreenIdentityCompatibilityIfEnabled()
            -> Bool
        {
            guard isEnabled else { return false }
            lastChromeMV3SidePanelOffscreenIdentityReport = nil
            return true
        }

        @available(macOS 15.5, *)
        @discardableResult
        func tearDownChromeMV3NetworkCompatibilityIfEnabled() -> Bool {
            guard isEnabled else { return false }
            lastChromeMV3NetworkCompatibilityReport = nil
            return true
        }

        @available(macOS 15.5, *)
        @discardableResult
        func tearDownChromeMV3ExtensionEventAPIsIfEnabled() -> Bool {
            guard isEnabled else { return false }
            lastChromeMV3ExtensionEventAPIsReport = nil
            return true
        }

        @available(macOS 15.5, *)
        func chromeMV3PermissionBrokerReadinessReportIfEnabled(
            fromRewrittenBundleRoot rootURL: URL,
            writeReport: Bool = false
        ) -> ChromeMV3PermissionBrokerReadinessReport? {
            guard isEnabled else { return nil }

            let rootURL = rootURL.standardizedFileURL
            let report: ChromeMV3PermissionBrokerReadinessReport
            do {
                report = try ChromeMV3PermissionBrokerReadinessReportGenerator
                    .makeReport(
                        loadingPrerequisitesReportFrom: rootURL
                    )
            } catch {
                return nil
            }
            lastChromeMV3PermissionBrokerReadinessReport = report

            guard writeReport else { return report }
            return (try? ChromeMV3PermissionBrokerReadinessReportWriter.write(
                report,
                toRewrittenBundleRoot: rootURL
            )) ?? report
        }

        @available(macOS 15.5, *)
        func chromeMV3PermissionLifecycleReportIfEnabled(
            fromRewrittenBundleRoot rootURL: URL,
            writeReport: Bool = false
        ) -> ChromeMV3PermissionLifecycleReport? {
            guard isEnabled else { return nil }

            let rootURL = rootURL.standardizedFileURL
            let report: ChromeMV3PermissionLifecycleReport
            do {
                report = try ChromeMV3PermissionLifecycleReportGenerator
                    .makeReport(
                        loadingPrerequisitesReportFrom: rootURL
                    )
            } catch {
                return nil
            }
            lastChromeMV3PermissionLifecycleReport = report

            guard writeReport else { return report }
            return (try? ChromeMV3PermissionLifecycleReportWriter.write(
                report,
                toRewrittenBundleRoot: rootURL
            )) ?? report
        }

        @available(macOS 15.5, *)
        func chromeMV3PermissionsAPIContractReportIfEnabled(
            fromRewrittenBundleRoot rootURL: URL,
            writeReport: Bool = false
        ) -> ChromeMV3PermissionsAPIContractReport? {
            guard isEnabled else { return nil }

            let rootURL = rootURL.standardizedFileURL
            let report: ChromeMV3PermissionsAPIContractReport
            do {
                report = try ChromeMV3PermissionsAPIContractReportGenerator
                    .makeReport(
                        loadingPrerequisitesReportFrom: rootURL
                    )
            } catch {
                return nil
            }
            lastChromeMV3PermissionsAPIContractReport = report

            guard writeReport else { return report }
            return (try? ChromeMV3PermissionsAPIContractReportWriter.write(
                report,
                toRewrittenBundleRoot: rootURL
            )) ?? report
        }

        @available(macOS 15.5, *)
        func chromeMV3PermissionImplementationReportIfEnabled(
            fromRewrittenBundleRoot rootURL: URL,
            writeReport: Bool = false
        ) -> ChromeMV3PermissionImplementationReport? {
            guard isEnabled else { return nil }

            let rootURL = rootURL.standardizedFileURL
            let report: ChromeMV3PermissionImplementationReport
            do {
                report = try ChromeMV3PermissionImplementationReportGenerator
                    .makeReport(
                        loadingPrerequisitesReportFrom: rootURL
                    )
            } catch {
                return nil
            }
            lastChromeMV3PermissionImplementationReport = report

            guard writeReport else { return report }
            return (try? ChromeMV3PermissionImplementationReportWriter.write(
                report,
                toRewrittenBundleRoot: rootURL
            )) ?? report
        }

        @available(macOS 15.5, *)
        func chromeMV3PermissionsWebKitSyntheticHarnessReportIfEnabled(
            fromRewrittenBundleRoot rootURL: URL,
            writeReport: Bool = false
        ) async -> ChromeMV3PermissionImplementationReport? {
            guard isEnabled else { return nil }

            let rootURL = rootURL.standardizedFileURL
            let extensionID =
                lastChromeMV3RuntimeBridgePrerequisitesReport?.candidateID
                ?? lastChromeMV3TabsScriptingMVPReport?.extensionID
                ?? lastChromeMV3RuntimeJSMessagingMVPReport?.extensionID
                ?? lastChromeMV3JSBridgeContractReport?.extensionID
                ?? "permissions-js-mvp-extension"
            let profileID =
                lastChromeMV3TabsScriptingMVPReport?.profileID
                ?? lastChromeMV3RuntimeJSMessagingMVPReport?.profileID
                ?? lastChromeMV3JSBridgeContractReport?.profileID
                ?? "permissions-js-mvp-profile"
            let configuration =
                ChromeMV3PermissionsJSBridgeConfiguration.syntheticHarness(
                    extensionID: extensionID,
                    profileID: profileID
                )
            let result =
                await ChromeMV3PermissionsJSSyntheticHarness.run(
                    scriptBody:
                        ChromeMV3PermissionsJSSyntheticHarness
                        .reportVerificationScriptBody,
                    configuration: configuration
                )
            let report = result.report
            lastChromeMV3PermissionImplementationReport = report

            guard writeReport else { return report }
            return (try? ChromeMV3PermissionImplementationReportWriter.write(
                report,
                toRewrittenBundleRoot: rootURL
            )) ?? report
        }

        @available(macOS 15.5, *)
        func chromeMV3PasswordManagerFixtureReportIfEnabled(
            fromRewrittenBundleRoot rootURL: URL,
            writeReport: Bool = false
        ) -> ChromeMV3PasswordManagerFixtureReport? {
            guard isEnabled else { return nil }

            let rootURL = rootURL.standardizedFileURL
            let extensionID =
                lastChromeMV3RuntimeBridgePrerequisitesReport?.candidateID
                ?? lastChromeMV3TabsScriptingMVPReport?.extensionID
                ?? lastChromeMV3RuntimeJSMessagingMVPReport?.extensionID
                ?? lastChromeMV3JSBridgeContractReport?.extensionID
                ?? "password-manager-synthetic-extension"
            let profileID =
                lastChromeMV3TabsScriptingMVPReport?.profileID
                ?? lastChromeMV3RuntimeJSMessagingMVPReport?.profileID
                ?? lastChromeMV3JSBridgeContractReport?.profileID
                ?? "password-manager-synthetic-profile"
            let report =
                ChromeMV3PasswordManagerFixtureReportGenerator.makeReport(
                    extensionID: extensionID,
                    profileID: profileID,
                    runtimeJSMessagingMVPSummary:
                        lastChromeMV3RuntimeJSMessagingMVPReport?.summary,
                    tabsScriptingMVPSummary:
                        lastChromeMV3TabsScriptingMVPReport?.summary,
                    storageLocalImplementationSummary:
                        lastChromeMV3StorageLocalImplementationReport?
                        .summary,
                    nativeMessagingReadinessSummary:
                        lastChromeMV3NativeMessagingReadinessReport?.summary,
                    nativeMessagingImplementationSummary:
                        lastChromeMV3NativeMessagingImplementationReport?
                        .summary,
                    serviceWorkerLifecycleSummary:
                        lastChromeMV3ServiceWorkerLifecycleReport?.summary,
                    sharedLifecycleSessionSummary:
                        lastChromeMV3ServiceWorkerSharedLifecycleSessionReport?
                        .summary,
                    extensionEventAPIsSummary:
                        lastChromeMV3ExtensionEventAPIsReport?.summary
                )
            lastChromeMV3PasswordManagerFixtureReport = report

            guard writeReport else { return report }
            return (try? ChromeMV3PasswordManagerFixtureReportWriter.write(
                report,
                toRewrittenBundleRoot: rootURL
            )) ?? report
        }

        @available(macOS 15.5, *)
        func chromeMV3PasswordManagerCombinedSyntheticHarnessReportIfEnabled(
            fromRewrittenBundleRoot rootURL: URL,
            writeReport: Bool = false
        ) async -> ChromeMV3PasswordManagerFixtureReport? {
            guard isEnabled else { return nil }

            let rootURL = rootURL.standardizedFileURL
            let extensionID =
                lastChromeMV3RuntimeBridgePrerequisitesReport?.candidateID
                ?? lastChromeMV3TabsScriptingMVPReport?.extensionID
                ?? lastChromeMV3RuntimeJSMessagingMVPReport?.extensionID
                ?? lastChromeMV3JSBridgeContractReport?.extensionID
                ?? "password-manager-synthetic-extension"
            let profileID =
                lastChromeMV3TabsScriptingMVPReport?.profileID
                ?? lastChromeMV3RuntimeJSMessagingMVPReport?.profileID
                ?? lastChromeMV3JSBridgeContractReport?.profileID
                ?? "password-manager-synthetic-profile"
            let configuration =
                ChromeMV3PasswordManagerCombinedHarnessConfiguration
                .syntheticHarness(
                    extensionID: extensionID,
                    profileID: profileID
                )
            let result =
                await ChromeMV3PasswordManagerCombinedSyntheticHarness.run(
                    scriptBody:
                        ChromeMV3PasswordManagerCombinedSyntheticHarness
                        .reportVerificationScriptBody,
                    configuration: configuration
                )
            let report =
                ChromeMV3PasswordManagerFixtureReportGenerator.makeReport(
                    extensionID: extensionID,
                    profileID: profileID,
                    webKitExecutionSummary: result.webKitExecutionSummary,
                    runtimeJSMessagingMVPSummary:
                        lastChromeMV3RuntimeJSMessagingMVPReport?.summary,
                    tabsScriptingMVPSummary:
                        lastChromeMV3TabsScriptingMVPReport?.summary,
                    storageLocalImplementationSummary:
                        lastChromeMV3StorageLocalImplementationReport?
                        .summary,
                    nativeMessagingReadinessSummary:
                        lastChromeMV3NativeMessagingReadinessReport?.summary,
                    nativeMessagingImplementationSummary:
                        lastChromeMV3NativeMessagingImplementationReport?
                        .summary,
                    serviceWorkerLifecycleSummary:
                        lastChromeMV3ServiceWorkerLifecycleReport?.summary,
                    sharedLifecycleSessionSummary:
                        lastChromeMV3ServiceWorkerSharedLifecycleSessionReport?
                        .summary,
                    extensionEventAPIsSummary:
                        lastChromeMV3ExtensionEventAPIsReport?.summary
                )
            lastChromeMV3PasswordManagerFixtureReport = report

            guard writeReport else { return report }
            return (try? ChromeMV3PasswordManagerFixtureReportWriter.write(
                report,
                toRewrittenBundleRoot: rootURL
            )) ?? report
        }

        @available(macOS 15.5, *)
        @discardableResult
        func tearDownChromeMV3PasswordManagerFixtureIfEnabled() -> Bool {
            guard isEnabled else { return false }
            lastChromeMV3PasswordManagerFixtureReport = nil
            lastChromeMV3PasswordManagerCompatibilityReport = nil
            return true
        }

        @available(macOS 15.5, *)
        func chromeMV3PasswordManagerCompatibilityPassIfEnabled(
            rootURL: URL,
            explicitPackageRootURL: URL? = nil,
            writeReport: Bool = true
        ) -> ChromeMV3PasswordManagerCompatibilityReport? {
            guard isEnabled else { return nil }

            let report =
                ChromeMV3PasswordManagerCompatibilityPassRunner.run(
                    rootURL: rootURL,
                    explicitPackageRootURL: explicitPackageRootURL,
                    writeReport: writeReport
                )
            lastChromeMV3PasswordManagerCompatibilityReport = report
            return report
        }

        @available(macOS 15.5, *)
        @discardableResult
        func runChromeMV3ExtensionObjectProbeIfEnabled(
            explicitInternalExtensionObjectProbeAllowed: Bool,
            candidate: ChromeMV3RewrittenVariantCandidate,
            runtimeLoadabilityReport: ChromeMV3RuntimeLoadabilityReport?
        ) async -> ChromeMV3ExtensionObjectProbeDiagnostics? {
            guard isEnabled else { return nil }
            guard
                let decision =
                    chromeMV3ExtensionObjectProbeGateDecisionIfEnabled(
                        explicitInternalExtensionObjectProbeAllowed:
                            explicitInternalExtensionObjectProbeAllowed,
                        candidate: candidate,
                        runtimeLoadabilityReport: runtimeLoadabilityReport
                    )
            else {
                return nil
            }

            guard decision.canCreateExtensionObjectNow else {
                let diagnostics = ChromeMV3ExtensionObjectProbeDiagnostics.blocked(
                    gateDecision: decision
                )
                _ = chromeMV3WebKitObjectAcceptanceReportIfEnabled(
                    explicitInternalExtensionObjectProbeAllowed:
                        explicitInternalExtensionObjectProbeAllowed,
                    candidate: candidate,
                    runtimeLoadabilityReport: runtimeLoadabilityReport,
                    probeDiagnostics: diagnostics,
                    writeReport: true
                )
                return diagnostics
            }

            if let cachedChromeMV3ExtensionObjectProbeOwner,
               cachedChromeMV3ExtensionObjectProbeOwner
                .diagnostics()
                .resourceBaseURLPath == decision.input.resourceBaseURLPath
            {
                let diagnostics = await cachedChromeMV3ExtensionObjectProbeOwner
                    .runProbeIfAllowed()
                _ = chromeMV3WebKitObjectAcceptanceReportIfEnabled(
                    explicitInternalExtensionObjectProbeAllowed:
                        explicitInternalExtensionObjectProbeAllowed,
                    candidate: candidate,
                    runtimeLoadabilityReport: runtimeLoadabilityReport,
                    probeDiagnostics: diagnostics,
                    writeReport: true
                )
                return diagnostics
            }

            cachedChromeMV3ExtensionObjectProbeOwner?.tearDown()
            let owner = ChromeMV3ExtensionObjectProbeOwner(
                gateDecision: decision
            )
            cachedChromeMV3ExtensionObjectProbeOwner = owner
            let diagnostics = await owner.runProbeIfAllowed()
            _ = chromeMV3WebKitObjectAcceptanceReportIfEnabled(
                explicitInternalExtensionObjectProbeAllowed:
                    explicitInternalExtensionObjectProbeAllowed,
                candidate: candidate,
                runtimeLoadabilityReport: runtimeLoadabilityReport,
                probeDiagnostics: diagnostics,
                writeReport: true
            )
            return diagnostics
        }

        @available(macOS 15.5, *)
        @discardableResult
        func tearDownChromeMV3ExtensionObjectProbeIfEnabled()
            -> ChromeMV3ExtensionObjectProbeDiagnostics?
        {
            guard isEnabled else { return nil }
            cachedChromeMV3DetachedContextOwner?.tearDown()
            cachedChromeMV3DetachedContextOwner = nil
            let diagnostics =
                cachedChromeMV3ExtensionObjectProbeOwner?.tearDown()
            cachedChromeMV3ExtensionObjectProbeOwner = nil
            return diagnostics
        }

        @available(macOS 15.5, *)
        @discardableResult
        func tearDownChromeMV3DetachedContextIfEnabled()
            -> ChromeMV3DetachedContextOwnerDiagnostics?
        {
            guard isEnabled else { return nil }
            let diagnostics =
                cachedChromeMV3DetachedContextOwner?.tearDown()
            cachedChromeMV3DetachedContextOwner = nil
            return diagnostics
        }

        func chromeMV3ImportInternalExtensionIfEnabled(
            rootURL: URL,
            sourceURL: URL,
            profileID: String = "internal-debug-profile",
            enableInternal: Bool = false
        ) -> ChromeMV3LifecycleOperationResult? {
            guard isEnabled else { return nil }
            let result = ChromeMV3ExtensionLifecycleRegistry(rootURL: rootURL)
                .installUnpackedExtension(
                    at: sourceURL,
                    profileID: profileID,
                    enableInternal: enableInternal,
                    runtimeDiagnostics:
                        chromeMV3LifecycleRuntimeDiagnosticsSnapshot()
                )
            lastChromeMV3EndToEndInstallDiagnosticsReport = result.report
            return result
        }

        func chromeMV3RebuildInternalExtensionIfEnabled(
            rootURL: URL,
            profileID: String,
            extensionID: String
        ) -> ChromeMV3LifecycleOperationResult? {
            guard isEnabled else { return nil }
            let result = ChromeMV3ExtensionLifecycleRegistry(rootURL: rootURL)
                .rebuildExtension(
                    profileID: profileID,
                    extensionID: extensionID,
                    runtimeDiagnostics:
                        chromeMV3LifecycleRuntimeDiagnosticsSnapshot()
                )
            lastChromeMV3EndToEndInstallDiagnosticsReport = result.report
            return result
        }

        func chromeMV3UpdateInternalExtensionIfEnabled(
            rootURL: URL,
            profileID: String,
            extensionID: String,
            sourceURL: URL
        ) -> ChromeMV3LifecycleOperationResult? {
            guard isEnabled else { return nil }
            let result = ChromeMV3ExtensionLifecycleRegistry(rootURL: rootURL)
                .updateExtension(
                    profileID: profileID,
                    extensionID: extensionID,
                    from: sourceURL,
                    runtimeDiagnostics:
                        chromeMV3LifecycleRuntimeDiagnosticsSnapshot()
                )
            lastChromeMV3EndToEndInstallDiagnosticsReport = result.report
            return result
        }

        func chromeMV3UninstallInternalExtensionIfEnabled(
            rootURL: URL,
            profileID: String,
            extensionID: String
        ) -> ChromeMV3LifecycleOperationResult? {
            guard isEnabled else { return nil }
            if #available(macOS 15.5, *) {
                tearDownChromeMV3ControllerLoadOwner()
                tearDownChromeMV3DetachedContextOwner()
                tearDownChromeMV3ExtensionObjectProbeOwner()
            }
            tearDownChromeMV3EmptyControllerOwner()
            let result = ChromeMV3ExtensionLifecycleRegistry(rootURL: rootURL)
                .uninstallExtension(profileID: profileID, extensionID: extensionID)
            lastChromeMV3EndToEndInstallDiagnosticsReport = result.report
            return result
        }

        func chromeMV3ResetInternalExtensionStateIfEnabled(
            rootURL: URL,
            profileID: String,
            extensionID: String
        ) -> ChromeMV3LifecycleOperationResult? {
            guard isEnabled else { return nil }
            if #available(macOS 15.5, *) {
                tearDownChromeMV3ControllerLoadOwner()
                tearDownChromeMV3DetachedContextOwner()
            }
            tearDownChromeMV3EmptyControllerOwner()
            let result = ChromeMV3ExtensionLifecycleRegistry(rootURL: rootURL)
                .resetExtensionState(profileID: profileID, extensionID: extensionID)
            lastChromeMV3EndToEndInstallDiagnosticsReport = result.report
            return result
        }

        func chromeMV3RunEndToEndDiagnosticsIfEnabled(
            rootURL: URL,
            profileID: String,
            extensionID: String
        ) -> ChromeMV3EndToEndInstallDiagnosticsReport? {
            guard isEnabled else { return nil }
            let report = ChromeMV3ExtensionLifecycleRegistry(rootURL: rootURL)
                .writeEndToEndDiagnostics(
                    profileID: profileID,
                    extensionID: extensionID,
                    runtimeDiagnostics:
                        chromeMV3LifecycleRuntimeDiagnosticsSnapshot()
                )
            lastChromeMV3EndToEndInstallDiagnosticsReport = report
            return report
        }

        func chromeMV3LatestEndToEndDiagnosticsReportIfEnabled(
            rootURL: URL,
            profileID: String,
            extensionID: String
        ) -> ChromeMV3EndToEndInstallDiagnosticsReport? {
            guard isEnabled else { return nil }
            let report = ChromeMV3ExtensionLifecycleRegistry(rootURL: rootURL)
                .latestEndToEndDiagnosticsReport(
                    profileID: profileID,
                    extensionID: extensionID
                )
            lastChromeMV3EndToEndInstallDiagnosticsReport =
                report ?? lastChromeMV3EndToEndInstallDiagnosticsReport
            return report
        }

        func chromeMV3ListInternalCompatibilityDiagnosticsIfEnabled(
            rootURL: URL
        ) -> [ChromeMV3CompatibilityReportViewModel]? {
            guard isEnabled else { return nil }
            return ChromeMV3ExtensionLifecycleRegistry(rootURL: rootURL)
                .listCompatibilityReportViewModels()
        }

        func chromeMV3CompatibilityReportViewModelIfEnabled(
            rootURL: URL,
            profileID: String,
            extensionID: String
        ) -> ChromeMV3CompatibilityReportViewModel? {
            guard isEnabled else { return nil }
            return ChromeMV3ExtensionLifecycleRegistry(rootURL: rootURL)
                .compatibilityReportViewModel(
                    profileID: profileID,
                    extensionID: extensionID
                )
        }

        func chromeMV3ProductEnablementPreflightIfEnabled(
            rootURL: URL,
            profileID: String,
            extensionID: String,
            gateSet: ChromeMV3ProductRuntimeGateSet? = nil
        ) -> ChromeMV3ProductEnablementPreflightSection? {
            guard isEnabled else { return nil }
            let registry = ChromeMV3ExtensionLifecycleRegistry(rootURL: rootURL)
            let record = registry.loadLifecycleRecord(
                profileID: profileID,
                extensionID: extensionID
            )
            let report = registry.latestEndToEndDiagnosticsReport(
                profileID: profileID,
                extensionID: extensionID
            )
            guard record != nil || report != nil else { return nil }
            return ChromeMV3ProductEnablementPreflightSection.make(
                report: report,
                lifecycleRecord: record,
                gateSet: gateSet
            )
        }

        func chromeMV3ExportCompatibilityReportJSONIfEnabled(
            rootURL: URL,
            profileID: String,
            extensionID: String
        ) -> String? {
            guard isEnabled else { return nil }
            return ChromeMV3ExtensionLifecycleRegistry(rootURL: rootURL)
                .exportLatestEndToEndDiagnosticsJSON(
                    profileID: profileID,
                    extensionID: extensionID
                )
        }

        func chromeMV3RunArtifactCleanupIfEnabled(
            rootURL: URL,
            profileID: String,
            extensionID: String
        ) -> ChromeMV3ArtifactCleanupReport? {
            guard isEnabled else { return nil }
            if #available(macOS 15.5, *) {
                tearDownChromeMV3ControllerLoadOwner()
                tearDownChromeMV3DetachedContextOwner()
                tearDownChromeMV3ExtensionObjectProbeOwner()
            }
            tearDownChromeMV3EmptyControllerOwner()
            return ChromeMV3ExtensionLifecycleRegistry(rootURL: rootURL)
                .runArtifactCleanup(
                    profileID: profileID,
                    extensionID: extensionID
                )
        }

        func chromeMV3RunFinalFoundationReadinessReportIfEnabled(
            rootURL: URL,
            profileID: String,
            extensionID: String
        ) -> ChromeMV3FoundationReadinessReport? {
            guard isEnabled else { return nil }
            return ChromeMV3ExtensionLifecycleRegistry(rootURL: rootURL)
                .writeFoundationReadinessReport(
                    profileID: profileID,
                    extensionID: extensionID
                )
        }

        func chromeMV3WriteInternalCrashMarkerIfEnabled(
            rootURL: URL,
            profileID: String,
            extensionID: String,
            reason: String,
            lifecycleSessionLeftActive: Bool = true,
            nativeFixturePortLeftOpen: Bool = false
        ) -> ChromeMV3LifecycleOperationResult? {
            guard isEnabled else { return nil }
            return ChromeMV3ExtensionLifecycleRegistry(rootURL: rootURL)
                .writeCrashMarker(
                    profileID: profileID,
                    extensionID: extensionID,
                    reason: reason,
                    lifecycleSessionLeftActive: lifecycleSessionLeftActive,
                    nativeFixturePortLeftOpen: nativeFixturePortLeftOpen
                )
        }

        func chromeMV3RecoverInternalExtensionsIfEnabled(
            rootURL: URL,
            profileID: String,
            extensionID: String
        ) -> ChromeMV3LifecycleOperationResult? {
            guard isEnabled else { return nil }
            if #available(macOS 15.5, *) {
                tearDownChromeMV3ControllerLoadOwner()
                tearDownChromeMV3DetachedContextOwner()
                tearDownChromeMV3ExtensionObjectProbeOwner()
            }
            tearDownChromeMV3EmptyControllerOwner()
            let result = ChromeMV3ExtensionLifecycleRegistry(rootURL: rootURL)
                .runRecoveryScan(profileID: profileID, extensionID: extensionID)
            lastChromeMV3EndToEndInstallDiagnosticsReport = result.report
            return result
        }
    #endif

    func chromeMV3ExtensionManagerGate() -> ChromeMV3ExtensionManagerGate {
        ChromeMV3ExtensionManagerGate.evaluate(moduleEnabled: isEnabled)
    }

    func chromeMV3ExtensionManagerListViewModelIfEnabled(
        rootURL: URL,
        now: Date = Date()
    ) -> ChromeMV3ExtensionManagerListViewModel? {
        guard isEnabled else { return nil }
        return ChromeMV3ExtensionManagerViewModelBuilder.makeListViewModel(
            rootURL: rootURL,
            gate: chromeMV3ExtensionManagerGate(),
            now: now
        )
    }

    func chromeMV3ExtensionManagerDetailViewModelIfEnabled(
        rootURL: URL,
        profileID: String,
        extensionID: String
    ) -> ChromeMV3ExtensionManagerDetailViewModel? {
        guard isEnabled else { return nil }
        var detail = ChromeMV3ExtensionManagerViewModelBuilder.makeDetailViewModel(
            rootURL: rootURL,
            profileID: profileID,
            extensionID: extensionID,
            gate: chromeMV3ExtensionManagerGate()
        )
        if
            lastChromeMV3PopupOptionsRunResult?.launchRecord?.profileID
                == profileID,
            lastChromeMV3PopupOptionsRunResult?.launchRecord?.extensionID
                == extensionID
        {
            detail?.popupOptionsLaunchState.lastRunResult =
                lastChromeMV3PopupOptionsRunResult
        }
        return detail
    }

    func chromeMV3InstallUnpackedThroughManager(
        rootURL: URL,
        sourceURL: URL,
        profileID: String? = nil,
        enableInternal: Bool = false
    ) -> ChromeMV3ExtensionManagerActionResult {
        let gate = chromeMV3ExtensionManagerGate()
        guard gate.managerAvailableInDeveloperPreview else {
            return ChromeMV3ExtensionManagerActionResult.blocked(
                action: .installUnpacked,
                diagnostics: gate.diagnostics
            )
        }
        let result = ChromeMV3ExtensionManagerActionRunner.installUnpacked(
            rootURL: rootURL,
            sourceURL: sourceURL,
            profileID: resolvedChromeMV3ManagerProfileID(profileID),
            enableInternal: enableInternal,
            gate: gate,
            runtimeDiagnostics:
                chromeMV3ExtensionManagerRuntimeDiagnosticsSnapshot()
        )
        #if DEBUG
            lastChromeMV3EndToEndInstallDiagnosticsReport = result.report
        #endif
        return result
    }

    func chromeMV3PreflightLocalZipArchiveIfEnabled(
        rootURL: URL = ChromeMV3ExtensionManagerStoreLocation.defaultRootURL(),
        sourceURL: URL
    ) -> ChromeMV3PackageIntakeReport? {
        guard isEnabled else { return nil }
        return ChromeMV3PackageIntakeService(rootURL: rootURL)
            .preflightLocalZIPArchive(sourceURL: sourceURL)
    }

    func chromeMV3PreflightLocalCRXArchiveIfEnabled(
        rootURL: URL = ChromeMV3ExtensionManagerStoreLocation.defaultRootURL(),
        sourceURL: URL
    ) -> ChromeMV3PackageIntakeReport? {
        guard isEnabled else { return nil }
        return ChromeMV3PackageIntakeService(rootURL: rootURL)
            .preflightLocalCRXArchive(sourceURL: sourceURL)
    }

    func chromeMV3DiagnoseChromeWebStoreInputIfEnabled(
        rootURL: URL = ChromeMV3ExtensionManagerStoreLocation.defaultRootURL(),
        input: String
    ) -> ChromeMV3PackageIntakeReport? {
        guard isEnabled else { return nil }
        return ChromeMV3PackageIntakeService(rootURL: rootURL)
            .diagnoseChromeWebStoreInput(input)
    }

    func chromeMV3LatestPackageIntakeReportIfEnabled(
        rootURL: URL = ChromeMV3ExtensionManagerStoreLocation.defaultRootURL()
    ) -> ChromeMV3PackageIntakeReport? {
        guard isEnabled else { return nil }
        return ChromeMV3PackageIntakeService.latestReport(rootURL: rootURL)
    }

    func chromeMV3ImportLocalArchiveThroughManager(
        rootURL: URL = ChromeMV3ExtensionManagerStoreLocation.defaultRootURL(),
        sourceURL: URL,
        profileID: String? = nil,
        enableInternal: Bool = false
    ) -> ChromeMV3ExtensionManagerActionResult {
        let gate = chromeMV3ExtensionManagerGate()
        guard gate.managerAvailableInDeveloperPreview else {
            let action: ChromeMV3ExtensionManagerActionKind =
                sourceURL.pathExtension.lowercased() == "crx"
                    ? .importCRXArchive : .importZipArchive
            return ChromeMV3ExtensionManagerActionResult.blocked(
                action: action,
                diagnostics: gate.diagnostics
            )
        }
        let result = ChromeMV3ExtensionManagerActionRunner.importLocalArchive(
            rootURL: rootURL,
            sourceURL: sourceURL,
            profileID: resolvedChromeMV3ManagerProfileID(profileID),
            enableInternal: enableInternal,
            gate: gate,
            runtimeDiagnostics:
                chromeMV3ExtensionManagerRuntimeDiagnosticsSnapshot()
        )
        #if DEBUG
            lastChromeMV3EndToEndInstallDiagnosticsReport = result.report
        #endif
        return result
    }

    func chromeMV3UpdateUnpackedThroughManager(
        rootURL: URL,
        profileID: String,
        extensionID: String,
        sourceURL: URL
    ) -> ChromeMV3ExtensionManagerActionResult {
        let gate = chromeMV3ExtensionManagerGate()
        guard gate.managerAvailableInDeveloperPreview else {
            return ChromeMV3ExtensionManagerActionResult.blocked(
                action: .updateFromUnpacked,
                diagnostics: gate.diagnostics
            )
        }
        let result = ChromeMV3ExtensionManagerActionRunner.updateFromUnpacked(
            rootURL: rootURL,
            profileID: profileID,
            extensionID: extensionID,
            sourceURL: sourceURL,
            gate: gate,
            runtimeDiagnostics:
                chromeMV3ExtensionManagerRuntimeDiagnosticsSnapshot()
        )
        #if DEBUG
            lastChromeMV3EndToEndInstallDiagnosticsReport = result.report
        #endif
        return result
    }

    func chromeMV3SetInternalExtensionEnabledThroughManager(
        _ enabled: Bool,
        rootURL: URL,
        profileID: String,
        extensionID: String
    ) -> ChromeMV3ExtensionManagerActionResult {
        let gate = chromeMV3ExtensionManagerGate()
        guard gate.managerAvailableInDeveloperPreview else {
            return ChromeMV3ExtensionManagerActionResult.blocked(
                action: enabled ? .enableInternal : .disableInternal,
                diagnostics: gate.diagnostics
            )
        }
        let result = ChromeMV3ExtensionManagerActionRunner.setInternalEnabled(
            enabled,
            rootURL: rootURL,
            profileID: profileID,
            extensionID: extensionID,
            gate: gate
        )
        if enabled == false {
            _ = cachedChromeMV3PopupOptionsHostController?.close(
                profileID: profileID,
                extensionID: extensionID,
                reason: .disabledWhileOpen
            )
        }
        #if DEBUG
            lastChromeMV3EndToEndInstallDiagnosticsReport = result.report
        #endif
        return result
    }

    func chromeMV3RebuildThroughManager(
        rootURL: URL,
        profileID: String,
        extensionID: String
    ) -> ChromeMV3ExtensionManagerActionResult {
        let gate = chromeMV3ExtensionManagerGate()
        guard gate.managerAvailableInDeveloperPreview else {
            return ChromeMV3ExtensionManagerActionResult.blocked(
                action: .rebuild,
                diagnostics: gate.diagnostics
            )
        }
        let result = ChromeMV3ExtensionManagerActionRunner.rebuild(
            rootURL: rootURL,
            profileID: profileID,
            extensionID: extensionID,
            gate: gate,
            runtimeDiagnostics:
                chromeMV3ExtensionManagerRuntimeDiagnosticsSnapshot()
        )
        #if DEBUG
            lastChromeMV3EndToEndInstallDiagnosticsReport = result.report
        #endif
        return result
    }

    func chromeMV3RetryDiagnosticsThroughManager(
        rootURL: URL,
        profileID: String,
        extensionID: String
    ) -> ChromeMV3ExtensionManagerActionResult {
        let gate = chromeMV3ExtensionManagerGate()
        guard gate.managerAvailableInDeveloperPreview else {
            return ChromeMV3ExtensionManagerActionResult.blocked(
                action: .retryDiagnostics,
                diagnostics: gate.diagnostics
            )
        }
        let result = ChromeMV3ExtensionManagerActionRunner.rebuild(
            rootURL: rootURL,
            profileID: profileID,
            extensionID: extensionID,
            action: .retryDiagnostics,
            gate: gate,
            runtimeDiagnostics:
                chromeMV3ExtensionManagerRuntimeDiagnosticsSnapshot()
        )
        #if DEBUG
            lastChromeMV3EndToEndInstallDiagnosticsReport = result.report
        #endif
        return result
    }

    func chromeMV3RunDiagnosticsThroughManager(
        rootURL: URL,
        profileID: String,
        extensionID: String
    ) -> ChromeMV3ExtensionManagerActionResult {
        let gate = chromeMV3ExtensionManagerGate()
        guard gate.managerAvailableInDeveloperPreview else {
            return ChromeMV3ExtensionManagerActionResult.blocked(
                action: .runDiagnostics,
                diagnostics: gate.diagnostics
            )
        }
        let result = ChromeMV3ExtensionManagerActionRunner.runDiagnostics(
            rootURL: rootURL,
            profileID: profileID,
            extensionID: extensionID,
            gate: gate,
            runtimeDiagnostics:
                chromeMV3ExtensionManagerRuntimeDiagnosticsSnapshot()
        )
        #if DEBUG
            lastChromeMV3EndToEndInstallDiagnosticsReport = result.report
        #endif
        return result
    }

    func chromeMV3RunBitwardenManualSmokeThroughManager(
        rootURL: URL,
        profileID: String,
        extensionID: String,
        now: @escaping () -> Date = Date.init
    ) async -> ChromeMV3ExtensionManagerActionResult {
        let gate = chromeMV3ExtensionManagerGate()
        guard gate.managerAvailableInDeveloperPreview else {
            return ChromeMV3ExtensionManagerActionResult.blocked(
                action: .runBitwardenManualSmoke,
                diagnostics: gate.diagnostics
                    + [.manualSmokeLocalExperimentalGateClosed]
            )
        }
        return await ChromeMV3ExtensionManagerActionRunner
            .runBitwardenManualSmoke(
                rootURL: rootURL,
                profileID: profileID,
                extensionID: extensionID,
                gate: gate,
                now: now
            )
    }

    func chromeMV3RecoverThroughManager(
        rootURL: URL,
        profileID: String,
        extensionID: String
    ) -> ChromeMV3ExtensionManagerActionResult {
        let gate = chromeMV3ExtensionManagerGate()
        guard gate.managerAvailableInDeveloperPreview else {
            return ChromeMV3ExtensionManagerActionResult.blocked(
                action: .recover,
                diagnostics: gate.diagnostics
            )
        }
        tearDownChromeMV3ManagerRuntimeOwners()
        let result = ChromeMV3ExtensionManagerActionRunner.recover(
            rootURL: rootURL,
            profileID: profileID,
            extensionID: extensionID,
            gate: gate
        )
        #if DEBUG
            lastChromeMV3EndToEndInstallDiagnosticsReport = result.report
        #endif
        return result
    }

    func chromeMV3UninstallThroughManager(
        rootURL: URL,
        profileID: String,
        extensionID: String
    ) -> ChromeMV3ExtensionManagerActionResult {
        let gate = chromeMV3ExtensionManagerGate()
        guard gate.managerAvailableInDeveloperPreview else {
            return ChromeMV3ExtensionManagerActionResult.blocked(
                action: .uninstall,
                diagnostics: gate.diagnostics
            )
        }
        tearDownChromeMV3ManagerRuntimeOwners()
        _ = cachedChromeMV3PopupOptionsHostController?.close(
            profileID: profileID,
            extensionID: extensionID,
            reason: .uninstalledWhileOpen
        )
        let result = ChromeMV3ExtensionManagerActionRunner.uninstall(
            rootURL: rootURL,
            profileID: profileID,
            extensionID: extensionID,
            gate: gate
        )
        #if DEBUG
            lastChromeMV3EndToEndInstallDiagnosticsReport = result.report
        #endif
        return result
    }

    func chromeMV3ResetThroughManager(
        rootURL: URL,
        profileID: String,
        extensionID: String
    ) -> ChromeMV3ExtensionManagerActionResult {
        let gate = chromeMV3ExtensionManagerGate()
        guard gate.managerAvailableInDeveloperPreview else {
            return ChromeMV3ExtensionManagerActionResult.blocked(
                action: .reset,
                diagnostics: gate.diagnostics
            )
        }
        tearDownChromeMV3ManagerRuntimeOwners()
        _ = cachedChromeMV3PopupOptionsHostController?.close(
            profileID: profileID,
            extensionID: extensionID,
            reason: .resetWhileOpen
        )
        let result = ChromeMV3ExtensionManagerActionRunner.reset(
            rootURL: rootURL,
            profileID: profileID,
            extensionID: extensionID,
            gate: gate
        )
        #if DEBUG
            lastChromeMV3EndToEndInstallDiagnosticsReport = result.report
        #endif
        return result
    }

    func chromeMV3RunPermissionControlThroughManager(
        _ kind: ChromeMV3ExtensionManagerPermissionControlKind,
        rootURL: URL,
        profileID: String,
        extensionID: String,
        value: String,
        permissionPromptPresenter:
            ChromeMV3PermissionPromptPresenting? = nil
    ) -> ChromeMV3ExtensionManagerPermissionActionResult {
        let blocked: ([String]) -> ChromeMV3ExtensionManagerPermissionActionResult = {
            diagnostics in
            ChromeMV3ExtensionManagerPermissionActionResult(
                kind: kind,
                value: value,
                succeeded: false,
                returnedBoolean: false,
                promptRequest: nil,
                promptResult: nil,
                promptLifecycleRecords: [],
                runtimeSnapshot: nil,
                eventDispatchRecord: nil,
                serviceWorkerWakeAttempted: false,
                hiddenExtensionPageCreated: false,
                diagnostics: diagnostics
            )
        }
        guard isEnabled else {
            return blocked([
                "The extensions module is disabled; manager permission controls are blocked.",
            ])
        }
        let gate = chromeMV3ExtensionManagerGate()
        guard gate.managerAvailableInDeveloperPreview else {
            return blocked(gate.diagnostics.map(\.message))
        }
        let registry = ChromeMV3ExtensionLifecycleRegistry(rootURL: rootURL)
        guard
            let record = registry.loadLifecycleRecord(
                profileID: profileID,
                extensionID: extensionID
            )
        else {
            return blocked([
                "The internal MV3 lifecycle record was not found.",
            ])
        }
        guard record.runtimeState.internalRuntimeEnabled else {
            return blocked([
                "The extension is disabled; permission manager controls are blocked.",
            ])
        }
        let report = registry.latestEndToEndDiagnosticsReport(
            profileID: profileID,
            extensionID: extensionID
        )
        let manifestSummary = ChromeMV3ExtensionManagerManifestSummaryViewState
            .make(summary: report?.managerActiveManifestSummary, record: record)
        let promptGate = ChromeMV3PermissionPromptGateRecord.evaluate(
            moduleEnabled: gate.managerAvailableInDeveloperPreview,
            extensionEnabled: record.runtimeState.internalRuntimeEnabled,
            developerPreviewGate: gate.managerAvailableInDeveloperPreview,
            publicProductGate: false
        )
        let stateStore = ChromeMV3DeveloperPreviewPermissionStateStore(
            rootURL: rootURL
        )
        var owner = stateStore.loadRuntimeOwner(
            profileID: profileID,
            extensionID: extensionID,
            manifestSummary: manifestSummary
        )
        var promptRequests: [ChromeMV3PermissionPromptRequest] =
            stateStore.loadRecord(
                profileID: profileID,
                extensionID: extensionID
            )?.promptRequests ?? []
        var promptResults: [ChromeMV3PermissionPromptResultRecord] =
            stateStore.loadRecord(
                profileID: profileID,
                extensionID: extensionID
            )?.promptResults ?? []
        var lifecycle: [ChromeMV3PermissionPromptLifecycleRecord] =
            stateStore.loadRecord(
                profileID: profileID,
                extensionID: extensionID
            )?.promptLifecycleRecords ?? []

        func save(_ diagnostics: [String]) {
            _ = try? stateStore.save(
                owner: owner,
                gateRecord: promptGate,
                promptRequests: promptRequests,
                promptResults: promptResults,
                promptLifecycleRecords: lifecycle,
                diagnostics: diagnostics
            )
        }

        func input(
            permissions: [String] = [],
            origins: [String] = []
        ) -> ChromeMV3PermissionsAPIRequestInput {
            ChromeMV3PermissionsAPIRequestInput(
                extensionID: extensionID,
                profileID: profileID,
                sourceContext: .testFixture,
                userGestureModeled: true,
                extensionModuleEnabled: true,
                permissions: permissions,
                origins: origins
            )
        }

        switch kind {
        case .requestOptionalAPIPermission, .requestOptionalHostPermission:
            let requestInput = kind == .requestOptionalAPIPermission
                ? input(permissions: [value])
                : input(origins: [value])
            let requestResult = ChromeMV3PermissionsAPIContractEvaluator
                .request(
                    input: requestInput,
                    permissionStore: owner.permissionStore,
                    activeTabStore: owner.activeTabStore
                )
            let promptRequest = ChromeMV3PermissionPromptRequest.make(
                sequence:
                    promptRequests.count + promptResults.count
                    + lifecycle.count + 1,
                extensionName: record.displayName,
                sourceSurface: .extensionManager,
                input: requestInput,
                requestResult: requestResult,
                permissionStore: owner.permissionStore,
                gateRecord: promptGate
            )
            promptRequests.append(promptRequest)
            lifecycle.append(
                ChromeMV3PermissionPromptLifecycleRecord(
                    request: promptRequest,
                    stage: .promptCreated,
                    diagnostics: [
                        "Manager permission control created a prompt request.",
                    ]
                )
            )
            guard requestResult.wouldRequirePrompt,
                  promptRequest.promptEligibility.canPrompt
            else {
                let application = owner.request(input: requestInput)
                let promptResult = promptRequest.result(
                    ChromeMV3PermissionPromptResultDisposition.blocked,
                    diagnostics: promptRequest.promptEligibility.diagnostics
                )
                promptResults.append(promptResult)
                lifecycle.append(
                    ChromeMV3PermissionPromptLifecycleRecord(
                        request: promptRequest,
                        stage: .blocked,
                        resultDisposition:
                            ChromeMV3PermissionPromptResultDisposition.blocked,
                        diagnostics: promptResult.diagnostics
                    )
                )
                save(application.diagnostics)
                return ChromeMV3ExtensionManagerPermissionActionResult(
                    kind: kind,
                    value: value,
                    succeeded: false,
                    returnedBoolean: false,
                    promptRequest: promptRequest,
                    promptResult: promptResult,
                    promptLifecycleRecords: lifecycle,
                    runtimeSnapshot: owner.snapshot,
                    eventDispatchRecord: nil,
                    serviceWorkerWakeAttempted: false,
                    hiddenExtensionPageCreated: false,
                    diagnostics: application.diagnostics
                        + promptResult.diagnostics
                )
            }
            lifecycle.append(
                ChromeMV3PermissionPromptLifecycleRecord(
                    request: promptRequest,
                    stage: .promptPresented,
                    diagnostics: [
                        "Manager permission control invoked the developer-preview presenter.",
                    ]
                )
            )
            let presenter = permissionPromptPresenter
                ?? ChromeMV3AppHostedPermissionPromptPresenter()
            let promptResult =
                presenter.presentChromeMV3PermissionPrompt(promptRequest)
            promptResults.append(promptResult)
            let stage: ChromeMV3PermissionPromptLifecycleStage
            switch promptResult.disposition {
            case .accepted:
                stage = .accepted
            case .denied:
                stage = .denied
            case .dismissed:
                stage = .dismissed
            case .blocked, .unavailable:
                stage = .blocked
            }
            lifecycle.append(
                ChromeMV3PermissionPromptLifecycleRecord(
                    request: promptRequest,
                    stage: stage,
                    resultDisposition: promptResult.disposition,
                    diagnostics: promptResult.diagnostics
                )
            )
            let modeled: ChromeMV3ModeledPermissionPromptResult
            switch promptResult.disposition {
            case .accepted:
                modeled = .accepted
            case .denied:
                modeled = .denied
            case .dismissed:
                modeled = .dismissed
            case .blocked, .unavailable:
                modeled = .notProvided
            }
            let application = owner.request(
                input: requestInput,
                modeledPromptResult: modeled,
                productPromptResult: promptResult
            )
            let dispatch = promptResult.disposition
                == ChromeMV3PermissionPromptResultDisposition.accepted
                ? chromeMV3PermissionEventDispatcher
                    .dispatchChromeMV3PermissionEvent(
                        application.result.eventPayloadIfAccepted
                            ?? ChromeMV3PermissionsAPIContractEvaluator
                            .addedEventPayload(
                                requestInput: requestResult.input,
                                itemDecisions: requestResult.itemDecisions,
                                source: .requestAccepted
                            ),
                        sourceSurfaceID: nil
                    )
                : nil
            if promptResult.disposition
                == ChromeMV3PermissionPromptResultDisposition.accepted
            {
                lifecycle.append(
                    ChromeMV3PermissionPromptLifecycleRecord(
                        request: promptRequest,
                        stage: .downstreamInvalidated,
                        resultDisposition: promptResult.disposition,
                        diagnostics:
                            dispatch?.diagnostics
                            ?? [
                                "Manager permission control had no permissions.onAdded payload for downstream invalidation diagnostics.",
                            ]
                    )
                )
            }
            lifecycle.append(
                ChromeMV3PermissionPromptLifecycleRecord(
                    request: promptRequest,
                    stage: .resultPersisted,
                    resultDisposition: promptResult.disposition,
                    diagnostics: application.diagnostics
                )
            )
            save(application.diagnostics)
            return ChromeMV3ExtensionManagerPermissionActionResult(
                kind: kind,
                value: value,
                succeeded: promptResult.disposition
                    == ChromeMV3PermissionPromptResultDisposition.accepted
                    && application.returnedBoolean,
                returnedBoolean: application.returnedBoolean,
                promptRequest: promptRequest,
                promptResult: promptResult,
                promptLifecycleRecords: lifecycle,
                runtimeSnapshot: owner.snapshot,
                eventDispatchRecord: dispatch,
                serviceWorkerWakeAttempted: false,
                hiddenExtensionPageCreated: false,
                diagnostics: application.diagnostics
                    + promptResult.diagnostics
                    + (dispatch?.diagnostics ?? [])
            )

        case .revokeOptionalAPIPermission, .revokeOptionalHostPermission:
            let requestInput = kind == .revokeOptionalAPIPermission
                ? input(permissions: [value])
                : input(origins: [value])
            let application = owner.remove(input: requestInput)
            let dispatch = application.returnedBoolean
                ? chromeMV3PermissionEventDispatcher
                    .dispatchChromeMV3PermissionEvent(
                        application.result.eventPayloadIfApplied
                            ?? ChromeMV3PermissionsAPIContractEvaluator
                            .removedEventPayload(
                                requestInput: application.result.input,
                                itemDecisions: application.result.itemDecisions,
                                source: .removeCall
                            ),
                        sourceSurfaceID: nil
                    )
                : nil
            save(application.diagnostics)
            return ChromeMV3ExtensionManagerPermissionActionResult(
                kind: kind,
                value: value,
                succeeded: application.returnedBoolean,
                returnedBoolean: application.returnedBoolean,
                promptRequest: nil,
                promptResult: nil,
                promptLifecycleRecords: lifecycle,
                runtimeSnapshot: owner.snapshot,
                eventDispatchRecord: dispatch,
                serviceWorkerWakeAttempted: false,
                hiddenExtensionPageCreated: false,
                diagnostics: application.diagnostics
                    + (dispatch?.diagnostics ?? [])
            )

        case .clearActiveTabGrant:
            let application = owner.resetActiveTabGrants()
            save(application.diagnostics)
            return ChromeMV3ExtensionManagerPermissionActionResult(
                kind: kind,
                value: value,
                succeeded: application.lifecycleResult.grantsExpired
                    .isEmpty == false,
                returnedBoolean: application.lifecycleResult.grantsExpired
                    .isEmpty == false,
                promptRequest: nil,
                promptResult: nil,
                promptLifecycleRecords: lifecycle,
                runtimeSnapshot: owner.snapshot,
                eventDispatchRecord: nil,
                serviceWorkerWakeAttempted: false,
                hiddenExtensionPageCreated: false,
                diagnostics: application.diagnostics
            )
        }
    }

    func chromeMV3RunTrustedNativeHostControlThroughManager(
        _ kind: ChromeMV3NativeTrustedHostControlKind,
        rootURL: URL,
        profileID: String,
        extensionID: String,
        hostName: String,
        fixtureHostRootURL: URL? = nil
    ) -> ChromeMV3ExtensionManagerTrustedNativeHostActionResult {
        let blocked: ([String]) -> ChromeMV3ExtensionManagerTrustedNativeHostActionResult = {
            diagnostics in
            ChromeMV3ExtensionManagerTrustedNativeHostActionResult(
                kind: kind,
                hostName: hostName,
                succeeded: false,
                record: nil,
                snapshot: nil,
                preflight: nil,
                serviceWorkerWakeAttempted: false,
                nativeHostLaunchAttempted: false,
                diagnostics: diagnostics
            )
        }
        guard isEnabled else {
            return blocked([
                "The extensions module is disabled; trusted native host controls are blocked.",
            ])
        }
        let gate = chromeMV3ExtensionManagerGate()
        guard gate.managerAvailableInDeveloperPreview else {
            return blocked(gate.diagnostics.map(\.message))
        }
        let registry = ChromeMV3ExtensionLifecycleRegistry(rootURL: rootURL)
        guard
            let record = registry.loadLifecycleRecord(
                profileID: profileID,
                extensionID: extensionID
            )
        else {
            return blocked([
                "The internal MV3 lifecycle record was not found.",
            ])
        }
        guard record.runtimeState.internalRuntimeEnabled else {
            return blocked([
                "The extension is disabled; trusted native host controls are blocked.",
            ])
        }

        let report = registry.latestEndToEndDiagnosticsReport(
            profileID: profileID,
            extensionID: extensionID
        )
        let manifestSummary = ChromeMV3ExtensionManagerManifestSummaryViewState
            .make(summary: report?.managerActiveManifestSummary, record: record)
        let permissionState = nativeMessagingPermissionStateForManager(
            rootURL: rootURL,
            profileID: profileID,
            extensionID: extensionID,
            manifestSummary: manifestSummary
        )
        let fixtureRoot = (
            fixtureHostRootURL
                ?? rootURL.appendingPathComponent(
                    "NativeMessagingFixtureHosts",
                    isDirectory: true
                )
        )
        let lookupPolicy = ChromeMV3NativeHostLookupPolicy.macOS(
            explicitTestRootPath: fixtureRoot.path,
            extensionModuleEnabled: true
        )
        let lookup = lookupPolicy.lookupHost(named: hostName)
        let productPolicy = ChromeMV3NativeMessagingProductPolicy(
            extensionModuleEnabled: true,
            nativeMessagingAllowedByProductPolicy: true,
            userConsentRequired: true,
            userConsentGranted: false
        )
        let authorization = ChromeMV3NativeMessagingAuthorizationEvaluator
            .evaluate(
                extensionID: extensionID,
                permissionState: permissionState,
                hostManifest: lookup.manifest,
                productPolicy: productPolicy
            )
        let store = ChromeMV3NativeTrustedHostPolicyStore(rootURL: rootURL)
        let existing = store.record(
            profileID: profileID,
            extensionID: extensionID,
            hostName: hostName
        )
        let evaluation = ChromeMV3NativeTrustedHostPolicyEvaluator.evaluate(
            hostName: hostName,
            extensionID: extensionID,
            profileID: profileID,
            lookupResult: lookup,
            authorizationResult: authorization,
            approvedRootPaths: [fixtureRoot.path],
            control: kind,
            sequence: (existing?.approvalSequence ?? 0) + 1,
            existingRecord: existing
        )
        let snapshot: ChromeMV3NativeTrustedHostPolicySnapshot
        do {
            if kind == .reset {
                snapshot = try store.resetRecord(
                    profileID: profileID,
                    extensionID: extensionID,
                    hostName: hostName
                )
            } else {
                snapshot = try store.saveRecord(evaluation.record)
            }
        } catch {
            return blocked(
                evaluation.diagnostics
                    + [
                        "Failed to persist trusted native host policy: \(error.localizedDescription)",
                    ]
            )
        }

        if kind == .revoke || kind == .reset || kind == .deny {
            _ = cachedChromeMV3PopupOptionsHostController?.close(
                profileID: profileID,
                extensionID: extensionID,
                reason: .resetWhileOpen
            )
        }
        let savedRecord = kind == .reset ? nil : evaluation.record
        let preflight = ChromeMV3NativeMessagingPreflightEvaluator.evaluate(
            input: ChromeMV3NativeMessagingPreflightInput(
                extensionID: extensionID,
                profileID: profileID,
                hostName: hostName,
                operationKind: .longLivedNativePort,
                sourceContext: .extensionPage,
                permissionState: permissionState,
                productPolicy: productPolicy,
                trustedHostPolicyRecord: savedRecord
            ),
            lookupPolicy: lookupPolicy,
            lookupResult: lookup
        )
        return ChromeMV3ExtensionManagerTrustedNativeHostActionResult(
            kind: kind,
            hostName: hostName,
            succeeded:
                kind == .reset
                    || [
                        ChromeMV3NativeTrustedHostTrustState
                            .trustedForDeveloperPreview,
                        .userDenied,
                        .revoked,
                    ].contains(evaluation.record.trustState),
            record: savedRecord,
            snapshot: snapshot,
            preflight: preflight,
            serviceWorkerWakeAttempted: false,
            nativeHostLaunchAttempted: false,
            diagnostics:
                uniqueSortedSumiNativeHostManager(
                    evaluation.diagnostics
                        + snapshot.diagnostics
                        + preflight.diagnostics
                        + [
                            "Trusted native host manager control did not launch a native host.",
                            "No arbitrary native host directory scan occurred.",
                        ]
                )
        )
    }

    func chromeMV3OpenActionPopupThroughManager(
        rootURL: URL,
        profileID: String,
        extensionID: String
    ) -> ChromeMV3ExtensionManagerActionResult {
        openChromeMV3PopupOptionsThroughManager(
            rootURL: rootURL,
            profileID: profileID,
            extensionID: extensionID,
            surface: .actionPopup,
            action: .openActionPopup
        )
    }

    func chromeMV3OpenOptionsThroughManager(
        rootURL: URL,
        profileID: String,
        extensionID: String
    ) -> ChromeMV3ExtensionManagerActionResult {
        let state = ChromeMV3ProductPopupOptionsLaunchPlanner.makeLaunchState(
            rootURL: rootURL,
            profileID: profileID,
            extensionID: extensionID,
            managerGate: chromeMV3ExtensionManagerGate(),
            moduleEnabled: isEnabled,
            lastRunResult: lastChromeMV3PopupOptionsRunResult
        )
        guard let primary = state.primaryOptions else {
            let result = ChromeMV3ProductPopupOptionsRunResult.blocked(
                requestedSurface: nil,
                launchRecord: nil,
                diagnostics: [
                    ChromeMV3PopupOptionsBlocker.noOptionsPageDeclared.reason,
                ]
            )
            lastChromeMV3PopupOptionsRunResult = result
            return .popupOptions(action: .openOptions, result: result)
        }
        return openChromeMV3PopupOptions(
            primary,
            action: .openOptions
        )
    }

    func chromeMV3ClosePopupOptionsThroughManager(
        profileID: String,
        extensionID: String
    ) -> ChromeMV3ExtensionManagerActionResult {
        guard isEnabled else {
            return ChromeMV3ExtensionManagerActionResult.blocked(
                action: .closePopupOptions,
                diagnostics: [.moduleDisabled]
            )
        }
        let result = cachedChromeMV3PopupOptionsHostController?.close(
            profileID: profileID,
            extensionID: extensionID,
            reason: .userClosed
        ) ?? ChromeMV3ProductPopupOptionsRunResult(
            status: .succeeded,
            requestedSurface: nil,
            launchRecord: nil,
            lifecycleEvents: [],
            webViewCreated: false,
            webViewReleased: false,
            scriptHandlersRemoved: false,
            normalTabAttached: false,
            contentScriptsInjectedIntoProductPages: false,
            serviceWorkerWakeAttempted: false,
            nativeHostLaunchAttempted: false,
            popupOptionsBridgeInstalled: false,
            popupOptionsUserScriptInstalled: false,
            popupOptionsAPIAllowlist: [],
            popupOptionsAPICallsObserved: [],
            popupOptionsBlockedAPIs: [],
            popupOptionsLastAPIErrorSummary: nil,
            diagnostics: ["No popup/options WebView session was active."]
        )
        lastChromeMV3PopupOptionsRunResult = result
        return .popupOptions(action: .closePopupOptions, result: result)
    }

    private func openChromeMV3PopupOptionsThroughManager(
        rootURL: URL,
        profileID: String,
        extensionID: String,
        surface: ChromeMV3ProductPopupOptionsSurface,
        action: ChromeMV3ExtensionManagerActionKind
    ) -> ChromeMV3ExtensionManagerActionResult {
        let state = ChromeMV3ProductPopupOptionsLaunchPlanner.makeLaunchState(
            rootURL: rootURL,
            profileID: profileID,
            extensionID: extensionID,
            managerGate: chromeMV3ExtensionManagerGate(),
            moduleEnabled: isEnabled,
            lastRunResult: lastChromeMV3PopupOptionsRunResult
        )
        let launchRecord: ChromeMV3ProductPopupOptionsLaunchRecord
        switch surface {
        case .actionPopup:
            launchRecord = state.actionPopup
        case .optionsPage:
            launchRecord = state.optionsPages.first {
                $0.surface == .optionsPage
            } ?? state.actionPopup
        case .optionsUI:
            launchRecord = state.optionsPages.first {
                $0.surface == .optionsUI
            } ?? state.actionPopup
        }
        return openChromeMV3PopupOptions(launchRecord, action: action)
    }

    private func openChromeMV3PopupOptions(
        _ launchRecord: ChromeMV3ProductPopupOptionsLaunchRecord,
        action: ChromeMV3ExtensionManagerActionKind
    ) -> ChromeMV3ExtensionManagerActionResult {
        guard isEnabled else {
            return ChromeMV3ExtensionManagerActionResult.blocked(
                action: action,
                diagnostics: [.moduleDisabled]
            )
        }
        let result = chromeMV3PopupOptionsHostController().open(launchRecord)
        lastChromeMV3PopupOptionsRunResult = result
        return .popupOptions(action: action, result: result)
    }

    func chromeMV3ExportDiagnosticsJSONThroughManager(
        rootURL: URL,
        profileID: String,
        extensionID: String
    ) -> ChromeMV3ExtensionManagerActionResult {
        guard isEnabled else {
            return ChromeMV3ExtensionManagerActionResult.blocked(
                action: .exportDiagnosticsJSON,
                diagnostics: [.moduleDisabled]
            )
        }
        return ChromeMV3ExtensionManagerActionRunner
            .exportDiagnosticsJSON(
                rootURL: rootURL,
                profileID: profileID,
                extensionID: extensionID
            )
    }

    func chromeMV3ChromeWebStoreInstallDiagnosticThroughManager(
        rootURL: URL = ChromeMV3ExtensionManagerStoreLocation.defaultRootURL(),
        input: String? = nil
    )
        -> ChromeMV3ExtensionManagerActionResult
    {
        let gate = chromeMV3ExtensionManagerGate()
        guard gate.managerAvailableInDeveloperPreview else {
            return ChromeMV3ExtensionManagerActionResult.blocked(
                action: .chromeWebStoreInstall,
                diagnostics: gate.diagnostics
            )
        }
        if let input, input.trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false
        {
            return ChromeMV3ExtensionManagerActionRunner
                .chromeWebStoreDiagnostic(rootURL: rootURL, input: input)
        }
        return ChromeMV3ExtensionManagerActionRunner
            .chromeWebStoreInstallDeferred()
    }

    @discardableResult
    func tearDownChromeMV3EmptyControllerOwnerIfEnabled(
        trigger: ChromeMV3EmptyControllerTeardownTrigger
    ) -> ChromeMV3EmptyControllerDiagnostics? {
        guard isEnabled else { return nil }
        #if DEBUG
            if #available(macOS 15.5, *) {
                cachedChromeMV3ControllerLoadOwner?.tearDown()
                cachedChromeMV3ControllerLoadOwner = nil
            }
        #endif
        guard let cachedChromeMV3EmptyControllerOwner else {
            guard let decision =
                chromeMV3ControllerCreationGateDecisionIfEnabled(
                    explicitControllerCreationAllowed: false
                )
            else {
                return nil
            }
            return ChromeMV3EmptyControllerDiagnostics.notCreated(
                gateDecision: decision
            )
        }

        let diagnostics = cachedChromeMV3EmptyControllerOwner.tearDown(
            trigger: trigger
        )
        #if DEBUG
            if #available(macOS 15.5, *) {
                lastChromeMV3LiveNormalTabAttachmentSnapshot =
                    diagnostics.liveNormalTabAttachmentSnapshot
            }
        #endif
        self.cachedChromeMV3EmptyControllerOwner = nil
        return diagnostics
    }

    func normalTabUserScripts() -> [SumiUserScript] {
        managerIfNeededForNormalTabRuntime()?.normalTabUserScripts() ?? []
    }

    func prepareWebViewConfigurationForExtensionRuntime(
        _ configuration: WKWebViewConfiguration,
        reason: String
    ) {
        managerIfNeededForNormalTabRuntime()?.prepareWebViewConfigurationForExtensionRuntime(
            configuration,
            reason: reason
        )
    }

    func prepareWebViewForExtensionRuntime(
        _ webView: WKWebView,
        currentURL: URL?,
        reason: String
    ) {
        managerIfNeededForNormalTabRuntime()?.prepareWebViewForExtensionRuntime(
            webView,
            currentURL: currentURL,
            reason: reason
        )
    }

    func registerTabWithExtensionRuntimeIfLoaded(
        _ tab: Tab,
        reason: String
    ) {
        managerIfLoadedAndEnabled()?.registerTabWithExtensionRuntime(
            tab,
            reason: reason
        )
    }

    func releaseExternallyConnectableRuntimeIfLoaded(
        for webView: WKWebView,
        reason: String
    ) {
        cachedManager?.releaseExternallyConnectableRuntime(
            for: webView,
            reason: reason
        )
    }

    func notifyWindowOpenedIfLoaded(_ windowState: BrowserWindowState) {
        managerIfLoadedAndEnabled()?.notifyWindowOpened(windowState)
    }

    func notifyWindowClosedIfLoaded(_ windowId: UUID) {
        managerIfLoadedAndEnabled()?.notifyWindowClosed(windowId)
    }

    func notifyWindowFocusedIfLoaded(_ windowState: BrowserWindowState) {
        managerIfLoadedAndEnabled()?.notifyWindowFocused(windowState)
    }

    func switchProfileIfLoaded(_ profile: Profile) {
        managerIfLoadedAndEnabled()?.switchProfile(profile)
    }

    func notifyTabActivatedIfLoaded(newTab: Tab, previous: Tab?) {
        managerIfLoadedAndEnabled()?.notifyTabActivated(
            newTab: newTab,
            previous: previous
        )
    }

    func notifyTabClosedIfLoaded(_ tab: Tab) {
        managerIfLoadedAndEnabled()?.notifyTabClosed(tab)
    }

    func noteChromeMV3ContentScriptLifecycleEntrypointIfLoaded(
        _ tab: Tab,
        webView: WKWebView?,
        url: URL?,
        entrypoint: ChromeMV3ContentScriptLifecycleEntrypoint,
        reason: String
    ) {
        managerIfLoadedAndEnabled()?
            .noteChromeMV3ContentScriptLifecycleEntrypoint(
                tab: tab,
                webView: webView,
                url: url,
                entrypoint: entrypoint,
                reason: reason
            )
    }

    func notifyTabPropertiesChangedIfLoaded(
        _ tab: Tab,
        properties: WKWebExtension.TabChangedProperties
    ) {
        managerIfLoadedAndEnabled()?.notifyTabPropertiesChanged(
            tab,
            properties: properties
        )
    }

    func markTabEligibleAfterCommittedNavigationIfLoaded(
        _ tab: Tab,
        reason: String
    ) {
        managerIfLoadedAndEnabled()?.markTabEligibleAfterCommittedNavigation(
            tab,
            reason: reason
        )
    }

    func consumeRecentlyOpenedExtensionTabRequestIfLoaded(for url: URL) -> Bool {
        managerIfLoadedAndEnabled()?.consumeRecentlyOpenedExtensionTabRequest(
            for: url
        ) ?? false
    }

    func enableExtension(_ extensionId: String) async throws -> InstalledExtension {
        guard let manager = managerIfEnabled() else {
            throw ExtensionError.unsupportedOS
        }
        return try await manager.enableExtension(extensionId)
    }

    func disableExtension(_ extensionId: String) async throws {
        guard let manager = managerIfEnabled() else { return }
        try await manager.disableExtension(extensionId)
    }

    func uninstallExtension(_ extensionId: String) async throws {
        guard let manager = managerIfEnabled() else { return }
        try await manager.uninstallExtension(extensionId)
    }

    func orderedPinnedToolbarSlots(
        enabledExtensions: [InstalledExtension],
        sumiScriptsManagerEnabled: Bool
    ) -> [PinnedToolbarSlot] {
        managerIfLoadedAndEnabled()?.orderedPinnedToolbarSlots(
            enabledExtensions: enabledExtensions,
            sumiScriptsManagerEnabled: sumiScriptsManagerEnabled
        ) ?? []
    }

    func isPinnedToToolbar(_ extensionId: String) -> Bool {
        managerIfLoadedAndEnabled()?.isPinnedToToolbar(extensionId) ?? false
    }

    func pinToToolbar(_ extensionId: String) {
        managerIfEnabled()?.pinToToolbar(extensionId)
    }

    func unpinFromToolbar(_ extensionId: String) {
        managerIfEnabled()?.unpinFromToolbar(extensionId)
    }

    @discardableResult
    func requestExtensionRuntime(
        reason: ExtensionManager.ExtensionRuntimeRequestReason
    ) -> WKWebExtensionController? {
        managerIfEnabled()?.requestExtensionRuntime(reason: reason)
    }

    func getExtensionContext(
        for extensionId: String
    ) -> WKWebExtensionContext? {
        managerIfLoadedAndEnabled()?.getExtensionContext(for: extensionId)
    }

    func stableAdapter(for tab: Tab) -> ExtensionTabAdapter? {
        managerIfLoadedAndEnabled()?.stableAdapter(for: tab)
    }

    func setActionAnchorIfLoaded(for extensionId: String, anchorView: NSView) {
        managerIfLoadedAndEnabled()?.setActionAnchor(
            for: extensionId,
            anchorView: anchorView
        )
    }

    func cancelNativeMessagingSessionsIfLoaded(reason: String) {
        cachedManager?.cancelNativeMessagingSessions(reason: reason)
    }

    func closeAllOptionsWindowsIfLoaded() {
        cachedManager?.closeAllOptionsWindows()
    }

    var chromeMV3PopupOptionsActiveSessionCountForTesting: Int {
        cachedChromeMV3PopupOptionsHostController?.activeSessionCount ?? 0
    }

    var chromeMV3PermissionEventDispatchRecordsForTesting:
        [ChromeMV3PermissionEventDispatchRecord]
    {
        chromeMV3PermissionEventDispatcher.permissionEventDispatchRecords
    }

    func chromeMV3RegisterPermissionEventPageForTesting(
        surfaceID: String,
        profileID: String,
        extensionID: String,
        surface: ChromeMV3ProductPopupOptionsSurface,
        onAddedListenerCount: Int = 0,
        onRemovedListenerCount: Int = 0
    ) {
        chromeMV3PermissionEventDispatcher
            .registerChromeMV3PermissionEventPage(
                surfaceID: surfaceID,
                profileID: profileID,
                extensionID: extensionID,
                surface: surface,
                dispatchHandler: { _ in true }
            )
        chromeMV3PermissionEventDispatcher
            .updateChromeMV3PermissionEventListenerCount(
                surfaceID: surfaceID,
                profileID: profileID,
                extensionID: extensionID,
                surface: surface,
                eventKind: .onAdded,
                listenerCount: onAddedListenerCount
            )
        chromeMV3PermissionEventDispatcher
            .updateChromeMV3PermissionEventListenerCount(
                surfaceID: surfaceID,
                profileID: profileID,
                extensionID: extensionID,
                surface: surface,
                eventKind: .onRemoved,
                listenerCount: onRemovedListenerCount
            )
    }

    private func chromeMV3PopupOptionsHostController()
        -> ChromeMV3ProductPopupOptionsHostController
    {
        if let cachedChromeMV3PopupOptionsHostController {
            return cachedChromeMV3PopupOptionsHostController
        }
        let controller = ChromeMV3ProductPopupOptionsHostController(
            factory: chromeMV3PopupOptionsWebViewFactory(),
            permissionPromptPresenter:
                ChromeMV3AppHostedPermissionPromptPresenter(),
            permissionEventDispatcher: chromeMV3PermissionEventDispatcher
        )
        cachedChromeMV3PopupOptionsHostController = controller
        return controller
    }

    private func tearDownChromeMV3PopupOptionsHostController(
        reason: ChromeMV3ProductPopupOptionsTeardownReason
    ) {
        let result = cachedChromeMV3PopupOptionsHostController?
            .closeAll(reason: reason)
        if let result {
            lastChromeMV3PopupOptionsRunResult = result
        }
        cachedChromeMV3PopupOptionsHostController = nil
    }

    private func resolvedChromeMV3ManagerProfileID(
        _ profileID: String?
    ) -> String {
        if let profileID, profileID.isEmpty == false {
            return profileID
        }
        return browserManager?.currentProfile?.id.uuidString
            ?? initialProfileProvider()?.id.uuidString
            ?? "internal-debug-profile"
    }

    private func nativeMessagingPermissionStateForManager(
        rootURL: URL,
        profileID: String,
        extensionID: String,
        manifestSummary:
            ChromeMV3ExtensionManagerManifestSummaryViewState
    ) -> ChromeMV3NativeMessagingPermissionState {
        if manifestSummary.permissions.contains("nativeMessaging") {
            return .grantedByManifest
        }
        let store = ChromeMV3DeveloperPreviewPermissionStateStore(
            rootURL: rootURL
        )
        let granted =
            store.loadRecord(profileID: profileID, extensionID: extensionID)?
            .permissionRuntimeSnapshot.permissionStore.summary
            .grantedOptionalAPIPermissions.contains("nativeMessaging") ?? false
        if granted {
            return .grantedByManifest
        }
        if manifestSummary.optionalPermissions.contains("nativeMessaging") {
            return .deferred
        }
        return .missing
    }

    private func chromeMV3ExtensionManagerRuntimeDiagnosticsSnapshot()
        -> ChromeMV3LifecycleRuntimeDiagnosticsSnapshot
    {
        #if DEBUG
            return chromeMV3LifecycleRuntimeDiagnosticsSnapshot()
        #else
            return .none
        #endif
    }

    private func tearDownChromeMV3ManagerRuntimeOwners() {
        #if DEBUG
            if #available(macOS 15.5, *) {
                tearDownChromeMV3ControllerLoadOwner()
                tearDownChromeMV3DetachedContextOwner()
                tearDownChromeMV3ExtensionObjectProbeOwner()
            }
        #endif
        tearDownChromeMV3EmptyControllerOwner()
    }

    private func managerIfNeededForNormalTabRuntime() -> ExtensionManager? {
        guard isEnabled else { return nil }

        if let cachedManager {
            return cachedManager.hasEnabledInstalledExtensions ? cachedManager : nil
        }

        guard hasEnabledPersistedExtensions() else { return nil }
        return managerIfEnabled()
    }

    private func hasEnabledPersistedExtensions() -> Bool {
        guard let context else { return false }
        do {
            return try context.fetch(FetchDescriptor<ExtensionEntity>())
                .contains { $0.isEnabled }
        } catch {
            return false
        }
    }

    private func tearDownLoadedRuntime(reason: String) {
        guard let cachedManager else {
            surfaceStore.bind(nil)
            return
        }

        cachedManager.tearDownExtensionRuntime(
            reason: reason,
            removeUIState: true,
            releaseController: true
        )
        self.cachedManager = nil
        surfaceStore.bind(nil)
    }

    private func tearDownChromeMV3EmptyControllerOwner() {
        #if DEBUG
            if #available(macOS 15.5, *) {
                tearDownChromeMV3ControllerLoadOwner()
            }
        #endif
        let diagnostics = cachedChromeMV3EmptyControllerOwner?
            .tearDown(trigger: .moduleDisable)
        #if DEBUG
            if #available(macOS 15.5, *) {
                lastChromeMV3LiveNormalTabAttachmentSnapshot =
                    diagnostics?.liveNormalTabAttachmentSnapshot
            }
        #endif
        cachedChromeMV3EmptyControllerOwner = nil
    }

    #if DEBUG
        @available(macOS 15.5, *)
        private func tearDownChromeMV3ExtensionObjectProbeOwner() {
            tearDownChromeMV3ControllerLoadOwner()
            tearDownChromeMV3DetachedContextOwner()
            cachedChromeMV3ExtensionObjectProbeOwner?.tearDown()
            cachedChromeMV3ExtensionObjectProbeOwner = nil
        }

        @available(macOS 15.5, *)
        private func tearDownChromeMV3DetachedContextOwner() {
            tearDownChromeMV3ControllerLoadOwner()
            cachedChromeMV3DetachedContextOwner?.tearDown()
            cachedChromeMV3DetachedContextOwner = nil
        }

        @available(macOS 15.5, *)
        private func tearDownChromeMV3ControllerLoadOwner() {
            cachedChromeMV3ControllerLoadOwner?.tearDown()
            cachedChromeMV3ControllerLoadOwner = nil
        }

        private func chromeMV3LifecycleRuntimeDiagnosticsSnapshot()
            -> ChromeMV3LifecycleRuntimeDiagnosticsSnapshot
        {
            ChromeMV3LifecycleRuntimeDiagnosticsSnapshot(
                WebKitObjectDiagnosticsAvailable:
                    lastChromeMV3WebKitObjectAcceptanceReport != nil,
                contextCreationGateDiagnosticsAvailable:
                    lastChromeMV3ContextCreationGateReport != nil,
                controllerLoadGateDiagnosticsAvailable:
                    lastChromeMV3ControllerLoadGateReport != nil,
                runtimeBridgeReadinessDiagnosticsAvailable:
                    lastChromeMV3RuntimeBridgeReadinessReport != nil,
                runtimeJSMessagingDiagnosticsAvailable:
                    lastChromeMV3RuntimeJSMessagingMVPReport != nil,
                tabsScriptingDiagnosticsAvailable:
                    lastChromeMV3TabsScriptingMVPReport != nil,
                permissionsDiagnosticsAvailable:
                    lastChromeMV3PermissionImplementationReport != nil
                        || lastChromeMV3PermissionLifecycleReport != nil
                        || lastChromeMV3PermissionsAPIContractReport != nil,
                storageDiagnosticsAvailable:
                    lastChromeMV3StorageLocalImplementationReport != nil
                        || lastChromeMV3StorageAPIOperationsReport != nil
                        || lastChromeMV3StorageBrokerReadinessReport != nil,
                nativeMessagingDiagnosticsAvailable:
                    lastChromeMV3NativeMessagingReadinessReport != nil
                        || lastChromeMV3NativeMessagingImplementationReport != nil,
                serviceWorkerDiagnosticsAvailable:
                    lastChromeMV3ServiceWorkerLifecycleReport != nil
                        || lastChromeMV3ServiceWorkerSharedLifecycleSessionReport
                            != nil,
                eventAPIDiagnosticsAvailable:
                    lastChromeMV3ExtensionEventAPIsReport != nil,
                networkDiagnosticsAvailable:
                    lastChromeMV3NetworkCompatibilityReport != nil,
                sidePanelOffscreenIdentityDiagnosticsAvailable:
                    lastChromeMV3SidePanelOffscreenIdentityReport != nil,
                passwordManagerDiagnosticsAvailable:
                    lastChromeMV3PasswordManagerFixtureReport != nil
                        || lastChromeMV3PasswordManagerCompatibilityReport
                            != nil,
                diagnostics: [
                    "SumiExtensionsModule supplied DEBUG/internal diagnostic availability only.",
                    "Product normal-tab runtime remains unavailable.",
                ]
            )
        }

        private func loadChromeMV3WebKitObjectAcceptanceReport(
            fromRewrittenBundleRootPath rootPath: String
        ) -> ChromeMV3WebKitObjectAcceptanceReport? {
            let rootURL = URL(
                fileURLWithPath: rootPath,
                isDirectory: true
            ).standardizedFileURL
            return ChromeMV3ContextReadinessReportGenerator
                .loadObjectAcceptanceReport(
                    fromRewrittenBundleRoot: rootURL
                )?
                .report
        }

        private func loadChromeMV3RuntimeBridgeReadinessReport(
            fromRewrittenBundleRootPath rootPath: String
        ) -> ChromeMV3RuntimeBridgeReadinessReport? {
            let reportURL = URL(
                fileURLWithPath: rootPath,
                isDirectory: true
            ).standardizedFileURL
                .appendingPathComponent(
                    ChromeMV3RuntimeBridgeReadinessReportWriter
                        .reportFileName
                )
            guard let data = try? Data(contentsOf: reportURL) else {
                return nil
            }
            return try? JSONDecoder().decode(
                ChromeMV3RuntimeBridgeReadinessReport.self,
                from: data
            )
        }

        @available(macOS 15.5, *)
        private func chromeMV3ExtensionObjectProbeGateInput(
            profileHost: ChromeMV3ProfileHost,
            explicitInternalExtensionObjectProbeAllowed: Bool,
            candidate: ChromeMV3RewrittenVariantCandidate,
            runtimeLoadabilityReport: ChromeMV3RuntimeLoadabilityReport?,
            requestedContextCreation: Bool,
            requestedContextLoading: Bool,
            requestedControllerLoad: Bool,
            requestedExtensionCodeExecution: Bool,
            requestedUserScriptRegistration: Bool,
            requestedNativeMessagingLaunch: Bool
        ) -> ChromeMV3ExtensionObjectProbeGateInput {
            let resourceBaseURL = URL(
                fileURLWithPath: candidate.rewrittenVariantRootPath,
                isDirectory: true
            ).standardizedFileURL
            let runtimeReportFileExists =
                candidate.runtimeLoadabilityReportPath.map {
                    FileManager.default.fileExists(atPath: $0)
                }
                ?? (runtimeLoadabilityReport != nil)

            return ChromeMV3ExtensionObjectProbeGateInput(
                extensionsModuleEnabled: true,
                profileHostModuleState: profileHost.moduleState,
                explicitInternalExtensionObjectProbeAllowed:
                    explicitInternalExtensionObjectProbeAllowed,
                resourceBaseURLPath: candidate.rewrittenVariantRootPath
                    .isEmpty
                    ? nil
                    : resourceBaseURL.path,
                generatedBundleID: candidate.id,
                generatedBundleHash: candidate.rewrittenManifestSHA256
                    ?? runtimeLoadabilityReport?.rewrittenManifestHash?.sha256,
                generatedRewrittenBundleExists:
                    candidate.rewrittenVariantExists
                    && directoryExists(resourceBaseURL),
                runtimeLoadabilityReportExists:
                    runtimeLoadabilityReport != nil && runtimeReportFileExists,
                runtimeLoadabilityReportID: runtimeLoadabilityReport?.id,
                runtimeLoadabilityReportPath:
                    candidate.runtimeLoadabilityReportPath,
                runtimeLoadabilityReportSHA256:
                    candidate.runtimeLoadabilityReportSHA256,
                manifestVersion: candidate.manifestVersion
                    ?? inferredManifestVersion(
                        from: runtimeLoadabilityReport
                    ),
                runtimeLoadable: runtimeLoadabilityReport?.runtimeLoadable,
                staticRuntimeBlockers:
                    runtimeLoadabilityReport?.blockers ?? [],
                requestedContextCreation: requestedContextCreation,
                requestedContextLoading: requestedContextLoading,
                requestedControllerLoad: requestedControllerLoad,
                requestedExtensionCodeExecution:
                    requestedExtensionCodeExecution,
                requestedUserScriptRegistration:
                    requestedUserScriptRegistration,
                requestedNativeMessagingLaunch:
                    requestedNativeMessagingLaunch,
                staleAttachedWebViewCount:
                    cachedChromeMV3EmptyControllerOwner?
                    .liveNormalTabAttachmentDiagnostics()
                    .staleOrNeedsRecreationCount
                    ?? lastChromeMV3LiveNormalTabAttachmentSnapshot?
                    .staleOrNeedsRecreationCount
                    ?? 0
            )
        }

        private func directoryExists(_ url: URL) -> Bool {
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(
                atPath: url.path,
                isDirectory: &isDirectory
            ) && isDirectory.boolValue
        }

        private func inferredManifestVersion(
            from report: ChromeMV3RuntimeLoadabilityReport?
        ) -> Int? {
            guard let report else { return nil }
            if report.passedChecks.contains(.manifestShape) {
                return 3
            }
            return nil
        }
    #endif

    private func makeChromeMV3ProfileHost(
        candidateRewrittenVariants: [ChromeMV3RewrittenVariantCandidate]
    ) -> (host: ChromeMV3ProfileHost, profile: Profile?) {
        let profile = browserManager?.currentProfile ?? initialProfileProvider()
        let profileIdentifier = profile?.id.uuidString
            ?? ChromeMV3ProfileHost.unresolvedProfileIdentifier
        let dataStoreIdentity: ChromeMV3ProfileDataStoreIdentity
        if let profile {
            dataStoreIdentity = profile.isEphemeral
                ? .ephemeralProfileIdentifier(profile.id.uuidString)
                : .profileIdentifier(profile.id.uuidString)
        } else {
            dataStoreIdentity = .unresolved
        }

        return (
            ChromeMV3ProfileHost(
                profileIdentifier: profileIdentifier,
                extensionsEnabled: true,
                profileDataStoreIdentity: dataStoreIdentity,
                candidateRewrittenVariants: candidateRewrittenVariants
            ),
            profile
        )
    }
}

private func uniqueSortedSumiNativeHostManager(
    _ values: [String]
) -> [String] {
    Array(Set(values.filter { $0.isEmpty == false })).sorted()
}
