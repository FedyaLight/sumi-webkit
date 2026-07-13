//
//  SumiApp.swift
//  Sumi
//
//

import AppKit
import Carbon
import OSLog
import SwiftUI
import WebKit
import SumiDomain
import SumiWebRuntime

private struct SumiAppRootDependencies {
    let browserManager: BrowserManager
    let settingsManager: SumiSettingsService
    let keyboardShortcutManager: KeyboardShortcutManager
    let nowPlayingController: SumiNativeNowPlayingController
    let updaterService: SumiUpdaterService
    let defaultBrowserService: SumiDefaultBrowserService
    let windowRegistry: WindowRegistry
    let sidebarMouseButtonCaptureRegistry: SidebarMouseButtonCaptureRegistry
    let windowLifecycleService: BrowserWindowLifecycleService
}

@main
struct SumiApp: App {
    @State private var windowRegistry = WindowRegistry()
    @State private var settingsManager: SumiSettingsService
    @State private var keyboardShortcutManager = KeyboardShortcutManager()
    @State private var appOrchestrationOwner = BrowserAppOrchestrationOwner()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // Root runtime facade retained for SwiftUI observation. App lifecycle and platform callbacks
    // are routed through dedicated controllers and narrow protocols before reaching browser services.
    @StateObject private var browserManager: BrowserManager
    @StateObject private var nowPlayingController: SumiNativeNowPlayingController
    @StateObject private var menuFaviconInvalidator = SumiMenuFaviconInvalidator()
    private let updaterService: SumiUpdaterService
    private let defaultBrowserService: SumiDefaultBrowserService
    private let windowLifecycleService: BrowserWindowLifecycleService

