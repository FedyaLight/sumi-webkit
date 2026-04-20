# Core shell menu matrix

This file freezes the first complete single-toolbar Aura menu behavior from the
local Zen sources.

## Create popup

Order:

1. `Create Space`
2. `Create Folder`
3. separator
4. `New Empty Split`
5. `New Tab`

## Sidebar background menu

Aura keeps the create popup as the canonical background quick-actions surface
instead of inventing a different single-toolbar background menu.

Additional background-only actions may exist later, but first-pass parity keeps
the create popup order above intact.

## Space menu

Order:

1. `Rename Space`
2. `Change Space Icon`
3. `Change Space Theme`
4. `Default Profile/Container` submenu
5. separator
6. `Reorder Spaces`
7. `Unload Current Space`
8. `Unload Other Spaces`
9. separator
10. `Create Space`
11. `Delete Space`

Rules:

- the theme command routes to the canonical theme picker owner
- default profile/container is a submenu, not an inline picker
- Aura keeps your Essentials divergence, but space menu order follows Zen

## Folder menu

Order:

1. `Live Folder Options` submenu when applicable
2. optional separator when live-folder options are visible
3. `Rename Folder`
4. `Change Folder Icon`
5. separator
6. `Unload All`
7. `New Subfolder`
8. separator
9. `Change Folder Space` submenu
10. `Convert Folder to Space`
11. separator
12. `Unpack Folder`
13. `Delete Folder`

Rules:

- `New Subfolder` disables at depth `5`
- Aura keeps clean folder internals, but user-facing folder actions follow Zen
- live-folder controls remain behind their own owner and stay hidden unless the
  future live-folder service is active

## Tab menu

Aura keeps the host tab context menu but freezes the Zen split additions
exactly.

Relative order:

1. `Split Tabs` or `Un-split Tabs`
2. host split move row

Rules:

- `Split Tabs` is inserted immediately before the host `Move Tab To Split View`
  row
- `Split Tabs` appears only when `2..4` tabs are selected and none are already
  in split or the empty split placeholder path
- `Un-split Tabs` appears when any selected tab is already in split
- split layout preset changes route through the canonical split owner and must
  not create a second split menu path

## Launcher row menu additions

Launcher-backed rows keep the host row menu and add this frozen Zen-derived
edit cluster:

1. `Add to Essentials` or `Remove from Essentials`
2. separator
3. `Edit Title`
4. `Edit Icon`
5. `Edit Link`
6. separator
7. `Replace Launcher URL with Current`
8. `Reset Launcher`

Rules:

- `Replace Launcher URL with Current` and `Reset Launcher` are visible only for
  single-select changed pinned launchers
- changed-url launcher rows never expose those two actions inside Essentials
- `Edit Title` stays hidden for Essentials, matching Zen
- `Edit Icon` uses the same emoji or SVG picker family Zen uses for launcher,
  folder, and space icon overrides
- `Edit Link` is an Aura-owned extension; Zen exposes only the replace-current
  action, not a general-purpose link editor

## Split hover header

Order:

1. `Rearrange`
2. `Un-split`

Rules:

- this is a content-area hover command cluster, not a generic context menu
- the hover header stays visually distinct from menu rows and follows Zen's
  reveal behavior

## Split item menu

Order:

1. `Un-split Tab`
2. `Un-split and Keep Current Focus`
3. separator
4. `Grid Layout`
5. `Vertical Layout`
6. `Horizontal Layout`
7. separator
8. `Move Focus Left/Up`
9. `Move Focus Right/Down`
10. separator
11. `Close Split Item`

Rules:

- split layout preset rows are disabled once the resulting layout would exceed
  the `4`-item cap
- pin and unpin actions route through the group-wide propagation policy, not an
  individual tab override

## Glance command surface

The grounded Zen source exposes a dedicated overlay command cluster instead of
an independent glance context menu.

Order:

1. `Close`
2. `Expand as Tab`
3. `Split Glance Tab`

Rules:

- the close affordance enters a `waitconfirmation` state before committing a
  focused close
- overlay controls use the mirrored Zen icons and remain distinct from context
  menu rows

## Link context additions

Order relative to Zen shell additions:

1. `Split Link in New Tab`
2. `Open Link in Glance`

Rules:

- both items appear only for real link targets
- neither item appears for `mailto:` or `tel:` links
- `Open Link in Glance` routes through the same canonical glance owner as
  bookmark-triggered or command-triggered glance

## Address bar and unified hub

The address bar has one canonical trailing cluster:

1. `Copy Link`
2. site-controls button

The site-controls hub contains:

- header actions in this exact order:
  - `Share`
  - `Reader Mode`
  - `Screenshot`
  - `Bookmark`
- site settings section:
  - dynamic permission rows
  - no `ask/prompt` rows
  - cross-site cookie rows after the internal separator
- footer:
  - security info
  - actions menu

## Site-data actions menu

Order:

1. `Clear Site Data`
2. separator
3. `Manage Add-ons`
4. `Get Add-ons`
5. separator
6. `Site Settings`

## Menubar parity

### Appearance

Order:

1. disabled description row
2. `Auto`
3. `Light`
4. `Dark`

### Spaces

Order:

1. `Create Space`
2. `Change Theme`
3. `Rename Space`
4. `Change Space Icon`
5. separator
6. `Next Space`
7. `Previous Space`

### App menu

- `New Blank Window` is inserted after the standard new-window action
- `Toggle Pinned Tabs` appears in the View menu when workspaces are active

## Keyboard-exposed command actions

These actions must route through the same menu or command owners as their
pointer equivalents:

- `Create new split`
- `Un-split tabs`
- `Toggle compact mode`
- `Switch to next or previous space`
- `Switch to numbered space`
- `Focus address bar`
- `Show all command bar actions`

## Media card menu

Order:

1. `Focus Tab`
2. `Play/Pause`
3. `Mute/Unmute`
4. separator
5. `Dismiss Card`

## Rules

- menu order is fixed and intentional
- menu actions must route through the same shell interaction engine or service
  owner as the equivalent gesture
- menus do not contain Aura-webkit legacy actions that contradict Zen behavior
- context-menu icons should come from the mirrored Zen icon asset map for the
  first single-toolbar pass
