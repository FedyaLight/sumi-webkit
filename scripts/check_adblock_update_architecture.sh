#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=scripts/lib/architecture_guard.sh
source "$script_dir/lib/architecture_guard.sh"
guard_initialize "$repo_root"

for removed_file in \
  Sumi/ContentBlocking/SumiAdblockUpdatePipeline.swift \
  Sumi/ContentBlocking/SumiProtectionBundleRemoteUpdate.swift \
  Sumi/ContentBlocking/SumiContentBlockingScheduledTaskOwner.swift \
  Sumi/ContentBlocking/ProtectionRuntimeSynchronizer.swift \
  Sumi/ContentBlocking/SumiProfileContentBlockingRuntime.swift; do
  if [[ -e "$removed_file" || -L "$removed_file" ]]; then
    echo "error: retired Adblock god surface returned: $removed_file" >&2
    exit 1
  fi
done

for removed_symbol in \
  AdblockUpdateManifestStore \
  AdblockGenerationGarbageCollector \
  AdblockUpdateCoordinator \
  SumiContentBlockingScheduledTaskOwner \
  AdblockWebKitRuleListStore \
  ProtectionRuntimeSynchronizer \
  SumiProfileContentBlockingRuntime; do
  removed_symbol_count="$(
    guard_count_matches "\\b${removed_symbol}\\b" Sumi SumiTests --glob '*.swift'
  )"
  if (( removed_symbol_count > 0 )); then
    echo "error: retired Adblock abstraction returned: $removed_symbol" >&2
    exit 1
  fi
done

profile_specific_runtime_count="$(
  guard_count_matches \
    'hasProfileSpecificRuleLists|profileSubjects|refreshProfileSubjects|profileUserContentPublisher' \
    Sumi/ContentBlocking SumiTests --glob '*.swift'
)"
if (( profile_specific_runtime_count > 0 )); then
  echo "error: retired profile-specific content-blocking runtime seam returned" >&2
  exit 1
fi

line_budgets=(
  "Sumi/ContentBlocking/AdblockGenerationArchive.swift|280"
  "Sumi/ContentBlocking/AdblockGenerationMutationGate.swift|100"
  "Sumi/ContentBlocking/AdblockGenerationRecovery.swift|170"
  "Sumi/ContentBlocking/AdblockGenerationRetention.swift|130"
  "Sumi/ContentBlocking/AdblockPreparedBundleInstaller.swift|260"
  "Sumi/ContentBlocking/AdblockPersistedGenerationActivation.swift|100"
  "Sumi/ContentBlocking/AdblockGenerationStartup.swift|140"
  "Sumi/ContentBlocking/AdblockRuleListRuntime.swift|300"
  "Sumi/ContentBlocking/AdblockSitePolicy.swift|210"
  "Sumi/ContentBlocking/AdblockManifestRuleListProvider.swift|130"
  "Sumi/ContentBlocking/ContentBlockingTaskRegistry.swift|100"
  "Sumi/ContentBlocking/SumiAdBlockingModule.swift|200"
  "Sumi/ContentBlocking/SumiProtectionBundleRemoteUpdater.swift|160"
  "Sumi/ContentBlocking/SumiProtectionBundleReleaseValidator.swift|220"
  "Sumi/ContentBlocking/SumiProtectionBundleCache.swift|200"
  "Sumi/ContentBlocking/SumiProtectionBundleCacheTransaction.swift|570"
  "Sumi/ContentBlocking/SumiProtectionBundleQuarantine.swift|250"
  "Sumi/ContentBlocking/SumiAdblockNativeRuleBundle.swift|190"
  "Sumi/ContentBlocking/SumiAdblockNativeBundleReader.swift|290"
  "Sumi/ContentBlocking/SumiAdblockNativeGenerationProjector.swift|210"
  "Sumi/ContentBlocking/SumiPreparedAdblockBundleResolver.swift|330"
  "Sumi/ContentBlocking/SumiContentBlockingService.swift|360"
  "Sumi/ContentBlocking/SumiContentBlockingStateMachine.swift|125"
  "Sumi/ContentBlocking/SumiRuleListProviderRuntime.swift|130"
  "Sumi/ContentBlocking/ContentBlockingTaskRegistry.swift|80"
)
for budget in "${line_budgets[@]}"; do
  file="${budget%%|*}"
  maximum="${budget#*|}"
  guard_require_file "$file"
  actual="$(guard_count_lines "$file")"
  if (( actual > maximum )); then
    echo "error: $file grew beyond its architectural role ($actual > $maximum LOC)" >&2
    exit 1
  fi
done