    init() {
        StartupPerformanceTrace.appLaunchStarted()
        let nowPlayingController = SumiNativeNowPlayingController()
        let updaterService = SumiUpdaterService()
        let defaultBrowserService = SumiDefaultBrowserService()
        let webViewSessions = WebViewSessionRepository()
        let moduleRegistry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: .standard)
        )
        let browserManager = BrowserManager(
            webViewSessions: webViewSessions,
            moduleRegistry: moduleRegistry,
            startupPersistence: SumiStartupPersistenceComposition.browserManagerStartupPersistence,
            browserConfiguration: BrowserConfiguration.shared,
            nowPlayingController: nowPlayingController,
            permissionSiteActivityStore: SumiPermissionSiteActivityStore(),
            externalAppResolver: SumiNSWorkspaceExternalAppResolver(),
            sidebarHostRecoveryCoordinator: SidebarHostRecoveryCoordinator()
        )
        self.updaterService = updaterService
        self.defaultBrowserService = defaultBrowserService
        self.windowLifecycleService = BrowserWindowLifecycleService(
            tabManager: browserManager.tabManager,
            persist: { [weak browserManager] windowState in
                browserManager?.windowSessionBundle.persistence.persist(windowState)
            }
        )
        _nowPlayingController = StateObject(wrappedValue: nowPlayingController)
        _settingsManager = State(initialValue: SumiSettingsService(nowPlayingController: nowPlayingController))
        _browserManager = StateObject(wrappedValue: browserManager)
    }

    var body: some Scene {
        WindowGroup {
            rootContentView(
                windowState: nil,
                initialWorkspaceTheme: browserManager.startupWorkspaceTheme
            )
                .onAppear {
                    setupApplicationLifecycle()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            SumiCommands(
                browserContext: makeCommandsBrowserContext(),
                windowRegistry: windowRegistry,
                shortcutManager: keyboardShortcutManager,
                updaterService: updaterService,
                menuFaviconInvalidator: menuFaviconInvalidator
            )
        }
    }

    // MARK: - Application Lifecycle Setup

    /// Configures application-level dependencies and callbacks when the first window appears.
    ///
    /// This function wires AppKit callbacks, window registry callbacks, shared WebKit services,
    /// settings, and keyboard shortcuts into their browser runtime services.
    private func setupApplicationLifecycle() {
        appOrchestrationOwner.setupIfNeeded(
            dependencies: BrowserAppOrchestrationOwner.Dependencies(
                appDelegate: appDelegate,
                browserManager: browserManager,
                windowRegistry: windowRegistry,
                webViewLifecycle: browserManager.webViewRuntime.lifecycleService,
                settingsManager: settingsManager,
                keyboardShortcutManager: keyboardShortcutManager,
                nowPlayingController: nowPlayingController,
                windowShellContentViewFactory: makeWindowShellContentViewFactory(),
                fallbackPersistenceSave: SumiStartupPersistenceComposition.saveMainContext,
                startUpdater: { updaterService.start() }
            )
        )
    }

    private func makeWindowShellContentViewFactory() -> BrowserWindowShellService.ContentViewFactory {
        let settingsManager = settingsManager
        let keyboardShortcutManager = keyboardShortcutManager
        let nowPlayingController = nowPlayingController
        let updaterService = updaterService
        let defaultBrowserService = defaultBrowserService
        let sidebarMouseButtonCaptureRegistry = appDelegate.sidebarMouseButtonCaptureRegistry
        let windowLifecycleService = windowLifecycleService

        return { [weak browserManager] windowRegistry, windowState in
            guard let browserManager else {
                RuntimeDiagnostics.emit(
                    "⚠️ [SumiApp] Ignored late window-content request after browser runtime deallocation"
                )
                return NSView()
            }
            return Self.makeWindowShellContentView(
                dependencies: SumiAppRootDependencies(
                    browserManager: browserManager,
                    settingsManager: settingsManager,
                    keyboardShortcutManager: keyboardShortcutManager,
                    nowPlayingController: nowPlayingController,
                    updaterService: updaterService,
                    defaultBrowserService: defaultBrowserService,
                    windowRegistry: windowRegistry,
                    sidebarMouseButtonCaptureRegistry: sidebarMouseButtonCaptureRegistry,
                    windowLifecycleService: windowLifecycleService
                ),
                windowState: windowState
            )
        }
    }

    private func makeCommandsBrowserContext() -> SumiCommandsBrowserContext {
        SumiCommandsBrowserContext(
            runtime: .live(
                browserManager: browserManager,
                defaultBrowserService: defaultBrowserService
            )
        )
    }

    private func rootContentView(
        windowState: BrowserWindowState?,
        initialWorkspaceTheme: WorkspaceTheme?
    ) -> some View {
        Self.makeRootContentView(
            dependencies: SumiAppRootDependencies(
                browserManager: browserManager,
                settingsManager: settingsManager,
                keyboardShortcutManager: keyboardShortcutManager,
                nowPlayingController: nowPlayingController,
                updaterService: updaterService,
                defaultBrowserService: defaultBrowserService,
                windowRegistry: windowRegistry,
                sidebarMouseButtonCaptureRegistry: appDelegate.sidebarMouseButtonCaptureRegistry,
                windowLifecycleService: windowLifecycleService
            ),
            windowState: windowState,
            initialWorkspaceTheme: initialWorkspaceTheme
        )
    }

    private static func makeWindowShellContentView(
        dependencies: SumiAppRootDependencies,
        windowState: BrowserWindowState
    ) -> NSView {
        let contentView = makeRootContentView(
            dependencies: dependencies,
            windowState: windowState,
            initialWorkspaceTheme: dependencies.browserManager.tabManager.spaceStateOwner.currentSpace?.workspaceTheme
        )

        return NSHostingView(rootView: contentView)
    }

    private static func makeRootContentView(
        dependencies: SumiAppRootDependencies,
        windowState: BrowserWindowState?,
        initialWorkspaceTheme: WorkspaceTheme?
    ) -> some View {
        ContentView(
            windowLifecycleHandler: dependencies.windowLifecycleService,
            browserContext: .make(
                browserManager: dependencies.browserManager,
                updaterService: dependencies.updaterService,
                defaultBrowserService: dependencies.defaultBrowserService
            ),
            updaterService: dependencies.updaterService,
            windowState: windowState,
            initialWorkspaceTheme: initialWorkspaceTheme
        )
            .ignoresSafeArea(.all)
            .writingToolsBehavior(.disabled)
            .environmentObject(dependencies.browserManager.glanceManager)
            .environmentObject(dependencies.browserManager.optionalModules.extensions.surfaceStore)
            .environmentObject(dependencies.nowPlayingController)
            .environment(dependencies.windowRegistry)
            .environment(\.sumiSettings, dependencies.settingsManager)
            .environment(\.sumiModuleRegistry, dependencies.browserManager.moduleRegistry)
            .environment(\.sumiProtectionCoordinator, dependencies.browserManager.protectionCoordinator)
            .environment(\.sumiExtensionsModule, dependencies.browserManager.optionalModules.extensions)
            .environment(\.sumiBoostsModule, dependencies.browserManager.optionalModules.boosts)
            .environment(\.sidebarMouseButtonCaptureRegistry, dependencies.sidebarMouseButtonCaptureRegistry)
            .environment(dependencies.keyboardShortcutManager)
    }
}
