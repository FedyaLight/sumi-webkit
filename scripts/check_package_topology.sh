#!/usr/bin/env bash
# Every local package is an independently tested boundary. The authoritative
# CI manifest owns that inventory; this guard derives package topology from it
# instead of keeping a second allowlist.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

guard_require_directory Packages
guard_require_command python3
guard_require_file scripts/ci/ci_manifest.py
guard_require_file scripts/ci/test-manifest.json

package_suites="$(
  python3 scripts/ci/ci_manifest.py list nightly swift-package
)" || exit
expected_manifests=''
while IFS= read -r suite; do
  [[ -n "$suite" ]] || continue
  package_path="$(
    python3 scripts/ci/ci_manifest.py suite-field "$suite" path
  )" || exit
  expected_manifests="${expected_manifests}${package_path}/Package.swift"$'\n'
done <<< "$package_suites"
expected_manifests="$(printf '%s' "$expected_manifests" | sort)"

manifest_inventory="$(mktemp "${TMPDIR:-/tmp}/sumi-package-manifests.XXXXXX")"
trap 'rm -f "$manifest_inventory"' EXIT
if ! find Packages -mindepth 2 -maxdepth 2 -name Package.swift -print \
    > "$manifest_inventory"; then
  guard_fatal 'failed to enumerate local Swift packages'
fi
actual_manifests="$(sort "$manifest_inventory")"

if [[ "$actual_manifests" != "$expected_manifests" ]]; then
  printf '%s\n' 'error: local packages and authoritative CI suites differ' >&2
  printf 'expected:\n%s\n' "$expected_manifests" >&2
  printf 'actual:\n%s\n' "$actual_manifests" >&2
  exit 1
fi

# SumiTests imports local package modules while being hosted by Sumi.app. They
# stay dynamic so dyld shares one image across host and test bundle.
while IFS= read -r manifest; do
  [[ -n "$manifest" ]] || continue
  guard_require_file "$manifest"
  dynamic_product_count="$(guard_count_matches 'type: \.dynamic' "$manifest")"
  if (( dynamic_product_count == 0 )); then
    printf 'error: hosted-test package product must stay dynamic: %s\n' \
      "$manifest" >&2
    exit 1
  fi
done <<< "$actual_manifests"

echo "package topology passed"