focused_files=(
  Sumi/ContentBlocking/AdblockGenerationArchive.swift
  Sumi/ContentBlocking/AdblockGenerationMutationGate.swift
  Sumi/ContentBlocking/AdblockGenerationRecovery.swift
  Sumi/ContentBlocking/AdblockGenerationRetention.swift
  Sumi/ContentBlocking/AdblockPreparedBundleInstaller.swift
  Sumi/ContentBlocking/AdblockPersistedGenerationActivation.swift
  Sumi/ContentBlocking/AdblockGenerationStartup.swift
  Sumi/ContentBlocking/AdblockRuleListRuntime.swift
  Sumi/ContentBlocking/AdblockSitePolicy.swift
  Sumi/ContentBlocking/AdblockManifestRuleListProvider.swift
  Sumi/ContentBlocking/SumiAdBlockingModule.swift
  Sumi/ContentBlocking/ContentBlockingTaskRegistry.swift
  Sumi/ContentBlocking/SumiProtectionBundleRemoteUpdater.swift
  Sumi/ContentBlocking/SumiProtectionBundleReleaseValidator.swift
  Sumi/ContentBlocking/SumiProtectionBundleCache.swift
  Sumi/ContentBlocking/SumiProtectionBundleCacheTransaction.swift
  Sumi/ContentBlocking/SumiProtectionBundleQuarantine.swift
  Sumi/ContentBlocking/SumiAdblockNativeRuleBundle.swift
  Sumi/ContentBlocking/SumiAdblockNativeBundleReader.swift
  Sumi/ContentBlocking/SumiAdblockNativeGenerationProjector.swift
  Sumi/ContentBlocking/SumiPreparedAdblockBundleResolver.swift
  Sumi/ContentBlocking/SumiContentBlockingService.swift
  Sumi/ContentBlocking/SumiContentBlockingStateMachine.swift
  Sumi/ContentBlocking/SumiRuleListProviderRuntime.swift
  Sumi/ContentBlocking/ContentBlockingTaskRegistry.swift
)

owner_count="$(guard_count_matches '\bOwner\b|Owner\.swift' "${focused_files[@]}")"
if (( owner_count > 0 )); then
  echo "error: Adblock update responsibility was hidden behind an Owner name" >&2
  exit 1
fi

trapping_dictionary_count="$(
  guard_count_matches 'Dictionary\(uniqueKeysWithValues:\s*release\.assets' \
    Sumi/ContentBlocking --glob '*.swift'
)"
if (( trapping_dictionary_count > 0 )); then
  echo "error: untrusted release asset names must not use a trapping dictionary initializer" >&2
  exit 1
fi

native_io_count="$(guard_count_matches 'CryptoKit|OSLog|FileManager|Data\(contentsOf:|JSONSerialization' \
  Sumi/ContentBlocking/SumiAdblockNativeRuleBundle.swift \
  Sumi/ContentBlocking/SumiAdblockNativeGenerationProjector.swift)"
if (( native_io_count > 0 )); then
  echo "error: native bundle model/projection regained filesystem or diagnostics IO" >&2
  exit 1
fi

native_responsibility_count="$(guard_count_matches \
  '\b(load|bundledDirectoryURL|contentRuleListDefinitions|stagedShardURLs|compiledGenerationManifest)\s*\(' \
  Sumi/ContentBlocking/SumiAdblockNativeRuleBundle.swift)"
if (( native_responsibility_count > 0 )); then
  echo "error: native bundle value regained reader/projector responsibilities" >&2
  exit 1
fi

provider_leak_count="$(guard_count_matches \
  'changesPublisher|AnyCancellable|ruleSourceGeneration|beginRuleSourceRefresh|isCurrentRuleSourceRefresh|disableAfterRuleSourceFailure' \
  Sumi/ContentBlocking/SumiContentBlockingService.swift \
  Sumi/ContentBlocking/SumiContentBlockingStateMachine.swift)"
if (( provider_leak_count > 0 )); then
  echo "error: provider observation/generation leaked back into policy runtime" >&2
  exit 1
fi

profile_scoped_global_provider_count="$(guard_count_matches \
  'profileId' \
  Sumi/ContentBlocking/SumiContentRuleListSet.swift \
  Sumi/ContentBlocking/AdblockManifestRuleListProvider.swift \
  Sumi/ContentBlocking/SumiRuleListProviderRuntime.swift \
  Sumi/ContentBlocking/SumiContentBlockingService.swift)"
if (( profile_scoped_global_provider_count > 0 )); then
  echo "error: global content-rule publication regained a fake profile-specific API" >&2
  exit 1
fi

untyped_registry_count="$(guard_count_matches 'ContentBlockingTaskRegistry\(\)' \
  Sumi/ContentBlocking SumiTests --glob '*.swift')"
