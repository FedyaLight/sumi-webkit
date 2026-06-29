#!/usr/bin/env bash
set -euo pipefail

# Verifies the unpacked URLPredictor Rust static library slices against the
# reference SHA-256 digests tracked in
# Vendor/DDG/URLPredictor/Binary/CHECKSUMS.sha256.
#
# This complements scripts/bootstrap_vendor_binaries.sh, which checks the
# downloaded archive. Run it after bootstrap to guard against drift in the
# unpacked tree (partial re-extract, locally edited slice, stale copy).

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
binary_dir="$repo_root/Vendor/DDG/URLPredictor/Binary"
checksums="$binary_dir/CHECKSUMS.sha256"

if [[ ! -f "$checksums" ]]; then
  echo "error: CHECKSUMS.sha256 not found at: $checksums" >&2
  echo "       Run scripts/bootstrap_vendor_binaries.sh first." >&2
  exit 1
fi

if [[ ! -d "$binary_dir/URLPredictorRust.xcframework" ]]; then
  echo "error: URLPredictorRust.xcframework not unpacked under: $binary_dir" >&2
  echo "       Run scripts/bootstrap_vendor_binaries.sh first." >&2
  exit 1
fi

# shasum -c reads "DIGEST  PATH" lines relative to the checksums file's dir.
# macOS ships shasum; fall back to sha256sum on Linux CI.
cd "$binary_dir"
if command -v shasum >/dev/null 2>&1; then
  if shasum -a 256 -c "$checksums"; then
    echo "OK: URLPredictor binary slices match CHECKSUMS.sha256."
    exit 0
  fi
elif command -v sha256sum >/dev/null 2>&1; then
  if sha256sum -c "$checksums"; then
    echo "OK: URLPredictor binary slices match CHECKSUMS.sha256."
    exit 0
  fi
else
  echo "error: neither shasum nor sha256sum is available." >&2
  exit 1
fi

echo "error: one or more URLPredictor binary slices failed verification." >&2
echo "       If url_predictor was upgraded, regenerate CHECKSUMS.sha256 from the" >&2
echo "       freshly unpacked files. Otherwise, re-run bootstrap_vendor_binaries.sh." >&2
exit 1
