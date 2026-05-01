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
    static let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
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
    static var didApplyInitialShellSize: UInt8 = 0
}

extension NSWindow {
    @MainActor
    func applyBrowserChromeConfiguration() {
        styleMask = styleMask.union(SumiBrowserChromeConfiguration.requiredStyleMask)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        titlebarSeparatorStyle = .none
        toolbar = nil
        hideNativeStandardWindowButtonsForBrowserChrome()
    }

    @MainActor
    func applyBrowserWindowShellConfiguration(shouldApplyInitialSize: Bool) {
        backgroundColor = SumiBrowserWindowShellConfiguration.backgroundColor
        isOpaque = SumiBrowserWindowShellConfiguration.isOpaque
        collectionBehavior.insert(.fullScreenPrimary)
        contentView?.wantsLayer = true
        contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        contentView?.layer?.isOpaque = false
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
            (objc_getAssociatedObject(self, &SumiBrowserWindowAssociatedKeys.didApplyInitialShellSize) as? Bool)
                ?? false
        }
        set {
            objc_setAssociatedObject(
                self,
                &SumiBrowserWindowAssociatedKeys.didApplyInitialShellSize,
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

    /// No Touch Bar for browser windows. This custom chrome path has previously hit
    /// `_NSTouchBarFinderObservation` KVO faults during panel and window teardown.
    override func makeTouchBar() -> NSTouchBar? {
        nil
    }

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let didChange = super.makeFirstResponder(responder)
        if didChange {
            NotificationCenter.default.post(name: Self.firstResponderDidChangeNotification, object: self)
        }
        return didChange
    }

    // Adapted from DuckDuckGo MainWindow.keyDown:
    // To avoid beep sounds, route keyDown through performKeyEquivalent so the menu chain runs like Safari.
    override func keyDown(with event: NSEvent) {
        if isFindInPageCmdF(event) {
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

@MainActor
extension NSWindow {
    func hideNativeStandardWindowButtonsForBrowserChrome(
        buttonTypes: [NSWindow.ButtonType] = SumiBrowserChromeConfiguration.buttonTypes
    ) {
        for type in buttonTypes {
            guard let button = standardWindowButton(type) else { continue }
            button.identifier = nil
            button.setAccessibilityIdentifier(nil)
            applyNativeStandardWindowButtonState(button, isVisible: false)
        }
    }

    /// MiniWindow intentionally remains on AppKit's native titlebar-button path.
    /// Browser windows call `hideNativeStandardWindowButtonsForBrowserChrome()`
    /// and render `BrowserWindowTrafficLights` instead.
    func configureNativeStandardWindowButtonsForMiniWindowChrome(
        buttonTypes: [NSWindow.ButtonType] = SumiBrowserChromeConfiguration.buttonTypes
    ) {
        for type in buttonTypes {
            guard let button = standardWindowButton(type) else { continue }
            if let identifier = BrowserWindowControlsAccessibilityIdentifiers.identifier(for: type) {
                button.identifier = NSUserInterfaceItemIdentifier(identifier)
                button.setAccessibilityIdentifier(identifier)
            }
            applyNativeStandardWindowButtonState(button, isVisible: true)
        }
    }

    private func applyNativeStandardWindowButtonState(_ button: NSButton, isVisible: Bool) {
        button.wantsLayer = true
        button.layer?.removeAllAnimations()
        button.superview?.layer?.removeAllAnimations()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            button.layer?.opacity = isVisible ? 1 : 0
            button.isTransparent = !isVisible
            if isVisible == false {
                button.frame = parkedNativeStandardWindowButtonFrame(for: button)
            }
            button.alphaValue = isVisible ? 1 : 0
            button.isHidden = !isVisible
            button.isEnabled = isVisible
            button.setAccessibilityElement(isVisible)
        }

        button.updateTrackingAreas()
        button.needsDisplay = true
        if let superview = button.superview {
            superview.updateTrackingAreas()
            superview.needsDisplay = true
            if isVisible {
                superview.needsLayout = true
            }
            invalidateCursorRects(for: superview)
        }
    }

    private func parkedNativeStandardWindowButtonFrame(for button: NSButton) -> NSRect {
        var frame = button.frame
        frame.origin.x = -10_000 - frame.width
        return frame
    }
}
