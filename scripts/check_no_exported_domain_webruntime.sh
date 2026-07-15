#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

guard_expect_no_matches \
  '@_exported Domain/WebRuntime re-exports' \
  '@_exported import Sumi(Domain|WebRuntime)' \
  -g '*.swift' .
guard_finish 'Domain/WebRuntime re-export boundary'
