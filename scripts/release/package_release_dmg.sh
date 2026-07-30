#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
architecture="${ARCHITECTURE:-arm64}"
configuration="${CONFIGURATION:-Release}"
release_channel="${RELEASE_CHANNEL:-release}"
derived_data_path="${DERIVED_DATA_PATH:-${repo_root}/build/ReleaseDmg-${architecture}}"
output_dir="${OUTPUT_DIR:-${repo_root}/release/artifacts}"
app_path="${APP_PATH:-}"
skip_build="${SKIP_BUILD:-0}"
skip_guardrails="${SKIP_ARCHITECTURE_GUARDRAILS:-0}"

case "${architecture}" in
  arm64 | x86_64) ;;
  *)
    echo "error: ARCHITECTURE must be arm64 or x86_64, got: ${architecture}" >&2
    exit 1
    ;;
esac

if [[ "${skip_guardrails}" != "1" ]]; then
  "${repo_root}/scripts/check_architecture_guardrails.sh"
fi

if [[ -z "${app_path}" ]]; then
  if [[ "${skip_build}" != "1" ]]; then
    xcodebuild \
      -quiet \
      -project "${repo_root}/Sumi.xcodeproj" \
      -scheme Sumi \
      -configuration "${configuration}" \
      -destination "platform=macOS,arch=${architecture}" \
      -derivedDataPath "${derived_data_path}" \
      build
  fi
  app_path="${derived_data_path}/Build/Products/${configuration}/Sumi.app"
fi

if [[ ! -d "${app_path}" ]]; then
  echo "error: Missing app bundle: ${app_path}" >&2
  exit 1
fi

package_frameworks_dir="${derived_data_path}/Build/Products/${configuration}/PackageFrameworks"
app_frameworks_dir="${app_path}/Contents/Frameworks"
shopt -s nullglob
package_frameworks=("${package_frameworks_dir}"/*.framework)
if [[ ! -d "${package_frameworks_dir}" || ${#package_frameworks[@]} -eq 0 ]]; then
  echo "error: Missing Swift package frameworks: ${package_frameworks_dir}" >&2
  exit 1
fi

mkdir -p "${app_frameworks_dir}"
embedded_package_frameworks=()
for framework_path in "${package_frameworks[@]}"; do
  framework_name="$(basename "${framework_path}")"
  embedded_framework_path="${app_frameworks_dir}/${framework_name}"
  rm -rf "${embedded_framework_path}"
  ditto "${framework_path}" "${embedded_framework_path}"
  embedded_package_frameworks+=("${embedded_framework_path}")
done

temporary_root="$(mktemp -d /tmp/SumiReleaseDmg.XXXXXX)"
verification_mount="$(mktemp -d /tmp/SumiReleaseDmgMount.XXXXXX)"
mounted=0

cleanup() {
  if [[ "${mounted}" == "1" ]]; then
    diskutil eject "${verification_mount}" >/dev/null 2>&1 || true
  fi
  rm -rf "${temporary_root}" "${verification_mount}"
}
trap cleanup EXIT

signing_cert_dir="${temporary_root}/signing-certificates"
mkdir -p "${signing_cert_dir}"
(
  cd "${signing_cert_dir}"
  codesign -d --extract-certificates "${app_path}"
)
signing_identity="$(shasum -a 1 "${signing_cert_dir}/codesign0" | awk '{print $1}')"
for framework_path in "${embedded_package_frameworks[@]}"; do
  codesign --force --sign "${signing_identity}" "${framework_path}"
done
codesign \
  --force \
  --sign "${signing_identity}" \
  --preserve-metadata=identifier,entitlements,flags,runtime,requirements \
  "${app_path}"

executable_path="${app_path}/Contents/MacOS/Sumi"
actual_architectures="$(lipo -archs "${executable_path}")"
if [[ "${actual_architectures}" != "${architecture}" ]]; then
  echo "error: Expected ${architecture} app executable, got: ${actual_architectures}" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=1 "${app_path}"

info_plist="${app_path}/Contents/Info.plist"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${info_plist}")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${info_plist}")"
archive_name="Sumi-${version}-${build}-${release_channel}-macos-${architecture}.dmg"
output_path="${OUTPUT_PATH:-${output_dir}/${archive_name}}"
staging_dir="${temporary_root}/staging"

mkdir -p "${staging_dir}" "${output_dir}"
ditto "${app_path}" "${staging_dir}/Sumi.app"
ln -s /Applications "${staging_dir}/Applications"

rm -f "${output_path}"
diskutil image create from \
  --format UDZO \
  --volumeName "Sumi ${architecture}" \
  "${staging_dir}" \
  "${output_path}" >/dev/null

diskutil image info "${output_path}" >/dev/null
diskutil image attach \
  --nobrowse \
  --readOnly \
  --mountPoint "${verification_mount}" \
  "${output_path}" >/dev/null
mounted=1

packaged_architectures="$(lipo -archs "${verification_mount}/Sumi.app/Contents/MacOS/Sumi")"
if [[ "${packaged_architectures}" != "${architecture}" ]]; then
  echo "error: Packaged executable architecture mismatch: ${packaged_architectures}" >&2
  exit 1
fi
codesign --verify --deep --strict --verbose=1 "${verification_mount}/Sumi.app"

diskutil eject "${verification_mount}" >/dev/null
mounted=0

printf 'Created %s release DMG:\n%s\n' "${architecture}" "${output_path}"
shasum -a 256 "${output_path}"
