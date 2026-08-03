#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

OUTPUT_APPCAST="${repo_root}/docs/appcast-alpha.xml" \
BRIDGE_OUTPUT_APPCAST="${repo_root}/docs/appcast.xml" \
  "${repo_root}/scripts/release/generate_alpha_appcast.sh" "${1:-${repo_root}/release/artifacts/0.0.2}"
