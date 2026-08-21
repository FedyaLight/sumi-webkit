# Local Adblock Generation

Sumi bundles a filter catalog, not compiled rules. The user
selects lists and presses **Apply**; Sumi then downloads exactly those sources,
converts them locally with SafariConverterLib, and publishes one atomic
generation containing WebKit network rules, advanced filtering artifacts, and
`$removeparam` rules.

The recommended lists are the initial selection. Every catalog
entry can be enabled or disabled. **Update** rebuilds the current selection.
There is no separate Protection level and no dependency on a prepared-bundle
repository. The blocker does not use DuckDuckGo Tracker Radar.

```text
SumiAdblockBundle/
  manifest.json
  network/*.json
  .webext/{rules.bin,engine.bin,meta.bin,rules.txt,removeparam.json,cosmetic-domains.json}
```

Domain-scoped cosmetic rules (`css-display-none` with an `if-domain`
trigger) are stored in `cosmetic-domains.json` and served through the
advanced blocking pipeline instead of the WebKit rule lists: WebKit applies
every cosmetic selector to every document, while the advanced pipeline
matches them against the document host. Generic and `unless-domain`
cosmetics stay in the WebKit lists for first-paint timing. Startup attempts a
local transactional migration of installed generations that still carry these
rules in their shards. A failed migration keeps the original generation active
and records the failure in the ContentBlocking log.

Apply is transactional: download, conversion, validation, WebKit compilation,
and archive publication must all succeed before the active generation changes.
Startup restores only the active cached generation without network access or
bundle conversion; if its compiled WebKit lists are absent, they are rebuilt
from that archive. Once a new generation is active, inactive archive artifacts
and compiled WebKit lists are removed. Navigation only uses compiled WebKit
lists and the lazily loaded advanced engine.

`Off` is zero-cost: no filter downloads, conversion, advanced engine, URL
cleaning contribution, observers, or background update work. Sumi performs no
automatic list updates; network work happens only after explicit Apply/Update.
