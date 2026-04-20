# Aura smoke acceptance checklist

The deeper behavioral source of truth lives in:

- `/Users/fedaefimov/Downloads/Aura/Aura/docs/architecture/core-shell-overview.md`
- `/Users/fedaefimov/Downloads/Aura/Aura/docs/architecture/core-shell-interaction-model.md`
- `/Users/fedaefimov/Downloads/Aura/Aura/docs/architecture/core-shell-menu-matrix.md`
- `/Users/fedaefimov/Downloads/Aura/Aura/docs/architecture/core-shell-state-and-restore.md`
- `/Users/fedaefimov/Downloads/Aura/Aura/docs/architecture/core-shell-acceptance-matrix.md`
- `/Users/fedaefimov/Downloads/Aura/Aura/docs/architecture/core-shell-address-bar-compact-and-keyboard.md`
- `/Users/fedaefimov/Downloads/Aura/Aura/docs/architecture/urlbar-action-learner.md`
- `/Users/fedaefimov/Downloads/Aura/Aura/docs/architecture/sidebar-visual-model.md`
- `/Users/fedaefimov/Downloads/Aura/Aura/docs/architecture/empty-space-and-folder-runtime.md`
- `/Users/fedaefimov/Downloads/Aura/Aura/docs/architecture/panel-and-menu-surfaces.md`
- `/Users/fedaefimov/Downloads/Aura/Aura/docs/architecture/compact-mode-legal-state-matrix.md`
- `/Users/fedaefimov/Downloads/Aura/Aura/docs/architecture/blank-window-and-window-modes.md`
- `/Users/fedaefimov/Downloads/Aura/Aura/docs/architecture/ctrl-tab-panel-and-transient-surfaces.md`
- `/Users/fedaefimov/Downloads/Aura/Aura/docs/architecture/live-folders-boundary.md`
- `/Users/fedaefimov/Downloads/Aura/Aura/docs/architecture/space-switch-theme-and-media.md`
- `/Users/fedaefimov/Downloads/Aura/Aura/docs/architecture/media-card-visual-model.md`
- `/Users/fedaefimov/Downloads/Aura/Aura/docs/architecture/zen-split-view-parity.md`
- `/Users/fedaefimov/Downloads/Aura/Aura/docs/architecture/aura-customization-bundle.md`
- `/Users/fedaefimov/Downloads/Aura/Aura/docs/architecture/aura-settings-surface.md`
- `/Users/fedaefimov/Downloads/Aura/Aura/docs/architecture/aura-settings-information-architecture.md`
- `/Users/fedaefimov/Downloads/Aura/Aura/docs/architecture/zen-readiness-audit.md`
- `/Users/fedaefimov/Downloads/Aura/Aura/docs/architecture/zen-theme-picker-parity.md`
- `/Users/fedaefimov/Downloads/Aura/Aura/docs/architecture/zen-menu-panel-visual-parity.md`
- `/Users/fedaefimov/Downloads/Aura/Aura/docs/architecture/zen-glance-parity.md`
- `/Users/fedaefimov/Downloads/Aura/Aura/docs/architecture/zen-split-glance-sidebar-parity.md`
- `/Users/fedaefimov/Downloads/Aura/Aura/docs/architecture/zen-combinatorial-gap-audit.md`
- `/Users/fedaefimov/Downloads/Aura/Aura/docs/architecture/zen-github-issues-scenario-audit.md`
- `/Users/fedaefimov/Downloads/Aura/Aura/docs/architecture/zen-source-grounding.md`
- `/Users/fedaefimov/Downloads/Aura/Aura/docs/architecture/zen-launcher-parity.md`
- `/Users/fedaefimov/Downloads/Aura/Aura/docs/architecture/zen-component-map.md`
- `/Users/fedaefimov/Downloads/Aura/Aura/docs/architecture/zen-test-grounded-shell-behaviors.md`
- `/Users/fedaefimov/Downloads/Aura/Aura/docs/architecture/zen-release-notes-scenario-audit.md`

## Core

- first launch opens a real Helium-based Aura window, not plain Helium chrome
- spaces switch in one window
- folders reorder correctly across nested levels
- essentials stay live in original profile until closed
- glance and split behaviors follow the frozen core-shell interaction rules
- split-view follows the dedicated Zen split parity contract, including tab
  context rows, hover header controls, duplication rules, and `4`-member
  layout-tree semantics
