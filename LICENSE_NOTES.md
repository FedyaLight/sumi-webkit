# License Notes

Sumi is GPL-3.0. Third-party components keep their own notices where they are
vendored or directly used.

## Prepared protection bundles

`sumi-webkit` consumes prepared protection bundles only. Raw list fetching,
conversion, and bundle generation belong outside the browser in the sibling
`sumi-protection-bundles` repository. Any upstream list contents used by that
external generation pipeline may have their own licenses, terms, and notices
from the upstream list projects.

Prepared `trackingNetwork` assets may be generated from DuckDuckGo Tracker
Radar / Tracker Data Set (TDS):

- Source: `https://staticcdn.duckduckgo.com/trackerblocking/v6/current/macos-tds.json`
- License: CC BY-NC-SA 4.0
- License URL: `https://creativecommons.org/licenses/by-nc-sa/4.0/`

Those generated tracking assets are derived protection-bundle data. They are
for non-commercial Sumi use and remain subject to the CC BY-NC-SA 4.0
non-commercial and share-alike terms. The share-alike terms apply to derived
`trackingNetwork` data distributed from the generated protection bundles.
Release and bundle manifests preserve the source name, source URL, license URL,
attribution, generation date, source SHA-256, rule count, and shard count before
Sumi consumes the prepared shards.

Sumi.app does not fetch DDG tracker data directly, run TrackerRadarKit
conversion, or generate tracking WebKit rules in the browser runtime. Prepared
`trackingNetwork` shards from signed protection-bundle releases are the only
runtime tracking data path.

## Adblock redirect/noop resource compatibility metadata

Sumi recognizes a small set of uBO-compatible redirect/noop resource names for
diagnostics and future compatibility wiring: `noopjs`, `noopcss`,
`1x1-transparent.gif`, `noopframe`, and `noop.txt`, plus selected aliases.
These entries are Sumi-owned metadata only. Sumi does not vendor Brave
`adblock-resources` files, uBlock Origin resource contents, or a full redirect
resource tree.

The final browser product does not ship a redirect/scriptlet runtime path, and
no Brave/uBO resource payload is copied into Sumi.app.
