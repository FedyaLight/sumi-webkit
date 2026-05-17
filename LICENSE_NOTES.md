# License Notes

Sumi is GPL-3.0. Third-party components keep their own notices where they are
vendored or directly used.

## Brave adblock-rust

`Vendor/Brave/AdblockRustAdapter` is retained as developer/off-browser tooling
around Brave's `adblock` crate from `brave/adblock-rust` while prepared-bundle
generation moves out of this repository.

- Upstream: https://github.com/brave/adblock-rust
- Crate license: MPL-2.0
- Sumi usage: developer-side prepared-bundle generation only
- Runtime role: none in Sumi.app; the browser does not invoke the helper, parse raw
  lists, or use it as a live WebKit request interceptor/WebExtension

This notice does not make the entire Sumi Adblock module MPL-2.0. Sumi remains
GPL-3.0, with the vendored/used Brave `adblock` crate component governed by
MPL-2.0 as applicable.

## Prepared protection bundles

`sumi-webkit` consumes prepared protection bundles only. Raw list fetching,
conversion, and future bundle generation belong outside the browser, planned for
a separate `sumi-protection-bundles` repository driven by GitHub Actions. Any
upstream list contents used by that external generation pipeline may have their
own licenses, terms, and notices from the upstream list projects.

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

The final browser product does not ship a redirect/scriptlet runtime path. No
Brave/uBO resource payload is copied into Sumi.app, and the Brave
`adblock-rust` notice above now covers only retained developer tooling outside
the app runtime.
