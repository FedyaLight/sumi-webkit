# Media card visual model

This document freezes Aura's first implementation-ready media card model for
the single-toolbar sidebar shell.

Zen is the target interaction language. Aura keeps Helium as the media runtime
source of truth and only rewrites placement, styling, and shell choreography.

## Model

- one card per active background media session
- cards are window-scoped, not space-scoped
- multiple cards stack in the sidebar footer with stable spacing
- the currently visible active tab does not render as a background card
- cards reuse the same upstream session metadata and actions already surfaced by
  Helium's media controller

## Required card content

- artwork thumbnail when available
- title
- artist, channel, or source label when available
- progress and duration when upstream exposes them
- play or pause
- previous and next when supported
- mute or unmute
- microphone and camera mute when the card is representing media sharing
- focus tab
- dismiss for the current playback epoch only

## Hover and animation rules

- metadata marquee starts only on hover when text is actually overflowing
- hover-reveal controls must not reserve dead layout space when hidden
- notes animation is displayed on the focus affordance area of the card, not as
  a separate row
- notes animation fades away while the card itself is hovered, matching Zen's
  focus-first hover treatment
- reduced-motion mode may replace animation with a static note indicator
- picture-in-picture or fullscreen sessions suppress the normal sidebar card
  path instead of duplicating the same media surface twice

## Audio activity rules

- notes animation appears only when a session is both `playing` and `audible`
- muted sessions never animate notes
- paused sessions never animate notes
- buffering sessions may keep artwork and controls visible but do not animate
  notes unless the session is still explicitly audible
- notes animation is decorative only and must not change card geometry

## Layout rules

- cards use full sidebar width inside the footer region
- cards stack with the frozen `media stack gap`
- card body padding is grounded to Zen's `4px 6px` media shell
- transport buttons use `2px` spacing with `26px` icon boxes and `5px` inner
  padding
- progress bar height is `4px` and only reveals its thumb on hover
- controls and progress bar do not reflow the rest of the sidebar on hover
- artwork crop must stay stable while metadata updates
- dismissing or revealing a card must not introduce footer jitter
- long-duration or sharing-focused sessions may hide timeline position

## Sharing and suppression rules

- multiple active sessions remain globally controllable across all spaces
- media-sharing mode swaps playback controls for device controls
- hovered cards reveal extra controls without reserving dead layout space
- picture-in-picture or fullscreen sessions suppress the standard background
  card presentation
- suppression must come from explicit runtime state, not inferred timers

## Performance guardrails

- notes animation must be paint-only or equivalent lightweight visual state
- no polling for audio activity, progress, or session presence
- progress updates must route through upstream media session events or an
  equivalent Helium-owned cadence, not a new Aura timer loop
- card visuals must degrade cleanly when artwork or duration is missing
- long titles must truncate cleanly when hover marquee is inactive

## What remains intentionally downstream

- exact icon asset used for the notes indicator
- exact easing curve and cadence of the notes animation
- exact artwork corner radius if not already implied by the shell token family

These remain Aura downstream decisions unless a grounded Zen source proves a
better canonical value.
