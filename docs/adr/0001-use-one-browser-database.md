# Use one browser database

Sumi stores all app-owned structured browser data for one Local Installation in one GRDB-managed `Sumi.sqlite` database. A `profile_id` and foreign-key cascades provide Browser Profile scoping; WebKit website data, Keychain secrets, user-selected files, extension packages, and rebuildable blobs remain in their Platform Stores. Separate per-profile databases were rejected because Sumi performs cross-profile workspace, window, import, backup, and retirement operations that should share a real transaction rather than a coordinator over multiple WAL files.
