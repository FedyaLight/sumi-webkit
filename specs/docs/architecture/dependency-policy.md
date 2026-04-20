# Dependency policy

Aura adds dependencies only for concrete value.

## Rules

- Prefer existing Helium/Chromium capabilities over new third-party layers.
- Do not add a dependency just to avoid writing a small adapter or helper.
- Every dependency must have:
  - a clear owner
  - a removal story
  - a reason it is better than upstream or stdlib alternatives

## Risk policy

- Cheap-to-migrate layers may take more experimentation.
- Critical runtime, persistence, and browser integration layers must stay
  conservative and easy to reason about.
- If a dependency would become part of the hot path for tabs, profiles, media,
  theme, extensions, or restore, the burden of proof is high.

## JS and TS note

Aura is native-first today. If JS/TS surfaces grow later:

- prefer strict typing
- prefer one source of truth for contracts
- handle ESM-only packages deliberately
- use module resolution that understands `exports`

## Supply chain

- dependency review is a required PR gate
- CodeQL scanning is enabled for the repo
- secrets never live in dependency configuration checked into the repo
