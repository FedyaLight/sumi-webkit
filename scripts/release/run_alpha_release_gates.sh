#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
derived_data_root="${SUMI_RELEASE_GATES_DERIVED_DATA_PATH:-/tmp/SumiAlphaReleaseGates}"
destination="platform=macOS,arch=arm64"

xcode_version="$(xcodebuild -version | awk '/^Xcode / { print $2; exit }')"
xcode_major="${xcode_version%%.*}"
if [[ -z "${xcode_version}" || -z "${xcode_major}" || "${xcode_major}" -lt 27 ]]; then
  echo "error: Sumi alpha release gates require Xcode 27 or newer." >&2
  echo "       Active xcodebuild version: ${xcode_version:-unknown}" >&2
  exit 1
fi

"${repo_root}/scripts/check_architecture_guardrails.sh"
"${repo_root}/scripts/bootstrap_vendor_binaries.sh"
"${repo_root}/scripts/verify_vendor_checksums.sh"

rm -rf "${derived_data_root}"
mkdir -p "${derived_data_root}"

xcodebuild test \
  -project "${repo_root}/Sumi.xcodeproj" \
  -scheme Sumi \
  -destination "${destination}" \
  -parallel-testing-enabled NO \
  -derivedDataPath "${derived_data_root}/SumiTests" \
  -resultBundlePath "${derived_data_root}/SumiTests.xcresult"

xcodebuild test \
  -project "${repo_root}/Sumi.xcodeproj" \
  -scheme SumiSmoke \
  -destination "${destination}" \
  -parallel-testing-enabled NO \
  -derivedDataPath "${derived_data_root}/SumiSmoke" \
  -resultBundlePath "${derived_data_root}/SumiSmoke.xcresult"
