Brave vendored adapters
=======================

`AdblockRustAdapter` is a small local helper executable around
`brave/adblock-rust` (`adblock` crate, MPL-2.0). Sumi uses it as the production
compiler backend for the native Adblock module's offline ABP/uBO-to-WebKit
content-blocking translation.

The helper is built by the Xcode app target with `cargo build --locked` and
copied beside the app executable as `sumi-adblock-rust-adapter`. A Rust toolchain
with Cargo must be installed for normal app and unit-test builds.

This executable is intentionally temporary. The production-suitable long-term
shape is a Rust static library or XCFramework with a narrow C ABI wrapper; that
would remove process spawning and make packaging/signing more explicit. Until
then, Swift reaches the helper only through `AdblockRustCompiler`, the helper is
invoked only as a short-lived compiler step, and it is never a live request
interceptor.

The browser runtime does not use adblock-rust as a per-request engine. WebKit
runtime blocking remains native `WKContentRuleList`.
