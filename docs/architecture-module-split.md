# Sumi module split (Phase 7 scaffold)
#
# The app still builds as a single Xcode target (`Sumi`). Full SPM/Xcode target
# isolation is the end state; until then, `scripts/check_domain_isolation_boundary.sh`
# enforces Foundation-only on a growing allowlist of domain files.
#
# Intended dependency direction (compile-time once targets exist):
#
#   SumiDomain          — Foundation models, URL/site identity, permission keys
#        ▲
#   SumiWebRuntime      — WebKit, TabWebViewSession, WindowWebViewRegistry
#        ▲
#   SumiAppUI           — SwiftUI / AppKit chrome, BrowserManager composition
#
# Do not reverse edges. Domain must never import SwiftUI, AppKit, or WebKit.
#
# Expand DOMAIN_FILES in check_domain_isolation_boundary.sh as types are peeled
# out of Models that still embed runtime (Tab WebView mirror, BrowserWindowState
# dual-write, BrowserConfiguration, etc.).
