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

## Adblock filter-list registry

Sumi's native Adblock registry stores upstream filter-list metadata and URLs.
The application does not vendor those third-party list contents; selected lists
are fetched from their upstream maintainers at update time. Those fetched list
contents may have their own licenses, terms, and notices from the upstream list
projects.

## AdGuard SafariConverterLib comparison

Sumi does not currently vendor or ship AdGuard SafariConverterLib. The developer
comparison harness in `scripts/compare_native_adblock_compilers.sh` can clone a
local checkout of `AdguardTeam/SafariConverterLib` for explicit native compiler
comparison only.

- Upstream: https://github.com/AdguardTeam/SafariConverterLib
- License: GPL-3.0
- Sumi usage in this revision: developer comparison harness only; not a
  production app dependency and not an enhanced/runtime metadata source

## Adblock redirect/noop resource compatibility metadata

Sumi recognizes a small set of uBO-compatible redirect/noop resource names for
diagnostics and future compatibility wiring: `noopjs`, `noopcss`,
`1x1-transparent.gif`, `noopframe`, and `noop.txt`, plus selected aliases.
These entries are Sumi-owned metadata only. Sumi does not vendor Brave
`adblock-resources` files, uBlock Origin resource contents, or a full redirect
resource tree.

The current WKWebView implementation classifies those redirect resources as
unsupported because WebKit content blockers do not replace HTTP(S) response
bodies and `WKURLSchemeHandler` cannot intercept WebKit's built-in HTTP(S)
schemes. This keeps license handling simple: no Brave/uBO resource payload is
copied into the app, and the existing Brave `adblock-rust` MPL-2.0 notice above
continues to cover only the Rust compiler dependency.
