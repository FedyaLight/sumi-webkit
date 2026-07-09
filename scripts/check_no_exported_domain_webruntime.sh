#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
matches="$(rg -n '@_exported import Sumi(Domain|WebRuntime)' -g '*.swift' . || true)"
if [[ -n "$matches" ]]; then
  printf 'error: @_exported import SumiDomain/SumiWebRuntime is forbidden:\n%s\n' "$matches" >&2
  exit 1
fi
echo "no @_exported Domain/WebRuntime re-exports"
