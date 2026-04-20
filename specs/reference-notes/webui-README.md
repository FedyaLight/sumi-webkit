# Aura WebUI

Primary browser chrome must not be implemented here.

Aura's main interface is being built directly into Helium's native Chromium
Views/macOS bridge surfaces. This directory is reserved only for optional,
isolated secondary pages such as `aura://settings/`.

If a feature belongs to the visible browser chrome, it should live in
`/Users/fedaefimov/Downloads/Aura/Aura/aura/native`, not here.

Secondary pages in this directory must stay isolated from the primary browser
chrome runtime and use narrow typed contracts only.

`aura://settings/` is expected to expose the frozen Aura-owned IA:

- `Theme`
- `Layout`
- `Spaces & Essentials`
- `Keyboard`
- `Import/Export`
