# Workspace Theme Surface Model

## Goal

Ensure runtime theme, theme preview, and chrome token resolution all flow through one workspace-theme owner.

## Owners

- `WorkspaceThemeCoordinator.swift`
Owns committed workspace theme, preview theme, and interactive transition state.
- `ResolvedThemeContext.swift`
Exposes the resolved chrome scheme and blended token inputs for the current window state.
- `ChromeThemeTokens.swift`
Produces the concrete chrome colors used by browser-owned surfaces.

## Rules

- Theme picker preview and runtime theme switching use the same coordinator.
- Browser chrome consumes resolved theme tokens, not page-derived colors.
- Global app appearance remains independent from workspace color styling.
- Space switching updates workspace theme through the interactive transition path only.

## Anti-patterns to avoid

- Separate editor-only owners that paint window chrome independently from the runtime coordinator.
- Late post-commit theme refreshes after a space switch already completed.
- Reading workspace theme directly from multiple managers instead of through resolved window theme state.