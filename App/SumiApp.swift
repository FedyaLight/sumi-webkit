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

@main
struct SumiApp: App {
    @State private var windowRegistry = WindowRegistry()
    @State private var webViewCoordinator = WebViewCoordinator()
    @State private var settingsManager: SumiSettingsService
    @State private var keyboardShortcutManager = KeyboardShortcutManager()
    @State private var appOrchestrationOwner = BrowserAppOrchestrationOwner()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // NOTE: `BrowserManager` remains the central app coordinator; incremental refactors move
    // capabilities behind protocols and `@Environment` (see `WebViewCoordinator`, `WindowRegistry`).
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
            ContentView(
                windowLifecycleHandler: browserManager,
                browserContext: .live(browserManager: browserManager),
                initialWorkspaceTheme: browserManager.startupWorkspaceTheme
            )
                .ignoresSafeArea(.all)
                .writingToolsBehavior(.disabled)
                .environmentObject(browserManager.glanceManager)
                .environmentObject(browserManager.extensionSurfaceStore)
                .environmentObject(nowPlayingController)
                .environment(windowRegistry)
                .environment(webViewCoordinator)
                .environment(\.sumiSettings, settingsManager)
                .environment(\.sumiModuleRegistry, browserManager.moduleRegistry)
                .environment(\.sumiExtensionsModule, browserManager.extensionsModule)
                .environment(\.sumiUserscriptsModule, browserManager.userscriptsModule)
                .environment(keyboardShortcutManager)
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
    /// This function sets up the following connections:
    /// - AppDelegate ↔ BrowserManager: For app termination cleanup and menu routing
    /// - WindowRegistry callbacks: Register, close, and activate window state
    /// - Keyboard shortcut manager: Enable global keyboard shortcuts
    ///
    /// Cross-cutting wiring (documented technical debt, not alternate product paths):
    /// - `BrowserManager` holds the shared `WebViewCoordinator` and `WindowRegistry` until DI is wider.
    /// Follow-up: narrow `BrowserManager` by moving window/session setup into dedicated services.
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
                browserManager: browserManager,
                settingsManager: settingsManager,
                keyboardShortcutManager: keyboardShortcutManager,
                nowPlayingController: nowPlayingController,
                windowRegistry: windowRegistry,
                webViewCoordinator: webViewCoordinator,
                windowState: windowState
            )
        }
    }

    private func makeCommandsBrowserContext() -> SumiCommandsBrowserContext {
        SumiCommandsBrowserContext(
            runtime: .live(browserManager: browserManager)
        )
    }

    private static func makeWindowShellContentView(
        browserManager: BrowserManager,
        settingsManager: SumiSettingsService,
        keyboardShortcutManager: KeyboardShortcutManager,
        nowPlayingController: SumiNativeNowPlayingController,
        windowRegistry: WindowRegistry,
        webViewCoordinator: WebViewCoordinator,
        windowState: BrowserWindowState?
    ) -> NSView {
        let contentView = ContentView(
            windowLifecycleHandler: browserManager,
            browserContext: .live(browserManager: browserManager),
            windowState: windowState,
            initialWorkspaceTheme: browserManager.tabManager.currentSpace?.workspaceTheme
        )
            .ignoresSafeArea(.all)
            .environmentObject(browserManager.glanceManager)
            .environmentObject(browserManager.extensionSurfaceStore)
            .environmentObject(nowPlayingController)
            .environment(windowRegistry)
            .environment(webViewCoordinator)
            .environment(\.sumiSettings, settingsManager)
            .environment(\.sumiModuleRegistry, browserManager.moduleRegistry)
            .environment(\.sumiProtectionCoordinator, browserManager.protectionCoordinator)
            .environment(\.sumiExtensionsModule, browserManager.extensionsModule)
            .environment(\.sumiUserscriptsModule, browserManager.userscriptsModule)
            .environment(keyboardShortcutManager)

        return NSHostingView(rootView: contentView)
    }
}
