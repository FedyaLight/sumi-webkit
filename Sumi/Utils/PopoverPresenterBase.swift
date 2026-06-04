import AppKit
import SwiftUI

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
        duration: TimeInterval,
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
}
