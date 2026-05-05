import Foundation
import SwiftData
import UserScript
import WebKit

@MainActor
final class SumiUserscriptsModule {
    static let shared = SumiUserscriptsModule()

    private let moduleRegistry: SumiModuleRegistry
    private let context: ModelContext?
    private let managerFactory: @MainActor (ModelContext?) -> SumiScriptsManager

    private var cachedManager: SumiScriptsManager?
    weak var browserManager: BrowserManager?

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

    func attach(browserManager: BrowserManager) {
        self.browserManager = browserManager
        cachedManager?.attach(browserManager: browserManager)
    }

    func setEnabled(_ isEnabled: Bool) {
        moduleRegistry.setEnabled(isEnabled, for: .userScripts)
        if isEnabled == false {
            cachedManager?.deactivateFromUserscriptsModule()
        }
    }

    func managerIfEnabled() -> SumiScriptsManager? {
        guard isEnabled else { return nil }

        if let cachedManager {
            cachedManager.activateFromUserscriptsModule()
            return cachedManager
        }

        let manager = managerFactory(context)
        if let browserManager {
            manager.attach(browserManager: browserManager)
        }
        manager.activateFromUserscriptsModule()
        cachedManager = manager
        return manager
    }

    func normalTabUserScripts(
        for url: URL,
        webViewId: UUID,
        profileId: UUID?,
        isEphemeral: Bool
    ) -> [UserScript] {
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
