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

    /// Immutable application lifecycle boundary installed once by the app
    /// composition root. Event order is part of the registry contract:
    /// prepare precedes public registration, publish precedes awaiter/focus
    /// delivery, close observes an already-detached window, all-windows-closed
    /// follows close, and any focused-window promotion is delivered last.
    struct EventSink {
        let prepareWindowRegistration: @MainActor (BrowserWindowState) -> Void
        let publishWindowRegistration: @MainActor (BrowserWindowState) -> Void
        let closeWindow: @MainActor (BrowserWindowState) -> Void
        let activateWindow: @MainActor (BrowserWindowState) -> Void
        let changeWindowVisibility: @MainActor (BrowserWindowState) -> Void
        let closeAllWindows: @MainActor () -> Void
    }

    struct EventSinkInstallationReceipt: Equatable {
        fileprivate let registryIdentity: ObjectIdentifier

        func belongs(to registry: WindowRegistry) -> Bool {
            registryIdentity == ObjectIdentifier(registry)
        }
    }

    /// Exact authority for one committed physical window registration. A
    /// same-ID replacement receives a new generation, so stale UI cannot
    /// become current again through durable-identity ABA.
    struct WindowRegistrationReceipt: Equatable, Hashable {
        fileprivate let registryIdentity: ObjectIdentifier
        fileprivate let windowID: UUID
        fileprivate let windowIdentity: ObjectIdentifier
        fileprivate let generation: UInt64
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
    private var registrationReceipts: [UUID: WindowRegistrationReceipt] = [:]

    @ObservationIgnored
    private var nextRegistrationGeneration: UInt64 = 0

    @ObservationIgnored
    private var windowAwaiters: [UUID: WindowAwaiter] = [:]

    @ObservationIgnored
    private var eventSink: EventSink?

    @ObservationIgnored
    private var eventSinkInstallationReceipt: EventSinkInstallationReceipt?

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

    var canInstallEventSink: Bool {
        eventSink == nil
    }

    var hasInstalledEventSink: Bool {
        eventSink != nil
    }

    /// Installs the application lifecycle sink exactly once. A rejected second
    /// installation cannot replace any callback and returns no authority.
    @discardableResult
    func installEventSink(
        _ sink: EventSink
    ) -> EventSinkInstallationReceipt? {
        guard eventSink == nil else { return nil }
        let receipt = EventSinkInstallationReceipt(
            registryIdentity: ObjectIdentifier(self)
        )
        eventSink = sink
        eventSinkInstallationReceipt = receipt
        return receipt
    }

    func validatesEventSinkInstallation(
        _ receipt: EventSinkInstallationReceipt
    ) -> Bool {
        eventSinkInstallationReceipt == receipt && receipt.belongs(to: self)
    }

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
        eventSink?.prepareWindowRegistration(window)
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
        nextRegistrationGeneration &+= 1
        registrationReceipts[window.id] = WindowRegistrationReceipt(
            registryIdentity: ObjectIdentifier(self),
            windowID: window.id,
            windowIdentity: ObjectIdentifier(window),
            generation: nextRegistrationGeneration
        )
        eventSink?.publishWindowRegistration(window)
        guard _windows[window.id] === window,
              validatePublication(window),
              _windows[window.id] === window
        else {
            // A synchronous publication callback may reject or close the exact
            // object. Do not resume awaiters or activation observers with a
            // half-committed registration.
            if _windows[window.id] === window {
                _windows.removeValue(forKey: window.id)
                registrationReceipts.removeValue(forKey: window.id)
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
            eventSink?.activateWindow(window)
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
        registrationReceipts.removeValue(forKey: id)
        unbindAppKitWindow(for: id)
        if wasActive {
            activeWindowId = nil
        }

        // External cleanup observes the window as already detached. Reentrant
        // unregister therefore cannot duplicate close/all-windows callbacks.
        eventSink?.closeWindow(closingWindow)

        if windows.isEmpty {
            eventSink?.closeAllWindows()
        }

        // AppKit focus/key-window state owns active-window selection. Closing
        // the active window may only promote a surviving window AppKit already
        // reports as key/main; otherwise wait for the next didBecomeKey signal.
        if wasActive, activeWindowId == nil {
            if let focusedWindow = focusedRegisteredWindow() {
                activeWindowId = focusedWindow.id
                eventSink?.activateWindow(focusedWindow)
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
        eventSink?.activateWindow(registeredWindow)
        RuntimeDiagnostics.emit {
            "🪟 [WindowRegistry] Active window: \(registeredWindow.id)"
        }
    }

    func notifyWindowVisibilityChanged(_ window: BrowserWindowState) {
        eventSink?.changeWindowVisibility(window)
    }

    func registrationReceipt(
        for window: BrowserWindowState
    ) -> WindowRegistrationReceipt? {
        guard _windows[window.id] === window,
              let receipt = registrationReceipts[window.id],
              receipt.registryIdentity == ObjectIdentifier(self),
              receipt.windowIdentity == ObjectIdentifier(window)
        else { return nil }
        return receipt
    }

    func window(
        ifCurrent receipt: WindowRegistrationReceipt
    ) -> BrowserWindowState? {
        guard receipt.registryIdentity == ObjectIdentifier(self),
              registrationReceipts[receipt.windowID] == receipt,
              let window = _windows[receipt.windowID],
              ObjectIdentifier(window) == receipt.windowIdentity
        else { return nil }
        return window
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

    func unbindAppKitWindow(
        _ appKitWindow: NSWindow?,
        from windowState: BrowserWindowState
    ) {
        guard let appKitWindow,
              shells[windowState.id]?.window === appKitWindow
        else { return }
        shells.removeValue(forKey: windowState.id)
    }

    /// AppKit window lookup from the shell map.
    func appKitWindow(for windowId: UUID) -> NSWindow? {
        shells[windowId]?.window
    }

    func appKitWindow(for windowState: BrowserWindowState) -> NSWindow? {
        appKitWindow(for: windowState.id)
    }

    func windowState(forAppKitWindow appKitWindow: NSWindow) -> BrowserWindowState? {
        windows.values.first { state in
            self.appKitWindow(for: state) === appKitWindow
        }
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
