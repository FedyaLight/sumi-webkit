//
//  KeyboardShortcutManager.swift
//  Sumi
//
//  Created by Jonathan Caudill on 09/30/2025.
//
//  Keyboard routing for browser windows follows the DuckDuckGo macOS pattern:
//  a scoped local monitor (see MainViewController customKeyDown) plus menu delivery
//  via NSMenu.performKeyEquivalent, adapted under the Apache License, Version 2.0.
//  Copyright © 2020 DuckDuckGo. All rights reserved.
//  https://www.apache.org/licenses/LICENSE-2.0
//

import Carbon
import Foundation
import AppKit
import SwiftUI
import WebKit

@MainActor
@Observable
class KeyboardShortcutManager {
    private final class EventMonitorHandle {
        private let monitor: Any

        init(monitor: Any) {
            self.monitor = monitor
        }

        deinit {
            NSEvent.removeMonitor(monitor)
        }
    }

    /// While > 0, the browser key monitor passes all events through (Settings shortcut recorder uses its own monitor).
    private static var shortcutRecorderCaptureDepth: Int = 0
    static var isShortcutRecorderCaptureActive: Bool { shortcutRecorderCaptureDepth > 0 }
    static func pushShortcutRecorderCaptureSession() {
        shortcutRecorderCaptureDepth += 1
    }
    static func popShortcutRecorderCaptureSession() {
        if shortcutRecorderCaptureDepth > 0 {
            shortcutRecorderCaptureDepth -= 1
        }
    }

    private let userDefaults = UserDefaults.standard
    private let shortcutsKey = "keyboard.shortcuts"
    private let shortcutsVersionKey = "keyboard.shortcuts.version"
    private let currentVersion = 8 // Increment when changing default shortcut surface
    private let hiddenActions: Set<ShortcutAction> = [.toggleTopBarAddressView]
    /// Shortcuts left to AppKit / system responders when not handled by the menu + shortcut map.
    /// Note: Cmd+Q is not listed here so `closeBrowser` can run via `executeShortcut` when SwiftUI `Commands`
    /// does not handle `NSMenu.performKeyEquivalent`.
    private let systemOwnedShortcuts: Set<KeyCombination> = [
        KeyCombination(key: ",", modifiers: [.command]),
        KeyCombination(key: "h", modifiers: [.command]),
        KeyCombination(key: "m", modifiers: [.command]),
    ]

    /// Hash-based storage for O(1) lookup: ["cmd+t": KeyboardShortcut]
    private var shortcutMap: [String: KeyboardShortcut] = [:]

    /// All shortcuts for UI display (sorted by display name)
    var shortcuts: [KeyboardShortcut] {
        Array(shortcutMap.values)
            .filter { !hiddenActions.contains($0.action) }
            .sorted { $0.action.displayName < $1.action.displayName }
    }

    weak var browserManager: BrowserManager?
    weak var windowRegistry: WindowRegistry?

    init() {
        loadShortcuts()
        setupGlobalMonitor()
    }

    func setBrowserManager(_ manager: BrowserManager) {
        self.browserManager = manager
        self.windowRegistry = manager.windowRegistry
    }

    // MARK: - Persistence

    private func loadShortcuts() {
        let savedVersion = userDefaults.integer(forKey: shortcutsVersionKey)

        // Load from UserDefaults or use defaults
        if let data = userDefaults.data(forKey: shortcutsKey),
           let decoded = decodePersistedShortcuts(from: data) {
            // Populate hash map from loaded shortcuts
            for shortcut in decoded {
                if hiddenActions.contains(shortcut.action) {
                    continue
                }
                shortcutMap[shortcut.lookupKey] = shortcut
            }

            // Check if we need to merge new shortcuts
            if savedVersion < currentVersion {
                mergeWithDefaults()
                savePersistedShortcutVersion()
            } else if decoded.count != shortcutMap.count {
                saveShortcuts()
            }
        } else {
            // Use defaults and populate hash map
            let defaults = KeyboardShortcut.defaultShortcuts
            for shortcut in defaults {
                shortcutMap[shortcut.lookupKey] = shortcut
            }
            savePersistedShortcutVersion()
            saveShortcuts()
        }
    }

    private func decodePersistedShortcuts(from data: Data) -> [KeyboardShortcut]? {
        try? JSONDecoder().decode([KeyboardShortcut].self, from: data)
    }

    private func savePersistedShortcutVersion() {
        userDefaults.set(currentVersion, forKey: shortcutsVersionKey)
    }

