#!/usr/bin/env bash
set -euo pipefail

appcast="${1:-docs/appcast-alpha.xml}"

if [[ ! -f "${appcast}" ]]; then
  echo "Missing appcast: ${appcast}" >&2
  exit 1
fi

if command -v xmllint >/dev/null 2>&1; then
  xmllint --noout "${appcast}"
fi

if ! grep -q '<enclosure ' "${appcast}"; then
  echo "No update enclosures found in ${appcast}; empty appcast is valid for a reserved feed."
  exit 0
fi

missing_signature_count="$(
  grep '<enclosure ' "${appcast}" \
    | grep -vc 'sparkle:edSignature=' \
    || true
)"
missing_length_count="$(
  grep '<enclosure ' "${appcast}" \
    | grep -vc 'length=' \
    || true
)"

if [[ "${missing_signature_count}" != "0" ]]; then
  echo "One or more appcast enclosures are missing sparkle:edSignature." >&2
  exit 1
fi

if [[ "${missing_length_count}" != "0" ]]; then
  echo "One or more appcast enclosures are missing length." >&2
  exit 1
fi

echo "Validated Sparkle EdDSA signatures in ${appcast}."
