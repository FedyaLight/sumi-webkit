#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_ROOT="${ROOT}/SumiTests/Fixtures/AutofillPages"
PORT="${SUMI_AUTOFILL_FIXTURE_PORT:-8765}"

if [[ ! -d "${FIXTURE_ROOT}" ]]; then
  echo "Fixture directory not found: ${FIXTURE_ROOT}" >&2
  exit 1
fi

echo "Serving autofill fixtures from:"
echo "  ${FIXTURE_ROOT}"
echo
echo "Primary URLs (use HTTP, not file://):"
echo "  http://127.0.0.1:${PORT}/login-basic.html"
echo "  http://127.0.0.1:${PORT}/login-autocomplete.html"
echo "  http://127.0.0.1:${PORT}/login-same-origin-iframe.html"
echo "  http://127.0.0.1:${PORT}/login-cross-origin-iframe.html"
echo "  http://127.0.0.1:${PORT}/login-dynamic-spa.html"
echo
echo "Cross-origin iframe page also expects localhost alias on the same port."
echo "Press Ctrl+C to stop."
echo

cd "${FIXTURE_ROOT}"
exec python3 -m http.server "${PORT}" --bind 127.0.0.1
