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
import Sparkle
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
                .environmentObject(browserManager.peekManager)
                .environmentObject(browserManager.extensionSurfaceStore)
                .environment(windowRegistry)
                .environment(webViewCoordinator)
                .environment(\.sumiSettings, settingsManager)
                .environment(keyboardShortcutManager)
                .onAppear {
                    setupApplicationLifecycle()
                }
        }
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
    /// - AppDelegate ↔ BrowserManager: For app termination cleanup and Sparkle update integration
    /// - WindowRegistry callbacks: Register, close, and activate window state
    /// - Keyboard shortcut manager: Enable global keyboard shortcuts
    ///
    /// Cross-cutting wiring (documented technical debt, not alternate product paths):
    /// - `BrowserManager` holds the shared `WebViewCoordinator` and `WindowRegistry` until DI is wider.
    /// Follow-up: narrow `BrowserManager` by moving window/session setup into dedicated services.
    private func setupApplicationLifecycle() {
        guard !didSetupApplicationLifecycle else { return }
        didSetupApplicationLifecycle = true

        // Connect AppDelegate for termination and updates
        appDelegate.windowRegistry = windowRegistry
        appDelegate.commandRouter = browserManager
        appDelegate.windowRouter = browserManager
        appDelegate.webViewLookup = browserManager
        appDelegate.externalURLHandler = browserManager
        appDelegate.persistenceHandler = browserManager
        appDelegate.updateHandler = browserManager
        browserManager.appDelegate = appDelegate

        // Required: routing and cleanup call `requireWebViewCoordinator()` after this point.
        browserManager.webViewCoordinator = webViewCoordinator
        browserManager.windowRegistry = windowRegistry
        browserManager.sumiSettings = settingsManager
        browserManager.tabManager.sumiSettings = settingsManager
        SumiNativeNowPlayingController.shared.configure(
            browserManager: browserManager
        )

        // Configure managers that depend on settings
        browserManager.compositorManager.setUnloadTimeout(
            settingsManager.tabUnloadTimeout
        )

        // Initialize keyboard shortcut manager
        keyboardShortcutManager.setBrowserManager(browserManager)

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
                browserManager.extensionManager.notifyWindowClosed(windowId)
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
        }
    }
}
