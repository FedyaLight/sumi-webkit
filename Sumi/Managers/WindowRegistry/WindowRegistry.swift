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
    enum RegistrationResult: Equatable {
        case registered
        case alreadyRegistered
        case rejectedIdentityConflict
        case rejectedDuringPublication
    }

    private struct WindowAwaiter {
        let existingWindowIDs: Set<UUID>
        let continuation: CheckedContinuation<BrowserWindowState?, Never>
    }

    /// All registered window states (ignored from observation to avoid actor isolation issues)
    @ObservationIgnored
    private var _windows: [UUID: BrowserWindowState] = [:]

    /// Window models being synchronously restored and validated. They are not
    /// externally discoverable until `commitRegistration` moves the exact
    /// object into `_windows`.
    @ObservationIgnored
    private var provisionalWindows: [UUID: BrowserWindowState] = [:]

    @ObservationIgnored
    private var windowAwaiters: [UUID: WindowAwaiter] = [:]

    /// Phase 6A: AppKit NSWindow handles keyed by window id (weak). SoT for shell lookup.
    @ObservationIgnored
    private var shells: [UUID: BrowserWindowShell] = [:]

    var windows: [UUID: BrowserWindowState] {
        _windows
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
    var onWindowClose: ((BrowserWindowState) -> Void)?

    /// Callback for post-registration setup (e.g., setting TabManager reference)
    @ObservationIgnored
    var prepareWindowRegistration: ((BrowserWindowState) -> Void)?

    /// Callback after a prepared window has passed validation and entered the
    /// public registry. Extension lifecycle publication belongs here, not in
    /// the provisional restoration callback above.
    @ObservationIgnored
    var publishWindowRegistration: ((BrowserWindowState) -> Void)?

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
    @discardableResult
    func register(_ window: BrowserWindowState) -> RegistrationResult {
        let result = beginRegistration(window)
        guard result == .registered else { return result }
        return commitRegistration(window)
            ? .registered
            : .rejectedDuringPublication
    }

    /// Makes the exact model available only to the synchronous restoration
    /// transaction. Awaiters, extension observers, and normal registry reads
    /// cannot observe this provisional state.
    @discardableResult
    func beginRegistration(_ window: BrowserWindowState) -> RegistrationResult {
        if let registeredWindow = _windows[window.id]
            ?? provisionalWindows[window.id] {
            guard registeredWindow !== window else {
                return .alreadyRegistered
            }
            RuntimeDiagnostics.emit {
                "🪟 [WindowRegistry] Rejected different window object with registered id: \(window.id)"
            }
            return .rejectedIdentityConflict
        }

        provisionalWindows[window.id] = window
        prepareWindowRegistration?(window)
        return .registered
    }

    /// Atomically publishes one exact prepared object. Publication callbacks
    /// run before awaiters resume, so a consumer can never receive a window
    /// whose extension lifecycle has not yet been committed.
    @discardableResult
    func commitRegistration(
        _ window: BrowserWindowState,
        validatePublication: @MainActor (BrowserWindowState) -> Bool = { _ in true }
    ) -> Bool {
        guard provisionalWindows[window.id] === window,
              _windows[window.id] == nil
        else {
            return false
        }

        provisionalWindows.removeValue(forKey: window.id)
        _windows[window.id] = window
        publishWindowRegistration?(window)
        guard _windows[window.id] === window,
              validatePublication(window),
              _windows[window.id] === window
        else {
            // A synchronous publication callback may reject or close the exact
            // object. Do not resume awaiters or activation observers with a
            // half-committed registration.
            if _windows[window.id] === window {
                _windows.removeValue(forKey: window.id)
                unbindAppKitWindow(for: window.id)
                if activeWindowId == window.id {
                    activeWindowId = nil
                }
            }
            return false
        }
        let matchingAwaiterIDs = windowAwaiters.compactMap { entry in
            entry.value.existingWindowIDs.contains(window.id) ? nil : entry.key
        }
        for awaiterID in matchingAwaiterIDs {
            guard let awaiter = windowAwaiters.removeValue(forKey: awaiterID) else {
                continue
            }
            awaiter.continuation.resume(returning: window)
        }

        if activeWindowId == window.id {
            onActiveWindowChange?(window)
        }
        RuntimeDiagnostics.emit {
            "🪟 [WindowRegistry] Registered window: \(window.id)"
        }
        return true
    }

    /// Unregister a window when it closes
    func unregister(_ id: UUID) {
        guard let closingWindow = windows[id] else {
            RuntimeDiagnostics.emit {
                "🪟 [WindowRegistry] Ignored duplicate unregister for window: \(id)"
            }
            return
        }

        let wasActive = activeWindowId == id
        _windows.removeValue(forKey: id)
        unbindAppKitWindow(for: id)
        if wasActive {
            activeWindowId = nil
        }

        // External cleanup observes the window as already detached. Reentrant
        // unregister therefore cannot duplicate close/all-windows callbacks.
        onWindowClose?(closingWindow)

        if windows.isEmpty {
            onAllWindowsClosed?()
        }

        // AppKit focus/key-window state owns active-window selection. Closing
        // the active window may only promote a surviving window AppKit already
        // reports as key/main; otherwise wait for the next didBecomeKey signal.
        if wasActive, activeWindowId == nil {
            if let focusedWindow = focusedRegisteredWindow() {
                activeWindowId = focusedWindow.id
                onActiveWindowChange?(focusedWindow)
            }
        }

        RuntimeDiagnostics.emit {
            "🪟 [WindowRegistry] Unregistered window: \(id)"
        }
    }

    /// Cancels only the exact model that has not crossed the publication
    /// boundary. A committed window must leave through `unregister(_:)` so its
    /// close, extension, focus, and all-windows-closed lifecycles stay balanced.
    @discardableResult
    func rollbackProvisionalRegistration(
        _ window: BrowserWindowState
    ) -> Bool {
        guard provisionalWindows[window.id] === window else {
            return false
        }
        provisionalWindows.removeValue(forKey: window.id)
        unbindAppKitWindow(for: window.id)
        if activeWindowId == window.id {
            activeWindowId = nil
        }
        return true
    }

    /// Rejects one exact registration regardless of whether it is still
    /// provisional or has just crossed publication. Committed state leaves
    /// through normal unregister lifecycle; an object sharing only the UUID
    /// can never discard the registered model.
    @discardableResult
    func discardRejectedRegistration(
        _ window: BrowserWindowState
    ) -> Bool {
        if rollbackProvisionalRegistration(window) {
            return true
        }
        guard windows[window.id] === window else { return false }
        unregister(window.id)
        return true
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

        guard activeWindowId != registeredWindow.id else { return }

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

    /// Binds the AppKit window into the shell map (sole SoT for AppKit window handles).
    func bindAppKitWindow(_ window: NSWindow?, to windowState: BrowserWindowState) {
        bindAppKitWindow(window, for: windowState.id)
    }

    func bindAppKitWindow(_ window: NSWindow?, for windowId: UUID) {
        if let shell = shells[windowId] {
            shell.window = window
            if window == nil {
                shells.removeValue(forKey: windowId)
            }
            return
        }
        guard let window else { return }
        shells[windowId] = BrowserWindowShell(windowId: windowId, window: window)
    }

    func unbindAppKitWindow(for windowId: UUID) {
        shells.removeValue(forKey: windowId)
    }

    /// AppKit window lookup from the shell map.
    func appKitWindow(for windowId: UUID) -> NSWindow? {
        shells[windowId]?.window
    }

    func appKitWindow(for windowState: BrowserWindowState) -> NSWindow? {
        appKitWindow(for: windowState.id)
    }

    func windowState(containing appKitWindow: NSWindow) -> BrowserWindowState? {
        windows.values.first { state in
            guard let browserWindow = self.appKitWindow(for: state) else { return false }
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