    private func mergeWithDefaults() {
        let defaultShortcuts = KeyboardShortcut.defaultShortcuts
        var needsUpdate = false
        let forcedBrowserDefaults: Set<ShortcutAction> = [
            .newTab,
            .closeTab,
            .undoCloseTab,
            .newWindow,
            .closeWindow,
        ]

        for defaultShortcut in defaultShortcuts where forcedBrowserDefaults.contains(defaultShortcut.action) {
            if let existingKey = shortcutMap.first(where: { $0.value.action == defaultShortcut.action })?.key {
                if shortcutMap[existingKey] != defaultShortcut {
                    shortcutMap.removeValue(forKey: existingKey)
                    shortcutMap[defaultShortcut.lookupKey] = defaultShortcut
                    needsUpdate = true
                }
            } else {
                shortcutMap[defaultShortcut.lookupKey] = defaultShortcut
                needsUpdate = true
            }
        }

        for defaultShortcut in defaultShortcuts {
            if hiddenActions.contains(defaultShortcut.action) {
                continue
            }
            if forcedBrowserDefaults.contains(defaultShortcut.action) {
                continue
            }
            // Check if this shortcut already exists (by action)
            if !shortcutMap.values.contains(where: { $0.action == defaultShortcut.action }) {
                // Add missing shortcut
                shortcutMap[defaultShortcut.lookupKey] = defaultShortcut
                needsUpdate = true
            }
        }

        if needsUpdate {
            saveShortcuts()
        }
    }

    private func saveShortcuts() {
        if let encoded = try? JSONEncoder().encode(shortcuts) {
            userDefaults.set(encoded, forKey: shortcutsKey)
        }
    }

    // MARK: - Public Interface

    /// O(n) lookup of shortcut by action (for specific action queries)
    func shortcut(for action: ShortcutAction) -> KeyboardShortcut? {
        shortcutMap.values.first { $0.action == action && $0.isEnabled }
    }

    func updateShortcut(action: ShortcutAction, keyCombination: KeyCombination) {
        // Find the existing shortcut first
        guard var shortcut = shortcutMap.values.first(where: { $0.action == action }) else {
            return
        }

        // Remove old entry
        shortcutMap.removeValue(forKey: shortcut.lookupKey)

        // Update and add back
        shortcut.keyCombination = keyCombination
        shortcutMap[keyCombination.lookupKey] = shortcut
        saveShortcuts()
    }

    func toggleShortcut(action: ShortcutAction, isEnabled: Bool) {
        if let key = shortcutMap.first(where: { $0.value.action == action })?.key,
           var shortcut = shortcutMap[key] {
            shortcut.isEnabled = isEnabled
            shortcutMap[key] = shortcut
            saveShortcuts()
        }
    }

    func resetToDefaults() {
        shortcutMap.removeAll()
        let defaults = KeyboardShortcut.defaultShortcuts
        for shortcut in defaults {
            shortcutMap[shortcut.lookupKey] = shortcut
        }
        saveShortcuts()
    }

    // MARK: - Conflict Detection

    func hasConflict(keyCombination: KeyCombination, excludingAction: ShortcutAction? = nil) -> ShortcutAction? {
        guard let shortcut = shortcutMap[keyCombination.lookupKey],
              shortcut.isEnabled else {
            return nil
        }

        if shortcut.action != excludingAction {
            return shortcut.action
        }
        return nil
    }

    func isValidKeyCombination(_ keyCombination: KeyCombination) -> Bool {
        // Basic validation - ensure it's not empty and has at least one modifier
        guard !keyCombination.key.isEmpty else { return false }

        // Require at least one modifier for most keys (except function keys, etc.)
        let functionKeys = ["f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12",
                           "escape", "delete", "forwarddelete", "home", "end", "pageup", "pagedown",
                           "help", "tab", "return", "space", "uparrow", "downarrow", "leftarrow", "rightarrow"]

        if functionKeys.contains(keyCombination.key.lowercased()) {
            return true
        }

        return !keyCombination.modifiers.isEmpty
    }

    // MARK: - Shortcut Execution (menu-backed shortcuts + palette-only keys)

