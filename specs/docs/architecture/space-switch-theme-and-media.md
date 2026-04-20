# Space switching, theme transitions, and media cards

This document freezes the runtime behavior that ties together:

- switching spaces
- workspace theme transitions
- background media card behavior

Zen release notes repeatedly showed these systems interacting. Aura therefore
models them as one coordinated shell path instead of three unrelated view
effects.

## Ownership

- `AuraShellCoordinator`
  - owns the space switch transaction and visible shell choreography
- `AuraProfileRouter`
  - resolves the destination profile and target selection
- `AuraThemeService`
  - owns workspace theme interpolation and editor/runtime parity
- `AuraMediaSessionService`
  - owns media card projection and dismissal policy

Helium remains the owner of real tabs, profiles, media sessions, and content
views.

## Space switch transaction

Every space switch follows one transaction:

1. resolve destination space and bound profile
2. resolve destination selection and split or glance context
3. warm the target tab or content host when possible
4. coordinate shell chrome with the active space change (`setActiveSpace` / page controller)
5. blend workspace theme during the switch
6. commit destination selection and profile binding
7. settle media cards and transient surfaces

This transaction is shared regardless of how the switch was triggered:

- sidebar or Spaces list selection
- keyboard shortcut
- URL bar result
- drag-hover auto-switch

## Space switching rules

- switching to the already active space is a no-op with no theme animation
- if only one space exists, the switcher remains hidden and no switch animation
  path is armed
- space switching restores the last valid selection for that space
- the destination tab should be warmed before commit when the runtime can do so
  cheaply
- shell animation must not start a second later than profile or tab commit
- switching spaces must not mutate split or glance state belonging to the
  origin space
- transient surfaces owned by the origin space are dismissed unless explicitly
  shared across spaces
- switching spaces must be measurably performant, not merely visually correct

## Theme transition rules

- workspace theme blends during the space transition, not after it
- the theme owner is the same for runtime application and editor preview
- global light/dark remains separate from workspace theme
- site rendering follows global light/dark only
- theme transition affects Aura chrome surfaces only
- compact mode and fullscreen must use the same theme transition path, not a
  fallback path
- theme interpolation must avoid white flashes, sudden resets, or post-commit
  correction jumps
- rendering should minimize visible dithering artifacts in gradients where the
  native Helium surface allows it

## Theme customization rules

Aura keeps Zen-like flexibility without pretending we know every internal Zen
algorithm:

- per-space themes are persisted in profile state
- monochrome themes are a first-class option
- the color algorithm is configurable and limited to the grounded Zen set:
  `complementary`, `splitComplementary`, `analogous`, `triadic`, `floating`
- theme editing must support more than one color point, capped at `3`
- theme editing supports `auto/light/dark` scheme selection
- theme editing persists opacity and texture strength
- preset pages and preset selections are explicit saved data, not ad hoc UI
  state
- invalid theme input should normalize or fall back cleanly instead of leaving
  partially transparent or corrupted chrome
- editor changes preview through the same transition owner used at runtime

## Media card rules

Aura reuses Helium's multi-session media runtime and projects it into sidebar
cards.

- one card per active background session
- muted-but-playing sessions remain visible
- the currently visible active tab does not render as a background card
- media cards are ordered by most recently active background session first
- dismissing a card hides it for the current playback epoch only
- if playback stops and later resumes as a new session epoch, the card may
  reappear
- media cards are window-scoped, not space-scoped
- switching spaces may cause the previously visible tab to become a background
  media card
- the media stack must not push the sidebar footer into unstable layout jumps

## Media controls and focus

- card controls route to the same upstream Helium media actions already used by
  the toolbar media controller
- notes animation appears only for sessions that are both playing and audible
- note animation respects reduced-motion settings and may degrade to a static
  indicator
- focusing a media card's tab switches to the owning space if needed
- focusing a media card does not destroy the session card model unless the tab
  becomes the current visible active tab
- dismissing a card never closes the tab or kills the media session

## Compact mode interactions

- space switching, theme transitions, and media card updates must all behave
  correctly in compact mode
- compact mode reveal should not force media cards to remount unnecessarily
- floating sidebar reveal must show the correct current media stack for the
  window
- theme transitions in compact mode must remain synchronized with the space
  switch transaction

## Anti-regression rules from Zen behavior

- space switching and theme transitions should feel smoother than a hard cut
- theme background animation must track the space switch transaction, not lag behind commit
- media-controller-style UI should not introduce obvious idle performance cost
- if a theme or media session is missing data, Aura must degrade cleanly
  without layout breakage

## What remains intentionally unspecified

- exact easing curves and durations for the transition
- exact card pixel geometry and artwork crop behavior
- the precise algorithm names Zen uses internally for theme computation

These values should remain downstream Aura choices until a grounded source or
live implementation proves a better canonical answer.
