#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

usage() {
  cat <<'USAGE'
Usage: scripts/ci/preflight.sh <fast|portable|full>

  fast      Validate changed text, shell syntax, JSON, and the CI manifest.
  portable  Run fast checks and all architecture guardrails.
  full      Run portable checks and the complete PR test profile.
USAGE
}

run_fast_checks() {
  local script
  local json_file

  git diff --check
  git diff --cached --check

  while IFS= read -r script; do
    [[ -n "$script" ]] && bash -n "$script"
  done < <(git ls-files '*.sh' '.githooks/*')

  for json_file in \
    scripts/ci/test-manifest.json \
    docs/persistence/persistence-map.json \
    Sumi/Resources/Localizable.xcstrings; do
    python3 -m json.tool "$json_file" >/dev/null
  done

  scripts/ci/check_test_sharding.sh
}

run_portable_checks() {
  run_fast_checks
  scripts/check_architecture_guardrails.sh
}

case "${1:-}" in
  fast)
    [[ $# -eq 1 ]] || { usage; exit 2; }
    run_fast_checks
    ;;
  portable)
    [[ $# -eq 1 ]] || { usage; exit 2; }
    run_portable_checks
    ;;
  full)
    [[ $# -eq 1 ]] || { usage; exit 2; }
    run_portable_checks
    scripts/ci/run_tests.sh verify-toolchain pr
    scripts/ci/run_tests.sh profile pr
    ;;
  *)
    usage
    exit 2
    ;;
esac