if (( untyped_registry_count > 0 )); then
  echo "error: content-blocking task registry lost its exact key type" >&2
  exit 1
fi

required_contracts=(
  'Sumi/ContentBlocking/AdblockGenerationArchive.swift|ContentBlockingItemExchange\.swap'
  'Sumi/ContentBlocking/SumiProtectionBundleCacheTransaction.swift|ContentBlockingItemExchange\.swap'
  'Sumi/ContentBlocking/SumiPreparedAdblockBundleResolver.swift|unavailableMarkerFileName'
  'Sumi/ContentBlocking/AdblockGenerationRetention.swift|previousGenerationId'
  'Sumi/ContentBlocking/AdblockRuleListRuntime.swift|mutationGate\.stop\(\)'
  'Sumi/ContentBlocking/SumiProtectionBundleRemoteUpdater.swift|cache\.commit\('
  'Sumi/ContentBlocking/AdblockPreparedBundleInstaller.swift|bundleReader\.contentRuleListDefinitions'
  'Sumi/ContentBlocking/AdblockPreparedBundleInstaller.swift|generationProjector\.compiledManifest'
  'Sumi/ContentBlocking/SumiContentBlockingService.swift|SumiRuleListProviderRuntime'
  'Sumi/ContentBlocking/SumiRuleListProviderRuntime.swift|ContentBlockingTaskRegistry<TaskKey>'
  'Sumi/ContentBlocking/AdblockRuleListPublication.swift|stagePreparedContentBlockingUpdate'
  'Sumi/ContentBlocking/AdblockRuleListPublication.swift|publishStagedContentBlockingUpdate'
  'Sumi/ContentBlocking/SumiAdBlockingModule.swift|private var runtimeLevel = SumiProtectionLevel\.off'
  'Sumi/ContentBlocking/ProtectionAttachmentService.swift|ruleProvider\.setRuntimeLevel\(level\)'
)
for contract in "${required_contracts[@]}"; do
  file="${contract%%|*}"
  pattern="${contract#*|}"
  contract_count="$(guard_count_matches "$pattern" "$file")"
  if (( contract_count == 0 )); then
    guard_record_failure "required Adblock architecture contract is missing from $file: $pattern"
    exit 1
  fi
done

rollback_transaction=Sumi/ContentBlocking/SumiProtectionBundleCacheTransaction.swift
rollback_marker_line="$(guard_capture_matches 'try quarantineIO\.publishUnavailableMarker' "$rollback_transaction" | head -1 | cut -d: -f1)"
rollback_swap_line="$(guard_capture_matches 'ContentBlockingItemExchange\.swap\(destination, stagedBundleURL\)' "$rollback_transaction" | tail -1 | cut -d: -f1)"
restored_phase_line="$(guard_capture_matches 'phase = \.revalidatingRestored' "$rollback_transaction" | cut -d: -f1)"
restored_receipt_line="$(guard_capture_matches 'restoredReceipt == previousReceipt' "$rollback_transaction" | cut -d: -f1)"
post_restore_quarantine_line="$(awk -v start="$restored_receipt_line" 'NR > start && /try quarantine\(/ { print NR; exit }' "$rollback_transaction")"

if [[ -z "$rollback_marker_line" || -z "$rollback_swap_line" || -z "$restored_phase_line" || -z "$restored_receipt_line" || -z "$post_restore_quarantine_line" ]] \
  || (( rollback_marker_line >= rollback_swap_line )) \
  || (( rollback_swap_line >= restored_phase_line )) \
  || (( restored_phase_line >= restored_receipt_line )) \
  || (( restored_receipt_line >= post_restore_quarantine_line )); then
  echo "error: protection rollback must swap back, revalidate the exact restored receipt, then quarantine" >&2
  exit 1
fi

rollback_trap_count="$(guard_count_matches 'precondition|preconditionFailure|fatalError|try\?' \
  Sumi/ContentBlocking/SumiProtectionBundleCacheTransaction.swift \
  Sumi/ContentBlocking/SumiProtectionBundleQuarantine.swift)"
if (( rollback_trap_count > 0 )); then
  echo "error: protection rollback corruption and forensic cleanup must use typed failures" >&2
  exit 1
fi

split_boolean_count="$(guard_count_matches '\b(setPreparedBundleRuntimeEnabled|func setEnabled\(_ isEnabled: Bool\))' \
  Sumi/ContentBlocking/SumiAdBlockingModule.swift \
  Sumi/ContentBlocking/ProtectionAttachmentRuleProviding.swift)"
if (( split_boolean_count > 0 )); then
  echo "error: atomic Adblock runtime level regressed to split boolean forwarding" >&2
  exit 1
fi

echo "Adblock update architecture guard passed"
