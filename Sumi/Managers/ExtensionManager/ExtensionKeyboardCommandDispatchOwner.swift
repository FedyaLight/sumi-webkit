//
//  ExtensionKeyboardCommandDispatchOwner.swift
//  Sumi
//
//  Dispatches browser-level keyboard events to WebKit extension commands
//  (manifest `commands` shortcuts), mirroring Safari's dispatch order:
//  browser shortcuts first, then extension commands, then the page.
//

import AppKit
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionKeyboardCommandDispatchOwner {
    private let profileRuntime: ExtensionProfileRuntime
    private let diagnostics: ExtensionRuntimeDiagnostics

    init(
        profileRuntime: ExtensionProfileRuntime,
        diagnostics: ExtensionRuntimeDiagnostics
    ) {
        self.profileRuntime = profileRuntime
        self.diagnostics = diagnostics
    }

    /// Callers must have already offered the event to Sumi's own shortcuts;
    /// a matching extension command consumes the event before the page.
    func performCommand(for event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        // Manifest commands always carry a primary modifier
        // (Command/MacCtrl/Ctrl/Alt); skip plain typing without touching
        // extension contexts.
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.isDisjoint(with: [.command, .control, .option]) == false else {
            return false
        }

        // Deterministic winner when two extensions declare the same shortcut.
        let contexts = profileRuntime.contextsForCurrentProfile()
            .sorted { $0.key < $1.key }
        for (extensionId, extensionContext) in contexts {
            guard extensionContext.isLoaded else { continue }
            if extensionContext.performCommand(for: event) {
                diagnostics.trace(
                    "extension keyboard command performed extensionId=\(extensionId)"
                )
                return true
            }
        }
        return false
    }
}

// MARK: - ExtensionManager facade
