import Combine
import Foundation

/// Public extension-subsystem boundary.
///
/// Mutable runtime ownership lives in role-exact collaborators. This type
/// composes those roles and preserves the product-facing API without exposing
/// `ExtensionManager` as a service locator.
@MainActor
final class SumiExtensionsModule {
    private let demand: SumiExtensionModuleDemand
    private let managerLifetime: SumiExtensionManagerLifetime
    let settingsCatalog: SumiExtensionSettingsCatalogSurface
    let contentBlocking: SumiExtensionContentBlockingSurface
    let toolbarActions: SumiExtensionToolbarActionSurface
    let runtimeSurface: SumiExtensionRuntimeSurface
    let compatibilityDiagnostics: SumiExtensionCompatibilityDiagnosticsSurface

    var surfaceStore: BrowserExtensionSurfaceStore {
        managerLifetime.surfaceStore
    }

    #if DEBUG
    convenience init(
        moduleRegistry: SumiModuleRegistry = .unavailable(),
        database: SumiDatabase? = nil,
        browserConfiguration: BrowserConfiguration? = nil,
        initialProfileProvider: @escaping @MainActor () -> Profile? = { nil },
        profileReferenceAdmission: ProfileReferenceAdmissionLedger = .failClosed(),
        safariExtensionImportStore:
            (any SafariExtensionImportStoring & SafariExtensionImportRecordProviding)? = nil,
        managerFactory: (@MainActor (
            SumiDatabase,
            Profile?,
            BrowserConfiguration,
            SumiModuleRegistry
        ) -> ExtensionManager)? = nil,
        surfaceStore: BrowserExtensionSurfaceStore? = nil
    ) {
        self.init(
            moduleRegistry: moduleRegistry,
            database: database,
            browserConfiguration: browserConfiguration,
            initialProfileProvider: initialProfileProvider,
            profileReferenceAdmission: profileReferenceAdmission,
            compiledRuleListCatalog: SumiCompiledContentRuleListCatalog(),
            safariExtensionImportStore: safariExtensionImportStore,
            managerFactory: managerFactory,
            surfaceStore: surfaceStore
        )
    }
    #endif

    init(
        moduleRegistry: SumiModuleRegistry = .unavailable(),
        database: SumiDatabase? = nil,
        browserConfiguration: BrowserConfiguration? = nil,
        initialProfileProvider: @escaping @MainActor () -> Profile? = { nil },
        profileReferenceAdmission: ProfileReferenceAdmissionLedger = .failClosed(),
        compiledRuleListCatalog: SumiCompiledContentRuleListCataloging,
        safariExtensionImportStore:
            (any SafariExtensionImportStoring & SafariExtensionImportRecordProviding)? = nil,
        managerFactory: (@MainActor (
            SumiDatabase,
            Profile?,
            BrowserConfiguration,
            SumiModuleRegistry
        ) -> ExtensionManager)? = nil,
        surfaceStore: BrowserExtensionSurfaceStore? = nil
    ) {
        let resolvedSurfaceStore = surfaceStore ?? BrowserExtensionSurfaceStore(
            binding: nil
        )
        let resolvedImportStore:
            any SafariExtensionImportStoring & SafariExtensionImportRecordProviding
        if let safariExtensionImportStore {
            resolvedImportStore = safariExtensionImportStore
        } else if let database {
            resolvedImportStore = SafariExtensionImportStore(database: database)
        } else {
            resolvedImportStore = SafariExtensionImportStore.transient
        }
        let resolvedManagerFactory = managerFactory ?? {
            ExtensionManager(
                database: $0,
                initialProfile: $1,
                profileReferenceAdmission: profileReferenceAdmission,
                browserConfiguration: $2,
                moduleRegistry: $3,
                extensionPreferences: $3.userDefaults
            )
        }
        let managerLifetime = SumiExtensionManagerLifetime(
            moduleRegistry: moduleRegistry,
            database: database,
            browserConfiguration: browserConfiguration ?? .shared,
            initialProfileProvider: initialProfileProvider,
            managerFactory: resolvedManagerFactory,
            surfaceStore: resolvedSurfaceStore
        )
        let contentBlocking = SumiExtensionContentBlockingSurface(
            database: database,
            compiledRuleListCatalog: compiledRuleListCatalog,
            moduleRegistry: moduleRegistry,
            lifetime: managerLifetime
        )
        let toolbarActions = SumiExtensionToolbarActionSurface(
            lifetime: managerLifetime,
            surfaceStore: resolvedSurfaceStore
        )
        let settingsCatalog = SumiExtensionSettingsCatalogSurface(
            lifetime: managerLifetime,
            importStore: resolvedImportStore
        )

        self.managerLifetime = managerLifetime
        self.contentBlocking = contentBlocking
        self.toolbarActions = toolbarActions
        self.settingsCatalog = settingsCatalog
        runtimeSurface = SumiExtensionRuntimeSurface(lifetime: managerLifetime)
        compatibilityDiagnostics = SumiExtensionCompatibilityDiagnosticsSurface(
            lifetime: managerLifetime,
            settingsCatalog: settingsCatalog,
            contentBlocking: contentBlocking
        )
        demand = SumiExtensionModuleDemand(
            lifetime: managerLifetime,
            contentBlocking: contentBlocking,
            toolbarActions: toolbarActions
        )
    }

    var isEnabled: Bool { demand.isEnabled }
    var enabledChanges: AnyPublisher<Bool, Never> { demand.enabledChanges }
    var hasLoadedRuntime: Bool { demand.hasLoadedRuntime }
    var hasAttachedRuntime: Bool { managerLifetime.hasAttachedRuntime }

    func bindRuntimeProvider(
        _ provider: @escaping @MainActor () -> SumiExtensionsModuleRuntime?
    ) {
        demand.bindRuntimeProvider(provider)
    }

    func attach(runtime: SumiExtensionsModuleRuntime) {
        demand.attach(runtime: runtime)
    }

    func setEnabled(_ isEnabled: Bool) {
        demand.setEnabled(isEnabled)
    }

    func quiesceForWebsiteDataMutation(profileIDs: Set<UUID>) -> Bool {
        demand.quiesceForWebsiteDataMutation(profileIDs: profileIDs)
    }

    func retireProfileRuntimeIfLoaded(
        profileID: UUID,
        fallbackProfileID: UUID
    ) -> Bool {
        managerLifetime.retireProfileRuntimeIfLoaded(
            profileID: profileID,
            fallbackProfileID: fallbackProfileID
        )
    }

    func retireBrowserAttachmentIfLoaded() {
        managerLifetime.retireBrowserAttachmentIfLoaded()
    }

    func containsProfileRuntimeReference(to profileID: UUID) -> Bool {
        managerLifetime.containsProfileRuntimeReference(to: profileID)
    }

    #if DEBUG
        /// Low-level runtime tests may inspect the injected manager. Product
        /// consumers must use a role-exact module surface instead.
        func managerForTesting(materializeIfNeeded: Bool = true) -> ExtensionManager? {
            if materializeIfNeeded {
                return managerLifetime.managerIfEnabled()
            }
            return managerLifetime.loadedManagerIfEnabled()
        }
    #endif
}
