#!/usr/bin/env bash
# Fail if HistoryTabRecorder lives under Models/Tab (W6/R11 — belongs in Sumi/History/).
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

forbidden="Sumi/Models/Tab/HistoryTabRecorder.swift"
expected="Sumi/History/HistoryTabRecorder.swift"

guard_expect_absent_path 'HistoryTabRecorder under Models/Tab' "$forbidden"
guard_require_directory Sumi/Models/Tab
guard_require_file "$expected"

# Also catch accidental copies / renames still under Models/Tab.
if matches="$(find Sumi/Models/Tab -name '*HistoryTabRecorder*' -print)"; then
  :
else
  guard_fatal 'failed to enumerate HistoryTabRecorder artifacts'
fi

if [[ -n "$matches" ]]; then
  guard_record_failure "HistoryTabRecorder artifacts remain under Models/Tab: $matches"
fi

guard_finish 'HistoryTabRecorder location guardrail'
