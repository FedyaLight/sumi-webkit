#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
current_root="$(git -C "$repo_root" rev-parse --show-toplevel)"

if [[ "$current_root" != "$repo_root" ]]; then
  printf 'error: expected repository root %s; found %s\n' "$repo_root" "$current_root" >&2
  exit 1
fi

git -C "$repo_root" config --local core.hooksPath .githooks
printf 'Git hooks enabled from %s/.githooks\n' "$repo_root"
