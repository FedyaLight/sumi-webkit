# Aura downstream layout

Aura is a downstream product layer, not a fork that freely edits upstream code.

## Product reference

- `Zen` is the canonical UX and behavior reference.
- Aura keeps its own Essentials semantics as the intentional divergence.
- `Nook` may still be useful to inspect old experiments, but it is not an
  architecture source of truth and should not be ported structurally.

## Top-level layout

- `aura/native`
  Native browser chrome built directly into Helium desktop surfaces.
- `aura/services`
  Product-domain services.
- `aura/adapters`
  Thin Chromium/Helium integration hooks.
- `aura/mojom`
  Optional narrow typed boundaries for isolated secondary surfaces only.
- `config`
  Pinned upstreams, ownership, build assumptions.
- `schemas`
  Versioned persisted state schemas.
- `docs`
  Architecture, migration, and performance contracts.

## Ownership rules

- Do not create a second always-live shell runtime beside Helium.
- Do not implement product logic directly in Chromium view classes.
- Do not let a secondary WebUI surface become the owner of browser chrome.
- Do not add a second implementation of an existing surface.
- If a cross-subsystem flow cannot be expressed through typed service events or
  narrow contracts, the design is not ready.
- If Helium already provides the capability cleanly, prefer upstream behavior
  over Aura-specific replacement logic.
- The primary visible browser chrome must live in native Helium/Chromium Views
  surfaces, not in a parallel HTML shell.
