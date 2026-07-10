#!/usr/bin/env bash
# Keep Swift packages reserved for boundaries with real independent value.
# A genuinely independent, tested boundary may be added by deliberately
# updating this allowlist together with its project and CI integration.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

expected_manifests="$(
  printf '%s\n' \
    'Packages/SumiDomain/Package.swift' \
    'Packages/SumiWebRuntime/Package.swift'
)"
actual_manifests="$(
  find Packages -mindepth 2 -maxdepth 2 -name Package.swift -print | sort
)"

if [[ "$actual_manifests" != "$expected_manifests" ]]; then
  printf '%s\n' 'error: package topology drifted from the two intentional module boundaries' >&2
  printf 'expected:\n%s\n' "$expected_manifests" >&2
  printf 'actual:\n%s\n' "$actual_manifests" >&2
  exit 1
fi

echo "package topology passed"
