#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULT_SOURCE="$ROOT/../references/apple-browsers"
SOURCE="$DEFAULT_SOURCE"
EXPECTED_REF=""
DRY_RUN=0
ALLOW_DIRTY=0

usage() {
  cat <<'EOF'
Usage: scripts/sync_ddg_vendor_snapshot.sh [options]

Synchronize Sumi's vendored DuckDuckGo Swift source snapshot from a checked-out
DuckDuckGo/apple-browsers repository.

Options:
  --source PATH   Upstream apple-browsers checkout.
                  Defaults to ../references/apple-browsers.
  --ref REF       Require the upstream checkout HEAD to match REF.
  --dry-run       Show the rsync changes without modifying Vendor/DDG.
  --allow-dirty   Permit a dirty Sumi worktree. Use only on a throwaway branch.
  -h, --help      Show this help.

The script does not checkout or pull upstream for you, and it does not replace
Sumi's pruned Package.swift manifest. It synchronizes only the Common and
Navigation targets (upstream tests are not vendored). Update the source
checkout explicitly, then run this script from a clean Sumi worktree so the
resulting diff is a reviewable vendor snapshot.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      [[ $# -ge 2 ]] || {
        echo "error: --source requires a path" >&2
        exit 2
      }
      SOURCE="$2"
      shift 2
      ;;
    --ref)
      [[ $# -ge 2 ]] || {
        echo "error: --ref requires a git ref" >&2
        exit 2
      }
      EXPECTED_REF="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --allow-dirty)
      ALLOW_DIRTY=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: required tool is not available: $1" >&2
    exit 1
  fi
}

require_tool git
require_tool rsync

if [[ ! -d "$SOURCE/.git" ]]; then
  echo "error: source is not a git checkout: $SOURCE" >&2
  exit 1
fi

BROWSER_SERVICES_SOURCE="$SOURCE/SharedPackages/BrowserServicesKit"
BROWSER_SERVICES_DEST="$ROOT/Vendor/DDG/BrowserServicesKit"

for path in "$BROWSER_SERVICES_SOURCE"; do
  if [[ ! -f "$path/Package.swift" ]]; then
    echo "error: missing Package.swift under expected upstream package path: $path" >&2
    exit 1
  fi
done

if [[ "$ALLOW_DIRTY" -eq 0 ]] && [[ -n "$(git -C "$ROOT" status --porcelain)" ]]; then
  echo "error: Sumi worktree is dirty. Commit/stash first, or pass --allow-dirty on a throwaway branch." >&2
  exit 1
fi

if ! git -C "$SOURCE" diff --quiet || ! git -C "$SOURCE" diff --cached --quiet; then
  echo "error: upstream source checkout has uncommitted changes: $SOURCE" >&2
  exit 1
fi

SOURCE_HEAD="$(git -C "$SOURCE" rev-parse HEAD)"
if [[ -n "$EXPECTED_REF" ]]; then
  EXPECTED_COMMIT="$(git -C "$SOURCE" rev-parse --verify "$EXPECTED_REF^{commit}")"
  if [[ "$SOURCE_HEAD" != "$EXPECTED_COMMIT" ]]; then
    echo "error: source HEAD is $SOURCE_HEAD, expected $EXPECTED_COMMIT ($EXPECTED_REF)." >&2
    exit 1
  fi
fi

RSYNC_ARGS=(
  -a
  --delete
  --exclude .git/
  --exclude .build/
  --exclude .swiftpm/
)
if [[ "$DRY_RUN" -eq 1 ]]; then
  RSYNC_ARGS+=(--dry-run --itemize-changes)
fi

echo "Syncing DDG Swift snapshot from $SOURCE_HEAD"

sync_directory() {
  local source_dir="$1"
  local dest_dir="$2"

  if [[ ! -d "$source_dir" ]]; then
    echo "error: missing upstream directory: $source_dir" >&2
    exit 1
  fi
  if [[ "$DRY_RUN" -eq 0 ]]; then
    mkdir -p "$dest_dir"
  elif [[ ! -d "$dest_dir" ]]; then
    echo "would create directory: $dest_dir"
  fi
  rsync "${RSYNC_ARGS[@]}" "$source_dir/" "$dest_dir/"
}

for target in Common Navigation; do
  sync_directory \
    "$BROWSER_SERVICES_SOURCE/Sources/$target" \
    "$BROWSER_SERVICES_DEST/Sources/$target"
done

# Sumi prunes Common further than upstream: the TLD component (and its
# URLPredictor dependency) is not vendored.
if [[ "$DRY_RUN" -eq 0 ]]; then
  rm -rf "$BROWSER_SERVICES_DEST/Sources/Common/TLD"
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "Dry run complete. No files changed."
  exit 0
fi

perl -0pi -e \
  "s/Source revision \\(Swift snapshot\\): [0-9a-f]+/Source revision (Swift snapshot): $SOURCE_HEAD/" \
  "$ROOT/Vendor/DDG/README.md"

bash "$ROOT/scripts/check_ddg_vendor_test_boundary.sh"

echo "DDG vendor snapshot synchronized from $SOURCE_HEAD."
echo "Review Vendor/DDG and run the Sumi build/test slice that covers the changed products."
