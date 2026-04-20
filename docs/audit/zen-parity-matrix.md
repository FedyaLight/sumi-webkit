# Sumi Zen Parity Matrix

Last updated: 2026-04-02

## Ground Truth

- Zen behavior sources:
  - `src/zen/tests/{folders,glance,spaces,split_view,tabs,urlbar,window_sync}`
  - `src/zen/spaces/ZenSpace.mjs`
  - `src/zen/common/styles/zen-theme.css`
  - `src/zen/common/styles/zen-omnibox.css`
- Sumi implementation anchors:
  - `Sumi/Managers/BrowserManager/BrowserManager.swift`
  - `Sumi/Managers/TabManager/TabManager.swift`
  - `Sumi/Models/Tab/Tab.swift`

## Current Snapshot


| Domain                        | Zen Sources                        | Sumi Anchors                                                          | Parity  | Severity | Notes                                                                                                                         |
| ----------------------------- | ---------------------------------- | --------------------------------------------------------------------- | ------- | -------- | ----------------------------------------------------------------------------------------------------------------------------- |
| Tabs and empty state          | `tests/tabs/*`                     | `TabManager`, `BrowserManager`, `SpaceTab`                            | partial | P1       | Core flows mostly work, but close, empty-state and selection still mix old and new paths.                                     |
| Launcher lifecycle            | tabs and workspace pin behavior    | `TabManager`, `PinnedGrid`, `SpaceView`, `TabFolderView`              | partial | P1       | Essentials, space-pinned and folder launchers share one model, but legacy runtime reads still leak into counts and selection. |
| Folders                       | `tests/folders/*`                  | `TabFolderView`, `TabManager`                                         | partial | P1       | Folder launcher model exists; owner/live-folder and reset parity are still missing.                                           |
| Spaces                        | `tests/spaces/*`                   | `SpacesSideBarView`, `SpacesList`, `BrowserManager`                   | partial | P1       | Switching works, but some chrome surfaces still bypass the theme token source.                                                |
| Floating URL bar              | `tests/urlbar/*`                   | `CommandPaletteView`                                                  | partial | P1       | Core behavior works, but there is no automated regression coverage for click-through, focus and draft restore.                |
| Glance                        | `tests/glance/*`                   | `Tab`, `PeekManager`, `PeekOverlayView`                               | partial | P1       | Trigger and overlay exist; close, select-parent and split handoff need repeatable smoke coverage.                             |
| Split view                    | `tests/split_view/*`               | `SplitViewManager`, `WebsiteView`, `SpaceView`                        | partial | P1       | Core 2-pane split works, but split plus launcher/folder/glance interactions remain high-risk.                                 |
| Theme and chrome              | `zen-theme.css`, `zen-omnibox.css` | `Colors`, `WindowView`, `SpaceGradientBackgroundView`, sidebar/topbar | partial | P1       | Token layer exists, but multiple surfaces still branch off gradient brightness or direct colors.                              |
| Window sync / session restore | `tests/window_sync/*`              | `BrowserManager`, `WindowSessionModels`, `BrowserWindowState`         | partial | P2       | Restore logic exists, but multi-window drift is not under regression coverage.                                                |
| Missing Zen parity backlog    | all above                          | multiple                                                              | missing | P2       | Several Zen-tested behaviors are still absent or only partially implemented.                                                  |


## Missing or Incomplete Zen Parity Backlog


| Zen Area                                              | Status in Sumi | Notes                                                                                                                            |
| ----------------------------------------------------- | -------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| Folder owner/live-folder behavior                     | missing        | Zen has dedicated tests for owner tabs, live folders, visibility and reset cases.                                                |
| Workspace bookmarks and double-click new-tab behavior | missing        | Zen has explicit workspace bookmark and double-click new-tab scenarios; Sumi has no matching behavior yet.                       |
| Window sync parity                                    | missing        | Zen has dedicated `window_sync` tests; Sumi currently relies on ad hoc state restoration.                                        |
| Full floating URL bar regression set                  | partial        | Sumi implements floating URL bar but lacks parity checks for non-floating click path and selection semantics.                    |
| Split plus folder/glance combination coverage         | partial        | Zen has dedicated tests for split with folders and split with glance; Sumi has implementation but no stable regression baseline. |


## Audit Conventions

- `present`: behavior exists and matches Zen closely enough that only regression coverage is needed.
- `partial`: behavior exists but differs from Zen or mixes multiple state models.
- `missing`: behavior is not implemented or exists only as stub/TODO.
- Severity:
  - `P1`: core browsing/state-machine risk
  - `P2`: parity gap or predictable logic mismatch
  - `P3`: visual/polish backlog