import Combine
import Foundation

/// Module gate for Live Folders (RSS / GitHub). When disabled, runtime stays inactive
/// and `startAfterTabRestore` must not load disk state or schedule refresh work.
@MainActor
final class SumiLiveFoldersModule: ObservableObject {
    private let moduleRegistry: SumiModuleRegistry
    private let changesSubject = PassthroughSubject<Void, Never>()
    private weak var manager: SumiLiveFolderManager?
    private var runtimeProvider: (@MainActor () -> SumiLiveFolderRuntime)?
    private(set) var hasAttachedRuntime = false

    init(moduleRegistry: SumiModuleRegistry) {
        self.moduleRegistry = moduleRegistry
    }

    var isEnabled: Bool {
        moduleRegistry.isEnabled(.liveFolders)
    }

    var changesPublisher: AnyPublisher<Void, Never> {
        changesSubject.eraseToAnyPublisher()
    }

    /// Binds the Live Folder manager + runtime factory for enable-after-startup.
    func bind(
        manager: SumiLiveFolderManager,
        runtimeProvider: @escaping @MainActor () -> SumiLiveFolderRuntime
    ) {
        self.manager = manager
        self.runtimeProvider = runtimeProvider
    }

    func attach(runtime: SumiLiveFolderRuntime) {
        manager?.attach(runtime: runtime)
        hasAttachedRuntime = true
    }

    func setEnabled(_ isEnabled: Bool) {
        let wasEnabled = self.isEnabled
        guard wasEnabled != isEnabled else { return }
        moduleRegistry.setEnabled(isEnabled, for: .liveFolders)

        if isEnabled == false {
            manager?.stopAndClearRuntime()
            hasAttachedRuntime = false
        } else {
            attachRuntimeFromProviderIfNeeded()
            manager?.startAfterTabRestore(isEnabled: true)
        }

        changesSubject.send(())
    }

    private func attachRuntimeFromProviderIfNeeded() {
        guard hasAttachedRuntime == false, let runtimeProvider else { return }
        attach(runtime: runtimeProvider())
    }
}
