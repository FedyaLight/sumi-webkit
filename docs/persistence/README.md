# Sumi persistence map

The enforceable inventory is [`persistence-map.json`](persistence-map.json). It describes stores by their real owner and technology; it does not pretend SwiftData, Core Data, WebKit, JSON, Keychain, and UserDefaults share a transaction or repository abstraction.

Run `scripts/check_persistence_inventory.sh` after changing a store, a persistent model, a format version, or a fixture. The check is also part of `scripts/check_architecture_guardrails.sh`. It semantically discovers production persistence signals, SwiftData `@Model` types, Core Data model versions/current version, and format-version declarations. Every exact `(signal kind, source path)` pair must be assigned to a family or explicitly classified as a user-owned/transient operation, so a newly introduced persistence mechanism in an already-known file still fails the guard. Fixture files are an exact set with locked byte counts and SHA-256 hashes.

## Durable inventory

| Family | Class | Owner/version | Logical root | Recovery truth |
|---|---|---|---|---|
| Startup browser state | Authoritative | `SumiStartupSchemaV1` 1.0.0 | Application Support runtime root, `default.store` | Structured SQLite corruption alone can quarantine; schema/migration/lock failures fail closed |
| Bookmarks | Authoritative | `BookmarksModel` 6 | Application Support runtime `Bookmarks` root | Core Data lightweight migration; load failure does not authorize deletion |
| Preferences and small sessions | Authoritative | Per-key owners; split archive v2 | Runtime UserDefaults domain | Per-owner default/legacy decode; no domain transaction |
| Permission activity | Authoritative | `SumiPermissionPersistenceAuthority` v1 | Runtime `Permissions` root | Unsupported/malformed bytes fail closed and are preserved as unreadable |
| Credentials | Authoritative | Independent Basic Auth/companion Keychain owners | macOS Keychain | Exact service/account reads and scoped deletion; no Sumi backup |
| Boosts | Authoritative | Shipped unversioned `SumiBoostStore.DiskState` | Sumi `Boosts` root | Malformed JSON loads empty and preserves unreadable bytes |
| Live folders | Authoritative | Shipped unversioned `SumiLiveFolderDiskState` | Runtime `live-folders.json` | Malformed JSON loads empty without modifying the file |
| Extension packages | Authoritative | Package install transaction plus SwiftData `ExtensionEntity` | Runtime extension package roots | Staged filesystem publication; later metadata/runtime reconciliation |
| WebKit website data | Authoritative | WebKit; profile UUID is Sumi identity | WebKit-selected default/profile stores | Only WebKit APIs inspect or delete it |
| WebKit extension storage | Authoritative | WebKit plus controller/directory owners | WebKit-selected and runtime extension-storage roots | Ordered legacy-directory retirement; no package/metadata transaction |
| Import journal | Recovery | `SumiImportTransactionJournalRecord` v1 | Runtime `ImportTransaction.json` | Fsynced phases and completed tombstone drive compensation/recovery |
| Logical backups | Backup | `SumiBackupArchive` v1 | User-selected URL or runtime `Backups` root | Validate before mutation; future/malformed archives are rejected |
| Favicon blobs | Cache | Metadata schema v2 | Runtime `Favicons/v2` root | Invalid metadata/blob is discarded and rebuilt |
| Generated adblock archive | Cache | Generation schema 6, reads 1...6 | Sumi `Adblock` root | Topology/path/size/hash checks precede active-manifest publication |
| Remote protection bundles | Cache | Release/native/signature schema 1 | Sumi `AdblockRemoteBundles` root | Signature/hash verification, rollback, quarantine, unavailable marker |
| Download application choices | Authoritative | Shipped unversioned record array | Sumi `DownloadApplications.json` | Decode failure yields no custom handlers |
| WebKit content rule lists | Cache | WebKit bytecode plus Sumi identifier catalog | WebKit-selected rule-list store | Remove/recompile only through WebKit APIs |

The JSON map is normative for each family's responsible production types, exact logical location policy, backup scope, legacy sources, and corruption policy.

## Cross-store consistency

There is no distributed transaction. The actual multi-store boundaries are:

| Operation | Commit order | Compensation / non-atomic boundary |
|---|---|---|
| Import or restore | Validate archive → pre-restore backup → prepared journal → SwiftData/runtime → Core Data bookmarks → completed journal | Runtime/bookmark checkpoints compensate committed phases. JSON, SwiftData, and Core Data are not atomic. |
| Extension install/update | Validate/stage package → publish package → SwiftData metadata → WebKit activation → preference keys | Filesystem staging rolls back; later reconciliation repairs metadata/runtime. WebKit is outside the transaction. |
| Profile/privacy deletion | Resolve scope → WebKit deletion → scoped Keychain/permission/cache/default cleanup → authoritative profile commit | Idempotent best effort. Privacy deletion intentionally does not recreate already-deleted bytes. |
| Adblock update | Verify signed remote bundle → remote cache → generated archive → WebKit compilation → active catalog/status | Old cache/generation/catalog remains active until the final marker. The stores are not atomic. |
| Window/session checkpoint | Serialized SwiftData tab writes → UserDefaults session hints | Restore validates/repairs hints against SwiftData; snapshots are intentionally not transactional. |

## Immutable fixtures

[`manifest.json`](../../SumiTests/Fixtures/Persistence/manifest.json) records every fixture's provenance, role, size, hash, and consuming test. Tests copy checked-in bytes and never manufacture an “old” payload from current production encoders.

- The startup fixture is a real SQLite/WAL/SHM family created once from the exact persistent declarations at historical commit `50f8ff4bea88a5d317afb7afac7e4c2966923f7b`, including removed UserScript entities. The archived app could not be relaunched because its old local DDG binary dependency is unavailable, so this proves declaration/runtime compatibility rather than execution by the historical binary.
- The bookmark fixture is a real SQLite store built from the shipped `BookmarksModel 2` model and contains a synthetic bookmark that must survive lightweight migration to model 6.
- JSON fixtures are static wire payloads for shipped formats. Unsupported, malformed, and tampered variants are separate immutable adversarial inputs.
- WebKit and Keychain physical stores are OS-owned and machine/container-specific, so portable binary fixtures would be misleading. Their ownership and cleanup boundaries remain guarded semantically; no fixture claims migration access Sumi does not have.

Before this slice the repository had versioned production schemas and runtime-generated migration test inputs, but no checked-in persistence inventory, no fixture manifest, and no immutable persistence migration fixtures. The map now covers all 17 durable families above, while explicitly classifying the download filesystem ports' in-memory allocator, byte finalizer, and incomplete-file cleaner as user-owned/ephemeral download boundaries, excluding other user-owned exports, and enumerating ephemeral state.
