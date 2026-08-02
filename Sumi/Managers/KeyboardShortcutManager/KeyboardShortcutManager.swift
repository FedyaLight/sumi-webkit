//
//  KeyboardShortcutManager.swift
//  Sumi
//
//  Keyboard routing for browser windows uses one scoped local monitor and one
//  action router shared with menu commands.
//

import AppKit
import Carbon
import Foundation
import SumiDomain
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
    private let systemOwnedShortcuts: Set<KeyCombination> = [
        KeyCombination(key: ",", modifiers: [.command]),
        KeyCombination(key: "h", modifiers: [.command]),
        KeyCombination(key: "m", modifiers: [.command]),
    ]

    private var shortcutsByAction: [ShortcutAction: KeyboardShortcut] = [:]
    private var enabledLookup: [String: ShortcutAction] = [:]
    private var eventMonitor: EventMonitorHandle?
    // WebKit re-sends natively unhandled keys through NSApp using the same NSEvent.
    // Weak pointer identity lets the monitor consume only that second delivery.
    private let webContentKeyDownEvents = NSHashTable<NSEvent>(
        options: [.weakMemory, .objectPointerPersonality]
    )
    private let installsEventMonitorWhenAttached: Bool

    private enum LocalKeyRoutingResult {
        case pass(NSEvent)
        case consume
    }

    weak var shortcutActionRouter: BrowserShortcutActionRouter?
    private var shortcutTargetResolver: BrowserShortcutTargetResolver?
    private(set) weak var extensionsModule: SumiExtensionsModule?

    init(userDefaults: UserDefaults = .standard, installEventMonitor: Bool = true) {
        self.store = KeyboardShortcutStore(userDefaults: userDefaults)
        self.validator = ShortcutValidator(systemOwnedShortcuts: systemOwnedShortcuts)
        self.installsEventMonitorWhenAttached = installEventMonitor
        loadShortcuts()
    }

    func attach(
        actionRouter: BrowserShortcutActionRouter,
        targetResolver: BrowserShortcutTargetResolver,
        extensionsModule: SumiExtensionsModule
    ) {
        shortcutActionRouter = actionRouter
        shortcutTargetResolver = targetResolver
        self.extensionsModule = extensionsModule
        if installsEventMonitorWhenAttached {
            setupLocalMonitor()
        }
    }

    var shortcuts: [KeyboardShortcut] {
        Array(shortcutsByAction.values)
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

    func shortcutDisplayString(for action: ShortcutAction) -> String? {
        shortcut(for: action)?.keyCombination.map(KeyboardShortcutPresentation.displayString(for:))
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

    func executeShortcut(
        _ event: NSEvent,
        in context: BrowserShortcutContext
    ) -> Bool {
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

        guard let action = resolvedShortcutAction(for: keyCombination) else {
            RuntimeDiagnostics.debug("No registered shortcut for \(keyCombination.lookupKey).", category: "KeyboardShortcutManager")
            return false
        }

        RuntimeDiagnostics.debug("Executing shortcut action '\(action.displayName)'.", category: "KeyboardShortcutManager")
        guard let shortcutActionRouter else { return false }
        return shortcutActionRouter.executeApplicationAction(action)
            || shortcutActionRouter.execute(action, in: context)
    }

    func resolvedShortcutAction(
        for keyCombination: KeyCombination
    ) -> ShortcutAction? {
        guard !systemOwnedShortcuts.contains(keyCombination) else { return nil }
        return enabledLookup[keyCombination.lookupKey]
    }

    @discardableResult
    func perform(_ action: ShortcutAction, keyWindow: NSWindow?) -> Bool {
        guard let shortcutActionRouter else { return false }
        if shortcutActionRouter.executeApplicationAction(action) {
            return true
        }
        switch shortcutTargetResolver?.resolve(keyWindow: keyWindow) ?? .none {
        case .browser(let context):
            return shortcutActionRouter.execute(action, in: context)
        case .foreignWindow(let window):
            guard action == .closeTab || action == .closeWindow else {
                return false
            }
            window.performClose(nil)
            return true
        case .none:
            return false
        }
    }

    func canPerform(
        _ action: ShortcutAction,
        keyWindow: NSWindow?
    ) -> Bool {
        guard let shortcutActionRouter else { return false }
        if shortcutActionRouter.canExecuteApplicationAction(action) {
            return true
        }
        guard case .browser(let context) = shortcutTargetResolver?
            .resolve(keyWindow: keyWindow) else {
            return false
        }
        return shortcutActionRouter.canExecute(action, in: context)
    }

    func commandPaletteActionPresentations(
        keyWindow: NSWindow?
    ) -> [CommandPaletteBrowserActionPresentation] {
        guard let shortcutActionRouter else { return [] }
        let target = shortcutTargetResolver?
            .resolve(keyWindow: keyWindow) ?? .none

        return ShortcutAction.commandPaletteCatalogOrder.compactMap {
            action in
            let isAvailable: Bool
            switch target {
            case .browser(let context):
                isAvailable =
                    shortcutActionRouter.canExecuteApplicationAction(action)
                    || shortcutActionRouter.canExecute(action, in: context)
            case .foreignWindow:
                isAvailable = action == .closeTab || action == .closeWindow
            case .none:
                isAvailable =
                    shortcutActionRouter.canExecuteApplicationAction(action)
            }
            guard isAvailable else { return nil }

            let title: String
            if case .browser(let context) = target {
                if action == .closeTab,
                   context.windowState.currentShortcutPinId != nil {
                    title = "Unload"
                } else if action == .toggleSidebar {
                    title = context.windowState.isSidebarVisible
                        ? "Hide Sidebar"
                        : "Show Sidebar"
                } else {
                    title = action.commandPaletteTitle
                }
            } else {
                title = action.commandPaletteTitle
            }
            return CommandPaletteBrowserActionPresentation(
                action: action,
                title: title,
                shortcutLabel: shortcutDisplayString(for: action)
            )
        }
    }

    func performFromCommandPalette(
        _ action: ShortcutAction,
        keyWindow: NSWindow?
    ) -> CommandPaletteShortcutExecutionOutcome? {
        guard let shortcutActionRouter else { return nil }
        if shortcutActionRouter.executeApplicationAction(action) {
            return .dismissPalette
        }
        switch shortcutTargetResolver?.resolve(keyWindow: keyWindow) ?? .none {
        case .browser(let context):
            return shortcutActionRouter.executeFromCommandPalette(
                action,
                in: context
            )
        case .foreignWindow(let window):
            guard action == .closeTab || action == .closeWindow else {
                return nil
            }
            window.performClose(nil)
            return .dismissPalette
        case .none:
            return nil
        }
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

    private func setupLocalMonitor() {
        guard eventMonitor == nil else { return }
        let monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            return self.routeLocalKeyDown(event, keyWindow: NSApp.keyWindow)
        }
        guard let monitor else { return }
        eventMonitor = EventMonitorHandle(monitor: monitor)
    }

    func routeLocalKeyDown(
        _ event: NSEvent,
        keyWindow: NSWindow?
    ) -> NSEvent? {
        if shouldConsumeWebKitRedispatchedKeyDown(event, keyWindow: keyWindow) {
            return nil
        }

        if Self.isShortcutRecorderCaptureActive {
            return event
        }

        guard case .browser(let context) = shortcutTargetResolver?
            .resolve(keyWindow: keyWindow) else {
            return event
        }

        if let routingResult = routeCommandPaletteShortcutIfNeeded(
            event,
            context: context
        ) {
            switch routingResult {
            case .pass(let event):
                return event
            case .consume:
                return nil
            }
        }

        if shouldBypassShortcutRouting(
            context: context
        ) {
            return event
        }

        if event.keyCode == UInt16(kVK_Escape),
           shortcutActionRouter?.isFindBarVisible == true {
            shortcutActionRouter?.hideFindBar()
            return nil
        }

        if executeShortcut(event, in: context) {
            return nil
        }

        if extensionsModule?.performExtensionKeyboardCommandIfLoaded(
            for: event
        ) == true {
            return nil
        }

        return event
    }

    private func shouldConsumeWebKitRedispatchedKeyDown(
        _ event: NSEvent,
        keyWindow: NSWindow?
    ) -> Bool {
        if webContentKeyDownEvents.contains(event) {
            webContentKeyDownEvents.remove(event)
            return !isFindInPageCommand(event)
        }

        guard isWebContentFirstResponder(in: event.window ?? keyWindow) else {
            return false
        }
        webContentKeyDownEvents.add(event)
        return false
    }

    private func isWebContentFirstResponder(in window: NSWindow?) -> Bool {
        var view = window?.firstResponder as? NSView
        while let currentView = view {
            if currentView is WKWebView {
                return true
            }
            view = currentView.superview
        }
        return false
    }

    private func isFindInPageCommand(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting(.capsLock)
        return flags == [.command]
            && event.charactersIgnoringModifiers?.lowercased() == "f"
    }

    private func shouldBypassShortcutRouting(
        context: BrowserShortcutContext
    ) -> Bool {
        if context.windowState.presentationState.isCommandPaletteVisible {
            return true
        }
        if shortcutActionRouter?.isNativeModalPresented(
            in: context.appKitWindow
        ) == true {
            return true
        }
        return false
    }

    private func routeCommandPaletteShortcutIfNeeded(
        _ event: NSEvent,
        context: BrowserShortcutContext
    ) -> LocalKeyRoutingResult? {
        let windowState = context.windowState
        guard windowState.presentationState.isCommandPaletteVisible else {
            return nil
        }

        guard let keyCombination = KeyCombination(from: event) else {
            return .pass(event)
        }

        if keyCombination == KeyCombination(key: "escape") {
            return .pass(event)
        }

        if systemOwnedShortcuts.contains(keyCombination) {
            shortcutActionRouter?.dismissCommandPalette(
                in: windowState,
                preserveDraft: true
            )
            return .pass(event)
        }

        guard let action = enabledLookup[keyCombination.lookupKey] else {
            return .pass(event)
        }

        switch action {
        case .focusAddressBar, .newTab:
            break
        default:
            shortcutActionRouter?.dismissCommandPalette(
                in: windowState,
                preserveDraft: true
            )
        }

        if executeShortcut(event, in: context) {
            return .consume
        }

        return .pass(event)
    }

}
