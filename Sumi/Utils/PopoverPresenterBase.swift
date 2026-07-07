import AppKit
import SwiftUI

enum PopoverPresenterMetrics {
    static let closeAnimationFallbackDelay: UInt64 = 350_000_000
}

@MainActor
enum PopoverPresenterChromeSupport {
    static func appearance(
        for colorScheme: ColorScheme,
        fallback: NSAppearance?
    ) -> NSAppearance {
        NSAppearance.sumiChromeAppearance(
            for: colorScheme,
            fallback: fallback
        )
    }

    /// Native-surface scheme for popovers anchored to a view: the space theme
    /// when known, otherwise the anchor window's (or app's) appearance.
    static func nativeSurfaceColorScheme(
        themeContext: ResolvedThemeContext?,
        anchorView: NSView?
    ) -> ColorScheme {
        if let themeContext {
            return themeContext.nativeSurfaceColorScheme
        }
        return ColorScheme(
            sumiChromeAppearance: anchorView?.window?.effectiveAppearance
                ?? NSApplication.shared.effectiveAppearance
        )
    }

    static func themeContext(
        _ context: ResolvedThemeContext,
        colorScheme: ColorScheme
    ) -> ResolvedThemeContext {
        var updated = context
        updated.globalColorScheme = colorScheme
        updated.chromeColorScheme = colorScheme
        updated.sourceChromeColorScheme = colorScheme
        updated.targetChromeColorScheme = colorScheme
        updated.sourceWorkspaceTheme = context.workspaceTheme
        updated.targetWorkspaceTheme = context.workspaceTheme
        updated.isInteractiveTransition = false
        updated.transitionProgress = 1.0
        return updated
    }

    static func animateContentSize(
        popover: NSPopover,
        to targetSize: NSSize
    ) {
        guard popover.contentSize != targetSize else { return }
        popover.contentSize = targetSize
    }

    static func isAnchorViewReady(
        _ anchorView: NSView,
        checkHiddenAncestors: Bool
    ) -> Bool {
        guard anchorView.window != nil, anchorView.alphaValue > 0 else {
            return false
        }
        if checkHiddenAncestors {
            return !anchorView.isHiddenOrHasHiddenAncestor
        }
        return !anchorView.isHidden
    }

    static func scheduleCloseFallback(
        task: inout Task<Void, Never>?,
        onTimeout: @escaping @MainActor () -> Void
    ) {
        task?.cancel()
        task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: PopoverPresenterMetrics.closeAnimationFallbackDelay)
            guard !Task.isCancelled else { return }
            onTimeout()
        }
    }

    static func closePopoverWithFallback(
        popover: NSPopover,
        closeFallbackTask: inout Task<Void, Never>?,
        onFallback: @escaping @MainActor () -> Void,
        onNotShown: @escaping @MainActor () -> Void
    ) {
        if popover.isShown {
            popover.close()
            scheduleCloseFallback(task: &closeFallbackTask, onTimeout: onFallback)
        } else {
            onNotShown()
        }
    }
}
