# Sumi Browser

Sumi presents pages through regular tabs and saved launchers. Split groups are durable sidebar items whose runtime pages are projected into a window when the group is active.

## Split View Language

**Split Group**:
A durable sidebar item containing two to four ordered page identities and one layout. The group keeps its identity when moved between Regular, Pinned, Folder, and Essentials.
_Avoid_: Split placeholder row, ghost row

**Regular Member**:
A split participant owned by a Space's regular tab collection.
_Avoid_: Unsaved launcher

**Launcher Member**:
A split participant owned by Pinned, a Pinned folder, or Essentials. A launcher may be loaded or unloaded without changing its durable identity.
_Avoid_: Placeholder tab

**Group Activation**:
Loading every runtime page of a launcher-backed split and focusing one participant. Individual launcher members cannot be loaded or unloaded independently while grouped.
_Avoid_: Member activation, partial loading

**Container Conversion**:
An atomic replacement of every member identity when a whole split group moves between Regular and launcher-backed containers. The group itself is not duplicated or dissolved.
_Avoid_: Split copy, group recreation

**Essential Split Tile**:
One Essentials grid item representing an entire split group. Its participants do not consume additional Essentials grid slots.
_Avoid_: Split member tiles

**Essential Selection Material**:
The site-derived visual treatment applied to a selected Essential or Essential Split Tile. It belongs only to the Essentials presentation and is never applied to Regular or Pinned launchers.
_Avoid_: Pinned backdrop, global launcher gradient

**Sidebar Visual Item**:
One ordered sidebar identity presented and moved as a whole. A regular tab, launcher, folder, or Split Group each occupies one visual position regardless of the number of durable records behind it.
_Avoid_: Render row record, split member slot

**Presented Drop Intent**:
The exact sidebar destination currently communicated by the visible drop gap. A completed drop commits that same destination even if rendering the gap changes surrounding geometry.
_Avoid_: Recomputed drop target, approximate hover slot

**Drag Presentation**:
The target-adaptive appearance of one Sidebar Visual Item while it is being moved. It preserves item identity while matching the row, folder, or Essentials surface of the current Presented Drop Intent.
_Avoid_: Drag snapshot copy, generic ghost
