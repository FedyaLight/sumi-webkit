# Browser chrome pipeline

Aura chrome is one native Helium/Chromium desktop chrome stack.

## Canonical surfaces

- sidebar
- address bar
- site controls
- media cards
- theme editor
- menus and transient panels

## Secondary settings surface

`aura://settings/` is allowed as an isolated secondary surface for
customization import, export, and reset. It must not become part of the
always-live primary shell runtime.

## Data flow

`Helium runtime -> Aura adapters -> Aura services/controllers -> native chrome surfaces`

## Hard rules

- one canonical address bar only
- no local duplicate URL bar implementations
- no second always-live shell runtime
- no primary browser chrome implemented as a parallel WebUI shell
- no direct feature ownership leaks across subsystems
- no pixel-perfect Zen values should be hard-coded unless they are grounded in
  `zen-source-grounding.md`
- one sidebar density token set and one transient surface taxonomy only
