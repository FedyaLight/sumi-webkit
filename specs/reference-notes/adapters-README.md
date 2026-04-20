# Aura adapters

Adapters are the only place where Aura touches Helium or Chromium browser
internals.

Their job is to translate:

- browser profiles
- tabs and web contents
- extension state
- media sessions
- window restore hooks
- drop hit testing and mount points

Adapters must stay thin and never become product-logic owners. They expose
verbs and geometry, not Aura shell policy.

All C++ product code in this repo uses `namespace aura_browser`, not
`namespace aura`, to avoid collisions with Chromium's existing `aura`
windowing namespace.
