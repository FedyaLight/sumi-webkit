# Profile and space routing

Aura preserves a single-window UX while allowing spaces bound to different
Chromium profiles.

## Model

- one physical Aura window
- each space is bound to one Chromium profile
- switching spaces swaps the active browsing context in-place

## Runtime lifecycle

Aura distinguishes shell selection from profile runtime loading.

- a space may be active in the Aura shell while its Chromium profile remains
  dormant
- switching into an empty space selects that space immediately without forcing
  profile runtime startup
- a profile loads only when the space needs real runtime-backed content:
  - a tab or launcher instance is opened
  - a live essential instance is shown
  - media or a download keeps the profile alive
- loaded profiles may be hidden yet still alive if they still own live
  Chromium state
- if a hidden profile-backed space has no live tabs, no live essential
  instance, no media, and no transfer activity, Aura
  should return it to a dormant state

The practical goal is:

- empty inactive space: metadata-only and close to zero shell overhead
- empty active space: active shell selection with dormant profile runtime
- hidden loaded space: no second window, no second browser shell, only the
  unavoidable Chromium profile/runtime cost for still-live content

## Deliberate divergence from Zen

Zen workspaces are deeply tied to container semantics. Aura does not copy that
mechanism. Spaces are mapped directly to Chromium profiles instead.

That divergence is intentional and must stay explicit so future implementation
does not mix container rules and profile rules into the same routing model.

## Essentials

- essentials are profile-owned launchers
- spaces bound to the same profile share one Essentials strip in sidebar chrome
- switching or swiping between same-profile spaces keeps that strip visually
  fixed
- a live swipe between different-profile spaces keeps Essentials page-owned for
  the duration of the gesture, so the strip moves with the page until commit
- static Essentials definitions live in per-profile structure, not in
  window-global customization state
- a live essential remains attached to the profile where it was opened
- live essential attachment records remain window-scoped
- closing or unloading it releases the instance
- relaunch uses the current space's profile
- if a live essential enters split and stays unpinned, its Essentials slot
  becomes a split proxy that redirects to the live split group
- pinning that split detaches it from the launcher:
  - the Essentials slot returns to the normal launcher immediately
  - the split becomes a standalone pinned entity
  - later unpinning does not relink it to the launcher

## Constraints

- profile routing does not live inside sidebar view code
- profile routing does not own media visibility, menu geometry, or compact-mode
  policy
- per-space theme definitions may persist with profile-owned structure, but
  theme interpolation remains `AuraThemeService` ownership
- restore must rebuild routing from persisted state, not from UI heuristics
- profile runtime state is transient and policy-driven, not a persisted source
  of truth
