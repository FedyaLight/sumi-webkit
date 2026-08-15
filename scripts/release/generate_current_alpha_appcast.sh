#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build_settings="$(
  xcodebuild -project "${repo_root}/Sumi.xcodeproj" \
    -target Sumi -configuration Release -showBuildSettings
)"
version="$(awk '$1 == "MARKETING_VERSION" && $2 == "=" { print $3; exit }' <<<"${build_settings}")"
build="$(awk '$1 == "CURRENT_PROJECT_VERSION" && $2 == "=" { print $3; exit }' <<<"${build_settings}")"
if [[ -z "${version}" || -z "${build}" ]]; then
  echo "error: Could not resolve Sumi version and build settings." >&2
  exit 1
fi

artifact_dir="${1:-${repo_root}/release/artifacts/${version}}"
universal_archive="${artifact_dir}/Sumi-${version}-macos-universal.dmg"
sparkle_archive_name="${SPARKLE_ARCHIVE_NAME:-Sumi-${version}-build${build}-macos-universal.dmg}"

if [[ ! -f "${universal_archive}" ]]; then
  echo "Missing universal Sparkle update archive: ${universal_archive}" >&2
  exit 1
fi

staging_dir="$(mktemp -d /tmp/SumiAlphaAppcast.XXXXXX)"
trap 'rm -rf "${staging_dir}"' EXIT
ln -s "${universal_archive}" "${staging_dir}/${sparkle_archive_name}"

OUTPUT_APPCAST="${repo_root}/docs/appcast-alpha.xml" \
MAXIMUM_VERSIONS=1 \
  "${repo_root}/scripts/release/generate_alpha_appcast.sh" "${staging_dir}"
