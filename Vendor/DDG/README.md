DDG vendored snapshot
=====================

This directory contains the in-repo DDG package snapshots used by Sumi's favicon
backend transplant.

Source repository: https://github.com/duckduckgo/apple-browsers
Source revision: 7360a348cc6bc0f06173d35dd59905ae165780c6

The packages are intentionally vendored inside the Sumi repository so the app
does not depend on a local `../references` checkout at build time.
