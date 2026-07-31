//
//  SumiBrowserWindow.swift
//  Sumi
//
//  Portions adapted from DuckDuckGo for macOS (MainWindow.keyDown), used under the Apache License, Version 2.0.
//  Copyright © 2020 DuckDuckGo. All rights reserved.
//  See: https://www.apache.org/licenses/LICENSE-2.0
//

import AppKit
import ObjectiveC.runtime

enum SumiBrowserChromeConfiguration {
    static let requiredStyleMask: NSWindow.StyleMask = [
        .titled,
        .closable,
        .miniaturizable,
        .resizable,
        .fullSizeContentView,
    ]
}

enum SumiBrowserWindowShellConfiguration {
    static let defaultContentSize = NSSize(width: 1320, height: 820)
    static let minimumContentSize = NSSize(width: 470, height: 382)
    static let backgroundColor = NSColor.clear
    static let isOpaque = false
    static let isReleasedWhenClosed = false
    static let isMovable = true

    @MainActor
    static func minimumFrameSize(for window: NSWindow) -> NSSize {
        window.frameRect(forContentRect: NSRect(origin: .zero, size: minimumContentSize)).size
    }
}

@MainActor
func promoteToSumiBrowserWindowIfNeeded(_ window: NSWindow) {
    // Do not class-swap SwiftUI-created windows. AppKit's titlebar/fullscreen
    // internals install private KVO before this bridge attaches, and changing
    // the class afterward can leave fullscreen transition observers corrupted.
    window.applyBrowserChromeConfiguration()
    window.applyBrowserWindowShellConfiguration(shouldApplyInitialSize: false)
}

private enum SumiBrowserWindowAssociatedKeys {
    static let didApplyInitialShellSize: UInt8 = 0

    static var didApplyInitialShellSizePointer: UnsafeRawPointer {
        withUnsafePointer(to: didApplyInitialShellSize) { UnsafeRawPointer($0) }
    }
}

extension NSWindow {
    @MainActor
    func applyBrowserChromeConfiguration() {
        styleMask = styleMask.union(SumiBrowserChromeConfiguration.requiredStyleMask)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        titlebarSeparatorStyle = .none
        toolbar = nil
        browserTrafficLightPlacement.reapply()
    }

    @MainActor
    func applyBrowserWindowShellConfiguration(shouldApplyInitialSize: Bool) {
        backgroundColor = SumiBrowserWindowShellConfiguration.backgroundColor
        isOpaque = SumiBrowserWindowShellConfiguration.isOpaque
        collectionBehavior.insert(.fullScreenPrimary)
        isReleasedWhenClosed = SumiBrowserWindowShellConfiguration.isReleasedWhenClosed
        isMovable = SumiBrowserWindowShellConfiguration.isMovable
        contentMinSize = SumiBrowserWindowShellConfiguration.minimumContentSize
        minSize = SumiBrowserWindowShellConfiguration.minimumFrameSize(for: self)

        guard shouldApplyInitialSize, hasAppliedInitialBrowserShellSize == false else {
            return
        }

        setContentSize(SumiBrowserWindowShellConfiguration.defaultContentSize)
        center()
        hasAppliedInitialBrowserShellSize = true
    }

    private var hasAppliedInitialBrowserShellSize: Bool {
        get {
            (objc_getAssociatedObject(self, SumiBrowserWindowAssociatedKeys.didApplyInitialShellSizePointer) as? Bool)
                ?? false
        }
        set {
            objc_setAssociatedObject(
                self,
                SumiBrowserWindowAssociatedKeys.didApplyInitialShellSizePointer,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
}

final class SumiBrowserWindow: NSWindow {
    static let firstResponderDidChangeNotification = Notification.Name("SumiBrowserWindow.firstResponderDidChange")

    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing bufferingType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: styleMask.union(.fullSizeContentView),
            backing: bufferingType,
            defer: flag
        )
        applyBrowserChromeConfiguration()
        applyBrowserWindowShellConfiguration(shouldApplyInitialSize: false)
    }

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        defer {
            NotificationCenter.default.post(name: Self.firstResponderDidChangeNotification, object: self)
        }
        return super.makeFirstResponder(responder)
    }

    // Adapted from DuckDuckGo MainWindow.keyDown:
    // Keep shortcut routing through the menu chain, while letting native text responders
    // receive ordinary key events so key repeat and text editing behave normally.
    override func keyDown(with event: NSEvent) {
        if isFindInPageCmdF(event) {
            super.keyDown(with: event)
            return
        }

        let shortcutModifiers = event.modifierFlags.intersection([.command, .control, .option])
        if shortcutModifiers.isEmpty {
            super.keyDown(with: event)
            return
        }

        _ = super.performKeyEquivalent(with: event)
    }

    /// Match "Find in Page" when Cmd+F is pressed so WebKit can still emit the expected beep when find is unavailable.
    private func isFindInPageCmdF(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
        guard flags == [.command] else { return false }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        return key == "f"
    }
}
