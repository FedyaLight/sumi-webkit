# Live folders boundary

Live folders are a real Zen feature, but they are not part of Aura's first core
shell rewrite.

This document exists so they do not accidentally leak into normal folders as
hidden behavior.

## Current decision

For the first Aura shell pass:

- normal folders are static organizational nodes
- live folders are out of scope
- no hidden feed logic, refresh logic, or remote data fetching should live
  inside normal folder models

## Why this boundary matters

Zen's release notes show that live folders bring their own compatibility and
fetching issues. That means they deserve:

- their own service owner
- their own persistence rules
- their own refresh and failure policy
- their own UI affordances

Folding this into normal folders would recreate the exact kind of tightly
coupled behavior Aura is trying to avoid.

## Future requirements for adopting live folders

Aura can adopt live folders later only if they arrive as a first-class feature
with:

- a dedicated `AuraLiveFoldersService` or equivalent owner
- explicit persisted node type, separate from normal folder semantics
- explicit refresh triggers and caching rules
- clear degraded behavior when feed or remote sources fail
- explicit performance budget for refresh activity

## Current shell guarantees

- folder drag and reorder logic stays generic and feed-agnostic
- restore logic treats all current folders as static folders only
- menu and sidebar behavior do not expose live-folder-only affordances yet

## Anti-pattern

Do not add booleans like `is_live_folder` to the normal folder model as a quick
shortcut. If Aura adopts live folders, it should do so through a separate model
and service boundary.
