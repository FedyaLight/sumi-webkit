//
//  SumiCommands.swift
//  Sumi
//
//  Menu bar commands for the Sumi browser application
//

import AppKit
import SwiftUI

struct SumiCommands: Commands {
    let browserManager: BrowserManager
    let windowRegistry: WindowRegistry
    let shortcutManager: KeyboardShortcutManager
    @Environment(\.sumiSettings) var sumiSettings

    init(browserManager: BrowserManager, windowRegistry: WindowRegistry, shortcutManager: KeyboardShortcutManager) {
        self.browserManager = browserManager
        self.windowRegistry = windowRegistry
        self.shortcutManager = shortcutManager
    }

    // MARK: - Dynamic Keyboard Shortcuts

    /// View extension to apply dynamic keyboard shortcut if enabled
    private func dynamicShortcut(_ action: ShortcutAction) -> some ViewModifier {
        let shortcut = shortcutManager.shortcut(for: action)
        let keyCombination = shortcut?.keyCombination
        return DynamicShortcutModifier(
            keyEquivalent: keyCombination.flatMap { KeyboardShortcutPresentation.keyEquivalent(for: $0) },
            modifiers: keyCombination.map { KeyboardShortcutPresentation.eventModifiers(for: $0.modifiers) } ?? []
        )
    }

    private func keyWindowIsManagedBrowserWindow() -> Bool {
        guard let keyWindow = NSApp.keyWindow else { return false }
        return windowRegistry.windows.values.contains(where: { $0.window === keyWindow })
    }

    private func closeKeyWindowOrCurrentTab() {
        if let keyWindow = NSApp.keyWindow, keyWindowIsManagedBrowserWindow() == false {
            keyWindow.performClose(nil)
            return
        }
        browserManager.closeCurrentTab()
    }

    private func closeKeyWindowOrSumiBrowserWindow() {
        if let keyWindow = NSApp.keyWindow, keyWindowIsManagedBrowserWindow() == false {
            keyWindow.performClose(nil)
            return
        }
        browserManager.closeActiveWindow()
    }

