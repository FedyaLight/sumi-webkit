#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
artifact_dir="${1:-${repo_root}/release/artifacts/0.0.2}"
universal_archive="${artifact_dir}/Sumi-0.0.2-macos-universal.dmg"
sparkle_archive_name="${SPARKLE_ARCHIVE_NAME:-Sumi-0.0.2-build3-macos-universal.dmg}"

if [[ ! -f "${universal_archive}" ]]; then
  echo "Missing universal Sparkle update archive: ${universal_archive}" >&2
  exit 1
fi

staging_dir="$(mktemp -d /tmp/SumiAlpha2Appcast.XXXXXX)"
trap 'rm -rf "${staging_dir}"' EXIT
ln -s "${universal_archive}" "${staging_dir}/${sparkle_archive_name}"

OUTPUT_APPCAST="${repo_root}/docs/appcast-alpha.xml" \
BRIDGE_OUTPUT_APPCAST="${repo_root}/docs/appcast.xml" \
MAXIMUM_VERSIONS=1 \
  "${repo_root}/scripts/release/generate_alpha_appcast.sh" "${staging_dir}"
