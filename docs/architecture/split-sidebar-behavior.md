# Split sidebar behavior

This document records the product decisions agreed on 2026-07-19 and updated on 2026-07-20 for split groups in Regular, Pinned, Folder, and Essentials.

## Core model

- A split group is one durable sidebar item with two to four ordered members.
- Moving a whole group preserves its group ID, layout, order, name, icon, selection, and reusable WebViews.
- The destination container owns the member kind. Moving a whole group between Regular and a saved container atomically converts every member rather than copying or dissolving the group.
- Pinned folders are Pinned containers with folder placement.
- Split groups cannot be merged with other split groups by WebView drag-and-drop.
- Center WebView drops never replace a split member. Only edge drops create or extend a split.

## Member conversion matrix

| Source | Active split target | Result |
| --- | --- | --- |
| Regular | Pinned or Folder | Move and convert to a Pinned launcher |
| Regular | Essentials | Move and convert to an Essential launcher |
| Pinned or Folder | Essentials | Move and convert to an Essential launcher |
| Essentials | Pinned or Folder | Move and convert to a Pinned launcher |
| Pinned or Essentials | Regular | Keep the saved launcher and add a new regular copy |

An unloaded launcher dropped into an active split is materialized immediately and becomes the active participant. Failure leaves topology and storage unchanged. Ordinary sidebar movement of an unloaded launcher does not load it.

## Whole-group movement

- Regular ↔ Pinned/Folder/Essentials changes the member identities in place and keeps the group.
- Pinned/Folder ↔ Essentials moves all launchers atomically and keeps the group.
- Saved → Regular converts every launcher to a regular `Tab` model without dissolving the group or retaining a saved copy. Loaded groups reuse their WebViews and keep the active participant; unloaded groups create all regular members without eagerly loading WebViews.
- A whole group occupies one sidebar item and is always dragged as a whole. A participant must first be separated before it can be dragged independently.
- Regular and Pinned rows expose selection only at group level. The focused member does not receive different typography or per-segment selection chrome.

## Essentials

- A split group occupies one Essentials grid slot regardless of member count.
- Grid capacity is measured in visual items, not launcher records. Internal member records may exceed the twelve-slot grid count so an existing Essential group can still grow to four members.
- A full Essentials grid accepts no new item or group. Adding a third or fourth member through the active WebView is still allowed because it consumes no new grid slot.
- Sidebar drops on Essential tiles never create or extend a split. Drops between tiles only perform ordinary Essentials placement.
- Compact templates preserve member order: two equal cells; three cells with members one and two stacked on the left and member three spanning the right; four cells in a 2×2 row-major grid.
- The compact template is independent of the browser's actual split layout. The WebView layout still follows the target pane and edge used for the drop.

## Essential selection chrome

- A split composition is one outer rounded tile. Member cells never draw their own rounded containers; they are sections clipped by the shared outer shape.
- Inactive split tiles have no outer stroke. Sections are separated by transparent internal gaps whose width equals the normal Essential selection-ring thickness.
- An active split uses each member's existing `PinnedTileAccentResolver` color. One outer ring and the straight internal dividers interpolate spatially between those colors.
- An active split fills the entire shared tile with the ordinary active Essential background. No member receives a separate focused fill.
- A custom group icon replaces the member composition and uses the ordinary single-color Essential ring.

## Group lifecycle

- A launcher-backed split loads and unloads only as a group. Clicking a participant loads every member and focuses that participant; clicking shared row chrome restores the last active participant, falling back to the first.
- `Unload Split View` unloads every runtime instance and preserves the group.
- `Delete Split View…` removes the saved group and all launcher members after confirmation.
- `Close Split View` closes every member of a regular group.
- Removing one participant dissolves a two-member group and leaves the survivor standalone.

## Separation and capacity

- Separating one participant places it immediately after the remaining group.
- Separating a two-member group or using `Separate All Tabs` expands members at the group's position in member order.
- If Essentials cannot hold every separated member, the earliest members fill available Essential slots and overflow members move to the beginning of the current Space's Pinned section, preserving order.

## Metadata and commands

- A group can be edited like a launcher: optional name and optional icon, but no URL.
- Without a name, rows display the localized equivalent of `N Tabs`.
- Without a group icon, sidebar surfaces show the member composition. With an icon, every surface shows one icon and the group behaves visually like a normal tab row/tile.
- Duplicate creates an inactive adjacent group. Saved duplicates remain unloaded; regular duplicates do not become selected.
- Explicit duplicate names use collision suffixes: `Name (2)`, `Name (3)`, and so on. Unnamed groups continue to use `N Tabs` without suffixes. The icon is copied.
- `Move to` moves the whole group atomically using the same rules as drag-and-drop.
- `Add Tab…` is available below four members and uses the floating bar. Existing items move into the group; a new URL creates a member in the group's container. Cancellation leaves no placeholder or ghost row.
- At four members, add commands and WebView split-drop zones are disabled and the existing split-limit notification is used.
- There is no `Share Split View…` or separate `Change Icon…` command. Icon changes happen through group or launcher `Edit`.

## Drag preview

- Preview is target-adaptive: Essential targets use the real Essential split tile; Regular, Pinned, and Folder targets use the real split row.
- Sidebar and preview share rendering modules rather than approximating one another.
- Member order, group icon/name, loaded state, group-level selection fill, and accent gradient match the corresponding sidebar item.
