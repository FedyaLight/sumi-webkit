import Foundation
import SwiftData

@available(macOS 15.5, *)
@MainActor
struct ExtensionManagerLifetimeControl {
    private let installedExtensions: InstalledExtensionCollection
    private let runtimeDemand: ExtensionRuntimeDemandAuthority
    private let mutations: ExtensionRuntimeMutationRegistry

    init(
        installedExtensions: InstalledExtensionCollection,
        runtimeDemand: ExtensionRuntimeDemandAuthority,
        mutations: ExtensionRuntimeMutationRegistry
    ) {
        self.installedExtensions = installedExtensions
        self.runtimeDemand = runtimeDemand
        self.mutations = mutations
    }

    func hasNormalTabRuntimeDemand() -> Bool {
        installedExtensions.records.contains(where: \.isEnabled)
            || runtimeDemand.hasRuntimeDemandWithoutEnabledExtensions
    }

    func runWhenTerminalAdmissionAvailable(
        _ operation: @escaping @MainActor () -> Void
    ) {
        mutations.runWhenTerminalAdmissionAvailable(operation)
    }
}

@MainActor
struct SumiExtensionsModuleRuntime {
    typealias CurrentProfileProvider = @MainActor () -> Profile?
    typealias BrowserAttacher = @MainActor (
        _ attachment: ExtensionManagerBrowserAttachment
    ) -> Void
    typealias LiveTabsProvider = @MainActor () -> [Tab]

    let currentProfile: CurrentProfileProvider
    let attachBrowser: BrowserAttacher
    let liveTabs: LiveTabsProvider
}

@MainActor
final class SumiExtensionManagerLifetime {
    private struct Resident {
        let manager: ExtensionManager
        let module: ExtensionManagerModuleResidence
    }

    private let moduleRegistry: SumiModuleRegistry
    private let context: ModelContext?
    private let browserConfiguration: BrowserConfiguration
    private let initialProfileProvider: @MainActor () -> Profile?
    private let managerFactory: @MainActor (
        ModelContext,
        Profile?,
        BrowserConfiguration,
        SumiModuleRegistry
    ) -> ExtensionManager

    let surfaceStore: BrowserExtensionSurfaceStore
    private var runtime: SumiExtensionsModuleRuntime?
    private var runtimeProvider: (
        @MainActor () -> SumiExtensionsModuleRuntime?
    )?
    private var resident: Resident?

    init(
        moduleRegistry: SumiModuleRegistry,
        context: ModelContext?,
        browserConfiguration: BrowserConfiguration,
        initialProfileProvider: @escaping @MainActor () -> Profile?,
        managerFactory: @escaping @MainActor (
            ModelContext,
            Profile?,
            BrowserConfiguration,
            SumiModuleRegistry
        ) -> ExtensionManager,
        surfaceStore: BrowserExtensionSurfaceStore
    ) {
        self.moduleRegistry = moduleRegistry
        self.context = context
        self.browserConfiguration = browserConfiguration
        self.initialProfileProvider = initialProfileProvider
        self.managerFactory = managerFactory
        self.surfaceStore = surfaceStore
    }

    var isEnabled: Bool { moduleRegistry.isEnabled(.extensions) }
    var hasLoadedRuntime: Bool { resident != nil }
    var hasAttachedRuntime: Bool { runtime != nil }
    var currentProfileID: UUID? { runtime?.currentProfile()?.id }
    var liveTabs: [Tab] { runtime?.liveTabs() ?? [] }

    func setEnabledInRegistry(_ isEnabled: Bool) {
        moduleRegistry.setEnabled(isEnabled, for: .extensions)
    }

    func bindRuntimeProvider(
        _ provider: @escaping @MainActor () -> SumiExtensionsModuleRuntime?
    ) {
        runtimeProvider = provider
    }

    func attach(runtime: SumiExtensionsModuleRuntime) {
        guard isEnabled else { return }
        self.runtime = runtime
        if let resident {
            runtime.attachBrowser(resident.module.browserAttachment)
        }
    }

    @discardableResult
    func attachRuntimeFromProviderIfNeeded() -> Bool {
        guard isEnabled else { return false }
        if runtime != nil { return true }
        guard let runtimeProvider, let runtime = runtimeProvider() else {
            return false
        }
        attach(runtime: runtime)
        return true
    }

    func clearAttachedRuntime() {
        runtime = nil
    }

    func retireBrowserAttachmentIfLoaded() {
        resident?.module.retireBrowserAttachment()
        clearAttachedRuntime()
    }

    func loadedCompatibilityDiagnosticsIfEnabled()
        -> ExtensionCompatibilityDiagnosticsSnapshot? {
        loadedModuleIfEnabled()?.compatibilityDiagnosticsSnapshot()
    }

    func loadedToolbarRuntimeIfEnabled() -> ExtensionToolbarRuntime? {
        loadedModuleIfEnabled()?.toolbarRuntime
    }

