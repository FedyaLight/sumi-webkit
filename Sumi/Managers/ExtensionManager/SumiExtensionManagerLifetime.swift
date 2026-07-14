import Foundation
import SwiftData

@MainActor
struct SumiExtensionsModuleRuntime {
    typealias CurrentProfileProvider = @MainActor () -> Profile?
    typealias ManagerAttacher = @MainActor (_ manager: ExtensionManager) -> Void
    typealias LiveTabsProvider = @MainActor () -> [Tab]

    let currentProfile: CurrentProfileProvider
    let attachManager: ManagerAttacher
    let liveTabs: LiveTabsProvider

    static let inactive = SumiExtensionsModuleRuntime(
        currentProfile: { nil },
        attachManager: { _ in },
        liveTabs: { [] }
    )
}

@MainActor
final class SumiExtensionManagerLifetime {
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
    private(set) var runtime = SumiExtensionsModuleRuntime.inactive
    private var runtimeProvider: (@MainActor () -> SumiExtensionsModuleRuntime)?
    private var cachedManager: ExtensionManager?
    private(set) var hasAttachedRuntime = false

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
    var hasLoadedRuntime: Bool { cachedManager != nil }
    var currentProfileID: UUID? { runtime.currentProfile()?.id }
    var liveTabs: [Tab] { runtime.liveTabs() }

    func setEnabledInRegistry(_ isEnabled: Bool) {
        moduleRegistry.setEnabled(isEnabled, for: .extensions)
    }

    func bindRuntimeProvider(
        _ provider: @escaping @MainActor () -> SumiExtensionsModuleRuntime
    ) {
        runtimeProvider = provider
    }

    func attach(runtime: SumiExtensionsModuleRuntime) {
        self.runtime = runtime
        hasAttachedRuntime = true
        if let cachedManager {
            runtime.attachManager(cachedManager)
        }
    }

    func attachRuntimeFromProviderIfNeeded() {
        guard hasAttachedRuntime == false, let runtimeProvider else { return }
        runtime = runtimeProvider()
        hasAttachedRuntime = true
    }

    func clearAttachedRuntime() {
        runtime = .inactive
        hasAttachedRuntime = false
    }

    func loadedManagerIfEnabled() -> ExtensionManager? {
        guard isEnabled else { return nil }
        return cachedManager
    }

    /// Teardown-only access to a resident manager after demand has already
    /// been disabled. This never materializes the optional runtime.
    func residentManager() -> ExtensionManager? {
        cachedManager
    }

    func managerIfEnabled() -> ExtensionManager? {
        guard isEnabled else { return nil }
        if let cachedManager {
            surfaceStore.bind(cachedManager)
            return cachedManager
        }
        guard let context else { return nil }

        let manager = managerFactory(
            context,
            runtime.currentProfile() ?? initialProfileProvider(),
            browserConfiguration,
            moduleRegistry
        )
        cachedManager = manager
        runtime.attachManager(manager)
        surfaceStore.bind(manager)
        return manager
    }

    func managerIfNeededForNormalTabRuntime() -> ExtensionManager? {
        guard isEnabled else { return nil }
        if let cachedManager {
            let hasRuntimeDemand =
                cachedManager.installedExtensionCollection.records.contains(
                    where: \.isEnabled
                )
                || cachedManager.runtimeDemand.admitsRuntime(
                    hasEnabledExtensions: false,
                    allowWithoutEnabledExtensions: false
                )
            return hasRuntimeDemand ? cachedManager : nil
        }
        guard hasEnabledPersistedExtensions() else { return nil }
        return managerIfEnabled()
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
        guard let cachedManager else { return true }
        return cachedManager.quiesceForWebsiteDataMutation(profileIDs: profileIDs)
    }

    func tearDownLoadedRuntime(reason: String) {
        guard let cachedManager else {
            surfaceStore.bind(nil)
            return
        }

        let result = cachedManager.shutDownExtensionRuntime(reason: reason)
        surfaceStore.bind(nil)
        if result.completionStatus == .mutationInProgress {
            scheduleRuntimeTeardownRetry(manager: cachedManager, reason: reason)
            return
        }
        guard result.completed else { return }
        _ = cachedManager.executeExtensionRuntimeRebuildPlan(
            result.tabRebuildPlan,
            reason: reason
        )
        self.cachedManager = nil
    }

    private func scheduleRuntimeTeardownRetry(
        manager: ExtensionManager,
        reason: String
    ) {
        manager.runtimeMutationRegistry.runWhenTerminalAdmissionAvailable {
            [weak self, weak manager] in
            Task { @MainActor [weak self, weak manager] in
                guard let self, let manager,
                      self.isEnabled == false,
                      self.cachedManager === manager
                else { return }
                self.tearDownLoadedRuntime(reason: "\(reason).deferred")
            }
        }
    }
}
