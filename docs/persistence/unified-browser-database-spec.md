# Unified browser database

## Goal

Replace Sumi's SwiftData startup store, Core Data bookmark store, structured JSON state, and browser-state `UserDefaults` payloads with one canonical SQLite persistence module. Keep only storage that belongs to macOS/WebKit, user-selected files, extension packages, or rebuildable caches outside the database.

There is no compatibility path for other installations or historical app versions. The only conversion input is the current local `com.sumi.browser` installation on the development Mac.

## Required behavior

- `Sumi.sqlite` is the sole runtime authority for profiles, spaces, tabs, folders, split state, history, bookmarks, permission decisions and activity, extension metadata, content-blocker site overrides, zapper rules and compiled-identifier metadata, window/session snapshots, and import recovery state.
- Browser Profile records use explicit profile UUIDs. Foreign keys prevent dangling profile, space, folder, history, bookmark, and permission references.
- Writes spanning related browser data use one SQLite transaction.
- The database uses WAL for the persistent installation, enables foreign keys, bounds busy waits, and exposes no GRDB or raw SQL types to browser UI and managers.
- Incognito state remains memory-only and WebKit continues to own cookies, local storage, IndexedDB, service workers, and other website data.
- Recently closed items remain process-local because they are an undo surface, not durable browser state.
- Keychain continues to own credentials. Extension packages, favicon/preview blobs, compiled content rules, remote bundles, downloads, and user-selected exports remain files.
- Scalar preferences such as theme and feature toggles remain in `UserDefaults`; browser records and Codable session payloads do not.
- Import parsers remain read-only source adapters. Every supported browser importer publishes parsed records through the canonical stores for the selected Browser Profile. Structural records and bookmarks use bounded SQLite transactions; bulk history is written in bounded batches. A durable database journal and compensation receipts coordinate these commits with WebKit-owned website data.
- Profile deletion removes database-owned profile data by transaction and delegates Platform Store cleanup to the existing WebKit/Keychain/file owners.
- Startup fails closed on permission, disk, schema, or unclassified database errors. Confirmed SQLite corruption is preserved before replacement.

## Local conversion

The current development installation is converted once outside the repository.
The operation preserves a byte-for-byte backup of every replaced source store,
validates counts and foreign keys, and then removes the old stores from runtime
use. No converter is checked in, shipped, or invoked at startup.

The conversion includes every Browser Profile in the current Local
Installation. Records whose domain is global remain global; records with
Browser Profile ownership retain their exact profile UUID.

## Acceptance

- Production source has no `SwiftData`, `CoreData`, `@Model`, `ModelContainer`, `ModelContext`, `NSPersistentContainer`, or bookmark `.xcdatamodeld` dependency.
- Production browser records are not stored as JSON files or `UserDefaults` data.
- Import, backup/restore, browsing-data cleanup, profile retirement, startup/session restore, extensions, history, bookmarks, and permissions use the new persistence module.
- Targeted persistence/import tests, architecture guards, and an app build pass.
- The converted local database matches source entity counts, passes `PRAGMA foreign_key_check`, and can be opened by the new runtime.
