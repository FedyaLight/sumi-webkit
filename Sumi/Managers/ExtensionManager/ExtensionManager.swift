import Foundation
import OSLog
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionManager: NSObject {
    static let logger = Logger.sumi(category: "Extensions")
    static let safariWebExtensionURLScheme =
        ExtensionContextPreparation.webExtensionURLScheme
    static let registerSafariWebExtensionURLScheme: Void =
        ExtensionContextPreparation.registerWebExtensionURLScheme
    private let controllerGraph: ExtensionControllerGraph
    private let contextLifecycleGraph: ExtensionContextLifecycleGraph
    private let normalTabGraph: ExtensionNormalTabGraph
    private let runtimePublicationGraph: ExtensionRuntimePublicationGraph
    private let actionUIGraph: ExtensionActionUIGraph
    private let installationRetirementGraph:
        ExtensionInstallationRetirementGraph
    let moduleResidence: ExtensionManagerModuleResidence

    #if DEBUG
        let isExtensionSupportAvailable = true
        let controllerIdentifierOwner = ExtensionControllerIdentifierOwner()
    #endif
    #if DEBUG || SUMI_DIAGNOSTICS
        let accountForkDiagnosticsUserScript:
            SafariExtensionAccountForkDiagnosticsUserScript
    #endif

    convenience init(
        database: SumiDatabase,
        initialProfile: Profile?,
        profileReferenceAdmission: ProfileReferenceAdmissionLedger,
        browserConfiguration: BrowserConfiguration? = nil,
        moduleRegistry: SumiModuleRegistry = .unavailable(),
        extensionPreferences: UserDefaults = .standard,
        profileWebExtensionRuntime: SumiProfileWebExtensionRuntime? = nil
    ) {
        self.init(
            database: database,
            initialProfile: initialProfile,
            profileReferenceAdmission: profileReferenceAdmission,
            browserConfiguration: browserConfiguration,
            moduleRegistry: moduleRegistry,
            extensionPreferences: extensionPreferences,
            profileWebExtensionRuntime: profileWebExtensionRuntime,
            assemblySeams: .production
        )
    }

    #if DEBUG
        convenience init(
            database: SumiDatabase,
            initialProfile: Profile?,
            browserConfiguration: BrowserConfiguration? = nil,
            moduleRegistry: SumiModuleRegistry = .unavailable(),
            extensionPreferences: UserDefaults = .standard,
            profileWebExtensionRuntime: SumiProfileWebExtensionRuntime? = nil
        ) {
            self.init(
                database: database,
                initialProfile: initialProfile,
                profileReferenceAdmission: .testingAllowingReferences(),
                browserConfiguration: browserConfiguration,
                moduleRegistry: moduleRegistry,
                extensionPreferences: extensionPreferences,
                profileWebExtensionRuntime: profileWebExtensionRuntime,
                assemblySeams: .production
            )
        }

        convenience init(
            database: SumiDatabase,
            initialProfile: Profile?,
            browserConfiguration: BrowserConfiguration? = nil,
            moduleRegistry: SumiModuleRegistry = .unavailable(),
            extensionPreferences: UserDefaults = .standard,
            profileWebExtensionRuntime: SumiProfileWebExtensionRuntime? = nil,
            attachedRuntimeDidInstall:
                @escaping ExtensionBrowserAttachmentAuthority.DidInstall,
            testInspectionDidAssemble:
                ExtensionManagerTestInspection.DidAssemble? = nil,
            testAssemblyOverrides:
                ExtensionManagerTestAssemblyOverrides? = nil
        ) {
            self.init(
                database: database,
                initialProfile: initialProfile,
                profileReferenceAdmission: .testingAllowingReferences(),
                browserConfiguration: browserConfiguration,
                moduleRegistry: moduleRegistry,
                extensionPreferences: extensionPreferences,
                profileWebExtensionRuntime: profileWebExtensionRuntime,
                assemblySeams: ExtensionManagerAssemblySeams(
                    attachedRuntimeDidInstall: attachedRuntimeDidInstall,
                    inspectionDidAssemble: testInspectionDidAssemble,
                    assemblyOverrides: testAssemblyOverrides
                )
            )
        }

        convenience init(
            database: SumiDatabase,
            initialProfile: Profile?,
            browserConfiguration: BrowserConfiguration? = nil,
            moduleRegistry: SumiModuleRegistry = .unavailable(),
            extensionPreferences: UserDefaults = .standard,
            profileWebExtensionRuntime: SumiProfileWebExtensionRuntime? = nil,
            testInspectionDidAssemble:
                @escaping ExtensionManagerTestInspection.DidAssemble,
            testAssemblyOverrides:
                ExtensionManagerTestAssemblyOverrides? = nil
        ) {
            self.init(
                database: database,
                initialProfile: initialProfile,
                profileReferenceAdmission: .testingAllowingReferences(),
                browserConfiguration: browserConfiguration,
                moduleRegistry: moduleRegistry,
                extensionPreferences: extensionPreferences,
                profileWebExtensionRuntime: profileWebExtensionRuntime,
                assemblySeams: ExtensionManagerAssemblySeams(
                    attachedRuntimeDidInstall: nil,
                    inspectionDidAssemble: testInspectionDidAssemble,
                    assemblyOverrides: testAssemblyOverrides
                )
            )
        }

        convenience init(
            database: SumiDatabase,
            initialProfile: Profile?,
            browserConfiguration: BrowserConfiguration? = nil,
            moduleRegistry: SumiModuleRegistry = .unavailable(),
            extensionPreferences: UserDefaults = .standard,
            profileWebExtensionRuntime: SumiProfileWebExtensionRuntime? = nil,
            testAssemblyOverrides:
                ExtensionManagerTestAssemblyOverrides
        ) {
            self.init(
                database: database,
                initialProfile: initialProfile,
                profileReferenceAdmission: .testingAllowingReferences(),
                browserConfiguration: browserConfiguration,
                moduleRegistry: moduleRegistry,
                extensionPreferences: extensionPreferences,
                profileWebExtensionRuntime: profileWebExtensionRuntime,
                assemblySeams: ExtensionManagerAssemblySeams(
                    attachedRuntimeDidInstall: nil,
                    inspectionDidAssemble: nil,
                    assemblyOverrides: testAssemblyOverrides
                )
            )
        }
    #endif

    private init(
        database: SumiDatabase,
        initialProfile: Profile?,
        profileReferenceAdmission: ProfileReferenceAdmissionLedger,
        browserConfiguration: BrowserConfiguration?,
        moduleRegistry: SumiModuleRegistry,
        extensionPreferences: UserDefaults,
        profileWebExtensionRuntime: SumiProfileWebExtensionRuntime? = nil,
        assemblySeams: ExtensionManagerAssemblySeams
    ) {
        let signpostState = PerformanceTrace.beginInterval("ExtensionManager.init")
        defer {
            PerformanceTrace.endInterval("ExtensionManager.init", signpostState)
        }
        _ = Self.registerSafariWebExtensionURLScheme

        #if DEBUG || SUMI_DIAGNOSTICS
            let accountForkDiagnosticsUserScript =
                SafariExtensionAccountForkDiagnosticsUserScript()
            self.accountForkDiagnosticsUserScript =
                accountForkDiagnosticsUserScript
            let moduleUserScripts: [SumiPageScript] = [
                accountForkDiagnosticsUserScript,
            ]
        #else
            let moduleUserScripts: [SumiPageScript] = []
        #endif

        let resolvedBrowserConfiguration = browserConfiguration ?? .shared
        let resolvedProfileWebExtensionRuntime = profileWebExtensionRuntime
            ?? SumiProfileWebExtensionRuntime(
                browserConfiguration: resolvedBrowserConfiguration,
                profileReferenceAdmission: profileReferenceAdmission,
                initialProfileProvider: { initialProfile }
            )
        let graphs = ExtensionManagerRootAssembler.assemble(
            database: database,
            initialProfile: initialProfile,
            browserConfiguration: resolvedBrowserConfiguration,
            moduleRegistry: moduleRegistry,
            extensionPreferences: extensionPreferences,
            profileWebExtensionRuntime: resolvedProfileWebExtensionRuntime,
            assemblySeams: assemblySeams
        )
        controllerGraph = graphs.controller
        contextLifecycleGraph = graphs.contexts
        normalTabGraph = graphs.normalTabs
        runtimePublicationGraph = graphs.runtimePublication
        actionUIGraph = graphs.actions
        installationRetirementGraph = graphs.installation
        moduleResidence = ExtensionManagerModuleResidence(
            browserRuntime: graphs.normalTabs.moduleRuntimeFactory.make(
                userScripts: moduleUserScripts
            ),
            surfaceBinding: graphs.actions.surfaceBinding,
            lifetimeControl: graphs.contexts.control,
            websiteDataQuiescence: graphs.contexts.websiteDataQuiescence,
            profileRetirement: graphs.contexts.profileRetirement,
            settingsCatalog: graphs.installation.settingsCatalog,
            toolbarRuntime: graphs.actions.toolbarRuntime,
            autofillRuntime: graphs.actions.autofillRuntime,
            attachment: graphs.runtimePublication.attacher,
            runtimeTermination: graphs.installation.runtimeTermination,
            compatibilityDiagnostics:
                graphs.actions.compatibilityDiagnostics
        )
        super.init()

        PerformanceTrace.emitEvent("ExtensionManager.runtimeComposed")
    }

    #if DEBUG
        var controllerIdentifier: UUID { controllerIdentifierOwner.identifier }
    #endif

    nonisolated static var isWebKitRuntimeTraceEnabled: Bool {
        RuntimeDiagnostics.isVerboseEnabled
    }

    nonisolated static var shouldObserveExtensionErrors: Bool {
        RuntimeDiagnostics.isVerboseEnabled
    }

    #if DEBUG
        struct TestHooks {
            var beforePersistInstalledRecord:
                ((InstalledExtension) throws -> Void)?
            var beforeControllerLoad:
                (@MainActor (String, WebExtensionStorageSnapshot) throws -> Void)?
            var backgroundContentWake:
                (@MainActor (String, WKWebExtensionContext) async throws -> Void)?
            var permissionPromptDecision:
                ((WKWebExtensionContext, [String], String) ->
                    ExtensionPermissionPromptDecision)?
            var didDispatchExtensionAction: ((String) -> Void)?
            var webExtensionDataCleanup:
                (@MainActor (String) async -> Bool)?
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
            get { actionUIGraph.debugSignals.hooks }
            set { actionUIGraph.debugSignals.hooks = newValue }
        }

        func clearDebugState() {
            actionUIGraph.debugSignals.hooks = TestHooks()
        }

        func dispatchAuxiliaryPublicationDebugEvent(
            _ event: ExtensionAuxiliaryPublicationDebugEvent
        ) {
            actionUIGraph.debugSignals
                .dispatchAuxiliaryPublication(event)
        }

        func dispatchNormalTabLifecycleDebugEvent(
            _ event: ExtensionNormalTabLifecycleDebugEvent
        ) {
            actionUIGraph.debugSignals
                .dispatchNormalTabLifecycle(event)
        }

        func drainExtensionRuntimeTasksForTests() async {
            await contextLifecycleGraph.testTaskDrain.drain()
        }

        func attach(browserManager: BrowserManager) {
            moduleResidence.browserAttachment.attach(to: browserManager)
        }

        func moduleBrowserRuntime() -> ExtensionModuleBrowserRuntime {
            moduleResidence.browserRuntime
        }

        func surfaceStoreBinding() -> BrowserExtensionSurfaceBinding {
            moduleResidence.surfaceBinding
        }

        func settingsCatalogBinding() -> ExtensionSettingsCatalogBinding {
            moduleResidence.settingsCatalog
        }

        func autofillRuntime() -> SafariExtensionAutofillRuntime {
            moduleResidence.autofillRuntime
        }

        @discardableResult
        func shutDownExtensionRuntime(
            reason: String,
            admission: ExtensionRuntimeShutdown.Admission = .forced
        ) -> ExtensionRuntimeShutdown.Result {
            moduleResidence.shutDown(reason: reason, admission: admission)
        }

        func executeExtensionRuntimeRebuildPlan(
            _ plan: ExtensionRuntimeTabRebuildPlan,
            reason: String
        ) -> [ExtensionRuntimeTabRebuildPlan.Execution] {
            moduleResidence.executeRebuildPlan(plan, reason: reason)
        }

        func quiesceForWebsiteDataMutation(profileIDs: Set<UUID>) -> Bool {
            moduleResidence.websiteDataQuiescence.quiesce(
                profileIDs: profileIDs
            )
        }
    #endif

    isolated deinit {
        let signpostState = PerformanceTrace.beginInterval("ExtensionManager.deinit")
        defer {
            PerformanceTrace.endInterval("ExtensionManager.deinit", signpostState)
        }
        _ = moduleResidence.shutDown(reason: "deinit")
        #if DEBUG
            controllerIdentifierOwner
                .removeTestStorageIfNeededForLoadedIdentifier()
        #endif
    }
}
