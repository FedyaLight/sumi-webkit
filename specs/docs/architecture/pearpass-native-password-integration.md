# PearPass Native Password Integration

## Status

Deferred. This track is intentionally parked while Aura focuses on Zen shell parity and current WebKit polish.

## Decision

Aura should prefer a first-party password flow backed by `PearPass desktop` over embedding the current PearPass browser extension runtime.

## Why

- The public PearPass browser extension is Chrome-first and MV3-first.
- Pulling that extension into Aura would recreate the same class of problems already seen with Bitwarden:
  - popup/background lifecycle
  - active tab and frame targeting
  - content-script injection
  - native messaging origin compatibility
- A native Aura integration keeps runtime, power usage, and fill UX under Aura control.

## Target Model

- `popup-first` password UX in Aura chrome
- on-demand connection to `PearPass desktop`
- no page-level background work until the user explicitly invokes the password manager
- fill targeted to the current tab and frame with Aura-owned routing

## Not In Scope Right Now

- No PearPass extension compatibility layer
- No migration away from current Safari-first extension platform during the Zen parity pass

