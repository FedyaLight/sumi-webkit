# License Notes

Sumi is GPL-3.0. Third-party components keep their own notices where they are
vendored or directly used.

## Prepared protection bundles

`sumi-webkit` consumes prepared protection bundles only. Raw list fetching,
conversion, and bundle generation belong outside the browser in the sibling
`sumi-protection-bundles` repository. Any upstream list contents used by that
external generation pipeline may have their own licenses, terms, and notices
from the upstream list projects.

Prepared `trackingNetwork` assets may be derived from DuckDuckGo Tracker Radar /
Tracker Data Set:

- Source: `https://staticcdn.duckduckgo.com/trackerblocking/v6/current/macos-tds.json`
- License: CC BY-NC-SA 4.0
- License URL: `https://creativecommons.org/licenses/by-nc-sa/4.0/`

Those generated tracking assets are non-commercial Sumi protection-bundle data
and remain subject to the CC BY-NC-SA 4.0 non-commercial and share-alike terms.
Release and bundle manifests preserve the source name, source URL, license URL,
attribution, generation date, source SHA-256, rule count, and shard count before
Sumi consumes the prepared shards.

The older in-browser DDG TrackerRadarKit path remains a temporary migration
fallback until prepared `trackingNetwork` output is manually proven comparable.
It must not be attached independently when a prepared `trackingNetwork` group is
active.

## Adblock redirect/noop resource compatibility metadata

Sumi recognizes a small set of uBO-compatible redirect/noop resource names for
diagnostics and future compatibility wiring: `noopjs`, `noopcss`,
`1x1-transparent.gif`, `noopframe`, and `noop.txt`, plus selected aliases.
These entries are Sumi-owned metadata only. Sumi does not vendor Brave
`adblock-resources` files, uBlock Origin resource contents, or a full redirect
resource tree.

The final browser product does not ship a redirect/scriptlet runtime path, and
no Brave/uBO resource payload is copied into Sumi.app.
