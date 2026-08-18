#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
architecture="${ARCHITECTURE:-arm64}"
configuration="${CONFIGURATION:-Release}"
release_channel="${RELEASE_CHANNEL:-stable}"
derived_data_path="${DERIVED_DATA_PATH:-${repo_root}/build/ReleaseDmg-${architecture}}"
output_dir="${OUTPUT_DIR:-${repo_root}/release/artifacts}"
app_path="${APP_PATH:-}"
skip_build="${SKIP_BUILD:-0}"
skip_guardrails="${SKIP_ARCHITECTURE_GUARDRAILS:-0}"

if [[ "${derived_data_path}" != /* ]]; then
  derived_data_path="${repo_root}/${derived_data_path}"
fi
if [[ "${output_dir}" != /* ]]; then
  output_dir="${repo_root}/${output_dir}"
fi
if [[ -n "${app_path}" && "${app_path}" != /* ]]; then
  app_path="${repo_root}/${app_path}"
fi

if [[ "${architecture}" != "arm64" ]]; then
  echo "error: Sumi release packages are Apple-silicon only; ARCHITECTURE must be arm64, got: ${architecture}" >&2
  exit 1
fi

if [[ "${skip_guardrails}" != "1" ]]; then
  "${repo_root}/scripts/check_architecture_guardrails.sh"
fi

if [[ -z "${app_path}" ]]; then
  if [[ "${skip_build}" != "1" ]]; then
    build_arguments=(
      xcodebuild
      -quiet
      -project "${repo_root}/Sumi.xcodeproj"
      -scheme Sumi
      -configuration "${configuration}"
      -derivedDataPath "${derived_data_path}"
    )
    build_arguments+=(-destination "platform=macOS,arch=arm64")
    build_arguments+=(build)
    "${build_arguments[@]}"
  fi
  app_path="${derived_data_path}/Build/Products/${configuration}/Sumi.app"
fi

if [[ ! -d "${app_path}" ]]; then
  echo "error: Missing app bundle: ${app_path}" >&2
  exit 1
fi

info_plist="${app_path}/Contents/Info.plist"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${info_plist}")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${info_plist}")"
declared_channel="$(/usr/libexec/PlistBuddy -c 'Print :SumiReleaseChannel' "${info_plist}")"

if [[ "${declared_channel}" != "${release_channel}" ]]; then
  echo "error: App declares ${declared_channel} channel, but packaging requested ${release_channel}." >&2
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
for framework_path in "${package_frameworks[@]}"; do
  framework_name="$(basename "${framework_path}")"
  embedded_framework_path="${app_frameworks_dir}/${framework_name}"
  rm -rf "${embedded_framework_path}"
  ditto "${framework_path}" "${embedded_framework_path}"
done

temporary_root="$(mktemp -d /tmp/SumiReleaseDmg.XXXXXX)"
verification_mount="$(mktemp -d /tmp/SumiReleaseDmgMount.XXXXXX)"
volume_name="Sumi"
layout_mount="/Volumes/${volume_name}"
mounted=0
layout_mounted=0

cleanup() {
  if [[ "${layout_mounted}" == "1" ]]; then
    hdiutil detach "${layout_mount}" >/dev/null 2>&1 || true
  fi
  if [[ "${mounted}" == "1" ]]; then
    diskutil eject "${verification_mount}" >/dev/null 2>&1 || true
  fi
  rm -rf "${temporary_root}" "${verification_mount}"
}
trap cleanup EXIT

"${repo_root}/scripts/release/sign_release_app.sh" "${app_path}"

executable_path="${app_path}/Contents/MacOS/Sumi"
actual_architectures="$(lipo -archs "${executable_path}")"
expected_architectures="${architecture}"
normalized_actual_architectures="$(tr ' ' '\n' <<<"${actual_architectures}" | LC_ALL=C sort | paste -sd ' ' -)"
if [[ "${normalized_actual_architectures}" != "${expected_architectures}" ]]; then
  echo "error: Expected ${expected_architectures} app executable, got: ${actual_architectures}" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=1 "${app_path}"

archive_name="Sumi-${version}-macos-${architecture}.dmg"
output_path="${OUTPUT_PATH:-${output_dir}/${archive_name}}"
staging_dir="${temporary_root}/staging"
rw_dmg="${temporary_root}/Sumi-release-rw.dmg"

mkdir -p "${staging_dir}" "${output_dir}"
ditto "${app_path}" "${staging_dir}/Sumi.app"
ln -s /Applications "${staging_dir}/Applications"

if [[ -e "${layout_mount}" ]]; then
  echo "error: ${layout_mount} is already mounted. Eject it before packaging." >&2
  exit 1
fi

rm -f "${output_path}"
hdiutil create \
  -volname "${volume_name}" \
  -srcfolder "${staging_dir}" \
  -ov \
  -format UDRW \
  "${rw_dmg}" >/dev/null

hdiutil attach -readwrite -noverify -noautoopen "${rw_dmg}" >/dev/null
layout_mounted=1

osascript <<'OSA'
tell application "Finder"
  set theDisk to disk "Sumi"
  open theDisk
  delay 1
  set theWindow to container window of theDisk
  set current view of theWindow to icon view
  set toolbar visible of theWindow to false
  set statusbar visible of theWindow to false
  set bounds of theWindow to {160, 140, 720, 400}
  set theOptions to icon view options of theWindow
  set arrangement of theOptions to not arranged
  set icon size of theOptions to 112
  set text size of theOptions to 13
  set position of item "Sumi.app" of theDisk to {170, 95}
  set position of item "Applications" of theDisk to {390, 95}
  update theDisk without registering applications
  delay 2
  close theWindow
end tell
OSA

cp "${app_path}/Contents/Resources/logo.icns" "${layout_mount}/.VolumeIcon.icns"
SetFile -a V "${layout_mount}/.VolumeIcon.icns"
SetFile -a C "${layout_mount}"
rm -rf "${layout_mount}/.fseventsd"
sync

hdiutil detach "${layout_mount}" >/dev/null
layout_mounted=0
hdiutil convert "${rw_dmg}" -format UDZO -o "${output_path}" -ov >/dev/null

diskutil image info "${output_path}" >/dev/null
diskutil image attach \
  --nobrowse \
  --readOnly \
  --mountPoint "${verification_mount}" \
  "${output_path}" >/dev/null
mounted=1

packaged_architectures="$(lipo -archs "${verification_mount}/Sumi.app/Contents/MacOS/Sumi")"
normalized_packaged_architectures="$(tr ' ' '\n' <<<"${packaged_architectures}" | LC_ALL=C sort | paste -sd ' ' -)"
if [[ "${normalized_packaged_architectures}" != "${expected_architectures}" ]]; then
  echo "error: Packaged executable architecture mismatch: ${packaged_architectures}" >&2
  exit 1
fi
codesign --verify --deep --strict --verbose=1 "${verification_mount}/Sumi.app"

diskutil eject "${verification_mount}" >/dev/null
mounted=0

printf 'Created %s release DMG:\n%s\n' "${architecture}" "${output_path}"
shasum -a 256 "${output_path}"
