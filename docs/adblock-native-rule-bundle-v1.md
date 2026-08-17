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
  .webext/{rules.bin,engine.bin,meta.bin,rules.txt,removeparam.json}
```

Apply is transactional: download, conversion, validation, WebKit compilation,
and archive publication must all succeed before the active generation changes.
The previous generation remains available for recovery. Startup restores the
cached generation without network access or conversion. Navigation only uses
compiled WebKit lists and the lazily loaded advanced engine.

`Off` is zero-cost: no filter downloads, conversion, advanced engine, URL
cleaning contribution, observers, or background update work. Sumi performs no
automatic list updates; network work happens only after explicit Apply/Update.
