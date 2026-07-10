#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

for removed_file in \
  Sumi/ContentBlocking/SumiAdblockUpdatePipeline.swift \
  Sumi/ContentBlocking/SumiProtectionBundleRemoteUpdate.swift \
  Sumi/ContentBlocking/SumiContentBlockingScheduledTaskOwner.swift \
  Sumi/ContentBlocking/ProtectionRuntimeSynchronizer.swift; do
  if [[ -e "$removed_file" ]]; then
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
  ProtectionRuntimeSynchronizer; do
  if rg -n "\\b${removed_symbol}\\b" Sumi SumiTests --glob '*.swift' >/dev/null; then
    echo "error: retired Adblock abstraction returned: $removed_symbol" >&2
    exit 1
  fi
done

check_max_lines() {
  local file="$1"
  local maximum="$2"
  local actual
  actual="$(wc -l < "$file" | tr -d ' ')"
  if (( actual > maximum )); then
    echo "error: $file grew beyond its architectural role ($actual > $maximum LOC)" >&2
    exit 1
  fi
}

check_max_lines Sumi/ContentBlocking/AdblockGenerationArchive.swift 280
check_max_lines Sumi/ContentBlocking/AdblockGenerationMutationGate.swift 100
check_max_lines Sumi/ContentBlocking/AdblockGenerationRecovery.swift 170
check_max_lines Sumi/ContentBlocking/AdblockGenerationRetention.swift 130
check_max_lines Sumi/ContentBlocking/AdblockPreparedBundleInstaller.swift 260
check_max_lines Sumi/ContentBlocking/AdblockPersistedGenerationActivation.swift 100
check_max_lines Sumi/ContentBlocking/AdblockGenerationStartup.swift 140
check_max_lines Sumi/ContentBlocking/AdblockRuleListRuntime.swift 300
check_max_lines Sumi/ContentBlocking/AdblockSitePolicy.swift 210
check_max_lines Sumi/ContentBlocking/AdblockManifestRuleListProvider.swift 130
check_max_lines Sumi/ContentBlocking/ContentBlockingTaskRegistry.swift 100
check_max_lines Sumi/ContentBlocking/SumiAdBlockingModule.swift 200
check_max_lines Sumi/ContentBlocking/SumiProtectionBundleRemoteUpdater.swift 160
check_max_lines Sumi/ContentBlocking/SumiProtectionBundleReleaseValidator.swift 220
check_max_lines Sumi/ContentBlocking/SumiProtectionBundleCacheTransaction.swift 270
check_max_lines Sumi/ContentBlocking/SumiAdblockNativeRuleBundle.swift 190
check_max_lines Sumi/ContentBlocking/SumiAdblockNativeBundleReader.swift 260
check_max_lines Sumi/ContentBlocking/SumiAdblockNativeGenerationProjector.swift 210
check_max_lines Sumi/ContentBlocking/SumiPreparedAdblockBundleResolver.swift 330
check_max_lines Sumi/ContentBlocking/SumiContentBlockingService.swift 360
check_max_lines Sumi/ContentBlocking/SumiContentBlockingStateMachine.swift 125
check_max_lines Sumi/ContentBlocking/SumiRuleListProviderRuntime.swift 130
check_max_lines Sumi/ContentBlocking/SumiProfileContentBlockingRuntime.swift 150
check_max_lines Sumi/ContentBlocking/ContentBlockingTaskRegistry.swift 80

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
  Sumi/ContentBlocking/SumiProtectionBundleCacheTransaction.swift
  Sumi/ContentBlocking/SumiAdblockNativeRuleBundle.swift
  Sumi/ContentBlocking/SumiAdblockNativeBundleReader.swift
  Sumi/ContentBlocking/SumiAdblockNativeGenerationProjector.swift
  Sumi/ContentBlocking/SumiPreparedAdblockBundleResolver.swift
  Sumi/ContentBlocking/SumiContentBlockingService.swift
  Sumi/ContentBlocking/SumiContentBlockingStateMachine.swift
  Sumi/ContentBlocking/SumiRuleListProviderRuntime.swift
  Sumi/ContentBlocking/SumiProfileContentBlockingRuntime.swift
  Sumi/ContentBlocking/ContentBlockingTaskRegistry.swift
)

