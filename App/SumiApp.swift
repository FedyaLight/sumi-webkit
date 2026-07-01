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

private struct SumiAppRootDependencies {
    let browserManager: BrowserManager
    let settingsManager: SumiSettingsService
    let keyboardShortcutManager: KeyboardShortcutManager
    let nowPlayingController: SumiNativeNowPlayingController
    let windowRegistry: WindowRegistry
    let webViewCoordinator: WebViewCoordinator
}

@main
struct SumiApp: App {
    @State private var windowRegistry = WindowRegistry()
    @State private var webViewCoordinator = WebViewCoordinator()
    @State private var settingsManager: SumiSettingsService
    @State private var keyboardShortcutManager = KeyboardShortcutManager()
    @State private var appOrchestrationOwner = BrowserAppOrchestrationOwner()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // Root runtime facade retained for SwiftUI observation. App lifecycle and platform callbacks
    // are routed through dedicated controllers and narrow protocols before reaching browser services.
    @StateObject private var browserManager: BrowserManager
    @StateObject private var nowPlayingController: SumiNativeNowPlayingController

    init() {
        StartupPerformanceTrace.appLaunchStarted()
        let nowPlayingController = SumiNativeNowPlayingController.shared
        _nowPlayingController = StateObject(wrappedValue: nowPlayingController)
        _settingsManager = State(initialValue: SumiSettingsService(nowPlayingController: nowPlayingController))
        _browserManager = StateObject(
            wrappedValue: BrowserManager(
                startupPersistence: SumiStartupPersistenceComposition.browserManagerStartupPersistence,
                browserConfiguration: BrowserConfiguration.shared,
                nowPlayingController: nowPlayingController
            )
        )
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
                shortcutManager: keyboardShortcutManager
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
                webViewCoordinator: webViewCoordinator,
                settingsManager: settingsManager,
                keyboardShortcutManager: keyboardShortcutManager,
                nowPlayingController: nowPlayingController,
                windowShellContentViewFactory: makeWindowShellContentViewFactory(),
                fallbackPersistenceSave: SumiStartupPersistenceComposition.saveMainContext,
                startUpdater: {
                    SumiUpdaterService.shared.start()
                }
            )
        )
    }

    private func makeWindowShellContentViewFactory() -> BrowserWindowShellService.ContentViewFactory {
        let browserManager = browserManager
        let settingsManager = settingsManager
        let keyboardShortcutManager = keyboardShortcutManager
        let nowPlayingController = nowPlayingController

        return { windowRegistry, webViewCoordinator, windowState in
            Self.makeWindowShellContentView(
                dependencies: SumiAppRootDependencies(
                    browserManager: browserManager,
                    settingsManager: settingsManager,
                    keyboardShortcutManager: keyboardShortcutManager,
                    nowPlayingController: nowPlayingController,
                    windowRegistry: windowRegistry,
                    webViewCoordinator: webViewCoordinator
                ),
                windowState: windowState
            )
        }
    }

    private func makeCommandsBrowserContext() -> SumiCommandsBrowserContext {
        SumiCommandsBrowserContext(
            runtime: .live(browserManager: browserManager)
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
                windowRegistry: windowRegistry,
                webViewCoordinator: webViewCoordinator
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
            initialWorkspaceTheme: dependencies.browserManager.tabManager.currentSpace?.workspaceTheme
        )

        return NSHostingView(rootView: contentView)
    }

    private static func makeRootContentView(
        dependencies: SumiAppRootDependencies,
        windowState: BrowserWindowState?,
        initialWorkspaceTheme: WorkspaceTheme?
    ) -> some View {
        ContentView(
            windowLifecycleHandler: dependencies.browserManager.appCommandRouter,
            browserContext: .live(browserManager: dependencies.browserManager),
            windowState: windowState,
            initialWorkspaceTheme: initialWorkspaceTheme
        )
            .ignoresSafeArea(.all)
            .writingToolsBehavior(.disabled)
            .environmentObject(dependencies.browserManager.glanceManager)
            .environmentObject(dependencies.browserManager.extensionsModule.surfaceStore)
            .environmentObject(dependencies.nowPlayingController)
            .environment(dependencies.windowRegistry)
            .environment(dependencies.webViewCoordinator)
            .environment(\.sumiSettings, dependencies.settingsManager)
            .environment(\.sumiModuleRegistry, dependencies.browserManager.moduleRegistry)
            .environment(\.sumiProtectionCoordinator, dependencies.browserManager.protectionCoordinator)
            .environment(\.sumiExtensionsModule, dependencies.browserManager.extensionsModule)
            .environment(\.sumiUserscriptsModule, dependencies.browserManager.userscriptsModule)
            .environment(dependencies.keyboardShortcutManager)
    }
}
