#!/usr/bin/env bash
# SumiBrowserCore package boundary (R7 / W3).
#
# Ensures SumiBrowserCore stays free of SwiftUI and builds standalone via
# `swift build`. Hosts Foundation-safe tab-structure event bus, UUID ports,
# and store protocols (SumiDomain). No SwiftUI / AppKit / WebKit.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

pkg="Packages/SumiBrowserCore"
sources="${pkg}/Sources"
forbidden_import_pattern='^import SwiftUI\b'
failures=0

printf '%s\n' 'BrowserCore package boundary guardrail'
printf '%s\n' '--------------------------------------'

if [[ ! -d "$sources" ]]; then
  printf 'error: BrowserCore package sources missing: %s\n' "$sources" >&2
  exit 1
fi

if rg -n "$forbidden_import_pattern" -g '*.swift' "$sources" >/dev/null 2>&1; then
  printf 'error: SumiBrowserCore imports SwiftUI:\n' >&2
  rg -n "$forbidden_import_pattern" -g '*.swift' "$sources" >&2 || true
  failures=$((failures + 1))
else
  printf 'ok  %s (no SwiftUI imports)\n' "$pkg"
fi

printf '==> swift build --package-path %s\n' "$pkg"
if ! swift build --package-path "$pkg"; then
  printf 'error: swift build failed for %s\n' "$pkg" >&2
  failures=$((failures + 1))
fi

if (( failures > 0 )); then
  exit 1
fi

echo "browser core package boundary passed"
