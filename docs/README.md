# Documentation

The README is the product-level entry point. The documents here separate user-facing status from implementation detail so a reader does not need to reconstruct Sumi from its source tree.

## Start Here

- [Product status and build instructions](../README.md)
- [Roadmap](roadmap.md)
- [Extension compatibility](extensions.md)
- [Install and update behavior](UPDATES.md)

## Architecture

- [Architecture overview](architecture-overview.md) — the short tour, state flow, role vocabulary, and guidance for new features.
- [Architecture case studies](architecture/case-studies.md) — why physical WebView ownership, profile-scoped extension runtimes, and snapshot restoration exist.
- [Runtime architecture reference](architecture.md) — the detailed maintainer specification and invariants.
- [Persistence](persistence/README.md) and [permissions](permissions/README.md) — subsystem entry points.

## Engineering and Releases

- [Performance profiling](performance-profiling.md)
- [Safari Web Extension engineering log](SumiSafariExtensionCompatibility.md)
- [Safari extension manual checks](SafariExtensionManualE2E.md)
- [Maintainer release process](RELEASES.md)
- [v0.0.1 release notes](releases/0.0.1.md)
- [CI and test ownership](../scripts/ci/README.md)

Documents describe the current `main` branch unless a version is named explicitly. Historical investigation notes are labeled as such and are not release claims.