    func toolbarRuntimeIfEnabled() -> ExtensionToolbarRuntime? {
        moduleIfEnabled()?.toolbarRuntime
    }

    func residentToolbarRuntime() -> ExtensionToolbarRuntime? {
        resident?.module.toolbarRuntime
    }

    private func moduleIfEnabled() -> ExtensionManagerModuleResidence? {
        guard isEnabled, let runtime else { return nil }
        if let resident {
            surfaceStore.activate(resident.module.surfaceBinding)
            return resident.module
        }
        guard let context else { return nil }

        let manager = managerFactory(
            context,
            runtime.currentProfile() ?? initialProfileProvider(),
            browserConfiguration,
            moduleRegistry
        )
        let module = manager.moduleResidence
        resident = Resident(manager: manager, module: module)
        runtime.attachBrowser(module.browserAttachment)
        surfaceStore.activate(module.surfaceBinding)
        return module
    }

    private func moduleIfNeededForNormalTabRuntime()
        -> ExtensionManagerModuleResidence? {
        guard isEnabled, runtime != nil else { return nil }
        if let resident {
            return resident.module.lifetimeControl.hasNormalTabRuntimeDemand()
                ? resident.module
                : nil
        }
        guard hasEnabledPersistedExtensions() else { return nil }
        return moduleIfEnabled()
    }

    func browserRuntimeIfNeededForNormalTab()
        -> ExtensionModuleBrowserRuntime? {
        moduleIfNeededForNormalTabRuntime()?.browserRuntime
    }

    func loadedBrowserRuntimeIfEnabled()
        -> ExtensionModuleBrowserRuntime? {
        loadedModuleIfEnabled()?.browserRuntime
    }

    func residentBrowserRuntime() -> ExtensionModuleBrowserRuntime? {
        resident?.module.browserRuntime
    }

    func settingsCatalogIfEnabled() -> ExtensionSettingsCatalogBinding? {
        moduleIfEnabled()?.settingsCatalog
    }

    func loadedSettingsCatalogIfEnabled()
        -> ExtensionSettingsCatalogBinding? {
        loadedModuleIfEnabled()?.settingsCatalog
    }

    func hasEnabledPersistedExtensions() -> Bool {
        guard let context else { return false }
        let descriptor = FetchDescriptor<ExtensionEntity>(
            predicate: #Predicate { $0.isEnabled }
        )
        do {
            return try context.fetchCount(descriptor) > 0
        } catch {
            RuntimeDiagnostics.debug(category: "Extensions") {
                "Could not count enabled persisted extensions: \(error.localizedDescription)"
            }
            return false
        }
    }

    func quiesceForWebsiteDataMutation(profileIDs: Set<UUID>) -> Bool {
        guard #available(macOS 15.5, *) else { return true }
        guard let module = resident?.module else { return true }
        return module.websiteDataQuiescence.quiesce(profileIDs: profileIDs)
    }

    func retireProfileRuntimeIfLoaded(
        profileID: UUID,
        fallbackProfileID: UUID
    ) -> Bool {
        guard let module = resident?.module else { return true }
        return module.profileRetirement.retire(
            profileID: profileID,
            fallbackProfileID: fallbackProfileID
        )
    }

    func containsProfileRuntimeReference(to profileID: UUID) -> Bool {
        resident?.module.profileRetirement.containsReference(to: profileID)
            ?? false
    }

    func tearDownLoadedRuntime(reason: String) {
        guard let resident else {
            surfaceStore.deactivate()
            return
        }

        let result = resident.module.shutDown(reason: reason)
        surfaceStore.deactivate()
        if result.completionStatus == .mutationInProgress {
            scheduleRuntimeTeardownRetry(
                manager: resident.manager,
                module: resident.module,
                reason: reason
            )
            return
        }
        guard result.completed else { return }
        _ = resident.module.executeRebuildPlan(
            result.tabRebuildPlan,
            reason: reason
        )
        self.resident = nil
    }

    private func scheduleRuntimeTeardownRetry(
        manager: ExtensionManager,
        module: ExtensionManagerModuleResidence,
        reason: String
    ) {
        module.lifetimeControl.runWhenTerminalAdmissionAvailable {
            [weak self, weak manager] in
            Task { @MainActor [weak self, weak manager] in
                guard let self, let manager,
                      self.isEnabled == false,
                      self.resident?.manager === manager
                else { return }
                self.tearDownLoadedRuntime(reason: "\(reason).deferred")
            }
        }
    }

    private func loadedModuleIfEnabled()
        -> ExtensionManagerModuleResidence? {
        guard isEnabled, runtime != nil else { return nil }
        return resident?.module
    }

    #if DEBUG
        func managerIfEnabled() -> ExtensionManager? {
            guard moduleIfEnabled() != nil else { return nil }
            return resident?.manager
        }

        func loadedManagerIfEnabled() -> ExtensionManager? {
            guard loadedModuleIfEnabled() != nil else { return nil }
            return resident?.manager
        }
    #endif
}
