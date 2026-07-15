#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

guard_require_file Sumi/Updates/SumiUpdaterService.swift
guard_expect_no_matches \
  'Sparkle/Combine import in updater policy service' \
  '^[[:space:]]*(@preconcurrency[[:space:]]+)?import[[:space:]]+(Sparkle|Combine)([[:space:]]|$)' \
  Sumi/Updates/SumiUpdaterService.swift
guard_expect_no_matches \
  'Sparkle import outside SumiSparkle adapters' \
  '^[[:space:]]*(@preconcurrency[[:space:]]+)?import[[:space:]]+Sparkle([[:space:]]|$)' \
  -g '*.swift' -g '!SumiSparkle*.swift' Sumi/Updates
guard_finish 'updater Sparkle boundary audit'
