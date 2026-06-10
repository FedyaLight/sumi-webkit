#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
URL_PREDICTOR_BINARY_DIR="$ROOT/Vendor/DDG/URLPredictor/Binary"
XCFRAMEWORK_PATH="$URL_PREDICTOR_BINARY_DIR/URLPredictorRust.xcframework"
ZIP_URL="https://github.com/duckduckgo/url_predictor/releases/download/0.3.13/URLPredictorRust.xcframework.zip"
ZIP_CHECKSUM="64a9158d40ceb86946638a98206a736cfc32dff5af1a544250d506686ea4459a"

if [[ -f "$XCFRAMEWORK_PATH/Info.plist" ]]; then
  echo "URLPredictorRust.xcframework already present."
  exit 0
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

zip_path="$tmpdir/URLPredictorRust.xcframework.zip"
echo "Downloading URLPredictorRust.xcframework..."
curl -fsSL "$ZIP_URL" -o "$zip_path"

if command -v shasum >/dev/null 2>&1; then
  actual_checksum="$(shasum -a 256 "$zip_path" | awk '{print $1}')"
elif command -v sha256sum >/dev/null 2>&1; then
  actual_checksum="$(sha256sum "$zip_path" | awk '{print $1}')"
else
  echo "error: shasum or sha256sum is required to verify the download." >&2
  exit 1
fi

if [[ "$actual_checksum" != "$ZIP_CHECKSUM" ]]; then
  echo "error: checksum mismatch for URLPredictorRust.xcframework.zip" >&2
  echo "expected: $ZIP_CHECKSUM" >&2
  echo "actual:   $actual_checksum" >&2
  exit 1
fi

mkdir -p "$URL_PREDICTOR_BINARY_DIR"
unzip -q "$zip_path" -d "$URL_PREDICTOR_BINARY_DIR"
echo "Installed $XCFRAMEWORK_PATH"
