# Split sidebar behavior

This document records the product decisions agreed on 2026-07-19 and updated on 2026-07-29 for split groups in Regular, Pinned, Folder, and Favorite.

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
| Regular | Favorite | Move and convert to a Favorite launcher |
| Pinned or Folder | Favorite | Move and convert to a Favorite launcher |
| Favorite | Pinned or Folder | Move and convert to a Pinned launcher |
| Pinned or Favorite | Regular | Move and convert to a regular tab; remove the saved launcher |

An unloaded launcher dropped into an active split is materialized immediately and becomes the active participant. Failure leaves topology and storage unchanged. Ordinary sidebar movement of an unloaded launcher does not load it.

Dragging a standalone item always transfers that item into the destination
container. It never leaves a second launcher, tab, or linked presentation row
in the source container.

## Whole-group movement

- Regular ↔ Pinned/Folder/Favorite changes the member identities in place and keeps the group.
- Pinned/Folder ↔ Favorite moves all launchers atomically and keeps the group.
- Saved → Regular converts every launcher to a regular `Tab` model without dissolving the group or retaining a saved copy. Loaded groups reuse their WebViews and keep the active participant; unloaded groups create all regular members without eagerly loading WebViews.
- A whole group occupies one sidebar item and is always dragged as a whole. A participant must first be separated before it can be dragged independently.
- Regular and Pinned rows expose selection only at group level. The focused member does not receive different typography or per-segment selection chrome.
- Dropping a whole group into a collapsed folder keeps that folder collapsed, matching an ordinary launcher drop.

## Sidebar ordering invariant

- Every visible row owns exactly one visual position in its immediate container. A split row therefore contributes one position regardless of member count; its hidden member records never participate in drag boundaries or sibling normalization.
- Geometry reports visual row identities and boundaries only. Conversion to durable records happens once, during the drop transaction.
- A drop within the same container always uses visual reorder. Catalog movement is reserved for different containers, so an in-place reorder cannot remove and reinsert a row through two competing index systems.
- Pinned and Folder ordering commits folders, standalone launchers, split containers, and split-member residence as one plan. No timer, observer, polling loop, or per-frame projection work is used for ordering.

## Sidebar tab-on-tab pairing

- The central vertical band of a Regular, Pinned, or Folder tab row is a split-pairing target. The top and bottom bands remain ordinary insertion boundaries, so pairing and reorder never compete for the same pointer position.
- A standalone target creates a two-member group in pointer-projected order. Hovering its left half reserves an empty leading pill and commits `[dragged, target]`; hovering its right half reserves an empty trailing pill and commits `[target, dragged]`. The projected row and existing target remain transparent and receive neither active nor hover material. The target's favicon stays on the ordinary-row leading coordinate, and its centered label uses the same `SplitGroupSegmentLabel`, width, spacing, and title-visibility policy used after commit. Only the empty placeholder receives the emphasized pill fill, and it contains neither a favicon nor a title.
- A two- or three-member target group accepts the incoming tab at the end of the group. The complete list lane behind that row receives the same rectangular containment highlight as a folder, without row rounding; individual member pills are not DnD targets. A four-member group is not a pairing target.
- Regular, Pinned, Folder, and Favorite standalone tabs may be sources. The target container owns the result and the existing `SplitDropService` performs all identity conversion, materialization, topology, and selection work.
- Whole-group and folder payloads never enter pairing. They continue to use ordinary row movement; split groups are not merged.
- Ordinary pointer hover never paints an individual member pill. It may reveal that member's action, while row-level hover continues to use the shared row surface.
- Hidden member and group actions reserve no title width. Regular and Pinned therefore use the same title projection until their trailing action is actually visible. A title is removed entirely unless the available width can show at least its first grapheme plus the ellipsis glyph.
- Reorder keeps the existing line-and-ring indicator.
- Favorite tiles remain reorder-only sidebar targets. Split creation or extension involving a Favorite target happens through the active WebView.

## Favorite

- A split group occupies one Favorite grid slot regardless of member count.
- Grid capacity is measured in visual items, not launcher records. Internal member records may exceed the twelve-slot grid count so an existing Favorite group can still grow to four members.
- A full Favorite grid accepts no new item or group. Adding a third or fourth member through the active WebView is still allowed because it consumes no new grid slot.
- Sidebar drops on Favorite tiles never create or extend a split. Drops between tiles only perform ordinary Favorite placement.
- Compact templates preserve member order: two equal cells; three cells with members one and two stacked on the left and member three spanning the right; four cells in a 2×2 row-major grid.
- The compact template is independent of the browser's actual split layout. The WebView layout still follows the target pane and edge used for the drop.

## Favorite selection chrome

