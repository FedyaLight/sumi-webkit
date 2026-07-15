#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

source_file="Sumi/Privacy/SumiGPCNavigationResponder.swift"
trap_pattern='\b(precondition|preconditionFailure|fatalError)[[:space:]]*\('

guard_require_file "$source_file"
trap_hits="$(guard_capture_matches "$trap_pattern" "$source_file")"
if [[ -n "$trap_hits" ]]; then
  printf '%s\n' "$trap_hits"
  echo "error: GPC exact-transaction handling must return a typed failure, not terminate the process" >&2
  exit 1
fi

echo "GPC navigation fail-closed guard passed"
