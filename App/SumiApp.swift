//
//  SumiApp.swift
//  Sumi
//
//  Created by Maciek Bagiński on 28/07/2025.
//  Updated by Aether Aurelia on 15/11/2025.
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
    @State private var settingsManager = SumiSettingsService()
    @State private var keyboardShortcutManager = KeyboardShortcutManager()
    @State private var didSetupApplicationLifecycle = false
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // NOTE: `BrowserManager` remains the central app coordinator; incremental refactors move
    // capabilities behind protocols and `@Environment` (see `WebViewCoordinator`, `WindowRegistry`).
    @StateObject private var browserManager = BrowserManager()

    var body: some Scene {
        WindowGroup {
            ContentView(initialWorkspaceTheme: browserManager.startupWorkspaceTheme)
                .ignoresSafeArea(.all)
                .writingToolsBehavior(.disabled)
                .environmentObject(browserManager)
                .environmentObject(browserManager.glanceManager)
                .environmentObject(browserManager.extensionSurfaceStore)
                .environment(windowRegistry)
                .environment(webViewCoordinator)
                .environment(\.sumiSettings, settingsManager)
                .environment(\.sumiModuleRegistry, browserManager.moduleRegistry)
                .environment(\.sumiTrackingProtectionModule, browserManager.trackingProtectionModule)
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
                browserManager: browserManager,
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
        guard !didSetupApplicationLifecycle else { return }
        didSetupApplicationLifecycle = true

        // Connect AppDelegate for termination and menu routing
        appDelegate.windowRegistry = windowRegistry
        appDelegate.commandRouter = browserManager
        appDelegate.windowRouter = browserManager
        appDelegate.webViewLookup = browserManager
        appDelegate.externalURLHandler = browserManager
        appDelegate.persistenceHandler = browserManager
        appDelegate.updateHandler = browserManager
        appDelegate.settingsHandler = settingsManager
        appDelegate.shortcutManager = keyboardShortcutManager
        appDelegate.refreshHistoryMenu()

        // Required: routing and cleanup call `requireWebViewCoordinator()` after this point.
        browserManager.webViewCoordinator = webViewCoordinator
        browserManager.windowRegistry = windowRegistry
        browserManager.sumiSettings = settingsManager

        // `MediaControlsView` also configures this, but tab selection / activation can refresh the
        // shared controller before the sidebar appears; without an early configure, `refreshImmediately`
        // clears state because `browserManager` was still nil on the controller.
        SumiNativeNowPlayingController.shared.configure(browserManager: browserManager)
        browserManager.tabManager.sumiSettings = settingsManager

        // Initialize keyboard shortcut manager
        keyboardShortcutManager.setBrowserManager(browserManager)

#if DEBUG
        presentUITestMiniWindowIfRequested()
#endif

        // Set up window lifecycle callbacks
        windowRegistry.onWindowRegister = { [weak browserManager] windowState in
            if let browserManager {
                browserManager.setupWindowState(windowState)
            }
        }

        for windowState in windowRegistry.allWindows {
            browserManager.setupWindowState(windowState)
        }

        windowRegistry.onWindowClose = {
            [webViewCoordinator, weak browserManager] windowId in
            // Only cleanup if browserManager still exists (it's captured weakly)
            if let browserManager = browserManager {
                browserManager.handleWindowWillClose(windowId)
                browserManager.extensionsModule.notifyWindowClosedIfLoaded(windowId)
                webViewCoordinator.cleanupWindow(
                    windowId,
                    tabManager: browserManager.tabManager
                )
                browserManager.splitManager.cleanupWindow(windowId)

                // Clean up incognito window if applicable
                if let windowState = browserManager.windowRegistry?.windows[windowId],
                   windowState.isIncognito {
                    Task {
                        await browserManager.closeIncognitoWindow(windowState)
                    }
                }
            } else {
                // BrowserManager was deallocated - perform minimal cleanup
                // Remove compositor container view to prevent leaks
                webViewCoordinator.removeCompositorContainerView(for: windowId)
                RuntimeDiagnostics.emit(
                    "⚠️ [SumiApp] Window \(windowId) closed after BrowserManager deallocation - performed minimal cleanup"
                )
            }
        }

        windowRegistry.onActiveWindowChange = {
            [weak browserManager] windowState in
            browserManager?.setActiveWindowState(windowState)
        }

        windowRegistry.onAllWindowsClosed = { [weak browserManager] in
            browserManager?.windowSessionService.prepareForAllWindowsClosed()
            Task { @MainActor [weak browserManager] in
                await browserManager?.performSiteDataPolicyAllWindowsClosedCleanup()
            }
        }

        Task { @MainActor [browserManager] in
            await browserManager.runAutomaticPermissionCleanupIfNeeded(
                for: browserManager.currentProfile
            )
        }
    }

#if DEBUG
    private func presentUITestMiniWindowIfRequested() {
        let processInfo = ProcessInfo.processInfo
        guard processInfo.arguments.contains("--uitest-smoke"),
              let urlString = processInfo.environment["SUMI_UITEST_MINI_WINDOW_URL"],
              let url = URL(string: urlString)
        else { return }

        let manager = browserManager
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            manager.externalMiniWindowManager.present(url: url)
        }
    }
#endif
}
