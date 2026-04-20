# Downstream patch policy

Aura stays maintainable only if its patch surface remains narrow.

## Order of preference

1. Reuse Helium behavior directly
2. Add Aura-owned native or service code
3. Add a thin adapter hook
4. Add a downstream patch only if the first three are impossible

## Patch rules

- patches must target one concern only
- patches must name the owned Aura subsystem they support
- patches must not bundle UI, persistence, and runtime logic together
- if a patch grows into feature ownership, move that logic into Aura-owned code
- patches must not create or justify a parallel shell runtime