if rg -n '\bOwner\b|Owner\.swift' "${focused_files[@]}" >/dev/null; then
  echo "error: Adblock update responsibility was hidden behind an Owner name" >&2
  exit 1
fi

if rg -n 'Dictionary\(uniqueKeysWithValues:\s*release\.assets' Sumi/ContentBlocking --glob '*.swift' >/dev/null; then
  echo "error: untrusted release asset names must not use a trapping dictionary initializer" >&2
  exit 1
fi

if rg -n 'CryptoKit|OSLog|FileManager|Data\(contentsOf:|JSONSerialization' \
  Sumi/ContentBlocking/SumiAdblockNativeRuleBundle.swift \
  Sumi/ContentBlocking/SumiAdblockNativeGenerationProjector.swift >/dev/null; then
  echo "error: native bundle model/projection regained filesystem or diagnostics IO" >&2
  exit 1
fi

if rg -n '\b(load|bundledDirectoryURL|contentRuleListDefinitions|stagedShardURLs|compiledGenerationManifest)\s*\(' \
  Sumi/ContentBlocking/SumiAdblockNativeRuleBundle.swift >/dev/null; then
  echo "error: native bundle value regained reader/projector responsibilities" >&2
  exit 1
fi

if rg -n 'changesPublisher|AnyCancellable|ruleSourceGeneration|beginRuleSourceRefresh|isCurrentRuleSourceRefresh|disableAfterRuleSourceFailure' \
  Sumi/ContentBlocking/SumiContentBlockingService.swift \
  Sumi/ContentBlocking/SumiContentBlockingStateMachine.swift >/dev/null; then
  echo "error: provider observation/generation leaked back into policy runtime" >&2
  exit 1
fi

if rg -n 'ContentBlockingTaskRegistry\(\)' \
  Sumi/ContentBlocking SumiTests --glob '*.swift' >/dev/null; then
  echo "error: content-blocking task registry lost its exact key type" >&2
  exit 1
fi

rg -q 'ContentBlockingItemExchange\.swap' Sumi/ContentBlocking/AdblockGenerationArchive.swift
rg -q 'ContentBlockingItemExchange\.swap' Sumi/ContentBlocking/SumiProtectionBundleCacheTransaction.swift
rg -q 'previousGenerationId' Sumi/ContentBlocking/AdblockGenerationRetention.swift
rg -q 'mutationGate\.stop\(\)' Sumi/ContentBlocking/AdblockRuleListRuntime.swift
rg -q 'cache\.commit\(' Sumi/ContentBlocking/SumiProtectionBundleRemoteUpdater.swift
rg -q 'bundleReader\.contentRuleListDefinitions' Sumi/ContentBlocking/AdblockPreparedBundleInstaller.swift
rg -q 'generationProjector\.compiledManifest' Sumi/ContentBlocking/AdblockPreparedBundleInstaller.swift
rg -q 'SumiRuleListProviderRuntime' Sumi/ContentBlocking/SumiContentBlockingService.swift
rg -q 'ContentBlockingTaskRegistry<TaskKey>' Sumi/ContentBlocking/SumiRuleListProviderRuntime.swift
rg -q 'stagePreparedContentBlockingUpdate' Sumi/ContentBlocking/AdblockRuleListPublication.swift
rg -q 'publishStagedContentBlockingUpdate' Sumi/ContentBlocking/AdblockRuleListPublication.swift
rg -q 'private var runtimeLevel = SumiProtectionLevel\.off' Sumi/ContentBlocking/SumiAdBlockingModule.swift
rg -q 'ruleProvider\.setRuntimeLevel\(level\)' Sumi/ContentBlocking/ProtectionAttachmentService.swift

if rg -n '\b(setPreparedBundleRuntimeEnabled|func setEnabled\(_ isEnabled: Bool\))' \
  Sumi/ContentBlocking/SumiAdBlockingModule.swift \
  Sumi/ContentBlocking/ProtectionAttachmentRuleProviding.swift >/dev/null; then
  echo "error: atomic Adblock runtime level regressed to split boolean forwarding" >&2
  exit 1
fi

echo "Adblock update architecture guard passed"
