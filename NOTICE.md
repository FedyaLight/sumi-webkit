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

Prepared tracking-protection data may be derived from DuckDuckGo Tracker Radar
or DuckDuckGo Tracker Data Set releases in the external protection-bundle
generation pipeline. Those data sources carry their own license terms and
attribution requirements.

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

Sumi Browser is not affiliated with Apple, DuckDuckGo, Arc, Zen, Bitwarden,
Proton, 1Password, browser2zen, or arc2zen.

Product names and trademarks belong to their respective owners and are used in
documentation only to describe compatibility goals, technical context, or user
workflow inspiration.
