# Zen icon asset map

This document tracks the exact icon sources Aura should copy from the local Zen
repo for the first single-toolbar native rewrite.

## Source grounding

- `/Users/fedaefimov/Downloads/Aura/Zen/src/browser/themes/shared/zen-icons/icons.css`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/browser/themes/shared/zen-icons/nucleo/`
- `/Users/fedaefimov/Downloads/Aura/Zen/src/browser/themes/shared/zen-icons/common/`

## Mirrored reference assets

Aura now keeps a mirrored reference copy at:

- `/Users/fedaefimov/Downloads/Aura/Aura/aura/resources/icons/zen-reference/zen-icons`

Provenance notes are preserved from Zen:

- `/Users/fedaefimov/Downloads/Aura/Aura/aura/resources/icons/zen-reference/zen-icons/nucleo/nucleo-copyright-notice.html`
- `/Users/fedaefimov/Downloads/Aura/Aura/aura/resources/icons/zen-reference/zen-icons/fluent/NOTE.md`
- `/Users/fedaefimov/Downloads/Aura/Aura/aura/resources/icons/zen-reference/zen-icons/sf/NOTE.md`

## First-pass icon families

### Theme picker

- `nucleo/sparkles.svg`
- `nucleo/face-sun.svg`
- `nucleo/moon-stars.svg`
- `nucleo/plus.svg`
- `nucleo/unpin.svg`
- `nucleo/algorithm.svg`
- `nucleo/arrow-left.svg`
- `nucleo/arrow-right.svg`

### URL bar and site controls

- `nucleo/link.svg`
- `nucleo/permissions.svg`
- `nucleo/permissions-fill.svg`
- `nucleo/share.svg`
- `nucleo/reader-mode.svg`
- `nucleo/camera.svg`
- `nucleo/bookmark-hollow.svg`
- `nucleo/bookmark.svg`
- `nucleo/security.svg`
- `nucleo/security-warning.svg`
- `nucleo/security-broken.svg`
- `nucleo/extension.svg`
- `nucleo/menu.svg`
- `nucleo/manage.svg`
- `nucleo/settings.svg`

### Permission rows and site settings

- `nucleo/settings-fill.svg`
- `nucleo/geo.svg`
- `nucleo/geo-fill.svg`
- `nucleo/geo-blocked.svg`
- `nucleo/xr.svg`
- `nucleo/xr-fill.svg`
- `nucleo/xr-blocked.svg`
- `nucleo/desktop-notification.svg`
- `nucleo/desktop-notification-fill.svg`
- `nucleo/desktop-notification-blocked.svg`
- `nucleo/camera-fill.svg`
- `nucleo/camera-blocked.svg`
- `nucleo/microphone.svg`
- `nucleo/microphone-fill.svg`
- `nucleo/microphone-blocked.svg`
- `nucleo/screen.svg`
- `nucleo/screen-blocked.svg`
- `nucleo/persistent-storage.svg`
- `nucleo/persistent-storage-fill.svg`
- `nucleo/persistent-storage-blocked.svg`
- `nucleo/popup.svg`
- `nucleo/popup-fill.svg`
- `nucleo/autoplay-media.svg`
- `nucleo/autoplay-media-fill.svg`
- `nucleo/autoplay-media-blocked.svg`
- `nucleo/cookies-fill.svg`
- `nucleo/extension-fill.svg`
- `nucleo/tracking-protection-fill.svg`

### Workspace, folder, and create menus

- `nucleo/duplicate-tab.svg`
- `nucleo/folder.svg`
- `nucleo/split.svg`
- `nucleo/plus.svg`
- `nucleo/menu.svg`
- `nucleo/edit-theme.svg`
- `nucleo/manage.svg`
- `nucleo/unpin.svg`
- `nucleo/close.svg`
- `nucleo/pin.svg`
- `nucleo/essential-add.svg`
- `nucleo/essential-remove.svg`

### Extensions and panel headers

- `nucleo/extension.svg`
- `nucleo/bookmark-star-on-tray.svg`
- `nucleo/history.svg`
- `nucleo/help.svg`
- `nucleo/library.svg`

### Media cards and audio affordances

- `nucleo/media-play.svg`
- `nucleo/media-pause.svg`
- `nucleo/media-next.svg`
- `nucleo/media-previous.svg`
- `nucleo/media-unmute.svg`
- `nucleo/media-mute.svg`
- `nucleo/microphone-fill.svg`
- `nucleo/microphone-blocked-fill.svg`
- `nucleo/video-fill.svg`
- `nucleo/video-blocked-fill.svg`
- `nucleo/screen.svg`
- `nucleo/close.svg`
- `nucleo/tab-audio-playing-small.svg`
- `nucleo/tab-audio-muted-small.svg`
- `nucleo/tab-audio-blocked-small.svg`

## Rules

- first native pass should use these mirrored assets for parity-critical
  surfaces instead of inventing replacement icons
- Aura may later remap internals, but it should not silently drift from the
  Zen icon language while parity remains the goal
- any icon not source-grounded in Zen should be treated as an Aura downstream
  default and documented as such