- A split composition is one outer rounded tile. Member cells never draw their own rounded containers; they are sections clipped by the shared outer shape.
- Inactive split tiles have no outer stroke. Sections are separated by transparent internal gaps whose width equals the normal Favorite selection-ring thickness.
- An active split uses each member's existing `PinnedTileAccentResolver` color. One outer ring and the straight internal dividers interpolate spatially between those colors.
- An active split fills the entire shared tile with the ordinary active Favorite background. No member receives a separate focused fill.
- A custom group icon replaces the member composition and uses the ordinary single-color Favorite ring.

## Group lifecycle

- A launcher-backed split loads and unloads only as a group. Clicking a participant loads every member and focuses that participant; clicking shared row chrome restores the last active participant, falling back to the first.
- `Unload Split View` unloads every runtime instance and preserves the group.
- `Delete Split View…` removes the saved group and all launcher members after confirmation.
- Regular split rows expose a separate close button for each visible participant. `Close Split View` in the group context menu closes every member.
- Removing one participant dissolves a two-member group and leaves the survivor standalone.

## Separation and capacity

- Separating one participant places it immediately after the remaining group.
- Separating a two-member group or using `Separate All Tabs` expands members at the group's position in member order.
- If Favorite cannot hold every separated member, the earliest members fill available Favorite slots and overflow members move to the beginning of the current Space's Pinned section, preserving order.

## Metadata and commands

- A group can be edited like a launcher: optional name and optional icon, but no URL.
- Without a name, rows display the localized equivalent of `N Tabs`.
- Without a group icon, sidebar surfaces show the member composition. With an icon, every surface shows one icon and the group behaves visually like a normal tab row/tile.
- Duplicate creates an inactive adjacent group. Saved duplicates remain unloaded; regular duplicates do not become selected.
- Explicit duplicate names use collision suffixes: `Name (2)`, `Name (3)`, and so on. Unnamed groups continue to use `N Tabs` without suffixes. The icon is copied.
- `Move to` moves the whole group atomically using the same rules as drag-and-drop.
- `Add Tab…` is available below four members and uses the command palette. Existing items move into the group; a new URL creates a member in the group's container. Cancellation leaves no placeholder or ghost row.
- At four members, add commands and WebView split-drop zones are disabled and the existing split-limit notification is used.
- There is no `Share Split View…` or separate `Change Icon…` command. Icon changes happen through group or launcher `Edit`.

## Drag preview

- Preview is target-adaptive: Favorite targets use the real Favorite split tile; Regular, Pinned, and Folder targets use the real split row.
- Sidebar and preview share rendering modules rather than approximating one another.
- Member order, group icon/name, loaded state, group-level selection fill, and accent gradient match the corresponding sidebar item.
- The drag preview remains attached to the pointer during tab-on-tab pairing. The empty reserved pill is destination presentation, not a replacement preview.

## Presentation architecture

- `SplitGroupSegmentedRow` is the single owner of split-row pill width, inner insets, spacing, clipping, selected material, and separators. Live rows, transition snapshots, and row drag previews only adapt member data and interaction into it.
- `SplitGroupRowIconView` is the single split-member icon treatment. Bitmap, system, and emoji sources all resolve into the canonical 18-point slot; only bitmap sources use aspect-fit and the four-point clip.
- Live adapters may fetch or observe favicon state. Snapshot and drag adapters receive resolved values and create no task, observer, timer, or cache of their own.
- Split-pairing hit testing normalizes Regular, uniform Pinned, measured Pinned, and Folder children into one visual-row candidate before applying admission policy. Row count and insertion geometry never depend on whether a row has split-pairing metadata.
- Row rendering owns no drag mutation or container conversion. Drop commands accept a durable group ID and reload the canonical group before validating source residence or changing topology.

## Transition snapshots

- Snapshot regular content uses the same visual row projection as the live sidebar: a split group is one row, never one row per hidden member record.
- Snapshot split rows use the live split-row layout metrics for the outer row, member pills, favicon baseline, and title-visibility threshold. Every snapshot member segment fills the same 28-point pill height as its live `SplitGroupSegment`, keeping the shared favicon-and-title label centered on the 36-point row throughout the transition. Custom group names/icons and unloaded-icon desaturation use the same presentation branch as the live row.
- Member icons are resolved before the transition through `SplitGroupMemberIconResolver`. Cached or stored launcher favicons take priority over a temporary live globe placeholder; snapshot views perform no asynchronous favicon work. Split-member bitmap snapshot icons use the same resizable, aspect-fit, 18-point frame and 4-point clipping shape as live split favicons, regardless of source-image intrinsic size. Ordinary launcher and regular-tab snapshots preserve their corresponding live icon presentation instead of inheriting split-only bitmap scaling.
- A transition snapshot may retain a pre-conversion Split Group value, but commits canonicalize that value by the durable group ID before validating source ownership. Container conversion never trusts snapshot member identities.
- When container conversion removes two or more regular members in one mutation, the regular-list animation accepts the replacement atomically. It must not animate the first raw member and reinterpret the remaining members as standalone rows.
