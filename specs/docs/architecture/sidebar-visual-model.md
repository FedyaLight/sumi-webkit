# Sidebar visual model

This document freezes the first implementation-ready visual model for Aura's
single-toolbar, single-sidebar shell.

Zen is the visual target. Aura diverges only in Essentials semantics, not in
the shell's visual density language.

## Visual goals

- look and feel within Zen-class parity for sidebar density and hierarchy
- one density token set across the whole sidebar
- no local per-view spacing constants
- no ad hoc "fix-up" paddings in individual hosts

## Sidebar section order

Top to bottom:

1. navigation controls + canonical address bar
2. essentials strip
3. active space header
4. pinned section for the active space
5. regular entry tree for the active space
6. `New Tab`
7. media card stack

## Source-grounded hard tokens

The following values are treated as grounded Zen-derived defaults:

- collapsed sidebar width: `60px`
- essentials item minimum height: `44px`
- tab block margin: `2px`
- base chrome radius: `7px`
- toolbar button radius: `6px`
- context menu radius: `8px`
- elevated shadow blur token: `9.73px`
- toolbar icon fallback size: `16px`

## Aura downstream defaults

These values are implementation defaults for Aura's first native pass. They are
not claimed to be exact Zen internals.

- sidebar section gap: `10px`
- group header horizontal padding: `10px`
- group header vertical padding: `6px`
- regular launcher row minimum height: `36px`
- pinned row minimum height: `36px`
- folder indent step: `14px`
- media card stack gap: `10px`
- footer gap between `New Tab` and media stack: `12px`

## Density rules

- Essentials are visually denser than cards, but larger than regular launcher
  rows.
- Pinned section rows and regular tree rows share the same row baseline.
- Group headers, separators, and footer affordances use one spacing scale.
- Hover-only affordances must not reserve dead layout space when hidden.
- The media stack grows downward and must never push the top shell into jitter.

## Sidebar width modes

- collapsed
- revealed compact
- expanded

Rules:

- collapsed width follows the frozen `60px` token
- revealed compact and expanded use the same density tokens
- compact reveal must not switch to a second visual language

## Section behavior rules

### Navigation and address bar

- navigation controls and address bar live in one top cluster
- the unified hub cluster aligns to the trailing edge of the address bar
- overflow extension strip appears directly below the address bar cluster

### Essentials

- same-profile spaces reuse one fixed Essentials strip
- switching to a different profile swaps that strip to the destination
  profile's Essentials
- essentials use the larger visual target size already grounded by Zen
- live essential state must not alter row geometry

### Space header and pinned section

- active space header acts as the collapse toggle for pinned rows
- pinned rows sit directly below the active space header
- collapsing the pinned section removes its height; it does not leave a spacer

### Entry tree

- regular entries use one indent model for folders and children
- folder collapse must animate height cleanly without leaving empty slots
- drag preview placeholders must respect the same row metrics as committed rows

### Footer and media

- `New Tab` sits above the media stack
- media cards are full-width sidebar cards in the footer region
- multiple cards stack with stable spacing and without relayout thrash
- decorative media notes animation must not alter row or footer geometry

## Hover and pressed timing

- hover fade-in timing for small affordances follows the fast Zen-style feel
- pressed states should feel immediate and never wait for layout changes
- density transitions must not rely on expensive blur or shadow recomputation

## Compact mode interaction

- in single-toolbar compact mode, the sidebar hides fully and reveals from the
  correct side edge
- revealed compact sidebar uses the same visual density tokens as expanded
  sidebar
- compact reveal must not leave phantom section gaps when media cards or pinned
  rows are absent

## Performance guardrails

- one density token set, computed once
- no repeated layout invalidation from hover-only controls
- no expensive material blur stack on every sidebar row
- no observer graph per section for simple visibility toggles
