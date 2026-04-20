# Media session pipeline

Aura uses Helium's existing media session runtime as the source of truth.

## Model

- one `BackgroundMediaSession` per background media source
- one expanded sidebar card per background session
- muted-but-playing sessions remain visible
- the currently visible active tab does not generate a background card
- the upstream Helium media controller already proving multiple simultaneous
  media sources is the canonical runtime input for Aura cards

## Rules

- no YouTube-only or Twitch-only ownership
- no single-active-player shortcut model
- media cards are event-driven and do not poll
- no custom HTML-media polling path when Helium already exposes the session
  metadata and controls
- cards are ordered by most recently active background session first
- card dismissal is per playback epoch and never closes the underlying tab
- media card visibility is window-scoped, not space-scoped
- focusing a media card may switch spaces, but it must route through the normal
  space-selection path

## Adapter contract

- `AuraMediaSessionService` reads session state from Helium/Chromium media
  session sources already used by Helium's toolbar media controller
- Aura only re-skins and re-places that state into sidebar cards
- control actions such as play, pause, seek, mute, and focus-tab route back to
  the same upstream session/control path
- notes animation eligibility is derived from the same upstream playing and
  audible state used by the session model

## Required session fields

- session id
- playback epoch id
- tab id
- title
- artist/channel when available
- source name and origin
- artwork when available
- audible state
- playback state
- buffering state when available
- muted state
- position and duration when available
- supported actions
