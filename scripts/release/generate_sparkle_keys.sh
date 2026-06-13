#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
generate_keys="$("${repo_root}/scripts/release/find_sparkle_tool.sh" generate_keys)"

cat <<'EOF'
Sparkle will create an EdDSA key pair.

Store the private key in a password manager or Keychain-backed secret store.
Commit only the public key in Sumi/Info.plist as SUPublicEDKey.
Do not commit the private key or paste it into release notes, appcasts, scripts, or workflows.

EOF

exec "${generate_keys}"
