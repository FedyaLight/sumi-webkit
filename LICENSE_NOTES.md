# License Notes

Sumi is GPL-3.0. Third-party components keep their own notices where they are
vendored or directly used.

## Brave adblock-rust

`Vendor/Brave/AdblockRustAdapter` builds a local helper executable that uses
Brave's `adblock` crate from `brave/adblock-rust`.

- Upstream: https://github.com/brave/adblock-rust
- Crate license: MPL-2.0
- Sumi usage: offline ABP/uBO-style filter translation into Apple/WebKit
  content-blocking JSON for the native Adblock compiler boundary
- Runtime role: compiler helper only; not a live WebKit request interceptor and
  not a WebExtension

This notice does not make the entire Sumi Adblock module MPL-2.0. Sumi remains
GPL-3.0, with the vendored/used Brave `adblock` crate component governed by
MPL-2.0 as applicable.
