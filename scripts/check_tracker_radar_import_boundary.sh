#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

guard_expect_no_matches \
  'TrackerRadarKit import in Sumi.app runtime' \
  '^[[:space:]]*(@preconcurrency[[:space:]]+)?import[[:space:]]+TrackerRadarKit([[:space:]]|$)' \
  -g '*.swift' Sumi
guard_finish 'TrackerRadarKit runtime import audit'
