import Combine
import Foundation

@MainActor
final class SumiExtensionModuleDemand {
    private let lifetime: SumiExtensionManagerLifetime
    private let contentBlocking: SumiExtensionContentBlockingSurface
    private let toolbarActions: SumiExtensionToolbarActionSurface
    private let enabledState: CurrentValueSubject<Bool, Never>

    init(
        lifetime: SumiExtensionManagerLifetime,
        contentBlocking: SumiExtensionContentBlockingSurface,
        toolbarActions: SumiExtensionToolbarActionSurface
    ) {
        self.lifetime = lifetime
        self.contentBlocking = contentBlocking
        self.toolbarActions = toolbarActions
        enabledState = CurrentValueSubject(lifetime.isEnabled)
    }

    var isEnabled: Bool { lifetime.isEnabled }
    var hasLoadedRuntime: Bool { lifetime.hasLoadedRuntime }
    var enabledChanges: AnyPublisher<Bool, Never> {
        enabledState.removeDuplicates().eraseToAnyPublisher()
    }

    func setEnabled(_ isEnabled: Bool) {
        let wasEnabled = lifetime.isEnabled
        lifetime.setEnabledInRegistry(isEnabled)

        if isEnabled == false {
            if wasEnabled {
                contentBlocking.markReloadRequiredForLiveTabs()
            }
            lifetime.tearDownLoadedRuntime(
                reason: "SumiExtensionModuleDemand.setEnabled(false)"
            )
            contentBlocking.clearRuntimeIfMaterialized()
            toolbarActions.clearPendingActionAnchors()
            lifetime.clearAttachedRuntime()
        } else if wasEnabled == false {
            lifetime.attachRuntimeFromProviderIfNeeded()
            contentBlocking.markReloadRequiredForLiveTabs()
        }
        if wasEnabled != isEnabled {
            enabledState.send(isEnabled)
        }
    }

    func bindRuntimeProvider(
        _ provider: @escaping @MainActor () -> SumiExtensionsModuleRuntime?
    ) {
        lifetime.bindRuntimeProvider(provider)
    }

    func attach(runtime: SumiExtensionsModuleRuntime) {
        lifetime.attach(runtime: runtime)
        toolbarActions.ensureActionMetadataLoadedIfNeeded()
    }

    func quiesceForWebsiteDataMutation(profileIDs: Set<UUID>) -> Bool {
        lifetime.quiesceForWebsiteDataMutation(profileIDs: profileIDs)
    }
}
