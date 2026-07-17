# Contributing

Sumi is an experimental native macOS browser. Contributions are welcome when
they keep the project clear, testable, and honest about unfinished behavior.

## Engineering Direction

Changes should preserve these project constraints:

- Native macOS and WebKit behavior should be preferred over heavy web-based
  browser chrome.
- Performance-first design matters. Avoid unnecessary background services,
  timers, hidden web views, or long-running work.
- Optional modules should not add runtime cost when disabled.
- Browser organization features should remain understandable across tabs,
  spaces, profiles, pinned items, essentials, Glance, and split view.
- Incomplete features should be documented as incomplete.

## Documentation

Document user-visible behavior changes, new settings, compatibility changes,
and any intentional limitations. Avoid benchmark claims unless the benchmark
methodology and reproduction steps are documented.

## Pull Requests

Before opening a pull request:

- Build or test the relevant target when possible.
- Keep unrelated refactors out of feature changes.
- Update public docs when behavior changes.
- Call out experimental areas, known gaps, and follow-up work.

## Local Preflight

Enable the repository-owned pre-push hook once per clone:

```bash
scripts/install_dev_hooks.sh
```

The hook runs `scripts/ci/preflight.sh portable`, the same portable entrypoint
used by GitHub Actions. Run the narrower or complete modes directly when useful:

```bash
scripts/ci/preflight.sh fast
scripts/ci/preflight.sh portable
scripts/ci/preflight.sh full
```

`fast` validates text, shell syntax, JSON, and CI test ownership. `portable`
adds every architecture guard. `full` additionally requires the manifest's
Xcode 27 toolchain and runs the complete PR test profile.

## Co-change Contracts

Some repository metadata is part of the implementation and must move in the
same change as its owner:

| Code change | Required companion change |
| --- | --- |
| Rename, add, or remove an XCTest class or method selected by CI | Update `scripts/ci/test-manifest.json` ownership or selection. |
| Move a persistence writer, schema owner, or durable file | Update `docs/persistence/persistence-map.json`. |
| Add or change user-visible localized text | Build with the manifest toolchain and commit the resulting `Localizable.xcstrings` extraction. |
| Change startup recovery ordering or exact-once behavior | Update the behavioral recovery tests; source guards should only protect ownership boundaries. |
| Add a distinct responsibility to a large owner | Introduce the narrowly named role in the same change instead of raising a structural hard limit. |

LOC and aggregate dependency metrics are early warnings, not reasons for
cosmetic edits. Hard limits remain for genuinely oversized files and explicit
role boundaries.

The project is not production-ready, so clarity about risk is more useful than
polished claims.
