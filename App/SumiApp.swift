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

@main
struct SumiApp: App {
    private static let startupRecoveryLog = Logger.sumi(category: "StartupRecovery")

    @State private var windowRegistry: WindowRegistry
    @State private var settingsManager: SumiSettingsService
    @State private var keyboardShortcutManager: KeyboardShortcutManager
    @State private var appOrchestrationOwner = BrowserAppOrchestrationOwner()
    @State private var startupRecovery = SumiStartupRecoveryTransaction()
    @State private var pendingProfileRetirementNotice:
        ProfileRetirementStartupRecoveryReport?
    @State private var isPresentingProfileRetirementNotice = false
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
        let windowRegistry = WindowRegistry()
        let moduleRegistry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: .standard)
        )
        let permissionPersistenceAuthority = SumiPermissionPersistenceAuthority(
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
            windowRegistry: windowRegistry,
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
        let keyboardShortcutManager = KeyboardShortcutManager()
        keyboardShortcutManager.attach(
            actionRouter: browserManager.shortcutActionRouter,
            targetResolver: browserManager.shortcutTargetResolver,
            extensionsModule: browserManager.optionalModules.extensions
        )
        self.updaterService = updaterService
        self.defaultBrowserService = defaultBrowserService
        self.windowLifecycleService = BrowserWindowLifecycleService(
            persistence: browserManager.windowSessionPersistenceCoordinator
        )
        _windowRegistry = State(initialValue: windowRegistry)
        _nowPlayingController = StateObject(wrappedValue: nowPlayingController)
        _settingsManager = State(initialValue: SumiSettingsService(nowPlayingController: nowPlayingController))
        _keyboardShortcutManager = State(
            initialValue: keyboardShortcutManager
        )
        _browserManager = StateObject(wrappedValue: browserManager)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch startupRecovery.state {
                case .pending, .recovering:
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Recovering browser data…")
                    }
                    .frame(minWidth: 520, minHeight: 240)
                case .ready:
                    rootContentView(
                        windowState: nil,
                        initialWorkspaceTheme: browserManager.spaceStateOwner
                            .currentSpace?.workspaceTheme
                    )
                    .onAppear {
                        setupApplicationLifecycle()
                        presentPendingProfileRetirementNoticeIfPossible()
                    }
                case .failed(let message, let backupURL):
                    VStack(spacing: 12) {
                        Text("Sumi could not complete startup recovery.")
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
                await recoverStartupDataIfNeeded()
            }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            if case .ready = startupRecovery.state {
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

    private func recoverStartupDataIfNeeded() async {
        let outcome = await startupRecovery.recoverIfNeeded(
            preflight: browserManager.profileRetirementStartupPreflight,
            recoverProfileRetirement: {
                try await browserManager.profileLifecycleBundle
                    .retirementStartupRecovery.recover()
            },
            recoverImport: {
                let transaction = SumiImportTransaction(
                    materializer: SumiImportRuntimeMaterializer(
                        tabFactory: browserManager.tabFactory,
                        tabBrowserRuntime: TabBrowserRuntimeFactory.make(
                            for: browserManager
                        )
                    ),
                    runtime: SumiImportRuntimeStore(
                        profileManager: browserManager.profileManager,
                        profileSelection: browserManager,
                        profileReferenceAdmission: browserManager
                            .profileReferenceAdmission,
                        state: browserManager.tabStateStore,
                        structuralInstaller: browserManager
                            .structuralInstallOwner,
                        persistence: browserManager
                            .structuralPersistence
                    ),
                    bookmarks: SumiImportBookmarkStore(
                        bookmarkManager: browserManager.bookmarkManager
                    ),
                    backupWriter: SumiBackupService(),
                    profileRetirement: browserManager.profileLifecycleBundle
                        .importRetirement
                )
                let recovery = try await transaction.recoverIfNeeded()
                // Bulk payloads staged for an import that never finished are
                // dead weight; nothing outlives the transaction that referenced
                // them, so anything still on disk here is an orphan.
                SumiImportBulkStagingStore().sweepOrphans()
                return recovery
            },
            hasSafeProfile: {
                browserManager.profileManager.profiles.isEmpty == false
            },
            startRuntime: {
                browserManager.startRuntimeAfterStartupRecovery()
            }
        )

        switch outcome {
        case .notClaimed:
            return
        case .recovered(let importReport, let profileRetirement):
            if profileRetirement.hasDeferredRecovery {
                pendingProfileRetirementNotice = profileRetirement
                for issue in profileRetirement.issues {
                    Self.startupRecoveryLog.error(
                        "Deferred profile retirement; profile=\(issue.profileID.uuidString, privacy: .public); phase=\(issue.phase, privacy: .public); kind=\(issue.kind.rawValue, privacy: .public); reason=\(issue.reason, privacy: .public)"
                    )
                }
                presentPendingProfileRetirementNoticeIfPossible()
            }
            if let importReport {
                let backupPath = importReport.preRestoreBackupURL?.path ?? "none"
                Self.startupRecoveryLog.notice(
                    "Recovered an interrupted import; preRestoreBackup=\(backupPath, privacy: .public)"
                )
            }
        case .failed(let failure):
            let backupPath = failure.backupURL?.path ?? "none"
            Self.startupRecoveryLog.error(
                "Startup recovery failed: \(failure.message, privacy: .public); preRestoreBackup=\(backupPath, privacy: .public)"
            )
        }
    }

    private func presentPendingProfileRetirementNoticeIfPossible() {
        guard pendingProfileRetirementNotice?.hasDeferredRecovery == true,
              isPresentingProfileRetirementNotice == false else {
            return
        }
        isPresentingProfileRetirementNotice = true
        Task { @MainActor in
            defer { isPresentingProfileRetirementNotice = false }
            await Task.yield()
            let presented = browserManager.chromeBundle
                .nativeDialogPresentationOwner.presentNoticeSheet(
                    BrowserNoticeSheetModel(
                        title: "Profile Recovery Is Still Pending",
                        subtitle: "Sumi is ready to use",
                        message: "A profile involved in an interrupted deletion was isolated. Its browser references were reassigned where possible, and private-data cleanup will be retried the next time Sumi starts."
                    )
                )
            if presented {
                pendingProfileRetirementNotice = nil
            }
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
            initialWorkspaceTheme: dependencies.browserManager.spaceStateOwner.currentSpace?.workspaceTheme
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
                updaterService: dependencies.updaterService,
                nowPlayingController: dependencies.nowPlayingController
            ),
            commandPaletteContext: dependencies.browserManager.urlBarBundle
                .commandPaletteBrowserContext.context,
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
