import Foundation
import SwiftData
import WebKit

@MainActor
final class SumiUserscriptsModule {
    static let shared = SumiUserscriptsModule()

    private let moduleRegistry: SumiModuleRegistry
    private let context: ModelContext?
    private let managerFactory: @MainActor (ModelContext?) -> SumiScriptsManager

    private var cachedManager: SumiScriptsManager?
    private var managerRuntime = SumiScriptsManagerRuntime.inactive

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

    func attach(browserManager: BrowserManager) {
        managerRuntime = .live(browserManager: browserManager)
        cachedManager?.attach(runtime: managerRuntime)
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

extension SumiScriptsManagerRuntime {
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            injectorRuntime: { [weak browserManager] in
                guard let browserManager else { return .inactive }
                return .live(browserManager: browserManager)
            },
            openTab: { [weak browserManager] url, background in
                guard let browserManager else { return }
                let tab = browserManager.tabManager.createNewTab(
                    url: url,
                    in: browserManager.tabManager.currentSpace
                )
                if background == false {
                    tab.activate()
                }
            },
            closeTab: { [weak browserManager] tabId in
                guard let browserManager else { return }
                if let tabId, let uuid = UUID(uuidString: tabId) {
                    browserManager.tabManager.removeTab(uuid)
                } else if let active = browserManager.tabManager.currentTab {
                    browserManager.tabManager.removeTab(active.id)
                }
            }
        )
    }
}

extension UserScriptInjectorRuntime {
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            downloadManager: { [weak browserManager] in
                browserManager?.downloadManager
            },
            notificationPermissionBridge: { [weak browserManager] in
                browserManager?.notificationPermissionBridge
            },
            notificationTabContext: { [weak browserManager] webViewId, webView in
                browserManager?.tabManager.tab(for: webViewId)?
                    .webNotificationTabContext(for: webView)
            }
        )
    }
}
