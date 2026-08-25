//
//  SumiCommands.swift
//  Sumi
//
//  Menu bar commands for the Sumi browser application
//

import AppKit
import SumiDomain
import SwiftUI

extension FocusedValues {
    @Entry var sumiSettingsWindowIsFocused: Bool?
}

struct SumiCommands: Commands {
    let browserContext: SumiCommandsBrowserContext
    let windowRegistry: WindowRegistry
    let shortcutManager: KeyboardShortcutManager
    let settingsNavigation: SettingsNavigationOwner
    private let updaterService: SumiUpdaterService
    @ObservedObject private var menuFaviconInvalidator: SumiMenuFaviconInvalidator
    @FocusedValue(\.sumiSettingsWindowIsFocused) private var settingsWindowIsFocused

    init(
        browserContext: SumiCommandsBrowserContext,
        windowRegistry: WindowRegistry,
        shortcutManager: KeyboardShortcutManager,
        settingsNavigation: SettingsNavigationOwner,
        updaterService: SumiUpdaterService,
        menuFaviconInvalidator: SumiMenuFaviconInvalidator = SumiMenuFaviconInvalidator()
    ) {
        self.browserContext = browserContext
        self.windowRegistry = windowRegistry
        self.shortcutManager = shortcutManager
        self.settingsNavigation = settingsNavigation
        self.updaterService = updaterService
        self._menuFaviconInvalidator = ObservedObject(wrappedValue: menuFaviconInvalidator)
    }

    // MARK: - Dynamic Keyboard Shortcuts

    /// View extension to apply dynamic keyboard shortcut if enabled
    private func dynamicShortcut(_ action: ShortcutAction) -> DynamicShortcutModifier {
        let shortcut = shortcutManager.shortcut(for: action)
        let keyCombination = shortcut?.keyCombination
        return DynamicShortcutModifier(
            keyEquivalent: keyCombination.flatMap { KeyboardShortcutPresentation.keyEquivalent(for: $0) },
            modifiers: keyCombination.map { KeyboardShortcutPresentation.eventModifiers(for: $0.modifiers) } ?? []
        )
    }

    private func performShortcut(_ action: ShortcutAction) {
        _ = shortcutManager.perform(action, keyWindow: NSApp.keyWindow)
    }

    private func browserActionButton(
        _ action: ShortcutAction,
        title: String? = nil
    ) -> some View {
        Button(title ?? action.displayName) {
            performShortcut(action)
        }
        .modifier(dynamicShortcut(action))
        .disabled(!shortcutManager.canPerform(action, keyWindow: NSApp.keyWindow))
    }

    private var closeFocusedWindowOrTabButton: some View {
        Button(settingsWindowIsFocused == true ? "Close Window" : "Close Tab") {
            if settingsWindowIsFocused == true {
                NSApp.keyWindow?.performClose(nil)
            } else {
                performShortcut(.closeTab)
            }
        }
        .modifier(
            settingsWindowIsFocused == true
                ? DynamicShortcutModifier(
                    keyEquivalent: KeyEquivalent("w"),
                    modifiers: [.command]
                )
                : dynamicShortcut(.closeTab)
        )
        .disabled(
            settingsWindowIsFocused != true
                && !shortcutManager.canPerform(.closeTab, keyWindow: NSApp.keyWindow)
        )
    }

