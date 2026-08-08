//
//  ExtensionKeyboardCommandDispatchOwner.swift
//  Sumi
//
//  Dispatches browser-level keyboard events to WebKit extension commands
//  (manifest `commands` shortcuts), mirroring Safari's dispatch order:
//  browser shortcuts first, then extension commands, then the page.
//

import AppKit
import SumiDomain
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionKeyboardCommandDispatchOwner {
    private final class EventMonitorHandle {
        private let monitor: Any

        init(_ monitor: Any) {
            self.monitor = monitor
        }

        deinit {
            NSEvent.removeMonitor(monitor)
        }
    }

    private final class ObserverHandle {
        private let observer: NSObjectProtocol

        init(_ observer: NSObjectProtocol) {
            self.observer = observer
        }

        deinit {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private let database: SumiDatabase
    private let assignments: ExtensionCommandAssignments
    private let profileRuntime: ExtensionProfileRuntime
    private let browser:
        ExtensionBrowserAttachmentAuthority.ActionBrowserProjection
    private let diagnostics: ExtensionRuntimeDiagnostics
    private var eventMonitor: EventMonitorHandle?
    private var bindingsObserver: ObserverHandle?

    init(
        database: SumiDatabase,
        profileRuntime: ExtensionProfileRuntime,
        browser: ExtensionBrowserAttachmentAuthority.ActionBrowserProjection,
        diagnostics: ExtensionRuntimeDiagnostics
    ) {
        self.database = database
        assignments = ExtensionCommandAssignments(database: database)
        self.profileRuntime = profileRuntime
        self.browser = browser
        self.diagnostics = diagnostics
        profileRuntime.keyboardCommandBindingsDidChange = { [weak self] in
            self?.reconcileBindingsAndMonitor()
        }
        let observer = NotificationCenter.default.addObserver(
            forName: .sumiKeyboardBindingsDidChange,
            object: database,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reconcileBindingsAndMonitor()
            }
        }
        bindingsObserver = ObserverHandle(observer)
        reconcileBindingsAndMonitor()
    }

    /// The host projection has already excluded native and browser-owned menu
    /// equivalents. Resolve one exact MV3 command and invoke that command
    /// directly so WebKit's event-level subset matching cannot pick a sibling
    /// binding with fewer modifiers.
    func performCommand(for event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              let eventWindow = event.window,
              !(eventWindow.firstResponder is KeyboardCommandCaptureResponder),
              let profileID = browser.keyboardProfileID(for: eventWindow)
        else { return false }

        return performCommand(for: event, profileID: profileID)
    }

    func performCommand(for event: NSEvent, profileID: UUID) -> Bool {
        guard event.type == .keyDown,
              let eventCombination = KeyCombination(from: event)
        else { return false }

        let contexts = profileRuntime.contexts(for: profileID)
            .sorted { $0.key < $1.key }
        for (extensionId, extensionContext) in contexts {
            guard extensionContext.isLoaded else { continue }
            for command in extensionContext.commands.sorted(by: {
                $0.id < $1.id
            }) {
                guard let activationKey = command.activationKey else {
                    continue
                }
                let commandCombination = KeyCombination(
                    key: activationKey,
                    modifiers: Modifiers(
                        eventModifierFlags: command.modifierFlags
                    )
                )
                guard commandCombination == eventCombination else { continue }

                extensionContext.performCommand(command)
                diagnostics.trace(
                    "extension keyboard command performed extensionId=\(extensionId) command=\(command.id)"
                )
                return true
            }
        }
        return false
    }

    #if DEBUG
        var hasEventMonitorForTesting: Bool { eventMonitor != nil }
    #endif

    private func reconcileMonitor() {
        guard hasActiveRegularCommand else {
            eventMonitor = nil
            return
        }
        guard eventMonitor == nil,
              let monitor = NSEvent.addLocalMonitorForEvents(
                matching: [.keyDown],
                handler: { [weak self] event in
                    self?.route(event) ?? event
                }
              ) else { return }
        eventMonitor = EventMonitorHandle(monitor)
    }

    private func reconcileBindingsAndMonitor() {
        reconcileBindings()
        reconcileMonitor()
    }

    private func reconcileBindings() {
        for (profileID, contexts) in profileRuntime.contextsByProfile {
            let projected = Dictionary(
                uniqueKeysWithValues: ((try? assignments.assignments(
                    profileID: profileID
                )) ?? []).map { ($0.identity, $0) }
            )

            for (extensionID, context) in contexts where context.isLoaded {
                for command in context.commands {
                    let identity = ExtensionCommandBindingIdentity(
                        profileID: profileID,
                        extensionID: extensionID,
                        commandName: command.id
                    )
                    guard let combination = projected[identity]?
                        .activeCombination else {
                        command.activationKey = nil
                        command.modifierFlags = []
                        continue
                    }
                    command.activationKey = combination.key
                    command.modifierFlags = eventModifiers(
                        for: combination.modifiers
                    )
                }
            }
        }
    }

    private func eventModifiers(for modifiers: Modifiers) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.control) { flags.insert(.control) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        return flags
    }

    private var hasActiveRegularCommand: Bool {
        profileRuntime.contextsByProfile.values.contains { contexts in
            contexts.values.contains { context in
                context.isLoaded && context.commands.contains { command in
                    guard command.activationKey != nil else { return false }
                    return !command.modifierFlags.isDisjoint(with: [
                        .command, .control, .option,
                    ])
                }
            }
        }
    }

    private func route(_ event: NSEvent) -> NSEvent? {
        guard let combination = KeyCombination(from: event),
              let eventWindow = event.window,
              browser.keyboardProfileID(for: eventWindow) != nil,
              !mainMenuOwns(combination) else {
            return event
        }
        return performCommand(for: event) ? nil : event
    }

    private func mainMenuOwns(_ combination: KeyCombination) -> Bool {
        guard let mainMenu = NSApp.mainMenu else { return false }
        return mainMenu.items.contains { menuItemOwns($0, combination) }
    }

    private func menuItemOwns(
        _ item: NSMenuItem,
        _ combination: KeyCombination
    ) -> Bool {
        if !item.keyEquivalent.isEmpty {
            let menuCombination = KeyCombination(
                key: item.keyEquivalent,
                modifiers: Modifiers(
                    eventModifierFlags: item.keyEquivalentModifierMask
                )
            )
            if menuCombination == combination {
                return true
            }
        }
        return item.submenu?.items.contains {
            menuItemOwns($0, combination)
        } == true
    }
}

// MARK: - ExtensionManager facade
