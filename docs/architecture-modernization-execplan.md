# Architecture Modernization Exec Plan

Last updated: 2026-07-02

## Baseline

- Starting score: 78/100.
- Target score: at least 84/100.
- Evidence baseline: `docs/refactor/modernization-audit.md`, `docs/architecture.md`, `xcodebuild -list -project Sumi.xcodeproj`.
- Current score estimate: 81/100 after adding CI architecture guardrails, a production SwiftData container boundary check, and clearer shell runtime dependency ownership.

## Assumptions

- No repository-root `AGENTS.md` exists, so the provided thread instructions are the active instructions.
- Architecture slices should preserve user behavior unless explicitly documented otherwise.
- Guardrail work is the safest first slice because it has zero runtime cost and protects existing browser boundaries before ownership refactors.
- Full Xcode test runs may be expensive; each slice will run the narrowest meaningful command and document anything broader that remains unverified.

## Ranked Backlog

| Rank | Slice | Expected files | Risk | Verification |
| --- | --- | --- | --- | --- |
| 1 | Aggregate architecture boundary scripts and run them in CI. | `scripts/check_architecture_guardrails.sh`, `.github/workflows/architecture-guardrails.yml` | Low | `scripts/check_architecture_guardrails.sh` |
| 2 | Guard production SwiftData container construction behind `SumiStartupPersistence`. | `scripts/check_startup_persistence_boundary.sh`, `scripts/check_architecture_guardrails.sh` | Low | `scripts/check_startup_persistence_boundary.sh`; `scripts/check_architecture_guardrails.sh` |
| 3 | Strengthen SwiftData startup schema guardrails without changing store shape. | `Sumi/Services/SumiStartupPersistence.swift`, `SumiTests/SumiStartupPersistenceTests.swift` | Medium | `xcodebuild test -project Sumi.xcodeproj -scheme Sumi -only-testing:SumiTests/SumiStartupPersistenceTests` |
| 4 | Move required app-shell dependency checks to `BrowserShellRuntime`. | `Sumi/Managers/BrowserManager/BrowserShellRuntime.swift`, `Sumi/Managers/BrowserManager/BrowserManager.swift` | Low | `xcodebuild test -project Sumi.xcodeproj -scheme Sumi -destination 'platform=macOS' -derivedDataPath .build/DerivedData-architecture-modernization-night -only-testing:SumiTests/BrowserManagerRuntimeWiringTests` |
| 5 | Reduce BrowserManager responsibility by extracting or tightening one cohesive planning boundary. | `Sumi/Managers/BrowserManager*`, related owner tests | Medium | Focused `SumiTests/Browser*OwnerTests` for the touched owner |
| 6 | Clarify one WebKit capability/runtime ownership path. | `Sumi/Components/WebView*`, `Sumi/Models/Tab*`, WebView owner tests | Medium | Focused WebView or tab runtime tests for the touched path |
| 7 | Narrow one sidebar/chrome state projection where it reduces dependency width. | `Sumi/Components/Sidebar/*`, `Navigation/Sidebar/*`, sidebar tests | Medium | Focused sidebar/chrome tests for the touched path |
| 8 | Add broader project guardrails only after the first slices show stable ownership boundaries. | `.github/workflows/*`, `scripts/*`, `SumiTests/*` | Medium | Script plus targeted Xcode tests |

## Stop Conditions

- A likely behavior regression appears and cannot be isolated safely.
- A required choice between two materially different architectures needs human product or design judgment.
- The same blocker repeats across three consecutive attempts.
- No safe architecture slice remains without broad rewrites or speculative abstraction.

## Current Progress

| Slice | Status | What changed | Verification | Remaining risk | Score estimate |
| --- | --- | --- | --- | --- | --- |
| Initial discovery | Complete | Confirmed `Sumi`, `SumiTests`, and `SumiUITests` targets plus shared schemes. No repo-local `AGENTS.md` was found. | `xcodebuild -list -project Sumi.xcodeproj` passed. | Subagent zone reports are still being collected. | 78/100 |
| Architecture guardrail CI | Complete | Added one local script that runs existing boundary scripts and a GitHub Actions workflow for PR/main protection. | `scripts/check_architecture_guardrails.sh` passed. | GitHub Actions runner execution is unverified until pushed. | 79/100 |
| Startup persistence boundary | Complete | Added a production scan that fails if SwiftData container, configuration, or schema construction moves outside `SumiStartupPersistence`. Wired it into the aggregate guardrail. | `scripts/check_startup_persistence_boundary.sh` passed; `scripts/check_architecture_guardrails.sh` passed. | Tests can still use in-memory containers directly; this slice only protects production runtime paths. | 80/100 |
| Shell runtime ownership | Complete | Moved required WebView coordinator, window registry, and shell content factory checks into `BrowserShellRuntime`; `BrowserManager` remains the public facade. | `xcodebuild test -project Sumi.xcodeproj -scheme Sumi -destination 'platform=macOS' -derivedDataPath .build/DerivedData-architecture-modernization-night -only-testing:SumiTests/BrowserManagerRuntimeWiringTests` passed. | Precondition text changed for missing bindings; no runtime behavior change is intended. | 81/100 |

## Before/After Estimate

- Before: 78/100.
- After current slice estimate: 81/100.
- Target after planned slices: 84/100 or higher.
