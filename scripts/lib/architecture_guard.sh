#!/usr/bin/env bash

# Shared primitives for source-based architecture checks.
#
# Ripgrep uses exit status 1 for a valid scan with no matches and status 2 for
# invalid input or an I/O error. The distinction is architectural evidence:
# callers may treat the former as zero, but must never turn the latter into a
# passing boundary check.

if [[ -n "${SUMI_ARCHITECTURE_GUARD_DSL_LOADED:-}" ]]; then
  return 0
fi
readonly SUMI_ARCHITECTURE_GUARD_DSL_LOADED=1

guard_failures=0
guard_repo_root=""

guard_fatal() {
  printf 'error: %s\n' "$1" >&2
  return 2
}

guard_initialize() {
  if (( $# != 1 )); then
    guard_fatal 'guard_initialize expects the repository root'
    return
  fi

  local root="$1"
  if [[ ! -d "$root" ]]; then
    guard_fatal "repository root is not a directory: $root"
    return
  fi

  guard_repo_root="$(cd "$root" && pwd -P)"
  cd "$guard_repo_root"
  guard_require_command rg
}

guard_require_command() {
  if (( $# != 1 )); then
    guard_fatal 'guard_require_command expects one command name'
    return
  fi
  if ! command -v "$1" >/dev/null 2>&1; then
    guard_fatal "required command is unavailable: $1"
  fi
}

guard_require_file() {
  if (( $# != 1 )); then
    guard_fatal 'guard_require_file expects one path'
    return
  fi
  if [[ ! -f "$1" ]]; then
    guard_fatal "required architecture source is missing: $1"
  fi
}

guard_require_directory() {
  if (( $# != 1 )); then
    guard_fatal 'guard_require_directory expects one path'
    return
  fi
  if [[ ! -d "$1" ]]; then
    guard_fatal "required architecture source directory is missing: $1"
  fi
}

guard_count_lines() {
  if (( $# != 1 )); then
    guard_fatal 'guard_count_lines expects one file path'
    return
  fi
  guard_require_file "$1" || return
  wc -l < "$1" | tr -d '[:space:]'
}

guard_capture_matches() {
  if (( $# < 2 )); then
    guard_fatal 'guard_capture_matches expects a pattern and at least one rg argument'
    return
  fi

  local pattern="$1"
  shift
  local output
  local scan_status
  if output="$(rg -n -e "$pattern" "$@" 2>&1)"; then
    scan_status=0
  else
    scan_status=$?
  fi

  case "$scan_status" in
    0)
      [[ -n "$output" ]] && printf '%s\n' "$output"
      ;;
    1)
      return 0
      ;;
    *)
      printf 'error: architecture scan failed (rg status %d)\n' "$scan_status" >&2
      if [[ -n "$output" ]]; then
        printf '%s\n' "$output" >&2
      fi
      return 2
      ;;
  esac
}

guard_capture_files() {
  if (( $# < 2 )); then
    guard_fatal 'guard_capture_files expects a pattern and at least one rg argument'
    return
  fi

  local pattern="$1"
  shift
  local output
  local scan_status
  if output="$(rg -l -e "$pattern" "$@" 2>&1)"; then
    scan_status=0
  else
    scan_status=$?
  fi

  case "$scan_status" in
    0)
      [[ -n "$output" ]] && printf '%s\n' "$output"
      ;;
    1)
      return 0
      ;;
    *)
      printf 'error: architecture file scan failed (rg status %d)\n' "$scan_status" >&2
      if [[ -n "$output" ]]; then
        printf '%s\n' "$output" >&2
      fi
      return 2
      ;;
  esac
}

guard_count_matches() {
  if (( $# < 2 )); then
    guard_fatal 'guard_count_matches expects a pattern and at least one rg argument'
    return
  fi

  local pattern="$1"
  shift
  local output
  local scan_status
  if output="$(rg --count-matches -e "$pattern" "$@" 2>&1)"; then
    scan_status=0
  else
    scan_status=$?
  fi

  case "$scan_status" in
    0)
      ;;
    1)
      printf '0\n'
      return 0
      ;;
    *)
      printf 'error: architecture scan failed (rg status %d)\n' "$scan_status" >&2
      if [[ -n "$output" ]]; then
        printf '%s\n' "$output" >&2
      fi
      return 2
      ;;
  esac

  local total=0
  local line
  local count
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    count="${line##*:}"
    if [[ ! "$count" =~ ^[0-9]+$ ]]; then
      guard_fatal "unexpected rg count output: $line"
      return
    fi
    total=$((total + count))
  done <<< "$output"
  printf '%d\n' "$total"
}

guard_count_swift_matches() {
  if (( $# < 2 )); then
    guard_fatal 'guard_count_swift_matches expects a pattern and at least one source root'
    return
  fi
  local pattern="$1"
  shift
  guard_count_matches "$pattern" -g '*.swift' "$@"
}

guard_record_failure() {
  guard_failures=$((guard_failures + 1))
  printf 'error: %s\n' "$1" >&2
}

guard_max() {
  if (( $# != 3 )); then
    guard_fatal 'guard_max expects a label, actual value and maximum'
    return
  fi
  local label="$1"
  local actual="$2"
  local maximum="$3"
  if [[ ! "$actual" =~ ^[0-9]+$ || ! "$maximum" =~ ^[0-9]+$ ]]; then
    guard_fatal "non-numeric maximum check: $label ($actual / $maximum)"
    return
  fi

  printf '%-56s %5d / %5d\n' "$label" "$actual" "$maximum"
  if (( actual > maximum )); then
    guard_record_failure "$label exceeds its structural ceiling ($actual > $maximum)"
  fi
}

guard_exact() {
  if (( $# != 3 )); then
    guard_fatal 'guard_exact expects a label, actual value and expected value'
    return
  fi
  local label="$1"
  local actual="$2"
  local expected="$3"
  if [[ ! "$actual" =~ ^[0-9]+$ || ! "$expected" =~ ^[0-9]+$ ]]; then
    guard_fatal "non-numeric exact check: $label ($actual / $expected)"
    return
  fi

  printf '%-56s %5d = %5d\n' "$label" "$actual" "$expected"
  if (( actual != expected )); then
    guard_record_failure "$label changed ($actual != $expected)"
  fi
}

guard_expect_absent_path() {
  if (( $# != 2 )); then
    guard_fatal 'guard_expect_absent_path expects a label and path'
    return
  fi
  local label="$1"
  local path="$2"
  if [[ -e "$path" || -L "$path" ]]; then
    guard_record_failure "$label returned at $path"
  fi
}

guard_expect_no_matches() {
  if (( $# < 3 )); then
    guard_fatal 'guard_expect_no_matches expects a label, pattern and rg arguments'
    return
  fi
  local label="$1"
  local pattern="$2"
  shift 2
  local count
  count="$(guard_count_matches "$pattern" "$@")" || return
  guard_exact "$label" "$count" 0
}

guard_finish() {
  if (( $# != 1 )); then
    guard_fatal 'guard_finish expects a success label'
    return
  fi
  if (( guard_failures > 0 )); then
    printf 'error: %d architecture guard failure(s)\n' "$guard_failures" >&2
    return 1
  fi
  printf '\n%s passed\n' "$1"
}
