#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

status=0

service_imports="$(
  grep -nE 'import (Sparkle|Combine)' Sumi/Updates/SumiUpdaterService.swift || [[ $? -eq 1 ]]
)"
if [[ -n "$service_imports" ]]; then
  printf 'SumiUpdaterService must not import Sparkle or Combine directly:\n%s\n' "$service_imports" >&2
  status=1
fi

disallowed_sparkle_imports="$(
  find Sumi/Updates -name '*.swift' -type f ! -name 'SumiSparkle*.swift' \
    -exec grep -nE 'import Sparkle' {} + || [[ $? -eq 1 ]]
)"
if [[ -n "$disallowed_sparkle_imports" ]]; then
  printf 'Sparkle imports must stay in SumiSparkle role files:\n%s\n' "$disallowed_sparkle_imports" >&2
  status=1
fi

if [[ "$status" -ne 0 ]]; then
  echo "updater Sparkle boundary audit failed" >&2
  exit "$status"
fi

echo "updater Sparkle boundary audit passed"
