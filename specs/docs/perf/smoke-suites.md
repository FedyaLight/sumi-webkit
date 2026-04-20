# Performance smoke suites

Run Aura and Helium on the same machine, same upstream revision, same pages.

## Required suites

1. cold start
2. warm start
3. idle on blank tab
4. idle on 10-tab mixed session
5. YouTube + Twitch background media
6. Bitwarden installed, locked, and unlocked
7. two-profile space switching

## Required metrics

- launch time
- idle CPU
- RSS / footprint
- process count
- energy impact / wakeups
- tab switch latency
- space switch latency

## Release rule

Any Aura feature that misses budget must be redesigned, deferred, or cut.
