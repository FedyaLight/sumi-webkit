# Blank window and window modes

Aura adopts Zen's distinction between a normal browser window and a blank
window, but keeps the implementation native to Helium.

## Window modes

Aura has two explicit window modes:

- `standard`
- `blank`

A blank window is not "just another space". It is a distinct shell mode with
its own startup and restore behavior.

## Standard window

A standard window owns the normal Aura shell:

- spaces
- profile routing
- essentials
- pinned sections
- folders
- media cards
- unified hub
- theme runtime

## Blank window

A blank window intentionally opens without the normal space and pinned context.

Blank windows:

- do not restore the standard sidebar tree
- do not attach essentials or pinned sections on open
- do not silently inherit the last active standard window state
- may still host real tabs and navigation through Helium
- remain a first-class window mode, not an implementation hack on top of the
  standard mode

## Startup and restore rules

- startup restore must remember whether a window was `standard` or `blank`
- a blank window should restore as blank unless the restore entry is invalid
- a standard window must not degrade into blank mode just because shell state
  is partially missing
- blank windows do not become the primary source of shell restore for normal
  spaces

## Keyboard and command semantics

Blank windows need explicit command routing:

- create blank window
- focus existing blank window if the product later adopts reuse behavior

The important rule is that blank-window shortcuts and commands must not be
implemented as aliases for "new tab" or "new space".

## Future compatibility

Blank windows intersect with future multi-window sync, but that work stays out
of the first shell rewrite. The only frozen rule now is that blank windows are
a distinct mode in state, restore, and command semantics.
