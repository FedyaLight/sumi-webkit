import AppKit
import SwiftUI

enum PopoverPresenterMetrics {
    static let closeAnimationFallbackDelay: UInt64 = 350_000_000
    static let resizeAnimationDuration: TimeInterval = 0.18
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
        from startSize: NSSize,
        to targetSize: NSSize,
        duration: TimeInterval = PopoverPresenterMetrics.resizeAnimationDuration,
        animationTask: inout Task<Void, Never>?
    ) {
        guard popover.contentSize != targetSize else { return }
        animationTask?.cancel()
        PopoverContentSizeAnimator.animate(
            popover: popover,
            from: startSize,
            to: targetSize,
            duration: duration,
            animationTask: &animationTask
        )
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
