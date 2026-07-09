#!/usr/bin/env bash
# Fail if HistoryTabRecorder lives under Models/Tab (W6/R11 — belongs in Sumi/History/).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

forbidden="Sumi/Models/Tab/HistoryTabRecorder.swift"
expected="Sumi/History/HistoryTabRecorder.swift"

if [[ -e "$forbidden" ]]; then
  printf 'error: HistoryTabRecorder must not live under Models/Tab:\n  found: %s\n  expected: %s\n' \
    "$forbidden" "$expected" >&2
  exit 1
fi

# Also catch accidental copies / renames still under Models/Tab.
matches="$(
  find Sumi/Models/Tab -name '*HistoryTabRecorder*' 2>/dev/null || true
)"

if [[ -n "$matches" ]]; then
  printf 'error: HistoryTabRecorder artifacts must not live under Models/Tab:\n%s\n' "$matches" >&2
  exit 1
fi

if [[ ! -f "$expected" ]]; then
  printf 'error: expected HistoryTabRecorder at %s\n' "$expected" >&2
  exit 1
fi

echo "HistoryTabRecorder location guardrail passed"
