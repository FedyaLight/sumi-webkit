# Building Aura

Aura is a downstream product layer over Helium and helium-macos.

## Local setup

1. Ensure upstream repos are present and pinned:
   - `./scripts/validate_upstreams.sh`
2. Prepare and bootstrap the real Helium-based workspace:
   - `./scripts/aura_dev.sh prepare`
   - `./scripts/aura_dev.sh setup`
3. Build and run the real browser:
   - `./scripts/aura_dev.sh browser`
   - `./scripts/aura_dev.sh run`
3.2. Refresh the temporary Aura branding pack if needed:
   - `./scripts/aura_dev.sh branding`
3.5. Run the fast repository checks before sending changes:
   - `./scripts/ci_smoke.sh`
4. Treat Aura code as the only downstream product layer:
   - `aura/native`
   - `aura/services`
   - `aura/adapters`
   - `aura/mojom`
   - `patches/helium`
   - `patches/helium-macos`

## Downstream patch policy

- Prefer Aura-owned modules and adapters first.
- Use downstream patches only for narrow integration hooks that cannot live in
  Aura-owned code.
- Keep patches small, isolated, and rebased independently for `helium` and
  `helium-macos`.
- Do not build a second browser shell beside Helium.
- Keep development branding in the downstream Aura asset pack rather than
  hand-editing the built app bundle.
