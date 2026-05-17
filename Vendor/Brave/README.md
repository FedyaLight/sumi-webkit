Brave vendored adapters
=======================

`AdblockRustAdapter` is retained as local developer tooling around
`brave/adblock-rust` (`adblock` crate, MPL-2.0) while prepared-bundle generation
moves out of `sumi-webkit`.

Sumi.app no longer builds, copies, or invokes this helper. The browser consumes
prepared protection bundles only; it does not fetch raw filter lists, parse
ABP/uBO syntax, or run `adblock-rust` at runtime. The planned long-term home for
generation is a separate `sumi-protection-bundles` repository driven by GitHub
Actions.

If this adapter remains useful during the transition, it should be run manually
or from external bundle-generation automation only. Browser runtime blocking
stays native `WKContentRuleList` compiled from verified prepared bundle shards.
