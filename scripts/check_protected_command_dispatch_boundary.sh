#!/usr/bin/env bash
# Protected commands are split into pure authority, stateless execution, and
# stateful scheduling. This guard prevents those responsibilities from merging.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

runtime='Sumi/Managers/WebViewRuntime'
authority="$runtime/DeferredWebViewCommandAuthority.swift"
executor="$runtime/DeferredWebViewCommandExecutor.swift"
scheduler="$runtime/DeferredProtectedCommandScheduler.swift"
command='Packages/SumiWebRuntime/Sources/SumiWebRuntime/Commands/DeferredWebViewCommand.swift'

for file in "$authority" "$executor" "$scheduler" "$command"; do
  [[ -f "$file" ]] || {
    printf 'error: protected-command boundary file missing: %s\n' "$file" >&2
    exit 1
  }
done

obsolete=(
  "$runtime/WebViewProtectedCommandDispatchOwner.swift"
  "$runtime/WebViewDeferredProtectedCommandExecutionOwner.swift"
)
for file in "${obsolete[@]}"; do
  [[ ! -e "$file" ]] || {
    printf 'error: obsolete protected-command god surface returned: %s\n' "$file" >&2
    exit 1
  }
done

if rg -n 'WebViewProtectedCommandDispatchOwner|WebViewDeferredProtectedCommandExecutionOwner' \
  Sumi SumiTests -g '*.swift'; then
  printf 'error: obsolete protected-command symbol returned\n' >&2
  exit 1
fi

if rg -n 'struct (Dependencies|Runtime|ValidationContext)' \
  "$authority" "$executor" "$scheduler"; then
  printf 'error: protected-command responsibility hidden in a generic bag\n' >&2
  exit 1
fi

if rg -n '\b(Tab|WebViewSessionRepository|VisibleWebViewRuntimeOwner|WebViewWindowServices)\b|switch[[:space:]]+command' \
  "$scheduler"; then
  printf 'error: scheduler regained model validation or command dispatch\n' >&2
  exit 1
fi

if rg -n '\bTask\b|retryTasks|retryAttempts|WebViewMediaProtectionOwner' "$executor"; then
  printf 'error: executor regained scheduling/protection state\n' >&2
  exit 1
fi

raw_switch_files="$(
  rg -l 'switch[[:space:]]+command' "$runtime" -g '*.swift' || true
)"
while IFS= read -r file; do
  [[ -z "$file" ]] && continue
  case "$file" in
    "$authority"|"$executor") ;;
    *)
      printf 'error: deferred command switch escaped authority/executor: %s\n' "$file" >&2
      exit 1
      ;;
  esac
done <<< "$raw_switch_files"

if ! rg -q 'enum DeferredProtectedCommandExecutionOutcome' "$command"; then
  printf 'error: deferred command execution lost typed outcome\n' >&2
  exit 1
fi

authority_test_count="$(
  rg -c 'func test' SumiTests/DeferredWebViewCommandAuthorityTests.swift || true
)"
if (( ${authority_test_count:-0} < 14 )); then
  printf 'error: command authority lost per-command/stale-membership coverage (%s < 14)\n' \
    "${authority_test_count:-0}" >&2
  exit 1
fi

echo 'protected command authority/executor/scheduler boundary passed'
