//
//  WindowRegistry.swift
//  Sumi
//
//  Tracks window states for cross-window coordination and command routing
//

import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
class WindowRegistry {
    private struct WindowAwaiter {
        let existingWindowIDs: Set<UUID>
        let continuation: CheckedContinuation<BrowserWindowState?, Never>
    }

    /// All registered window states (ignored from observation to avoid actor isolation issues)
    @ObservationIgnored
    private var _windows: [UUID: BrowserWindowState] = [:]

    @ObservationIgnored
    private var windowAwaiters: [UUID: WindowAwaiter] = [:]

    var windows: [UUID: BrowserWindowState] {
        get { _windows }
        set { _windows = newValue }
    }

    /// ID of the currently focused window (the only thing we actually observe)
    var activeWindowId: UUID?

    /// The currently focused window state (computed, not observed)
    var activeWindow: BrowserWindowState? {
        guard let id = activeWindowId else { return nil }
        return _windows[id]
    }

    /// Callback for window cleanup (set by whoever needs to clean up resources)
    @ObservationIgnored
    var onWindowClose: ((UUID) -> Void)?

    /// Callback for post-registration setup (e.g., setting TabManager reference)
    @ObservationIgnored
    var onWindowRegister: ((BrowserWindowState) -> Void)?

    /// Callback when active window changes
    @ObservationIgnored
    var onActiveWindowChange: ((BrowserWindowState) -> Void)?

    /// Called after the last window is removed from the registry (e.g. to reset single global session restore).
    @ObservationIgnored
    var onAllWindowsClosed: (() -> Void)?

    /// Register a new window
    func register(_ window: BrowserWindowState) {
        windows[window.id] = window

        let matchingAwaiterIDs = windowAwaiters.compactMap { entry in
            entry.value.existingWindowIDs.contains(window.id) ? nil : entry.key
        }
        for awaiterID in matchingAwaiterIDs {
            guard let awaiter = windowAwaiters.removeValue(forKey: awaiterID) else {
                continue
            }
            awaiter.continuation.resume(returning: window)
        }

        onWindowRegister?(window)
        RuntimeDiagnostics.emit {
            "🪟 [WindowRegistry] Registered window: \(window.id)"
        }
    }

    /// Unregister a window when it closes
    func unregister(_ id: UUID) {
        // Call cleanup callback if set
        onWindowClose?(id)

        windows.removeValue(forKey: id)

        if windows.isEmpty {
            onAllWindowsClosed?()
        }

        // If this was the active window, switch to another
        if activeWindowId == id {
            activeWindowId = windows.keys.first
        }

        RuntimeDiagnostics.emit {
            "🪟 [WindowRegistry] Unregistered window: \(id)"
        }
    }

    /// Set the active (focused) window
    func setActive(_ window: BrowserWindowState) {
        activeWindowId = window.id
        onActiveWindowChange?(window)
        RuntimeDiagnostics.emit {
            "🪟 [WindowRegistry] Active window: \(window.id)"
        }
    }

    /// Get all windows as an array
    var allWindows: [BrowserWindowState] {
        Array(windows.values)
    }

    func awaitNextRegisteredWindow(
        excluding existingWindowIDs: Set<UUID>
    ) async -> BrowserWindowState? {
        if let existingWindow = windows.values.first(where: {
            existingWindowIDs.contains($0.id) == false
        }) {
            return existingWindow
        }

        let awaiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                windowAwaiters[awaiterID] = WindowAwaiter(
                    existingWindowIDs: existingWindowIDs,
                    continuation: continuation
                )
            }
        } onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                guard let awaiter = self?.windowAwaiters.removeValue(forKey: awaiterID) else {
                    return
                }
                awaiter.continuation.resume(returning: nil)
            }
        }
    }
}
