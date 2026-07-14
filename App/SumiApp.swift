//
//  SumiApp.swift
//  Sumi
//
//

import AppKit
import Carbon
import OSLog
import SumiDomain
import SumiWebRuntime
import SwiftUI
import WebKit

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

private enum SumiImportRecoveryState {
    case pending
    case ready
    case failed(message: String, backupURL: URL?)
}

@main
struct SumiApp: App {
    private static let importRecoveryLog = Logger.sumi(category: "ImportRecovery")

    @State private var windowRegistry = WindowRegistry()
    @State private var settingsManager: SumiSettingsService
    @State private var keyboardShortcutManager = KeyboardShortcutManager()
    @State private var appOrchestrationOwner = BrowserAppOrchestrationOwner()
    @State private var importRecoveryState = SumiImportRecoveryState.pending
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
        let permissionPersistenceAuthority = SumiPermissionPersistenceAuthority(
            userDefaults: .standard,
            storageDirectory: SumiApplicationSupportDirectory.appRootURL()
                .appendingPathComponent("Permissions", isDirectory: true)
        )
        let permissionSiteActivityStore = SumiPermissionSiteActivityStore(
            persistenceAuthority: permissionPersistenceAuthority
        )
        let faviconSystem = SumiFaviconSystem(
            rootDirectory: SumiApplicationSupportDirectory.appRootURL()
                .appendingPathComponent("Favicons/v2", isDirectory: true),
            fetcher: SumiFaviconNetworkClient()
        )
        let browserManager = BrowserManager(
            webViewSessions: webViewSessions,
            moduleRegistry: moduleRegistry,
            startupPersistence: SumiStartupPersistenceComposition.browserManagerStartupPersistence,
            browserConfiguration: BrowserConfiguration.shared,
            dataServices: BrowserManagerDataServices.production(
                faviconSystem: faviconSystem
            ),
            nowPlayingController: nowPlayingController,
            permissionSiteActivityStore: permissionSiteActivityStore,
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
            Group {
                switch importRecoveryState {
                case .pending:
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Recovering browser data…")
                    }
                    .frame(minWidth: 520, minHeight: 240)
                case .ready:
                    rootContentView(
                        windowState: nil,
                        initialWorkspaceTheme: browserManager.startupWorkspaceTheme
                    )
                    .onAppear {
                        setupApplicationLifecycle()
                    }
                case .failed(let message, let backupURL):
                    VStack(spacing: 12) {
                        Text("Sumi could not recover an interrupted import.")
                            .font(.headline)
                        Text(message)
                            .multilineTextAlignment(.center)
                        if let backupURL {
                            Text("Pre-restore backup: \(backupURL.path)")
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(32)
                    .frame(minWidth: 520, minHeight: 240)
                }
            }
            .task {
                await recoverInterruptedImportIfNeeded()
            }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            if case .ready = importRecoveryState {
                SumiCommands(
                    browserContext: makeCommandsBrowserContext(),
                    windowRegistry: windowRegistry,
                    shortcutManager: keyboardShortcutManager,
                    updaterService: updaterService,
                    menuFaviconInvalidator: menuFaviconInvalidator
                )
            }
        }
    }

    // MARK: - Application Lifecycle Setup

    private func recoverInterruptedImportIfNeeded() async {
        guard case .pending = importRecoveryState else { return }
        let transaction = SumiImportTransaction(
            materializer: SumiImportRuntimeMaterializer(
                tabFactory: browserManager.tabManager.tabFactory,
                tabBrowserRuntime: TabBrowserRuntimeFactory.make(for: browserManager)
            ),
            runtime: SumiImportRuntimeStore(
                profileManager: browserManager.profileManager,
                tabManager: browserManager.tabManager,
                profileSelection: browserManager
            ),
            bookmarks: SumiImportBookmarkStore(
                bookmarkManager: browserManager.bookmarkManager
            ),
            backupWriter: SumiBackupService()
        )
        do {
            let report = try await transaction.recoverIfNeeded()
            importRecoveryState = .ready
            guard let report else { return }
            let backupPath = report.preRestoreBackupURL?.path ?? "none"
            Self.importRecoveryLog.notice(
                "Recovered an interrupted import; preRestoreBackup=\(backupPath, privacy: .public)"
            )
        } catch {
            let backupURL = (error as? SumiImportTransactionError)?.preRestoreBackupURL
            importRecoveryState = .failed(
                message: error.localizedDescription,
                backupURL: backupURL
            )
            let backupPath = backupURL?.path ?? "none"
            Self.importRecoveryLog.error(
                "Interrupted import recovery failed: \(error.localizedDescription, privacy: .public); preRestoreBackup=\(backupPath, privacy: .public)"
            )
        }
    }

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
            webContentContext: .make(
                browserManager: dependencies.browserManager,
                updaterService: dependencies.updaterService,
                defaultBrowserService: dependencies.defaultBrowserService
            ),
            sidebarContext: .make(
                browserManager: dependencies.browserManager,
                updaterService: dependencies.updaterService
            ),
            floatingBarContext: dependencies.browserManager.urlBarBundle
                .floatingBar.browserContext.context,
            nativeModalContext: .make(browserManager: dependencies.browserManager),
            findContext: .make(browserManager: dependencies.browserManager),
            splitContext: .make(browserManager: dependencies.browserManager),
            themeChromeContext: .make(browserManager: dependencies.browserManager),
            windowState: windowState,
            initialWorkspaceTheme: initialWorkspaceTheme
        )
            .ignoresSafeArea(.all)
            .writingToolsBehavior(.disabled)
            .environmentObject(dependencies.browserManager.glanceManager)
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
