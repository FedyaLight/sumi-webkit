//
//  SumiCommands.swift
//  Sumi
//
//  Menu bar commands for the Sumi browser application
//

import AppKit
import SwiftUI

struct SumiCommands: Commands {
    let browserContext: SumiCommandsBrowserContext
    let windowRegistry: WindowRegistry
    let shortcutManager: KeyboardShortcutManager
    @ObservedObject private var recentlyClosedManager: RecentlyClosedManager
    @Environment(\.sumiSettings) var sumiSettings

    init(
        browserContext: SumiCommandsBrowserContext,
        windowRegistry: WindowRegistry,
        shortcutManager: KeyboardShortcutManager
    ) {
        self.browserContext = browserContext
        self.windowRegistry = windowRegistry
        self.shortcutManager = shortcutManager
        self.recentlyClosedManager = browserContext.recentlyClosedManager
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
        browserContext.closeCurrentTab()
    }

    private func closeKeyWindowOrSumiBrowserWindow() {
        if let keyWindow = NSApp.keyWindow, keyWindowIsManagedBrowserWindow() == false {
            keyWindow.performClose(nil)
            return
        }
        browserContext.closeActiveWindow()
    }

    @CommandsBuilder
    private var applicationCommands: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Sumi") {
                browserContext.openSettingsTab(selecting: .about)
            }
        }

        CommandGroup(after: .appInfo) {
            SumiCheckForUpdatesCommand(updaterService: SumiUpdaterService.shared)
            Divider()
            Button("Make Sumi Default Browser") {
                browserContext.setAsDefaultBrowser()
            }
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                browserContext.openSettingsTab(selecting: sumiSettings.currentSettingsTab)
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(replacing: .saveItem) {
            EmptyView()
        }
    }

    @CommandsBuilder
    private var secondaryCommandMenus: some Commands {
        SumiHistoryCommands(
            browserContext: browserContext,
            shortcutManager: shortcutManager
        )

        SumiBookmarksCommands(
            browserContext: browserContext
        )

        CommandMenu("Extensions") {
            Button("Manage Extensions...") {
                browserContext.openSettingsTab(selecting: .extensions)
            }
            #if DEBUG
            Divider()
            Button("Run Safari Extension Acceptance Check") {
                browserContext.printSafariExtensionAcceptanceCheckToConsole()
            }
            .disabled(browserContext.extensionsDiagnosticsAreEnabled == false)
            Button("Run Safari Extension Native Messaging Probe") {
                browserContext.printSafariExtensionNativeMessagingProbeToConsole()
            }
            .disabled(browserContext.extensionsDiagnosticsAreEnabled == false)
            Button("Run Safari Extension Dev Diagnostics Report") {
                browserContext.printSafariExtensionDevDiagnosticsReportToConsole()
            }
            .disabled(browserContext.extensionsDiagnosticsAreEnabled == false)
            #endif
        }

        CommandMenu("Privacy") {
            Button("Clear Cookies for Current Site") {
                browserContext.clearCurrentPageCookies()
            }
            .disabled(browserContext.activePageHost == nil)

            Button("Clear Browsing History") {
                browserContext.clearAllHistoryFromMenu()
            }
        }

        CommandMenu("Appearance") {
            Button("Customize Space Gradient...") {
                browserContext.showGradientEditor()
            }
            .modifier(dynamicShortcut(.customizeSpaceGradient))
            .disabled(browserContext.canCustomizeSpaceGradient == false)
        }
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            EmptyView()
        }
        CommandGroup(replacing: .appTermination) {
            Button("Quit Sumi") {
                browserContext.showQuitDialog()
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
        CommandGroup(replacing: .windowList) {
            EmptyView()
        }
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
                browserContext.undoCloseTab()
            }
            .modifier(dynamicShortcut(.undoCloseTab))
            .disabled(recentlyClosedManager.canReopenRecentlyClosedItem == false)
        }

        // File Section
        CommandGroup(after: .newItem) {
            Button("New Tab") {
                browserContext.openNewTabSurfaceInActiveWindow()
            }
            .modifier(dynamicShortcut(.newTab))
            Button("New Window") {
                browserContext.createNewWindow()
            }
            .modifier(dynamicShortcut(.newWindow))

            Button("New Incognito Window") {
                browserContext.createIncognitoWindow()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()
            Button("Open Command Bar") {
                browserContext.openCommandBarForActivePage()
            }
            .modifier(dynamicShortcut(.focusAddressBar))
            .disabled(browserContext.hasActivePageTab == false)

            Button("Copy Current URL") {
                browserContext.copyCurrentURL()
            }
            .modifier(dynamicShortcut(.copyCurrentURL))
            .disabled(browserContext.hasActivePageTab == false)
        }

        // Sidebar commands
        CommandGroup(after: .sidebar) {
            Button("Toggle Sidebar") {
                browserContext.toggleSidebar()
            }
            .modifier(dynamicShortcut(.toggleSidebar))
        }

        // View commands
        CommandGroup(after: .windowSize) {
            Button("Find in Page") {
                browserContext.showFindBar()
            }
            .modifier(dynamicShortcut(.findInPage))
            .disabled(browserContext.hasActivePageTab == false)

            Button("Reload Page") {
                browserContext.refreshCurrentTabInActiveWindow()
            }
            .modifier(dynamicShortcut(.refresh))
            .disabled(browserContext.canReloadActivePage == false)

            Divider()

            Button("Zoom In") {
                browserContext.zoomInCurrentTab()
            }
            .modifier(dynamicShortcut(.zoomIn))
            .disabled(browserContext.hasActivePageTab == false)

            Button("Zoom Out") {
                browserContext.zoomOutCurrentTab()
            }
            .modifier(dynamicShortcut(.zoomOut))
            .disabled(browserContext.hasActivePageTab == false)

            Button("Actual Size") {
                browserContext.resetZoomCurrentTab()
            }
            .modifier(dynamicShortcut(.actualSize))
            .disabled(browserContext.hasActivePageTab == false)

            Divider()

            Button("Hard Reload (Ignore Cache)") {
                browserContext.hardReloadCurrentPage()
            }
            .modifier(dynamicShortcut(.hardReload))
            .disabled(browserContext.canReloadActivePage == false)

            Divider()

            Button("Web Inspector") {
                browserContext.openWebInspector()
            }
            .modifier(dynamicShortcut(.openDevTools))
            .disabled(
                browserContext.hasActivePageTab == false
                    || !RuntimeDiagnostics.isDeveloperInspectionEnabled
            )

            Divider()

            Button(browserContext.currentTabIsMuted ? "Unmute Audio" : "Mute Audio") {
                browserContext.toggleMuteCurrentTabInActiveWindow()
            }
            .modifier(dynamicShortcut(.muteUnmuteAudio))
            .disabled(
                browserContext.hasActivePageTab == false
                    || !browserContext.currentTabHasAudioContent)
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

private struct SumiCheckForUpdatesCommand: View {
    @ObservedObject var updaterService: SumiUpdaterService

    var body: some View {
        Button("Check for Updates…") {
            updaterService.checkForUpdatesFromUserAction()
        }
        .disabled(!updaterService.state.canCheckForUpdates)
    }
}
