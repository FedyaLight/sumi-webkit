#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

approved_files=(
  "Sumi/ContentBlocking/SumiTrackingProtection.swift"
)

is_approved() {
  local candidate="$1"
  local approved
  for approved in "${approved_files[@]}"; do
    if [[ "$candidate" == "$approved" ]]; then
      return 0
    fi
  done
  return 1
}

status=0
while IFS= read -r match; do
  relative_path="${match%%:*}"
  if ! is_approved "$relative_path"; then
    echo "disallowed TrackerRadarKit import: $match" >&2
    status=1
  fi
done < <(
  cd "$repo_root"
  find Sumi -type f -name '*.swift' -print0 |
    xargs -0 awk '
      /^[[:space:]]*(@preconcurrency[[:space:]]+)?import[[:space:]]+TrackerRadarKit([[:space:]]|$)/ {
        print FILENAME ":" FNR ":" $0
      }
    '
)

if [[ "$status" -ne 0 ]]; then
  echo "TrackerRadarKit imports are only allowed in the approved tracking adapter boundary." >&2
  exit "$status"
fi

echo "TrackerRadarKit import boundary audit passed"
