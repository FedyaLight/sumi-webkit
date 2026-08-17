# Sumi advanced-blocking runtime

This directory is the reproducible source for the two generated JavaScript
resources embedded by Sumi:

- `sumi-advanced-blocking.js` applies a document-scoped result returned by
  SafariConverterLib's `FilterEngine`. Sumi injects only a sub-1 KB bootstrap
  into every frame and compiles this larger runtime only when a lookup has a
  real CSS, ExtendedCSS, scriptlet, script, or URL-cleaning effect.
- `sumi-scriptlet-compiler.js` is loaded lazily in JavaScriptCore by the native
  process, so the much larger AdGuard scriptlet library is not parsed in every
  web frame.

The split preserves SafariConverterLib filtering semantics without putting the
scriptlet catalogue on the page hot path.

## Rebuild

Run `pnpm install --frozen-lockfile && pnpm build` in this directory. The build
writes deterministic minified resources to
`Sumi/Resources/ContentBlocking/`. Review and commit both generated files.

The runtime is paired with SafariConverterLib 4.3.0 (revision
`7a2e93f0afa70479cc59985f332025236c3f0c39`) and must be upgraded atomically
with the Swift package and prepared-bundle `runtimeVersion`.

## Licensing and provenance

This adapter is GPL-3.0-or-later, like Sumi. It links generated code from:

- [SafariConverterLib](https://github.com/AdguardTeam/SafariConverterLib),
  GPL-3.0, version 4.3.0.
- [AdGuard ExtendedCss](https://github.com/AdguardTeam/ExtendedCss), GPL-3.0,
  version 2.1.1.
- [AdGuard Scriptlets](https://github.com/AdguardTeam/Scriptlets), GPL-3.0,
  version 2.3.1.
