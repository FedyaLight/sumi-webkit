import Foundation
import SwiftData
import WebKit

@MainActor
final class SumiUserscriptsModule {
    private let moduleRegistry: SumiModuleRegistry
    private let context: ModelContext?
    private let managerFactory: @MainActor (ModelContext?) -> SumiScriptsManager

    private var cachedManager: SumiScriptsManager?
    private var managerRuntime = SumiScriptsManagerRuntime.inactive
    private var runtimeProvider: (@MainActor () -> SumiScriptsManagerRuntime)?
    private(set) var hasAttachedRuntime = false

    init(
        moduleRegistry: SumiModuleRegistry = .shared,
        context: ModelContext? = nil,
        // Explicit injection seam for focused tests; production constructs lazily only when enabled.
        managerFactory: @escaping @MainActor (ModelContext?) -> SumiScriptsManager = {
            SumiScriptsManager(context: $0)
        }
    ) {
        self.moduleRegistry = moduleRegistry
        self.context = context
        self.managerFactory = managerFactory
    }

    var isEnabled: Bool {
        moduleRegistry.isEnabled(.userScripts)
    }

    var hasLoadedRuntime: Bool {
        cachedManager != nil
    }

    /// Stores a factory used when the module is enabled after BrowserManager wiring.
    func bindRuntimeProvider(_ provider: @escaping @MainActor () -> SumiScriptsManagerRuntime) {
        runtimeProvider = provider
    }

    func attach(runtime: SumiScriptsManagerRuntime) {
        managerRuntime = runtime
        hasAttachedRuntime = true
        cachedManager?.attach(runtime: managerRuntime)
    }

    func setEnabled(_ isEnabled: Bool) {
        let wasEnabled = self.isEnabled
        moduleRegistry.setEnabled(isEnabled, for: .userScripts)
        if isEnabled == false {
            cachedManager?.deactivateFromUserscriptsModule()
            cachedManager = nil
            clearAttachedRuntime()
        } else if wasEnabled == false {
            attachRuntimeFromProviderIfNeeded()
        }
    }

    private func attachRuntimeFromProviderIfNeeded() {
        guard hasAttachedRuntime == false, let runtimeProvider else { return }
        attach(runtime: runtimeProvider())
    }

    private func clearAttachedRuntime() {
        managerRuntime = .inactive
        hasAttachedRuntime = false
    }

    func managerIfEnabled() -> SumiScriptsManager? {
        guard isEnabled else { return nil }

        if let cachedManager {
            cachedManager.activateFromUserscriptsModule()
            return cachedManager
        }

        let manager = managerFactory(context)
        manager.attach(runtime: managerRuntime)
        manager.activateFromUserscriptsModule()
        cachedManager = manager
        return manager
    }

    func normalTabUserScripts(
        for url: URL,
        webViewId: UUID,
        profileId: UUID?,
        isEphemeral: Bool
    ) -> [SumiUserScript] {
        guard let manager = managerIfEnabled() else { return [] }
        return manager.normalTabUserScripts(
            for: url,
            webViewId: webViewId,
            profileId: profileId,
            isEphemeral: isEphemeral
        )
    }

    func interceptInstallNavigationIfNeeded(_ url: URL) -> Bool {
        guard let manager = managerIfEnabled() else { return false }
        return manager.interceptInstallNavigationIfNeeded(url)
    }

    func cleanupWebViewIfLoaded(
        controller: WKUserContentController,
        webViewId: UUID
    ) {
        cachedManager?.cleanupWebView(
            controller: controller,
            webViewId: webViewId
        )
    }
}
