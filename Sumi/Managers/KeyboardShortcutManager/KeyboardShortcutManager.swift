//
//  KeyboardShortcutManager.swift
//  Sumi
//
//  Browser actions are recognized by AppKit menu equivalents. The only local
//  monitor is a conditional adapter for enabled MV3 extension commands.
//

import AppKit
import Foundation
import Observation
import SumiDomain

@MainActor
@Observable
class KeyboardShortcutManager {
    private let assignments: KeyboardCommandAssignments
    private let extensionAssignments: ExtensionCommandAssignments
    private let validator: ShortcutValidator
    private let systemOwnedShortcuts = KeyboardCommandAssignments
        .nativeReservations

    private var shortcutsByAction: [ShortcutAction: KeyboardShortcut] = [:]
    private var enabledLookup: [String: ShortcutAction] = [:]
    private(set) var bindingRevision: UInt64 = 0
    weak var shortcutActionRouter: BrowserShortcutActionRouter?
    private var shortcutTargetResolver: BrowserShortcutTargetResolver?

    init(
        userDefaults: UserDefaults = .standard,
        database: SumiDatabase? = nil
    ) {
        let resolvedDatabase: SumiDatabase
        if let database {
            resolvedDatabase = database
        } else {
            do {
                resolvedDatabase = try SumiDatabase.inMemory()
            } catch {
                preconditionFailure("Could not create shortcut database: \(error)")
            }
        }
        do {
            self.assignments = try KeyboardCommandAssignments(
                database: resolvedDatabase,
                legacyDefaults: userDefaults
            )
        } catch {
            preconditionFailure("Could not load keyboard shortcuts: \(error)")
        }
        self.extensionAssignments = ExtensionCommandAssignments(
            database: resolvedDatabase
        )
        self.validator = ShortcutValidator(systemOwnedShortcuts: systemOwnedShortcuts)
        loadShortcuts()
    }

    func attach(
        actionRouter: BrowserShortcutActionRouter,
        targetResolver: BrowserShortcutTargetResolver
    ) {
        shortcutActionRouter = actionRouter
        shortcutTargetResolver = targetResolver
    }

    var shortcuts: [KeyboardShortcut] {
        Array(shortcutsByAction.values)
            .filter {
                !KeyboardCommandAssignments.nativeCommandActions
                    .contains($0.action)
            }
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

    func bindingAssignment(
        for action: ShortcutAction
    ) -> BrowserActionBindingAssignment {
        assignments.assignment(for: action)
    }

    func setShortcut(
        action: ShortcutAction,
        keyCombination: KeyCombination,
        profileID: UUID? = nil
    ) -> ShortcutValidationResult {
        guard !KeyboardCommandAssignments.nativeCommandActions
            .contains(action) else {
            return .systemOwned
        }
        let validation = validate(
            keyCombination,
            excludingAction: action,
            profileID: profileID
        )
        guard validation.allowsAssignment, shortcutsByAction[action] != nil else {
            return validation
        }

        let previousOwner: ShortcutAction?
        if case .conflict(let action) = validation {
            previousOwner = action
        } else {
            previousOwner = nil
        }
        let extensionOwner: ExtensionCommandBindingIdentity?
        if let profileID {
            do {
                extensionOwner = try extensionAssignments.activeOwner(
                    for: keyCombination,
                    profileID: profileID
                )?.identity
            } catch {
                return .invalid
            }
        } else {
            extensionOwner = nil
        }
        do {
            try assignments.assign(
                keyCombination,
                to: action,
                replacing: previousOwner,
                replacing: extensionOwner
            )
        } catch {
            return .invalid
        }
        loadShortcuts()
        return .valid
    }

    @discardableResult
    func clearShortcut(action: ShortcutAction) -> Bool {
        guard shortcutsByAction[action] != nil,
              !KeyboardCommandAssignments.nativeCommandActions
                .contains(action) else {
            return false
        }
        do {
            try assignments.clear(action)
            loadShortcuts()
            return true
        } catch {
            return false
        }
    }

    func resetToDefaults() {
        do {
            try assignments.resetBrowserActions()
        } catch {
            return
        }
        loadShortcuts()
    }

    func validate(
        _ keyCombination: KeyCombination,
        excludingAction: ShortcutAction? = nil,
        profileID: UUID? = nil
    ) -> ShortcutValidationResult {
        let browserValidation = validator.validate(
            keyCombination,
            in: shortcutsByAction,
            excludingAction: excludingAction
        )
        guard browserValidation == .valid, let profileID else {
            return browserValidation
        }
        do {
            guard let extensionOwner = try extensionAssignments.activeOwner(
                for: keyCombination,
                profileID: profileID
            ) else {
                return browserValidation
            }
            return .namedConflict(extensionOwner.title)
        } catch {
            return .invalid
        }
    }

    func extensionCommandAssignments(
        profileID: UUID
    ) -> [ExtensionCommandBindingAssignment] {
        do {
            return try extensionAssignments.assignments(profileID: profileID)
        } catch {
            return []
        }
    }

    func validateExtensionCommand(
        _ keyCombination: KeyCombination,
        identity: ExtensionCommandBindingIdentity
    ) -> ShortcutValidationResult {
        do {
            return try extensionAssignments.validate(
                keyCombination,
                for: identity
            )
        } catch {
            return .invalid
        }
    }

    func setExtensionCommand(
        _ keyCombination: KeyCombination,
        identity: ExtensionCommandBindingIdentity
    ) -> ShortcutValidationResult {
        do {
            let result = try extensionAssignments.assign(
                keyCombination,
                to: identity
            )
            if result == .valid {
                try assignments.reload()
                loadShortcuts()
            }
            return result
        } catch {
            return .invalid
        }
    }

    func clearExtensionCommand(
        identity: ExtensionCommandBindingIdentity
    ) -> Bool {
        do {
            try extensionAssignments.clear(identity)
            bindingRevision &+= 1
            return true
        } catch {
            return false
        }
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
        case .foreignWindow:
            return false
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

        return ShortcutAction.commandPaletteCatalogOrder.compactMap { action in
            let isAvailable: Bool
            switch target {
            case .browser(let context):
                isAvailable =
                    shortcutActionRouter.canExecuteApplicationAction(action)
                    || shortcutActionRouter.canExecute(action, in: context)
            case .foreignWindow:
                isAvailable = false
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
        case .foreignWindow:
            return nil
        case .none:
            return nil
        }
    }

    private func loadShortcuts() {
        shortcutsByAction = Dictionary(
            uniqueKeysWithValues: ShortcutAction.allCases.map { action in
                (
                    action,
                    KeyboardShortcut(
                        action: action,
                        keyCombination: assignments.assignment(for: action)
                            .activeCombination
                    )
                )
            }
        )
        rebuildEnabledLookup()
        bindingRevision &+= 1
    }

    private func rebuildEnabledLookup() {
        enabledLookup = Dictionary(
            uniqueKeysWithValues: shortcutsByAction.values.compactMap { shortcut in
                guard let lookupKey = shortcut.lookupKey else { return nil }
                return (lookupKey, shortcut.action)
            }
        )
    }
}
