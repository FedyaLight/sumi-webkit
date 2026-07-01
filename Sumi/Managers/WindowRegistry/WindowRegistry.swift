//
//  WindowRegistry.swift
//  Sumi
//
//  Tracks window states for cross-window coordination and command routing
//

import AppKit
import Foundation
import Observation
import SwiftUI

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

    /// Callback when an AppKit window visibility signal changes.
    @ObservationIgnored
    var onWindowVisibilityChange: ((BrowserWindowState) -> Void)?

    /// Called after the last window is removed from the registry (e.g. to reset single global session restore).
    @ObservationIgnored
    var onAllWindowsClosed: (() -> Void)?

    @ObservationIgnored
    var keyAppKitWindowProvider: () -> NSWindow? = { NSApp.keyWindow }

    @ObservationIgnored
    var mainAppKitWindowProvider: () -> NSWindow? = { NSApp.mainWindow }

    private static let defaultRegistrationTimeoutNanoseconds: UInt64 = 2_000_000_000

    /// Register a new window
    func register(_ window: BrowserWindowState) {
        let wasRegistered = windows[window.id] != nil
        windows[window.id] = window

        if wasRegistered == false {
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
            if activeWindowId == window.id {
                onActiveWindowChange?(window)
            }
            RuntimeDiagnostics.emit {
                "🪟 [WindowRegistry] Registered window: \(window.id)"
            }
        }
    }

    /// Unregister a window when it closes
    func unregister(_ id: UUID) {
        guard windows[id] != nil else {
            RuntimeDiagnostics.emit {
                "🪟 [WindowRegistry] Ignored duplicate unregister for window: \(id)"
            }
            return
        }

        // Call cleanup callback if set
        onWindowClose?(id)

        windows.removeValue(forKey: id)

        if windows.isEmpty {
            onAllWindowsClosed?()
        }

        // AppKit focus/key-window state owns active-window selection. Closing
        // the active window may only promote a surviving window AppKit already
        // reports as key/main; otherwise wait for the next didBecomeKey signal.
        if activeWindowId == id {
            if let focusedWindow = focusedRegisteredWindow() {
                activeWindowId = focusedWindow.id
                onActiveWindowChange?(focusedWindow)
            } else {
                activeWindowId = nil
            }
        }

        RuntimeDiagnostics.emit {
            "🪟 [WindowRegistry] Unregistered window: \(id)"
        }
    }

    /// Set the active (focused) window
    func setActive(_ window: BrowserWindowState) {
        guard let registeredWindow = windows[window.id] else {
            activeWindowId = window.id
            RuntimeDiagnostics.emit {
                "🪟 [WindowRegistry] Pending active window: \(window.id)"
            }
            return
        }

        guard registeredWindow === window else {
            RuntimeDiagnostics.emit {
                "🪟 [WindowRegistry] Ignored active window change for stale window object: \(window.id)"
            }
            return
        }

        activeWindowId = registeredWindow.id
        onActiveWindowChange?(registeredWindow)
        RuntimeDiagnostics.emit {
            "🪟 [WindowRegistry] Active window: \(registeredWindow.id)"
        }
    }

    func notifyWindowVisibilityChanged(_ window: BrowserWindowState) {
        onWindowVisibilityChange?(window)
    }

    private func focusedRegisteredWindow() -> BrowserWindowState? {
        for appKitWindow in [keyAppKitWindowProvider(), mainAppKitWindowProvider()].compactMap(\.self) {
            if let windowState = windowState(containing: appKitWindow) {
                return windowState
            }
        }
        return nil
    }

    /// Get all windows as an array
    var allWindows: [BrowserWindowState] {
        Array(windows.values)
    }

    func windowState(containing appKitWindow: NSWindow) -> BrowserWindowState? {
        windows.values.first { state in
            guard let browserWindow = state.window else { return false }
            if browserWindow === appKitWindow {
                return true
            }
            return browserWindow.childWindows?.contains(where: { $0 === appKitWindow }) == true
        }
    }

    func awaitNextRegisteredWindow(
        excluding existingWindowIDs: Set<UUID>,
        timeoutNanoseconds: UInt64 = defaultRegistrationTimeoutNanoseconds
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

                guard timeoutNanoseconds > 0 else { return }
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                    guard !Task.isCancelled,
                          let awaiter = self?.windowAwaiters.removeValue(forKey: awaiterID)
                    else {
                        return
                    }
                    awaiter.continuation.resume(returning: nil)
                }
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
