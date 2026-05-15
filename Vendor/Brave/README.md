Brave vendored adapters
=======================

`AdblockRustAdapter` is a small, non-app-linked smoke-test CLI around
`brave/adblock-rust` (`adblock` crate, MPL-2.0). It exists to pin and verify the
offline ABP/uBO-to-WebKit content-blocking compilation surface while the Sumi app
keeps a fakeable Swift compiler boundary.

The browser runtime does not call this CLI and does not use adblock-rust as a
live request interceptor.

