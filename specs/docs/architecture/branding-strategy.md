# Branding strategy

Aura branding is treated as a first-class downstream concern, not as a manual
post-build tweak.

## Goal

The first branded development build should launch as `Aura.app` with a
temporary placeholder icon and Aura-owned bundle names, while staying easy to
rebase onto newer Helium revisions.

## Rules

- do not hand-edit the generated app bundle in `out/Default`
- do not patch branding directly in the middle of an active build
- keep branding changes in narrow downstream patches and reusable assets
- keep development bundle identifiers clearly marked as placeholders until
  release signing is ready
- the only allowed post-build bundle transform is the deterministic
  `scripts/materialize_aura_bundle.sh` step that copies a completed
  `Helium.app` into the branded `Aura.app` launch artifact for bring-up

## Current placeholder contract

- product name: `Aura`
- executable name: `Aura`
- development user-data directory: `~/Library/Application Support/dev.aura.browser`
- placeholder icon: rounded square with the letters `Au`

## First branding pass

1. Rename the built app bundle and executable from `Helium` to `Aura`.
2. Swap packaging and DMG metadata to Aura names.
3. Replace the upstream icon resources with the Aura placeholder asset pack.
4. Keep all source-side changes in the narrow downstream patch queue before the
   first UI pass:
   - `0000-brand-aura-core`
   - `0000-brand-aura-app-bundle`
   - `0001-brand-aura-assets`
5. Materialize `Aura.app` from a completed `Helium.app` as the first-launch
   artifact until the fully source-branded build path is proven end to end.

## Non-goals

- final production iconography
- final notarization identifiers
- marketing copy or website branding

Those can change later without disturbing the core browser runtime or the Aura
chrome integration work.
