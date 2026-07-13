#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

source_file="Sumi/Privacy/SumiGPCNavigationResponder.swift"
trap_pattern='\b(precondition|preconditionFailure|fatalError)[[:space:]]*\('

if rg -n "$trap_pattern" "$source_file"; then
  echo "error: GPC exact-transaction handling must return a typed failure, not terminate the process" >&2
  exit 1
fi

echo "GPC navigation fail-closed guard passed"
