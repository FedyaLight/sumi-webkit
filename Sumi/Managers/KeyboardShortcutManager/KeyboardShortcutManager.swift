//
//  KeyboardShortcutManager.swift
//  Sumi
//
//  Keyboard routing for browser windows follows the DuckDuckGo macOS pattern:
//  a scoped local monitor plus menu delivery via NSMenu.performKeyEquivalent.
//

import AppKit
import Carbon
import Foundation
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

    private static var shortcutRecorderCaptureDepth = 0
    static var isShortcutRecorderCaptureActive: Bool { shortcutRecorderCaptureDepth > 0 }

    static func pushShortcutRecorderCaptureSession() {
        shortcutRecorderCaptureDepth += 1
    }

    static func popShortcutRecorderCaptureSession() {
        if shortcutRecorderCaptureDepth > 0 {
            shortcutRecorderCaptureDepth -= 1
        }
    }

    private let store: KeyboardShortcutStore
    private let validator: ShortcutValidator
    private let hiddenActions = DefaultKeyboardShortcuts.hiddenActions
    private let systemOwnedShortcuts: Set<KeyCombination> = [
        KeyCombination(key: ",", modifiers: [.command]),
        KeyCombination(key: "h", modifiers: [.command]),
        KeyCombination(key: "m", modifiers: [.command]),
    ]

    private var shortcutsByAction: [ShortcutAction: KeyboardShortcut] = [:]
    private var enabledLookup: [String: ShortcutAction] = [:]
    private var dispatcher = ShortcutActionDispatcher()
    private var eventMonitor: EventMonitorHandle?

    weak var browserManager: BrowserManager? {
        didSet {
            dispatcher.browserManager = browserManager
        }
    }
    weak var windowRegistry: WindowRegistry? {
        didSet {
            dispatcher.windowRegistry = windowRegistry
        }
    }

    init(userDefaults: UserDefaults = .standard, installEventMonitor: Bool = true) {
        self.store = KeyboardShortcutStore(userDefaults: userDefaults)
        self.validator = ShortcutValidator(systemOwnedShortcuts: systemOwnedShortcuts)
        loadShortcuts()
        if installEventMonitor {
            setupGlobalMonitor()
        }
    }

    func setBrowserManager(_ manager: BrowserManager) {
        browserManager = manager
        windowRegistry = manager.windowRegistry
    }

    var shortcuts: [KeyboardShortcut] {
        Array(shortcutsByAction.values)
            .filter { !hiddenActions.contains($0.action) }
            .sorted {
                if $0.action.category != $1.action.category {
                    return $0.action.category.rawValue < $1.action.category.rawValue
                }
                return $0.action.displayName < $1.action.displayName
            }
    }

    func shortcut(for action: ShortcutAction) -> KeyboardShortcut? {
        guard let shortcut = shortcutsByAction[action],
              shortcut.keyCombination != nil else {
            return nil
        }
        return shortcut
    }

    func shortcutRecord(for action: ShortcutAction) -> KeyboardShortcut? {
        shortcutsByAction[action]
    }

    func setShortcut(action: ShortcutAction, keyCombination: KeyCombination) -> ShortcutValidationResult {
        let validation = validate(keyCombination, excludingAction: action)
        guard validation.allowsCommit, shortcutsByAction[action] != nil else {
            return validation
        }

        shortcutsByAction[action]?.keyCombination = keyCombination
        rebuildEnabledLookup()
        store.saveOverrides(shortcutsByAction, defaults: DefaultKeyboardShortcuts.shortcutsByAction)
        return .valid
    }

    @discardableResult
    func clearShortcut(action: ShortcutAction) -> Bool {
        guard shortcutsByAction[action] != nil else { return false }
        shortcutsByAction[action]?.keyCombination = nil
        rebuildEnabledLookup()
        store.saveOverrides(shortcutsByAction, defaults: DefaultKeyboardShortcuts.shortcutsByAction)
        return true
    }

    func resetToDefaults() {
        shortcutsByAction = DefaultKeyboardShortcuts.shortcutsByAction
        rebuildEnabledLookup()
        store.reset()
    }

    func validate(_ keyCombination: KeyCombination, excludingAction: ShortcutAction? = nil) -> ShortcutValidationResult {
        validator.validate(keyCombination, in: shortcutsByAction, excludingAction: excludingAction)
    }

    func conflict(for keyCombination: KeyCombination, excludingAction: ShortcutAction? = nil) -> ShortcutAction? {
        validator.conflict(for: keyCombination, in: shortcutsByAction, excludingAction: excludingAction)
    }

    func isValidKeyCombination(_ keyCombination: KeyCombination) -> Bool {
        validator.isValidKeyCombination(keyCombination)
    }

    func executeShortcut(_ event: NSEvent) -> Bool {
        if shouldPassUnmodifiedSpecialKeyThrough(event) {
            return false
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

        guard let action = enabledLookup[keyCombination.lookupKey] else {
            RuntimeDiagnostics.debug("No registered shortcut for \(keyCombination.lookupKey).", category: "KeyboardShortcutManager")
            return false
        }

        RuntimeDiagnostics.debug("Executing shortcut action '\(action.displayName)'.", category: "KeyboardShortcutManager")
        dispatcher.execute(action)
        return true
    }

    private func loadShortcuts() {
        shortcutsByAction = DefaultKeyboardShortcuts.shortcutsByAction

        guard let overrides = store.loadOverrides() else {
            rebuildEnabledLookup()
            return
        }

        for (action, keyCombination) in overrides where shortcutsByAction[action] != nil {
            if let keyCombination, validate(keyCombination, excludingAction: action).allowsCommit {
                shortcutsByAction[action]?.keyCombination = keyCombination
            } else if keyCombination == nil {
                shortcutsByAction[action]?.keyCombination = nil
            } else {
                store.reset()
                shortcutsByAction = DefaultKeyboardShortcuts.shortcutsByAction
                break
            }
        }

        rebuildEnabledLookup()
    }

    private func rebuildEnabledLookup() {
        enabledLookup = Dictionary(
            uniqueKeysWithValues: shortcutsByAction.values.compactMap { shortcut in
                guard let lookupKey = shortcut.lookupKey else { return nil }
                return (lookupKey, shortcut.action)
            }
        )
    }

    private func shouldPassUnmodifiedSpecialKeyThrough(_ event: NSEvent) -> Bool {
        let specialKeyCodes: Set<UInt16> = [
            36, 76, 123, 124, 125, 126, 115, 119, 116, 121,
        ]
        guard specialKeyCodes.contains(event.keyCode) else { return false }
        return !event.modifierFlags.contains(.command)
            && !event.modifierFlags.contains(.option)
            && !event.modifierFlags.contains(.control)
            && !event.modifierFlags.contains(.shift)
    }

    private func setupGlobalMonitor() {
        let monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            return self.handleLocalKeyDown(event)
        }
        guard let monitor else { return }
        eventMonitor = EventMonitorHandle(monitor: monitor)
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
        browserWindowState(containing: window) != nil
    }

    private func shouldBypassShortcutRouting(keyWindow: NSWindow) -> Bool {
        if let state = browserWindowState(containing: keyWindow),
           state.isCommandPaletteVisible {
            return true
        }
        if browserManager?.dialogManager.isVisible == true {
            return true
        }
        return false
    }

    private func browserWindowState(containing window: NSWindow) -> BrowserWindowState? {
        windowRegistry?.windows.values.first { state in
            guard let browserWindow = state.window else { return false }
            if browserWindow === window {
                return true
            }
            return browserWindow.childWindows?.contains(where: { $0 === window }) == true
        }
    }

    private func routeControlTabThroughMenu(event: NSEvent, routingFlags: NSEvent.ModifierFlags) -> Bool {
        guard event.keyCode == UInt16(kVK_Tab) else { return false }
        guard [.control, [.control, .shift]].contains(routingFlags) else { return false }
        guard let keyWindow = NSApp.keyWindow, isManagedSumiBrowserWindow(keyWindow) else { return false }
        if executeShortcut(event) { return true }
        return NSApp.mainMenu?.performKeyEquivalent(with: event) ?? false
    }

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

extension Notification.Name {
    static let shortcutExecuted = Notification.Name("shortcutExecuted")
}