- split and glance sidebar behavior follow the dedicated grouped-sidebar parity
  contract
- URL bar, compact mode, and keyboard behavior follow the frozen shell doc
- URL bar learner rules follow the separate learner contract
- the grounded Zen shell-command catalog is present in the canonical URL bar
  action service
- GitHub-issue-derived shell regressions are frozen separately from Firefox or
  packaging bugs
- sidebar density and panel/menu surfaces follow the frozen visual docs
- blank window, Ctrl+Tab, and live-folder boundaries follow the frozen docs
- space-switch, theme-transition, and media-card behavior follow the frozen
  runtime doc
- create popup, space menu, folder menu, and site-data actions menu follow the
  frozen Zen-derived menu order
- site-controls panel follows the frozen header, settings, and footer structure
- site-controls anchor hides correctly on empty-space and floating URL-bar
  paths
- changed pinned launchers show the frozen Zen slash-and-reset affordance
- Essentials never show that changed-url launcher affordance
- launcher icon overrides accept emoji or SVG assets and survive import/export
- launcher row menus expose the frozen edit and replace-current actions, plus
  Aura's explicit `Edit Link`

## Media

- YouTube + Twitch create two separate background cards
- muted-but-playing media remains visible
- Aura cards expose the same independently controllable sessions already visible
  in Helium's media controller
- audible playing sessions show the notes animation on the card
- paused or muted sessions do not animate notes
- media-sharing cards swap playback controls for device controls
- PiP or fullscreen sessions suppress the standard sidebar card
- media controls and device-control icons come from the mirrored Zen reference
  set for the first native pass

## Customization settings

- `aura://settings/` exposes customization export, import, and reset
- `aura://settings/` exposes Theme, Layout, Spaces & Essentials, Keyboard, and
  Import/Export sections
- import and export exclude browsing session/runtime state
- import preview shows replace-current confirmation before apply
- settings expose global dark-mode bias and acrylic-elements toggles
- settings expose URL-bar copy-link, PiP, and contextual-identity toggles
- settings expose wrap-around navigation and last-unpinned-close behavior
- settings do not duplicate the live site-controls popover runtime
- settings read current values from canonical typed customization state instead
  of reconstructing them from exported JSON

## Theme

- workspace theme changes during space switching
- theme editor stays bounded and does not break the window
- theme editor exposes scheme, algorithm, presets, opacity, texture, and up to
  3 color points
- theme editor honors the macOS Zen opacity range and 16-step texture ring
- theme picker geometry, controls, and icons follow the frozen Zen parity docs

## Split view

- `Split Tabs` inserts immediately before the host `Move Tab To Split View` row
- `Split Tabs` and `Un-split Tabs` follow the frozen Zen gating rules
- `Split Link in New Tab` uses the same split engine as drag-created split
- dragging a tab onto another tab for `300ms` exposes the split affordance
- active split content exposes `rearrange` and `unsplit` hover controls
- pressing `Escape` during split preview clears all preview residue
- split pin and unpin propagate to the full split group
- splits created from folder tabs preserve folder parent linkage
- split groups render as grouped non-collapsible sidebar units
- moving one split member to another space moves the whole split group
- valid split layout trees restore cleanly and invalid ones collapse safely

## Glance and sidebar

- switching away from a live glance closes only the visible overlay path
- returning to the parent or live child reopens the glance path
- live glance children do not count as standalone pinned or Essentials items
- on collapsed or Essential-backed rows, the live glance child renders as a
  nested parent-row affordance instead of a standalone row
- expanding a glance from an Essential-backed parent creates a regular tab
  outside the Essentials container
- moving a parent tab with a live glance moves the live glance child to the
  same space
- DnD workspace-switch with parent-linked glance and split groups is covered by
  dedicated parity checks before shipping

## Issue-driven regressions

- Essentials do not become accidentally draggable on ordinary click paths
- Essentials order does not jumble after reopen or restore
- external-open tab routing does not freeze space switching
- floating URL bar results stay anchored and selectable
- active-tab and current-URL results stay prioritized
- snapped or tiled window geometry does not break compact reveal
