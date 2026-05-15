# Sidebar split-view spike

## Result

`NavigationSplitView` remains the native reference for column semantics, but it is not a safe replacement for the current docked shell yet:

- Sumi supports both left and right sidebar positions, while the native split-view model is leading-column oriented.
- Full-window transient chrome intentionally sits outside content columns.
- Traffic-light ownership, drag geometry, and the current theme pipeline are shell-level concerns that would need extra duplication around a split view.

## Decision

Keep the cleaned manual shell for this iteration. Reopen a migration only if a future prototype preserves:

1. left/right sidebar parity;
2. full-window overlay behavior;
3. titlebar controls;
4. drag geometry;
5. the branded theme pipeline.
