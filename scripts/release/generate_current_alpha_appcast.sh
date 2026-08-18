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
if [[ "${artifact_dir}" != /* ]]; then
  artifact_dir="${repo_root}/${artifact_dir}"
fi
archive_name="Sumi-${version}-build${build}-macos-arm64.dmg"
arm_archive="${artifact_dir}/${archive_name}"
download_url_prefix="${DOWNLOAD_URL_PREFIX:-https://github.com/FedyaLight/sumi-webkit/releases/download/v${version}/}"

if [[ ! -f "${arm_archive}" ]]; then
  echo "Missing Apple-silicon Sparkle update archive: ${arm_archive}" >&2
  exit 1
fi

staging_dir="$(mktemp -d /tmp/SumiCurrentAlphaAppcast.XXXXXX)"
trap 'rm -rf "${staging_dir}"' EXIT
ln -s "${arm_archive}" "${staging_dir}/${archive_name}"

fresh_appcast="${staging_dir}/appcast.xml"
OUTPUT_APPCAST="${fresh_appcast}" \
DOWNLOAD_URL_PREFIX="${download_url_prefix}" \
MAXIMUM_VERSIONS=1 \
  "${repo_root}/scripts/release/generate_alpha_appcast.sh" "${staging_dir}"

for appcast in "${repo_root}/docs/appcast-alpha.xml" "${repo_root}/docs/appcast.xml"; do
  cp "${fresh_appcast}" "${appcast}"
done

for appcast in "${repo_root}/docs/appcast-alpha.xml" "${repo_root}/docs/appcast.xml"; do
  if ! grep -Eq '<sparkle:hardwareRequirements>[[:space:]]*arm64[[:space:]]*</sparkle:hardwareRequirements>' "${appcast}"; then
    echo "error: ${appcast} does not require arm64 hardware." >&2
    exit 1
  fi
  if ! grep -Fq "${archive_name}" "${appcast}"; then
    echo "error: ${appcast} does not reference ${archive_name}." >&2
    exit 1
  fi
done
