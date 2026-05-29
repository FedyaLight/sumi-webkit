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

The project is not production-ready, so clarity about risk is more useful than
polished claims.
