# Sumi Live Smoke Matrix

Use this with `[scripts/run_live_audit.sh](../../scripts/run_live_audit.sh)`.

## Result Format

For every scenario record:

- `scenario`
- `expected`
- `actual`
- `reproducibility`
- `severity`
- `parity status`

## Core Browsing

- Create a new tab from sidebar and keyboard.
- Open URL, search query, back, forward, reload.
- Close current tab, close last tab, confirm empty-state behavior.
- Open downloads, history and auth popup/login flow.

## Launcher Model

- Essentials: launcher-only -> open live -> backgrounded live -> selected live -> unload -> remove.
- Space-pinned: same state cycle as essentials.
- Folder launcher: move regular tab into folder, open it, close current page, reopen with one click.
- Verify hover affordance:
  - live launcher shows unload action
  - unopened launcher shows remove action.

## Drag and Drop

- Regular -> folder.
- Folder launcher -> top-level pinned.
- Pinned -> regular tail below `New Tab`.
- Essentials -> regular tabs.
- Same-container reorder for top-level pinned.
- Cross-container move during hover and while animations are still running.

## Floating URL Bar

- Open floating URL bar on empty state.
- Click outside the bar onto a tab/launcher and verify click-through behavior.
- Escape closes the bar without losing draft unexpectedly.
- Reopen and verify draft restore.

## Spaces and Theme

- Switch by bottom icon click.
- Switch by swipe if available.
- Verify cross-dissolve and no stray intermediate theme.
- Verify readability on:
  - toasts
  - dialogs
  - floating URL bar
  - status panel
  - sidebar hover/selected states.

## Glance and Split

- `Option+Click` opens Glance.
- `Open Link in Glance` from context menu uses same backend.
- Close Glance, promote to tab, send to split.
- Enter split, swap sides, toggle orientation, close left, close right.
- Verify split with launcher tab and split with folder launcher.

## Session and Multi-Window

- Restart with active regular tab.
- Restart with active launcher tab.
- Restart with active split session.
- Open second window and switch spaces independently.
- Verify no window-local state drift.

## Keyboard and Locale

- `Cmd+W` in English layout.
- `Cmd+W` in Russian layout.
- Launcher close/unload behavior through keyboard paths.

## Exit Criteria

- No `P0/P1` findings remain in core browsing, close flow, launcher lifecycle, Glance or split.
- All smoke scenarios have a recorded result.
- Every Zen domain has a `present/partial/missing` decision in the parity matrix.