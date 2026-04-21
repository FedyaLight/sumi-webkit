#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname "$0")" && pwd)"
ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
DERIVED="$ROOT/build-audit"
APP="$DERIVED/Build/Products/Debug/Sumi.app"

echo "==> Building Sumi audit target"
xcodebuild \
  -project "$ROOT/Sumi.xcodeproj" \
  -scheme Sumi \
  -configuration Debug \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build >/tmp/sumi-audit-build.log

echo "==> Launching app"
open "$APP"

echo "==> Waiting for process and window"
osascript <<'APPLESCRIPT'
tell application "System Events"
	repeat 40 times
		if exists process "Sumi" then
			tell process "Sumi"
				if (count of windows) > 0 then
					return "Sumi launch smoke passed"
				end if
			end tell
		end if
		delay 0.25
	end repeat
	error "Sumi launch smoke failed: no visible window"
end tell
APPLESCRIPT

echo "==> Smoke artifacts"
echo "Parity matrix:  $ROOT/docs/audit/zen-parity-matrix.md"
echo "Live checklist: $ROOT/docs/audit/live-smoke-matrix.md"
echo "Findings:       $ROOT/docs/audit/findings-2026-04-02.md"