    /// Runs user-configured shortcuts that are not handled by the main menu path (e.g. Option+D duplicate tab).
    func executeShortcut(_ event: NSEvent) -> Bool {
        let keyCode = event.keyCode
        if keyCode == 36 || keyCode == 76 { // 36 = Return, 76 = Enter (numpad)
            let hasModifiers = event.modifierFlags.contains(.command) ||
                event.modifierFlags.contains(.option) ||
                event.modifierFlags.contains(.control) ||
                event.modifierFlags.contains(.shift)
            if !hasModifiers {
                return false
            }
        }

        let navigationKeyCodes: Set<UInt16> = [
            123, 124, 125, 126, 115, 119, 116, 121,
        ]
        if navigationKeyCodes.contains(keyCode) {
            let hasModifiers = event.modifierFlags.contains(.command) ||
                event.modifierFlags.contains(.option) ||
                event.modifierFlags.contains(.control) ||
                event.modifierFlags.contains(.shift)
            if !hasModifiers {
                return false
            }
        }

        guard let keyCombination = KeyCombination(from: event) else {
            RuntimeDiagnostics.debug("Could not build KeyCombination from NSEvent.", category: "KeyboardShortcutManager")
            return false
        }

        if systemOwnedShortcuts.contains(keyCombination) {
            RuntimeDiagnostics.debug(
                "Passing system-owned shortcut \(keyCombination.lookupKey) through AppKit responder chain.",
                category: "KeyboardShortcutManager"
            )
            return false
        }

        guard let shortcut = shortcutMap[keyCombination.lookupKey],
              shortcut.isEnabled else {
            RuntimeDiagnostics.debug("No registered shortcut for \(keyCombination.lookupKey).", category: "KeyboardShortcutManager")
            return false
        }

        RuntimeDiagnostics.debug("Executing shortcut action '\(shortcut.action.displayName)'.", category: "KeyboardShortcutManager")
        executeAction(shortcut.action)
        return true
    }

    private func executeAction(_ action: ShortcutAction) {
        guard let browserManager = browserManager else { return }

        // Open find on the same turn as keyDown so SwiftUI can mount chrome and take focus before the next key event.
        if case .findInPage = action {
            browserManager.showFindBar()
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .shortcutExecuted,
                    object: nil,
                    userInfo: ["action": action]
                )
            }
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            switch action {
            // Navigation
            case .goBack:
                if let tab = browserManager.currentTabForActiveWindow(),
                   let windowId = self.windowRegistry?.activeWindow?.id,
                   let webView = browserManager.getWebView(for: tab.id, in: windowId) {
                    if webView.canGoBack {
                        webView.goBack()
                    }
                }
            case .goForward:
                if let tab = browserManager.currentTabForActiveWindow(),
                   let windowId = self.windowRegistry?.activeWindow?.id,
                   let webView = browserManager.getWebView(for: tab.id, in: windowId) {
                    if webView.canGoForward {
                        webView.goForward()
                    }
                }
            case .refresh:
                browserManager.refreshCurrentTabInActiveWindow()
            case .clearCookiesAndRefresh:
                browserManager.clearCurrentPageCookies()
                browserManager.refreshCurrentTabInActiveWindow()

            // Tab Management
            case .newTab:
                browserManager.openNewTabSurfaceInActiveWindow()
            case .closeTab:
                browserManager.closeCurrentTab()
            case .undoCloseTab:
                browserManager.undoCloseTab()
            case .nextTab:
                browserManager.selectNextTabInActiveWindow()
            case .previousTab:
                browserManager.selectPreviousTabInActiveWindow()
            case .goToTab1, .goToTab2, .goToTab3, .goToTab4, .goToTab5, .goToTab6, .goToTab7, .goToTab8:
                let tabIndex = Int(action.rawValue.components(separatedBy: "_").last ?? "0") ?? 1
                browserManager.selectTabByIndexInActiveWindow(tabIndex - 1)
            case .goToLastTab:
                browserManager.selectLastTabInActiveWindow()
            case .duplicateTab:
                browserManager.duplicateCurrentTab()
            case .toggleTopBarAddressView:
                browserManager.toggleTopBarAddressView()

            // Space Management
            case .nextSpace:
                browserManager.selectNextSpaceInActiveWindow()
            case .previousSpace:
                browserManager.selectPreviousSpaceInActiveWindow()

            // Window Management
            case .newWindow:
                browserManager.createNewWindow()
            case .closeWindow:
                browserManager.closeActiveWindow()
            case .closeBrowser:
                browserManager.showQuitDialog()
            case .toggleFullScreen:
                browserManager.toggleFullScreenForActiveWindow()

            // Tools & Features
            case .openCommandPalette:
                browserManager.openCommandPaletteForActiveWindow(reason: .keyboard)
            case .openDevTools:
                browserManager.openWebInspector()
            case .viewDownloads:
                browserManager.showDownloads()
            case .viewHistory:
                browserManager.showHistory()
            case .expandAllFolders:
                browserManager.expandAllFoldersInSidebar()

            case .focusAddressBar:
                let currentURL = browserManager.currentTabForActiveWindow()?.url.absoluteString ?? ""
                browserManager.openCommandPaletteForActiveWindow(
                    reason: .keyboard,
                    prefill: currentURL,
                    navigateCurrentTab: true
                )
            case .findInPage:
                break
            case .zoomIn:
                browserManager.zoomInCurrentTab()
            case .zoomOut:
                browserManager.zoomOutCurrentTab()
            case .actualSize:
                browserManager.resetZoomCurrentTab()

            case .toggleSidebar:
                browserManager.toggleSidebar()
            case .copyCurrentURL:
                browserManager.copyCurrentURL()
            case .hardReload:
                browserManager.hardReloadCurrentPage()
            case .muteUnmuteAudio:
                browserManager.toggleMuteCurrentTabInActiveWindow()
            case .customizeSpaceGradient:
                browserManager.showGradientEditor()
            }