    @CommandsBuilder
    private var applicationCommands: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Sumi") {
                browserManager.openSettingsTab(selecting: .about)
            }
        }

        CommandGroup(after: .appInfo) {
            Divider()
            Button("Make Sumi Default Browser") {
                browserManager.setAsDefaultBrowser()
            }
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                browserManager.openSettingsTab(selecting: sumiSettings.currentSettingsTab)
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(replacing: .saveItem) {}
    }

    @CommandsBuilder
    private var secondaryCommandMenus: some Commands {
        SumiHistoryCommands(
            browserManager: browserManager,
            shortcutManager: shortcutManager
        )

        SumiBookmarksCommands(browserManager: browserManager)

        CommandMenu("Extensions") {
            Button("Install Extension...") {
                browserManager.showExtensionInstallDialog()
            }

            Button("Manage Extensions...") {
                browserManager.openSettingsTab(selecting: .extensions)
            }
        }

        CommandMenu("Privacy") {
            Button("Clear Cookies for Current Site") {
                browserManager.clearCurrentPageCookies()
            }
            .disabled(browserManager.currentTabForActiveWindow()?.url.host == nil)

            Button("Clear Browsing History") {
                browserManager.clearAllHistoryFromMenu()
            }
        }

        CommandMenu("Appearance") {
            Button("Customize Space Gradient...") {
                browserManager.showGradientEditor()
            }
            .modifier(dynamicShortcut(.customizeSpaceGradient))
            .disabled(browserManager.tabManager.currentSpace == nil)
        }
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .appTermination) {
            Button("Quit Sumi") {
                browserManager.showQuitDialog()
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
        CommandGroup(replacing: .windowList) {}
        CommandGroup(replacing: .windowArrangement) {
            Button("Minimize") {
                NSApp.keyWindow?.miniaturize(nil)
            }
            .keyboardShortcut("m", modifiers: [.command])

            Button("Zoom") {
                NSApp.keyWindow?.zoom(nil)
            }

            Divider()

            Button("Close Tab") {
                closeKeyWindowOrCurrentTab()
            }
            .keyboardShortcut("w", modifiers: [.command])

            Button("Close Window") {
                closeKeyWindowOrSumiBrowserWindow()
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])

            Divider()

            Button("Bring All to Front") {
                NSApp.arrangeInFront(nil)
            }
        }

        applicationCommands

        // Edit Section
        CommandGroup(replacing: .undoRedo) {
            Button("Undo Close Tab") {
                browserManager.undoCloseTab()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
        }

        // File Section
        CommandGroup(after: .newItem) {
            Button("New Tab") {
                browserManager.openNewTabSurfaceInActiveWindow()
            }
            .modifier(dynamicShortcut(.newTab))
            Button("New Window") {
                browserManager.createNewWindow()
            }
            .modifier(dynamicShortcut(.newWindow))
            
            Button("New Incognito Window") {
                browserManager.createIncognitoWindow()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            
            Divider()
            Button("Open Command Bar") {
                let currentURL = browserManager.currentTabForActiveWindow()?.url.absoluteString ?? ""
                browserManager.focusFloatingURLBarForActiveWindow(
                    prefill: currentURL,
                    navigateCurrentTab: true
                )
            }
            .modifier(dynamicShortcut(.focusAddressBar))
            .disabled(browserManager.currentTabForActiveWindow() == nil)

            Button("Copy Current URL") {
                browserManager.copyCurrentURL()
            }
            .modifier(dynamicShortcut(.copyCurrentURL))
            .disabled(browserManager.currentTabForActiveWindow() == nil)
        }

        // Sidebar commands
        CommandGroup(after: .sidebar) {
            Button("Toggle Sidebar") {
                browserManager.toggleSidebar()
            }
            .modifier(dynamicShortcut(.toggleSidebar))
        }

        // View commands
        CommandGroup(after: .windowSize) {

            Button("Find in Page") {
                browserManager.showFindBar()
            }
            .modifier(dynamicShortcut(.findInPage))
            .disabled(browserManager.currentTabForActiveWindow() == nil)

            Button("Reload Page") {
                browserManager.refreshCurrentTabInActiveWindow()
            }
            .modifier(dynamicShortcut(.refresh))
            .disabled(browserManager.currentTabForActiveWindow() == nil)

            Divider()

            Button("Zoom In") {
                browserManager.zoomInCurrentTab()
            }
            .modifier(dynamicShortcut(.zoomIn))
            .disabled(browserManager.currentTabForActiveWindow() == nil)

            Button("Zoom Out") {
                browserManager.zoomOutCurrentTab()
            }
            .modifier(dynamicShortcut(.zoomOut))
            .disabled(browserManager.currentTabForActiveWindow() == nil)

            Button("Actual Size") {
                browserManager.resetZoomCurrentTab()
            }
            .modifier(dynamicShortcut(.actualSize))
            .disabled(browserManager.currentTabForActiveWindow() == nil)

            Divider()

            Button("Hard Reload (Ignore Cache)") {
                browserManager.hardReloadCurrentPage()
            }
            .modifier(dynamicShortcut(.hardReload))
            .disabled(browserManager.currentTabForActiveWindow() == nil)

            Divider()

            Button("Web Inspector") {
                browserManager.openWebInspector()
            }
            .modifier(dynamicShortcut(.openDevTools))
            .disabled(browserManager.currentTabForActiveWindow() == nil)

            Divider()

            Button(browserManager.currentTabIsMuted() ? "Unmute Audio" : "Mute Audio") {
                browserManager.toggleMuteCurrentTabInActiveWindow()
            }
            .modifier(dynamicShortcut(.muteUnmuteAudio))
            .disabled(
                browserManager.currentTabForActiveWindow() == nil
                    || !browserManager.currentTabHasAudioContent())
        }

        secondaryCommandMenus
    }
}

// MARK: - Dynamic Shortcut Modifier

/// View modifier that conditionally applies a keyboard shortcut based on user preferences
struct DynamicShortcutModifier: ViewModifier {
    let keyEquivalent: KeyEquivalent?
    let modifiers: EventModifiers

    func body(content: Content) -> some View {
        if let keyEquivalent = keyEquivalent {
            content.keyboardShortcut(keyEquivalent, modifiers: modifiers)
        } else {
            content
        }
    }
}
