# Space Theme Swipe Pipeline

This is the intended ownership model for workspace switching and workspace-theme updates.

## Owners

- `SidebarSwipeCaptureSurface.swift`
Captures horizontal scroll/swipe events at the sidebar edge.
- `SpaceSwipeGestureTracker.swift`
Normalizes live swipe progress before sidebar transition state updates.
- `SpacesSideBarView.swift`
Translates swipe events into window-local interactive workspace transitions.
- `WorkspaceThemeCoordinator.swift`
Owns committed theme, interactive preview theme, and transition progress.
- `BrowserManager.setActiveSpace(...)`
Commits the selected workspace and tab. It does not synthesize late theme previews.

## Rules

- Live swipe preview must begin from gesture progress, not from final space selection.
- Committing the selected space must not create a second theme transition.
- Browser chrome reads `ResolvedThemeContext`; it should not depend on workspace-specific `colorScheme` injection.
- Global `System / Light / Dark` appearance remains independent from workspace color styling.

## Anti-patterns to avoid

- Synthesizing an interactive theme transition only after the space selection already changed.
- Injecting a discrete workspace `colorScheme` into the whole chrome tree.
- Mixing multiple swipe progress sources without a single normalization step.
- Letting page-derived colors participate in workspace chrome theme selection.
