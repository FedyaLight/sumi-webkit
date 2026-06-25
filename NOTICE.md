# Notice

Sumi Browser is an independent open-source project licensed under the GNU
General Public License v3.0. See [LICENSE](LICENSE).

## Project Origin

The main Sumi browser app is developed as an independent project, but it was
not written entirely from scratch. The codebase started from the open-source
Nook browser and has been substantially reworked around Sumi's native macOS,
WebKit, and performance-first goals.

## DuckDuckGo Components

Sumi includes vendored or adapted open-source components from DuckDuckGo's
Apple browser projects, including BrowserServicesKit and URLPredictor. These
components are used under their applicable upstream licenses, including Apache
License 2.0 where indicated by upstream files or source headers.

Some AppKit/WebKit helper code in the Sumi app is adapted from DuckDuckGo
macOS browser code. Directly reused portions should retain their upstream
copyright and SPDX headers.

## Protection Bundle Sources

Sumi consumes prepared protection bundles generated outside the browser in
`FedyaLight/sumi-protection-bundles`. Sumi.app verifies release manifests,
hashes, byte sizes, paths, and signatures, then compiles prepared WebKit rule
shards. It does not fetch raw filter lists, parse ABP/uBO syntax, run
`adblock-rust`, or convert DuckDuckGo Tracker Radar data at runtime.

The `trackingNetwork` group is derived from DuckDuckGo Tracker Radar / Tracker
Data Set (TDS). Bundle metadata identifies the source as DuckDuckGo Tracker
Radar / TDS, records the TDS source URL and SHA-256 hash, and marks the
generated tracking data as CC BY-NC-SA 4.0, non-commercial, and share-alike.
Those terms apply to the generated tracking data in the protection bundles.

The current `adguardAdsPrivacy` adblock profile is generated from source lists
identified in the bundle manifest, including AdGuard DNS filter, AdGuard Base,
and uBlock filters for ads, badware risks, privacy, unbreak, and quick fixes.
Those source lists keep their own upstream terms. Sumi records source-list
names, URLs, hashes, byte sizes, and rule counts in bundle metadata rather than
claiming a single license for the combined adblock output.

## Browser Migration Compatibility

Sumi's Data & Recovery import/export services are compatible with public
browser2zen transfer data shapes and were informed by browser2zen's documented
Arc/Zen migration behavior. browser2zen is licensed under the MIT License and
its upstream license notice identifies browser2zen contributors, with arc2zen
by Rafael Cabezas also noted as MIT-licensed upstream work.

Sumi does not vendor browser2zen or arc2zen source code, does not ship their
assets, and does not add a runtime dependency on browser2zen or Python. If a
future change copies or closely adapts substantial upstream browser2zen or
arc2zen code, the relevant MIT copyright and permission notices must be
preserved in the affected source or distribution notices.

## Affiliation

Sumi Browser is not affiliated with Apple, DuckDuckGo, AdGuard, uBlock Origin,
Arc, Zen, Bitwarden, Proton, 1Password, browser2zen, or arc2zen.

Product names and trademarks belong to their respective owners and are used in
documentation only to describe compatibility goals, technical context, or user
workflow inspiration.
