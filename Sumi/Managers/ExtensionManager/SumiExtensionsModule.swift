import Foundation
import SwiftData

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

    init(
        moduleRegistry: SumiModuleRegistry = .unavailable(),
        context: ModelContext? = nil,
        browserConfiguration: BrowserConfiguration? = nil,
        initialProfileProvider: @escaping @MainActor () -> Profile? = { nil },
        safariExtensionImportStore: any SafariExtensionImportStoring & SafariExtensionImportRecordProviding = SafariExtensionImportStore.process,
        managerFactory: @escaping @MainActor (
            ModelContext,
            Profile?,
            BrowserConfiguration,
            SumiModuleRegistry
        ) -> ExtensionManager = {
            ExtensionManager(
                context: $0,
                initialProfile: $1,
                browserConfiguration: $2,
                moduleRegistry: $3
            )
        },
        surfaceStore: BrowserExtensionSurfaceStore? = nil
    ) {
        let resolvedSurfaceStore = surfaceStore ?? BrowserExtensionSurfaceStore(
            extensionManager: nil
        )
        let managerLifetime = SumiExtensionManagerLifetime(
            moduleRegistry: moduleRegistry,
            context: context,
            browserConfiguration: browserConfiguration ?? .shared,
            initialProfileProvider: initialProfileProvider,
            managerFactory: managerFactory,
            surfaceStore: resolvedSurfaceStore
        )
        let contentBlocking = SumiExtensionContentBlockingSurface(
            context: context,
            moduleRegistry: moduleRegistry,
            lifetime: managerLifetime
        )
        let toolbarActions = SumiExtensionToolbarActionSurface(
            lifetime: managerLifetime
        )
        let settingsCatalog = SumiExtensionSettingsCatalogSurface(
            lifetime: managerLifetime,
            importStore: safariExtensionImportStore
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
    var hasLoadedRuntime: Bool { demand.hasLoadedRuntime }
    var hasAttachedRuntime: Bool { managerLifetime.hasAttachedRuntime }

    func bindRuntimeProvider(
        _ provider: @escaping @MainActor () -> SumiExtensionsModuleRuntime
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