            NotificationCenter.default.post(
                name: .shortcutExecuted,
                object: nil,
                userInfo: ["action": action]
            )
        }
    }

    // MARK: - Local key monitor (DuckDuckGo-style)

    private var eventMonitor: EventMonitorHandle?

    private func setupGlobalMonitor() {
        let monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            return self.handleLocalKeyDown(event)
        }
        guard let monitor else { return }
        self.eventMonitor = EventMonitorHandle(monitor: monitor)
    }

    private func handleLocalKeyDown(_ event: NSEvent) -> NSEvent? {
        if Self.isShortcutRecorderCaptureActive {
            return event
        }

        guard let keyWindow = NSApp.keyWindow else { return event }
        guard isManagedSumiBrowserWindow(keyWindow) else { return event }

        if shouldBypassShortcutRouting(keyWindow: keyWindow) {
            return event
        }

        if event.keyCode == UInt16(kVK_Escape),
           browserManager?.currentTabForActiveWindow()?.findInPage.model.isVisible == true {
            browserManager?.findManager.hideFindBar()
            return nil
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
        /// Only ⌘⌥⌃⇧ — avoids failed `switch` matches when Caps Lock leaves `.alphaShift` in `modifierFlags`.
        let routingFlags = flags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let isWebViewFocused = keyWindow.firstResponder is WKWebView

        if routeControlTabThroughMenu(event: event, routingFlags: routingFlags) {
            return nil
        }

        if routeWebViewMenuChromeThroughMenu(
            event: event,
            routingFlags: routingFlags,
            key: key,
            isWebViewFocused: isWebViewFocused
        ) {
            return nil
        }

        if executeShortcut(event) {
            return nil
        }

        return event
    }

    private func isManagedSumiBrowserWindow(_ window: NSWindow) -> Bool {
        windowRegistry?.windows.values.contains(where: { $0.window === window }) == true
    }

    private func shouldBypassShortcutRouting(keyWindow: NSWindow) -> Bool {
        if let state = windowRegistry?.windows.values.first(where: { $0.window === keyWindow }),
           state.isCommandPaletteVisible {
            return true
        }
        if browserManager?.dialogManager.isVisible == true {
            return true
        }
        return false
    }

    /// Control+Tab / Control+Shift+Tab: run the shortcut map first, then `NSMenu.performKeyEquivalent`
    /// (SwiftUI `Commands` often does not handle the menu path; menu may also report `true` without running the action).
    private func routeControlTabThroughMenu(event: NSEvent, routingFlags: NSEvent.ModifierFlags) -> Bool {
        guard event.keyCode == UInt16(kVK_Tab) else { return false }
        guard [.control, [.control, .shift]].contains(routingFlags) else { return false }
        guard let keyWindow = NSApp.keyWindow, isManagedSumiBrowserWindow(keyWindow) else { return false }
        if executeShortcut(event) { return true }
        return NSApp.mainMenu?.performKeyEquivalent(with: event) ?? false
    }

    /// When the web view is focused, run registered shortcuts first, then the main menu.
    /// Order matters: `performKeyEquivalent` can return `true` without invoking SwiftUI command actions.
    private func routeWebViewMenuChromeThroughMenu(
        event: NSEvent,
        routingFlags: NSEvent.ModifierFlags,
        key: String,
        isWebViewFocused: Bool
    ) -> Bool {
        guard isWebViewFocused else { return false }

        let isCmdTabIndex = routingFlags == [.command] && "123456789".contains(key)

        let isBrowserChromeKey: Bool
        switch (key, routingFlags, routingFlags.contains(.command)) {
        case ("n", [.command], _),
            ("t", [.command], _),
            ("t", [.command, .shift], _),
            ("w", _, true),
            ("q", [.command], _),
            ("r", [.command], _):
            isBrowserChromeKey = true
        default:
            isBrowserChromeKey = false
        }

        guard isCmdTabIndex || isBrowserChromeKey else { return false }

        if executeShortcut(event) { return true }
        return NSApp.mainMenu?.performKeyEquivalent(with: event) ?? false
    }
}

// MARK: - Notification
extension Notification.Name {
    static let shortcutExecuted = Notification.Name("shortcutExecuted")
}
