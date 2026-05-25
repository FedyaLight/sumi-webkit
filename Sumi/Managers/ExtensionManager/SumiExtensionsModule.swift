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

    let surfaceStore: BrowserExtensionSurfaceStore

    private var cachedManager: ExtensionManager?
    private var cachedChromeMV3EmptyControllerOwner:
        ChromeMV3EmptyControllerOwner?
    #if DEBUG
        private var cachedChromeMV3ExtensionObjectProbeOwner:
            ChromeMV3ExtensionObjectProbeOwner?
        private var cachedChromeMV3DetachedContextOwner:
            ChromeMV3DetachedContextOwner?
        private var lastChromeMV3WebKitObjectAcceptanceReport:
            ChromeMV3WebKitObjectAcceptanceReport?
        private var lastChromeMV3ContextReadinessReport:
            ChromeMV3ContextReadinessReport?
        private var lastChromeMV3ContextCreationGateReport:
            ChromeMV3ContextCreationGateReport?
        private var lastChromeMV3RuntimeBridgePrerequisitesReport:
            ChromeMV3RuntimeBridgePrerequisitesReport?
        private var lastChromeMV3RuntimeBridgeReadinessReport:
            ChromeMV3RuntimeBridgeReadinessReport?
        private var lastChromeMV3StorageBrokerReadinessReport:
            ChromeMV3StorageBrokerReadinessReport?
        private var lastChromeMV3StorageAPIOperationsReport:
            ChromeMV3StorageAPIOperationsReport?
        private var lastChromeMV3RuntimeMessagingContractReport:
            ChromeMV3RuntimeMessagingContractReport?
        private var lastChromeMV3RuntimeMessageDispatcherSkeletonReport:
            ChromeMV3RuntimeMessageDispatcherSkeletonReport?
        private var lastChromeMV3JSBridgeContractReport:
            ChromeMV3JSBridgeContractReport?
        private var lastChromeMV3NativeMessagingReadinessReport:
            ChromeMV3NativeMessagingReadinessReport?
        private var lastChromeMV3RuntimeListenerContractReport:
            ChromeMV3RuntimeListenerContractReport?
        private var lastChromeMV3ServiceWorkerLifecycleReport:
            ChromeMV3ServiceWorkerLifecycleReport?
        private var lastChromeMV3PermissionBrokerReadinessReport:
            ChromeMV3PermissionBrokerReadinessReport?
        private var lastChromeMV3PermissionLifecycleReport:
            ChromeMV3PermissionLifecycleReport?
        private var lastChromeMV3PermissionsAPIContractReport:
            ChromeMV3PermissionsAPIContractReport?
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
        surfaceStore: BrowserExtensionSurfaceStore? = nil
    ) {
        self.moduleRegistry = moduleRegistry
        self.context = context
        self.browserConfiguration = browserConfiguration ?? .shared
        self.initialProfileProvider = initialProfileProvider
        self.managerFactory = managerFactory
        self.chromeMV3EmptyControllerOwnerFactory =
            chromeMV3EmptyControllerOwnerFactory
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
                    tearDownChromeMV3DetachedContextOwner()
                    tearDownChromeMV3ExtensionObjectProbeOwner()
                    lastChromeMV3WebKitObjectAcceptanceReport = nil
                    lastChromeMV3ContextReadinessReport = nil
                    lastChromeMV3ContextCreationGateReport = nil
                    lastChromeMV3RuntimeBridgePrerequisitesReport = nil
                    lastChromeMV3RuntimeBridgeReadinessReport = nil
                    lastChromeMV3StorageBrokerReadinessReport = nil
                    lastChromeMV3StorageAPIOperationsReport = nil
                    lastChromeMV3RuntimeMessagingContractReport = nil
                    lastChromeMV3RuntimeMessageDispatcherSkeletonReport = nil
                    lastChromeMV3JSBridgeContractReport = nil
                    lastChromeMV3NativeMessagingReadinessReport = nil
                    lastChromeMV3RuntimeListenerContractReport = nil
                    lastChromeMV3ServiceWorkerLifecycleReport = nil
                    lastChromeMV3PermissionBrokerReadinessReport = nil
                    lastChromeMV3PermissionLifecycleReport = nil
                    lastChromeMV3PermissionsAPIContractReport = nil
                }
            #endif
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
        let runtimeBridgePrerequisitesReport:
            ChromeMV3RuntimeBridgePrerequisitesReport?
        let runtimeBridgeReadinessReport:
            ChromeMV3RuntimeBridgeReadinessReport?
        let storageBrokerReadinessReportSummary:
            ChromeMV3StorageBrokerReadinessReportSummary?
        let storageAPIOperationsReportSummary:
            ChromeMV3StorageAPIOperationsReportSummary?
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
        let permissionBrokerReadinessReportSummary:
            ChromeMV3PermissionBrokerReadinessReportSummary?
        let permissionLifecycleReportSummary:
            ChromeMV3PermissionLifecycleReportSummary?
        let permissionsAPIContractReportSummary:
            ChromeMV3PermissionsAPIContractReportSummary?
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
                runtimeBridgePrerequisitesReport =
                    lastChromeMV3RuntimeBridgePrerequisitesReport
                runtimeBridgeReadinessReport =
                    lastChromeMV3RuntimeBridgeReadinessReport
                storageBrokerReadinessReportSummary =
                    lastChromeMV3StorageBrokerReadinessReport?.summary
                storageAPIOperationsReportSummary =
                    lastChromeMV3StorageAPIOperationsReport?.summary
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
                permissionBrokerReadinessReportSummary =
                    lastChromeMV3PermissionBrokerReadinessReport?.summary
                permissionLifecycleReportSummary =
                    lastChromeMV3PermissionLifecycleReport?.summary
                permissionsAPIContractReportSummary =
                    lastChromeMV3PermissionsAPIContractReport?.summary
            } else {
                probeDiagnostics = nil
                objectAcceptanceReport = nil
                contextReadinessReport = nil
                contextCreationGateReport = nil
                runtimeBridgePrerequisitesReport = nil
                runtimeBridgeReadinessReport = nil
                storageBrokerReadinessReportSummary = nil
                storageAPIOperationsReportSummary = nil
                runtimeMessagingContractReportSummary = nil
                runtimeMessageDispatcherSkeletonReportSummary = nil
                jsBridgeContractReportSummary = nil
                nativeMessagingReadinessReportSummary = nil
                runtimeListenerContractReportSummary = nil
                serviceWorkerLifecycleReportSummary = nil
                permissionBrokerReadinessReportSummary = nil
                permissionLifecycleReportSummary = nil
                permissionsAPIContractReportSummary = nil
            }
        #else
            probeDiagnostics = nil
            objectAcceptanceReport = nil
            contextReadinessReport = nil
            contextCreationGateReport = nil
            runtimeBridgePrerequisitesReport = nil
            runtimeBridgeReadinessReport = nil
            storageBrokerReadinessReportSummary = nil
            storageAPIOperationsReportSummary = nil
            runtimeMessagingContractReportSummary = nil
            runtimeMessageDispatcherSkeletonReportSummary = nil
            jsBridgeContractReportSummary = nil
            nativeMessagingReadinessReportSummary = nil
            runtimeListenerContractReportSummary = nil
            serviceWorkerLifecycleReportSummary = nil
            permissionBrokerReadinessReportSummary = nil
            permissionLifecycleReportSummary = nil
            permissionsAPIContractReportSummary = nil
        #endif
        return chromeMV3ProfileHostIfEnabled(
            candidateRewrittenVariants: candidates
        )?.diagnostics(
            candidateInventory: inventory,
            extensionObjectProbeDiagnostics: probeDiagnostics,
            extensionObjectAcceptanceReport: objectAcceptanceReport,
            contextReadinessReport: contextReadinessReport,
            contextCreationGateReport: contextCreationGateReport,
            runtimeBridgePrerequisitesReport:
                runtimeBridgePrerequisitesReport,
            runtimeBridgeReadinessReport:
                runtimeBridgeReadinessReport,
            storageBrokerReadinessReportSummary:
                storageBrokerReadinessReportSummary,
            storageAPIOperationsReportSummary:
                storageAPIOperationsReportSummary,
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
            permissionBrokerReadinessReportSummary:
                permissionBrokerReadinessReportSummary,
            permissionLifecycleReportSummary:
                permissionLifecycleReportSummary,
            permissionsAPIContractReportSummary:
                permissionsAPIContractReportSummary
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
            lastChromeMV3RuntimeBridgeReadinessReport = report

            guard writeReport else { return report }
            return (try? ChromeMV3RuntimeBridgeReadinessReportWriter.write(
                report,
                toRewrittenBundleRoot: rootURL
            )) ?? report
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
                        .diagnostics()
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
                    detachedContextOwnerDiagnostics: diagnostics
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
            lastChromeMV3JSBridgeContractReport = report

            guard writeReport else { return report }
            return (try? ChromeMV3JSBridgeContractReportWriter.write(
                report,
                toRewrittenBundleRoot: rootURL
            )) ?? report
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
    #endif

    @discardableResult
    func tearDownChromeMV3EmptyControllerOwnerIfEnabled(
        trigger: ChromeMV3EmptyControllerTeardownTrigger
    ) -> ChromeMV3EmptyControllerDiagnostics? {
        guard isEnabled else { return nil }
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
            tearDownChromeMV3DetachedContextOwner()
            cachedChromeMV3ExtensionObjectProbeOwner?.tearDown()
            cachedChromeMV3ExtensionObjectProbeOwner = nil
        }

        @available(macOS 15.5, *)
        private func tearDownChromeMV3DetachedContextOwner() {
            cachedChromeMV3DetachedContextOwner?.tearDown()
            cachedChromeMV3DetachedContextOwner = nil
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
