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
    struct Dependencies {
        let loadedContextsForCurrentProfile:
            @MainActor () -> [String: WKWebExtensionContext]
        let trace: @MainActor (@autoclosure () -> String) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
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
        let contexts = dependencies.loadedContextsForCurrentProfile()
            .sorted { $0.key < $1.key }
        for (extensionId, extensionContext) in contexts {
            guard extensionContext.isLoaded else { continue }
            if extensionContext.performCommand(for: event) {
                dependencies.trace(
                    "extension keyboard command performed extensionId=\(extensionId)"
                )
                return true
            }
        }
        return false
    }
}

@available(macOS 15.5, *)
extension ExtensionKeyboardCommandDispatchOwner.Dependencies {
    @MainActor
    static func live(manager: ExtensionManager) -> Self {
        Self(
            loadedContextsForCurrentProfile: { [weak manager] in
                manager?.extensionContexts ?? [:]
            },
            trace: { [weak manager] message in
                manager?.extensionRuntimeTrace(message())
            }
        )
    }
}

// MARK: - ExtensionManager facade

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    func performExtensionKeyboardCommand(for event: NSEvent) -> Bool {
        keyboardCommandDispatchOwner.performCommand(for: event)
    }
}
