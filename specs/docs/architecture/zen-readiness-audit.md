# Zen readiness audit

This file tracks how close Aura's downstream foundation is to a real Zen-class
native implementation.

## Status scale

- `spec frozen`
- `model complete`
- `stubbed`
- `implementation started`
- `implementation missing`

## Current subsystem status

| Subsystem | Status | Notes |
|---|---|---|
| Core shell interactions | spec frozen | DnD, reorder, split, glance, compact mode, and keyboard semantics are frozen, including Glance close, traversal, expand, and split parity from Zen code and tests. |
| Split view parity | model complete | Zen split commands, tab-context gating, `4`-member layout tree, duplication rules, hover headers, and Helium host strategy are frozen; live host wiring is still missing. |
| Split and glance sidebar semantics | spec frozen | Sidebar grouping, count exclusion, parent-linked reselection, and cross-space movement rules are now grounded from Zen tabbrowser, spaces, folders, and glance code. |
| Combination parity audit | spec frozen | Split/glance/Essentials/pinned/folders/DnD combinations are mapped, and Zen gaps or contradictions are explicit instead of implicit. |
| URL bar learner | stubbed | Action catalog and learner contracts are frozen; live Helium wiring is still missing. |
| Sidebar visual density | spec frozen | Single-toolbar density and surface rules are frozen. |
| Empty-space and folder runtime | model complete | Clean Aura runtime equivalents now replace Zen placeholder-tab internals in the spec/model layer. |
| Theme picker parity | spec frozen | Live Zen picker controls, preset pages, macOS opacity bounds, texture steps, and saved theme rules are frozen. |
| Menu and panel visuals | spec frozen | Single-toolbar menu/panel geometry and native macOS popover rules are grounded. |
| Site controls and unified extensions | spec frozen | Header order, add-ons/settings/footer structure, overflow threshold, context menu order, and anchor routing are grounded. |
| Icon asset parity | model complete | Zen icon set is mirrored locally with a first-pass asset map and provenance notes. |
| Zen test-grounded shell behavior | spec frozen | Compact width, popover height, folder density, overflow scrollbox, and floating URL bar rules are grounded. |
| Media cards | stubbed | Multi-session, audible state, playback epoch, hover-note rules, and projection stubs are in place. |
| Essentials semantics | model complete | Global launcher semantics and live-instance profile attachment are frozen. |
| Import/export customization | stubbed | Bundle contract, settings IA, URL-bar/theme prefs, and handler seams are frozen; live handlers are not implemented yet. |
| Multi-profile routing | model complete | Contracts now assume multiple profile states in one window. |
| Native Aura shell host | implementation missing | No live Aura-owned sidebar or address bar is mounted yet. |
| Aura settings page | stubbed | Route and handler seams are specified, but not wired into upstream settings yet. |
| Helium-backed media card UI | stubbed | Projection layer exists, but no live card host is mounted yet. |

## Overall assessment

- behavior and architecture parity are now strong enough for the first real
  native rewrite to proceed without large product ambiguities
- visual parity is strong for the single-toolbar shell, but live pixel polish
  still depends on the first native implementation pass
- source-grounded pre-build readiness for the single-toolbar shell is now
  roughly at the `95%` mark; the remaining gap is live Helium wiring and final
  pixel tuning
- browser runtime parity is still early because the implementation has barely
  started
- a few high-risk combination paths remain deliberate Aura decision points
  because Zen itself does not provide one fully coherent canonical answer

## Remaining deferred areas

- multi-toolbar shell variants
- live folders
- multi-window sync
- advanced shortcut rebinding UI
- non-shell onboarding and import flows
