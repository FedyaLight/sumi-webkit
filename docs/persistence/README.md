# Persistence

`Sumi.sqlite` is the only Sumi-owned database and the transaction boundary for
structured browser state. `SumiDatabase` owns schema bootstrap, connections,
transactions, and typed record stores. UI and browser managers do not import
GRDB.

The database contains profiles, workspace structure, tabs, bookmarks, history,
permissions, extension metadata, session snapshots, profile-retirement state,
site policies, adblock overrides and zapper rules, compiled content-rule
identifier metadata, live folders, favicon metadata, and import recovery state.

The remaining stores have distinct platform or lifetime ownership:

- `UserDefaults` stores scalar settings.
- Keychain stores credentials.
- WebKit stores cookies, LocalStorage, IndexedDB, service workers, and
  WebExtension website data.
- Feature directories store extension packages, favicon blobs, compiled rule
  lists, caches, and user-managed scripts.
- Incognito state, recently closed items, live views, and in-flight receipts
  remain in memory.

Schema version 1 is bootstrapped only for an empty database. No runtime
converter or historical schema migration is shipped. An unknown schema fails
closed. Confirmed SQLite corruption is preserved and verified before a fresh
database is created.

The normative storage inventory is
[`persistence-map.json`](persistence-map.json). Run
`scripts/check_persistence_inventory.sh` after changing persistence code.

The schema and transaction contract is described in
[Unified browser database](unified-browser-database-spec.md).
