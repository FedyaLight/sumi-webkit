# Reference map

`Zen` is the main reference for Aura.

`Nook` is not a migration base. At most, it is an archive of experiments that
helped identify what not to keep.

## Canonical sources

- `Zen`: UX, behavior, chrome model, theme interaction, menu structure
- `Helium`: browser runtime, extensions, stability, performance, battery
- `Aura`: Essentials semantics and the final shell composition

## Product behaviors to preserve

- spaces
- folders
- essentials
- pinned rows
- URL actions and shell behavior
- media stack
- theme behavior
- split view
- glance/peek

## What not to port directly

- monolithic manager ownership from `Nook`
- view-owned business logic
- duplicate chrome surfaces
- extension and theme side paths that bypass the primary owner
- any WebKit-era Bitwarden or extension workaround added only because `Nook`
  used a different engine/runtime

## Legacy inspection areas

- `/Users/fedaefimov/Downloads/Aura/Nook/Nook/Managers/BrowserManager`
- `/Users/fedaefimov/Downloads/Aura/Nook/Nook/Managers/TabManager`
- `/Users/fedaefimov/Downloads/Aura/Nook/Nook/Components/Sidebar`