    @CommandsBuilder
    private var applicationCommands: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Sumi") {
                browserContext.openSettingsTab(selecting: .about)
            }
        }

        CommandGroup(after: .appInfo) {
            SumiCheckForUpdatesCommand(updaterService: updaterService)
            Divider()
            Button("Make Sumi Default Browser") {
                browserContext.setAsDefaultBrowser()
            }
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                settingsNavigation.openSettings(
                    selecting: settingsNavigation.currentSettingsTab
                )
            }
            .keyboardShortcut(",", modifiers: [.command])
        }

        CommandGroup(replacing: .saveItem) {
            EmptyView()
        }

        CommandGroup(replacing: .printItem) {
            browserActionButton(.printPage)
        }
    }

    @CommandsBuilder
    private var secondaryCommandMenus: some Commands {
        SumiHistoryCommands(
            browserContext: browserContext,
            shortcutManager: shortcutManager,
            menuFaviconInvalidator: menuFaviconInvalidator
        )

        SumiBookmarksCommands(
            browserContext: browserContext,
            menuFaviconInvalidator: menuFaviconInvalidator
        )

        CommandMenu("Extensions") {
            browserActionButton(.manageExtensions, title: "Manage Extensions…")
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

            browserActionButton(
                .clearCookiesAndRefresh,
                title: "Clear Cookies and Reload"
            )

            Button("Clear Browsing History") {
                browserContext.clearAllHistoryFromMenu()
            }
        }

        CommandMenu("Appearance") {
            browserActionButton(
                .customizeSpaceGradient,
                title: "Customize Space Gradient…"
            )

            Divider()

            ForEach(
                Array(BrowserActionMenuOwnershipCatalog.appearance.dropFirst()),
                id: \.self
            ) { action in
                browserActionButton(action)
            }
        }

        CommandMenu("Tabs") {
            ForEach(
                Array(BrowserActionMenuOwnershipCatalog.tabs.dropFirst()),
                id: \.self
            ) { action in
                browserActionButton(action)
            }

            Divider()

            Menu("Split View") {
                ForEach(BrowserActionMenuOwnershipCatalog.splitView, id: \.self) { action in
                    browserActionButton(action)
                }
            }
        }

        CommandMenu("Spaces") {
            ForEach(BrowserActionMenuOwnershipCatalog.spaces, id: \.self) { action in
                browserActionButton(action)
            }
        }
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            EmptyView()
        }
        applicationCommands

        // File Section
        CommandGroup(after: .newItem) {
            Button("New Tab") {
                performShortcut(.newTab)
            }
            .modifier(dynamicShortcut(.newTab))
            Button("New Window") {
                performShortcut(.newWindow)
            }
            .modifier(dynamicShortcut(.newWindow))

            Button("New Private Window") {
                performShortcut(.newPrivateWindow)
            }
            .modifier(dynamicShortcut(.newPrivateWindow))

            Divider()
            Button("Open Command Bar") {
                performShortcut(.focusAddressBar)
            }
            .modifier(dynamicShortcut(.focusAddressBar))
            .disabled(browserContext.hasActivePageTab == false)

            Button("Copy Current URL") {
                performShortcut(.copyCurrentURL)
            }
            .modifier(dynamicShortcut(.copyCurrentURL))
            .disabled(browserContext.hasActivePageTab == false)

            Divider()

            closeFocusedWindowOrTabButton

            browserActionButton(.closeWindow)
        }

        // Sidebar commands
        CommandGroup(after: .sidebar) {
            Button("Toggle Sidebar") {
                performShortcut(.toggleSidebar)
            }
            .modifier(dynamicShortcut(.toggleSidebar))
        }

        // View commands
        CommandGroup(after: .windowSize) {
            Button("Find in Page") {
                performShortcut(.findInPage)
            }
            .modifier(dynamicShortcut(.findInPage))
            .disabled(browserContext.hasActivePageTab == false)

            Button("Reload Page") {
                performShortcut(.refresh)
            }
            .modifier(dynamicShortcut(.refresh))
            .disabled(browserContext.canReloadActivePage == false)

            Divider()

            Button("Zoom In") {
                performShortcut(.zoomIn)
            }
            .modifier(dynamicShortcut(.zoomIn))
            .disabled(browserContext.hasActivePageTab == false)

            Button("Zoom Out") {
                performShortcut(.zoomOut)
            }
            .modifier(dynamicShortcut(.zoomOut))
            .disabled(browserContext.hasActivePageTab == false)

            Button("Actual Size") {
                performShortcut(.actualSize)
            }
            .modifier(dynamicShortcut(.actualSize))
            .disabled(browserContext.hasActivePageTab == false)

            Divider()

            Button("Hard Reload (Ignore Cache)") {
                performShortcut(.hardReload)
            }
            .modifier(dynamicShortcut(.hardReload))
            .disabled(browserContext.canReloadActivePage == false)

            browserActionButton(.toggleReaderMode)

            browserActionButton(.newBoost)

            Divider()

            Button("Web Inspector") {
                performShortcut(.openDevTools)
            }
            .modifier(dynamicShortcut(.openDevTools))
            .disabled(
                browserContext.hasActivePageTab == false
                    || !RuntimeDiagnostics.isDeveloperInspectionEnabled
            )

            Divider()

            Button(browserContext.currentTabIsMuted ? "Unmute Audio" : "Mute Audio") {
                performShortcut(.muteUnmuteAudio)
            }
            .modifier(dynamicShortcut(.muteUnmuteAudio))
            .disabled(
                browserContext.hasActivePageTab == false
                    || !browserContext.currentTabHasAudioContent)

            Divider()

            browserActionButton(.viewDownloads)

            browserActionButton(.captureScreenshot)

            browserActionButton(.toggleTabsOnRight)

            Divider()
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
