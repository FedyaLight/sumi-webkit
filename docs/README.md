# Documentation

The README is the product-level entry point. The documents here separate user-facing status from implementation detail so a reader does not need to reconstruct Sumi from its source tree.

## Start Here

- [Product status and build instructions](../README.md)
- [Roadmap](roadmap.md)
- [Extension compatibility](extensions.md)
- [Install and update behavior](UPDATES.md)

## Architecture

- [Architecture overview](architecture-overview.md) — the short tour, state flow, role vocabulary, and guidance for new features.
- [Runtime architecture reference](architecture.md) — the detailed maintainer specification and invariants.
- [Page runtime lifecycle](architecture/page-runtime-lifecycle.md) — navigation authority, materialization, recovery, restore, and teardown.
- [Browser window lifecycle](architecture/browser-window-lifecycle.md) — native window ownership, restoration, and geometry.
- [Architecture case studies](architecture/case-studies.md) — why physical WebView ownership, profile-scoped extension runtimes, and snapshot restoration exist.
- [Persistence](persistence/README.md) and [permissions](permissions/README.md) — subsystem entry points.
- Architecture decisions: [one browser database](adr/0001-use-one-browser-database.md) and [stable page identity](adr/0002-keep-page-identity-stable-across-residency.md).

Focused subsystem contracts cover [browser chrome](architecture/browser-chrome-pipeline.md), [the URL Hub](url-hub/BEHAVIOR_PARITY.md), [the Command Palette](architecture/command-palette.md), [media sessions](architecture/media-session-pipeline.md), [Space theme transitions](architecture/space-theme-swipe-pipeline.md), and [split sidebar behavior](architecture/split-sidebar-behavior.md).

## Engineering and Releases

- [Performance profiling](performance-profiling.md)
- [Live smoke matrix](audit/live-smoke-matrix.md)
- [Extension compatibility](extensions.md)
- [Safari extension manual checks](SafariExtensionManualE2E.md)
- [Maintainer release process](RELEASES.md)
- [v0.0.1 Alpha 1 release notes](releases/0.0.1.md)
- [v0.0.2 Alpha 2 release notes](releases/0.0.2.md)
- [CI and test ownership](../scripts/ci/README.md)

Documents describe the current source tree unless a version or proposal status is named explicitly. Research notes and task trackers are temporary working material and do not belong in this index.
